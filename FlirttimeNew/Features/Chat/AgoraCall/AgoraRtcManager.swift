//
//  AgoraRtcManager.swift
//  FlirttimeNew
//
//  Thin wrapper around AgoraRtcEngineKit (mirrors agora.ts join/leave/mute/video/speaker).
//  Supports 1:1 and multi-party (group) remotes.
//

import Foundation
import UIKit
import AVFoundation
import ReplayKit
import AgoraRtcKit
// Keeps Agora screen-share plugin linked into the main app (error -157 without it).


protocol AgoraRtcManagerDelegate: AnyObject {
    func agoraRtcManagerDidJoinChannel(_ manager: AgoraRtcManager)
    func agoraRtcManager(_ manager: AgoraRtcManager, didFail error: String)
    func agoraRtcManager(_ manager: AgoraRtcManager, remoteUidJoined uid: UInt, userAccount: String?)
    /// `reason` distinguishes intentional quit vs network drop (reconnect grace).
    func agoraRtcManager(_ manager: AgoraRtcManager, remoteUidLeft uid: UInt, reason: AgoraUserOfflineReason)
    func agoraRtcManager(_ manager: AgoraRtcManager, remoteVideoStateChanged uid: UInt, hasVideo: Bool)
    func agoraRtcManager(_ manager: AgoraRtcManager, remoteAudioMuted uid: UInt, muted: Bool)
    func agoraRtcManager(_ manager: AgoraRtcManager, screenSharingChanged isSharing: Bool)
    func agoraRtcManager(
        _ manager: AgoraRtcManager,
        connectionStateChanged state: AgoraConnectionState,
        reason: AgoraConnectionChangedReason
    )
    func agoraRtcManagerTokenWillExpire(_ manager: AgoraRtcManager)
    /// Primary remote peer uplink quality for call UI network bars.
    func agoraRtcManager(_ manager: AgoraRtcManager, remoteNetworkQuality quality: AgoraNetworkQuality)
    /// Early signal that primary remote media is frozen / offline (before `didOfflineOfUid`).
    /// `isConfirmed` is a real drop (audio dead / quality down / offline) — show Poor now.
    func agoraRtcManager(
        _ manager: AgoraRtcManager,
        remotePeerUplinkUnstable uid: UInt,
        unstable: Bool,
        isConfirmed: Bool
    )
    /// Loudspeaker / earpiece / wired / Bluetooth — for control-bar icon + auto-switch.
    func agoraRtcManager(
        _ manager: AgoraRtcManager,
        audioRouteChanged route: AgoraCallAudioRoute,
        speakerOn: Bool
    )
    func agoraRtcManagerAudioInterruptionBegan(_ manager: AgoraRtcManager)
    func agoraRtcManagerAudioInterruptionEnded(_ manager: AgoraRtcManager)
    func agoraRtcManagerCameraUnavailable(_ manager: AgoraRtcManager)
    func agoraRtcManager(_ manager: AgoraRtcManager, thermalStateChanged state: ProcessInfo.ThermalState)
    func agoraRtcManagerDidBecomeActive(_ manager: AgoraRtcManager)
}

extension AgoraRtcManagerDelegate {
    func agoraRtcManager(_ manager: AgoraRtcManager, remoteAudioMuted uid: UInt, muted: Bool) {}
    func agoraRtcManager(_ manager: AgoraRtcManager, screenSharingChanged isSharing: Bool) {}
    func agoraRtcManager(
        _ manager: AgoraRtcManager,
        connectionStateChanged state: AgoraConnectionState,
        reason: AgoraConnectionChangedReason
    ) {}
    func agoraRtcManagerTokenWillExpire(_ manager: AgoraRtcManager) {}
    func agoraRtcManager(_ manager: AgoraRtcManager, remoteNetworkQuality quality: AgoraNetworkQuality) {}
    func agoraRtcManager(
        _ manager: AgoraRtcManager,
        remotePeerUplinkUnstable uid: UInt,
        unstable: Bool,
        isConfirmed: Bool
    ) {}
    func agoraRtcManager(
        _ manager: AgoraRtcManager,
        audioRouteChanged route: AgoraCallAudioRoute,
        speakerOn: Bool
    ) {}
    func agoraRtcManagerAudioInterruptionBegan(_ manager: AgoraRtcManager) {}
    func agoraRtcManagerAudioInterruptionEnded(_ manager: AgoraRtcManager) {}
    func agoraRtcManagerCameraUnavailable(_ manager: AgoraRtcManager) {}
    func agoraRtcManager(_ manager: AgoraRtcManager, thermalStateChanged state: ProcessInfo.ThermalState) {}
    func agoraRtcManagerDidBecomeActive(_ manager: AgoraRtcManager) {}
}

final class AgoraRtcManager: NSObject {

    weak var delegate: AgoraRtcManagerDelegate?

    private(set) var engine: AgoraRtcEngineKit?
    private(set) var localUid: UInt = 0
    private(set) var localUserAccount: String?
    /// Primary / first remote — kept for 1:1 / PiP convenience.
    private(set) var remoteUid: UInt?
    /// All remote participants currently in the channel (group calls).
    private(set) var remoteUids: [UInt] = []
    /// Agora uid → userAccount (often OneVibe user UUID) when available.
    private(set) var remoteUserAccounts: [UInt: String] = [:]
    private(set) var isVideoEnabled = false
    private(set) var isMuted = false
    private(set) var isSpeakerOn = true
    private(set) var currentAudioRoute: AgoraCallAudioRoute = .speaker
    private(set) var hasJoinedChannel = false
    private(set) var isScreenSharing = false
    /// True after user taps share and we prep UI / startScreenCapture, before Broadcast actually begins.
    private(set) var isScreenSharePreparing = false
    /// When true, keep forcing loudspeaker even if a headset is connected (user tapped Speaker).
    private var userForcedSpeaker = false
    /// User picked Speaker / Earpiece / Bluetooth from the sheet (or toggled speaker) — don't auto-steal.
    private var userPickedAudioOutput = false
    /// Earpiece strips `.allowBluetooth`, so the session may hide BT; keep picker options for this call.
    private var rememberedExternalDeviceDuringCall = false
    private var rememberedExternalTitle: String?
    /// WhatsApp sheet selection — drives checkmark + actual output device.
    private(set) var selectedAudioOutput: AgoraCallAudioOutputChoice = .speaker
    /// Prevents apply → routeChange → reconcile → apply loops that freeze the UI.
    private var isApplyingAudioRoute = false
    private var suppressRouteReconcileUntil = Date.distantPast
    /// Avoid hammering AVAudioSession on every Agora `.connected` (causes reconnect + choppy audio).
    private var lastAudioRecoverAt = Date.distantPast
    private let audioRecoverMinInterval: TimeInterval = 2.0

    /// Bundle id of the ReplayKit Broadcast Upload Extension.
    static let screenShareExtensionBundleId = "com.onevibe.live.ScreenShare"
    /// Darwin notification — extension listens and calls `finishBroadcastWithError` to end system Broadcast.
    static let screenShareStopNotificationName = "com.onevibe.live.screenshare.stop" as CFString

    private var localVideoView: UIView?
    private var remoteVideoView: UIView?
    private var remoteVideoViews: [UInt: UIView] = [:]
    private var pendingWithVideo = false
    private var systemBroadcastPicker: RPSystemBroadcastPickerView?
    private var didObserveScreenCapture = false
    private var didObserveScreenShareLifecycle = false
    private var screenShareStartTimeout: DispatchWorkItem?
    private var screenShareStopDebounce: DispatchWorkItem?
    private var screenShareBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var silentKeepAlivePlayer: AVAudioPlayer?
    /// Last join credentials — used for token renew + audio recovery.
    private var activeChannelName: String = ""
    private var activeToken: String = ""
    private var didObserveAudioSession = false
    private var currentVideoQualityIsLow = false
    private var didObserveThermal = false
    /// Camera encoder ladder: low 360p/400 → standard 360p/600 → high 480p → ultra 720p (excellent Wi-Fi).
    private var cameraVideoTier: CameraVideoTier = .standard
    /// Remote starts on HIGH for first paint; drop to low only after a decoded frame if uplink is poor.
    private var isRemoteSubscribedLow = false
    private var hasDecodedRemoteVideoFrame = false
    private var lastLocalTxQuality: AgoraNetworkQuality = .unknown
    /// Latest primary remote audio bitrate — freeze while this is live is talking jitter, not a drop.
    private var lastRemoteAudioBitrateKbps: Int = -1
    private var lastRemoteAudioStatsAt: Date?
    private var isPrimaryRemoteAudioMuted = false
    private var isPrimaryRemoteAudioFrozen = false
    /// App ID used to create the warm engine — recreate only when it changes.
    private var boundAppId: String?

    private enum CameraVideoTier: Int, Comparable {
        case low = 0
        case standard = 1
        case high = 2
        case ultra = 3

        static func < (lhs: CameraVideoTier, rhs: CameraVideoTier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Cloud Proxy ladder for restricted networks (UAE/KZ): auto → UDP → TCP/443.
    private var cloudProxyStage: CallCloudProxyStage = .auto
    private var isProxyRetryInFlight = false
    private var joinWatchdogWork: DispatchWorkItem?
    private var pendingJoin: PendingAgoraJoin?

    private struct PendingAgoraJoin {
        let appId: String
        let channel: String
        let token: String
        let uid: String
        let useUserAccount: Bool
        let withVideo: Bool
        let speakerOn: Bool
    }

    func join(
        appId: String,
        channel: String,
        token: String,
        uid: String,
        withVideo: Bool,
        speakerOn: Bool,
        localView: UIView?,
        remoteView: UIView?
    ) {
        leave()

        localVideoView = localView
        remoteVideoView = remoteView
        isVideoEnabled = withVideo
        pendingWithVideo = withVideo
        isMuted = false
        isSpeakerOn = speakerOn
        // Initial join preference is not a manual force — allow headset auto-switch on plug/join.
        userForcedSpeaker = false
        userPickedAudioOutput = false
        rememberedExternalDeviceDuringCall = false
        rememberedExternalTitle = nil
        selectedAudioOutput = speakerOn ? .speaker : .earpiece
        hasJoinedChannel = false
        currentAudioRoute = speakerOn ? .speaker : .earpiece
        activeChannelName = channel
        activeToken = token
        currentVideoQualityIsLow = false
        cameraVideoTier = .standard
        isRemoteSubscribedLow = false
        hasDecodedRemoteVideoFrame = false
        lastLocalTxQuality = .unknown
        isProxyRetryInFlight = false
        // Restricted-region cellular often blocks raw UDP — start on TCP/TLS 443. Wi-Fi stays auto.
        cloudProxyStage = CallInternationalDiagnostics.prefersForcedTCPCloudProxy ? .tcp : .auto

        // Server may return a numeric uid OR a string userAccount (UUID).
        // Token is bound to whichever was used when minting — mismatch → Agora error 110.
        let numericUid = UInt(uid)
        let useUserAccount = (numericUid == nil)
        localUserAccount = useUserAccount ? uid : nil
        localUid = numericUid ?? 0

        pendingJoin = PendingAgoraJoin(
            appId: appId,
            channel: channel,
            token: token,
            uid: uid,
            useUserAccount: useUserAccount,
            withVideo: withVideo,
            speakerOn: speakerOn
        )
        CallInternationalDiagnostics.logSessionStart(reason: "agora-join")

        requestPermissions(withVideo: withVideo) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                CallInternationalDiagnostics.noteFailure(layer: .agoraMedia, detail: "permission-denied")
                self.delegate?.agoraRtcManager(self, didFail: "Microphone/camera permission denied")
                return
            }
            self.startEngineAndJoin(
                appId: appId,
                channel: channel,
                token: token,
                uid: uid,
                useUserAccount: useUserAccount,
                withVideo: withVideo,
                speakerOn: speakerOn
            )
        }
    }

    /// Refresh Agora privilege mid-call (from `tokenPrivilegeWillExpire` / server).
    func renewToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        activeToken = trimmed
        let code = engine?.renewToken(trimmed) ?? -1
        AppLogger.debug("AgoraRtcManager: renewToken result=\(code)")
    }

    /// Re-assert audio after interrupt / app foreground / real media failure.
    /// Full path may call `setCategory` — do **not** use on every Agora `.connected`.
    func recoverAudioSessionAfterInterrupt() {
        let now = Date()
        guard now.timeIntervalSince(lastAudioRecoverAt) >= audioRecoverMinInterval else {
            AppLogger.debug("AgoraRtcManager: skip full audio recover (debounced)")
            return
        }
        lastAudioRecoverAt = now
        prepareAudioSession(isVideo: pendingWithVideo || isVideoEnabled)
        applySelectedAudioOutput()
        softRestorePublishedAudio()
        refreshAndPublishAudioRoute()
        AppLogger.debug("AgoraRtcManager: full audio recover speaker=\(isSpeakerOn) muted=\(isMuted) route=\(currentAudioRoute.title)")
    }

    /// Light restore after Agora reconnect — never full `setCategory` thrash.
    func softRestorePublishedAudio() {
        engine?.enableLocalAudio(true)
        engine?.muteLocalAudioStream(isMuted)
        engine?.muteAllRemoteAudioStreams(false)
        // Re-assert current choice without opening the freeze loop.
        suppressRouteReconcileUntil = Date().addingTimeInterval(0.75)
        switch selectedAudioOutput {
        case .speaker:
            engine?.setEnableSpeakerphone(true)
            try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        case .earpiece:
            // Must re-strip defaultToSpeaker or earpiece silently fails after reconnect.
            configureSessionForEarpiece()
            preferBuiltInReceiver()
            engine?.setEnableSpeakerphone(false)
            try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
        case .external:
            configureSessionAllowingBluetooth()
            preferExternalHeadset()
            engine?.setEnableSpeakerphone(false)
            try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
        }
    }

    /// Call after reconnect-grace expires for a dropped remote (not for intentional quit).
    func finalizeRemoteLeft(_ uid: UInt) {
        trackRemoteLeft(uid)
        unbindRemoteVideo(uid: uid)
    }

    private func startEngineAndJoin(
        appId: String,
        channel: String,
        token: String,
        uid: String,
        useUserAccount: Bool,
        withVideo: Bool,
        speakerOn: Bool
    ) {
        prepareAudioSession(isVideo: withVideo)

        let kit = obtainEngine(appId: appId)

        applyCloudProxy(to: kit, stage: cloudProxyStage)
        CallInternationalDiagnostics.noteAgoraJoinStarted(channel: channel, proxy: cloudProxyStage)

        kit.setChannelProfile(.communication)
        kit.setClientRole(.broadcaster)
        // Keep AVAudioSession when backgrounded — required for ReplayKit extension ↔ app link.
        kit.setParameters("{\"che.audio.keep.audiosession\":true}")
        // Stable VoIP audio on iOS (reduces choppy uplink vs default music profile).
        kit.setAudioProfile(.speechStandard)
        kit.setAudioScenario(.meeting)
        kit.enableAudio()
        kit.enableLocalAudio(true)
        kit.setDefaultAudioRouteToSpeakerphone(speakerOn)
        kit.setEnableSpeakerphone(speakerOn)
        kit.muteLocalAudioStream(false)
        kit.adjustRecordingSignalVolume(100)
        kit.adjustPlaybackSignalVolume(100)

        observeAudioSessionIfNeeded()
        observeThermalStateIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.reconcileAudioRouteAfterHardwareChange(reason: "join")
        }

        if withVideo {
            kit.enableVideo()
            kit.enableLocalVideo(true)
            kit.muteLocalVideoStream(false)
            applyVideoEncoderConfiguration(tier: .standard, engine: kit)
            applyFirstFrameOptimizations(to: kit, preferLowRemoteStream: false)
            if !Self.hasUsableCamera() {
                kit.enableLocalVideo(false)
                kit.muteLocalVideoStream(true)
                isVideoEnabled = false
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.agoraRtcManagerCameraUnavailable(self)
                }
            } else if let localView = localVideoView {
                let canvas = AgoraRtcVideoCanvas()
                canvas.uid = 0
                canvas.view = localView
                canvas.renderMode = .hidden
                kit.setupLocalVideo(canvas)
                kit.startPreview()
            }
        } else {
            // Audio call: enable video module for *receiving* remote screen-share / late video,
            // but never publish the camera until the user starts sharing or switches to video.
            kit.enableVideo()
            kit.enableLocalVideo(false)
            kit.muteLocalVideoStream(true)
            applyFirstFrameOptimizations(to: kit, preferLowRemoteStream: false)
        }

        let mediaOptions = makeMediaOptions(withVideo: withVideo)
        let tokenOrNil = token.isEmpty ? nil : token
        let result: Int32

        if useUserAccount {
            AppLogger.debug("AgoraRtcManager: joining userAccount=\(uid) channel=\(channel) video=\(withVideo)")
            result = kit.joinChannel(
                byToken: tokenOrNil,
                channelId: channel,
                userAccount: uid,
                mediaOptions: mediaOptions
            ) { [weak self] _, assignedUid, _ in
                self?.handleJoinSuccess(assignedUid: assignedUid, withVideo: withVideo)
            }
        } else {
            AppLogger.debug("AgoraRtcManager: joining uid=\(localUid) channel=\(channel) video=\(withVideo)")
            result = kit.joinChannel(
                byToken: tokenOrNil,
                channelId: channel,
                uid: localUid,
                mediaOptions: mediaOptions
            ) { [weak self] _, assignedUid, _ in
                self?.handleJoinSuccess(assignedUid: assignedUid, withVideo: withVideo)
            }
        }

        if result != 0 {
            let message = "Failed to join Agora channel (code \(result))"
            AppLogger.debug("AgoraRtcManager: \(message)")
            if !retryJoinWithNextCloudProxy(reason: "joinChannel-code-\(result)") {
                CallInternationalDiagnostics.noteFailure(layer: .agoraMedia, detail: message)
                delegate?.agoraRtcManager(self, didFail: message)
            }
            return
        }
        scheduleJoinWatchdog()
    }

    private func agoraProxyType(for stage: CallCloudProxyStage) -> AgoraCloudProxyType {
        switch stage {
        case .auto: return .noneProxy
        case .udp: return .udpProxy
        case .tcp: return .tcpProxy
        }
    }

    private func applyCloudProxy(to kit: AgoraRtcEngineKit, stage: CallCloudProxyStage) {
        let type = agoraProxyType(for: stage)
        // Changing proxy type requires clearing first when switching mid-session.
        _ = kit.setCloudProxy(.noneProxy)
        let code = kit.setCloudProxy(type)
        CallInternationalDiagnostics.noteCloudProxy(stage)
        AppLogger.debug("AgoraRtcManager: setCloudProxy \(stage.rawValue) result=\(code)")
    }

    private func scheduleJoinWatchdog() {
        joinWatchdogWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.hasJoinedChannel else { return }
            _ = self.retryJoinWithNextCloudProxy(reason: "join-watchdog-timeout")
        }
        joinWatchdogWork = work
        // Escalate auto → UDP quickly; UDP → TCP if the restricted carrier still blocks.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: work)
    }

    private func cancelJoinWatchdog() {
        joinWatchdogWork?.cancel()
        joinWatchdogWork = nil
    }

    /// Escalates auto → UDP Cloud Proxy → TCP/TLS 443. Returns true if a retry was started.
    @discardableResult
    private func retryJoinWithNextCloudProxy(reason: String) -> Bool {
        guard let pending = pendingJoin, !isProxyRetryInFlight else { return false }
        let next: CallCloudProxyStage?
        switch cloudProxyStage {
        case .auto: next = .udp
        case .udp: next = .tcp
        case .tcp: next = nil
        }
        guard let next else {
            CallInternationalDiagnostics.noteFailure(
                layer: .agoraMedia,
                detail: "cloud-proxy-exhausted reason=\(reason)"
            )
            return false
        }

        isProxyRetryInFlight = true
        cancelJoinWatchdog()
        CallInternationalDiagnostics.log(
            "cloudProxyRetry \(cloudProxyStage.rawValue)→\(next.rawValue) reason=\(reason)"
        )
        cloudProxyStage = next

        // Leave channel and switch proxy — keep the warm engine (destroy() adds seconds per retry).
        tearDownEngineForProxyRetry()
        DispatchQueue.main.async { [weak self] in
            guard let self, let pending = self.pendingJoin else { return }
            self.isProxyRetryInFlight = false
            self.hasJoinedChannel = false
            self.startEngineAndJoin(
                appId: pending.appId,
                channel: pending.channel,
                token: pending.token,
                uid: pending.uid,
                useUserAccount: pending.useUserAccount,
                withVideo: pending.withVideo,
                speakerOn: pending.speakerOn
            )
        }
        return true
    }

    private func tearDownEngineForProxyRetry() {
        if let engine {
            engine.leaveChannel(nil)
            _ = engine.setCloudProxy(.noneProxy)
        }
    }

    /// Reuse a warm engine. Area codes IN+AS skip CN/NA/EU probes on the India–UAE path.
    private func obtainEngine(appId: String) -> AgoraRtcEngineKit {
        if let engine, boundAppId == appId {
            engine.delegate = self
            return engine
        }
        if boundAppId != nil {
            AgoraRtcEngineKit.destroy()
            engine = nil
            boundAppId = nil
        }
        let config = AgoraRtcEngineConfig()
        config.appId = appId
        config.channelProfile = .communication
        config.audioScenario = .meeting
        // Asia excluding CN (0x8) | India (0x20) — skip CN/NA/EU probe on India–UAE path.
        config.areaCode = AgoraAreaCodeType(rawValue: 0x8 | 0x20) ?? .global
        let kit = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        boundAppId = appId
        engine = kit
        AppLogger.debug("AgoraRtcManager: created engine areaCode=AS|IN appIdLen=\(appId.count)")
        return kit
    }

    private func handleJoinSuccess(assignedUid: UInt, withVideo: Bool) {
        if hasJoinedChannel {
            localUid = assignedUid
            return
        }
        cancelJoinWatchdog()
        localUid = assignedUid
        hasJoinedChannel = true
        isProxyRetryInFlight = false
        AppLogger.debug("AgoraRtcManager: joined channel uid=\(assignedUid) proxy=\(cloudProxyStage.rawValue)")
        CallInternationalDiagnostics.noteAgoraConnected()

        // Re-assert publish/subscribe after join (some SDK builds drop options with userAccount).
        engine?.updateChannel(with: makeMediaOptions(withVideo: withVideo))
        engine?.enableLocalAudio(true)
        engine?.muteLocalAudioStream(isMuted)
        // Ensure we never inherit a muted-remote state from a prior screen-share attempt.
        engine?.muteAllRemoteAudioStreams(false)
        engine?.muteAllRemoteVideoStreams(false)
        applySelectedAudioOutput()
        if withVideo {
            engine?.enableLocalVideo(true)
            engine?.muteLocalVideoStream(!isVideoEnabled)
            if let localView = localVideoView {
                bindLocalVideo(to: localView)
                engine?.startPreview()
            }
        } else {
            engine?.enableLocalVideo(false)
            engine?.muteLocalVideoStream(true)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reconcileAudioRouteAfterHardwareChange(reason: "did-join")
            self.delegate?.agoraRtcManagerDidJoinChannel(self)
        }
    }

    /// Ensures the video module can decode remote screen-share / camera (audio & group calls).
    func ensureRemoteVideoReceiveEnabled() {
        guard let engine, hasJoinedChannel, !isScreenSharing else { return }
        engine.enableVideo()
        engine.muteAllRemoteVideoStreams(false)
    }

    private func makeMediaOptions(withVideo: Bool) -> AgoraRtcChannelMediaOptions {
        let mediaOptions = AgoraRtcChannelMediaOptions()
        mediaOptions.publishMicrophoneTrack = true
        mediaOptions.clientRoleType = .broadcaster
        mediaOptions.channelProfile = .communication
        mediaOptions.autoSubscribeAudio = true
        mediaOptions.autoSubscribeVideo = true
        if isScreenSharing {
            mediaOptions.publishCameraTrack = false
            mediaOptions.publishScreenCaptureVideo = true
            mediaOptions.publishScreenCaptureAudio = false
        } else {
            // Explicitly turn screen publish OFF — otherwise camera never comes back after share.
            mediaOptions.publishCameraTrack = withVideo && isVideoEnabled
            mediaOptions.publishScreenCaptureVideo = false
            mediaOptions.publishScreenCaptureAudio = false
        }
        return mediaOptions
    }

    func leave() {
        cancelJoinWatchdog()
        pendingJoin = nil
        isProxyRetryInFlight = false
        cloudProxyStage = .auto
        hasJoinedChannel = false
        activeChannelName = ""
        activeToken = ""
        currentVideoQualityIsLow = false
        cameraVideoTier = .standard
        isRemoteSubscribedLow = false
        hasDecodedRemoteVideoFrame = false
        lastLocalTxQuality = .unknown
            lastRemoteAudioBitrateKbps = -1
        lastRemoteAudioStatsAt = nil
        isPrimaryRemoteAudioMuted = false
        isPrimaryRemoteAudioFrozen = false
        userForcedSpeaker = false
        userPickedAudioOutput = false
        rememberedExternalDeviceDuringCall = false
        rememberedExternalTitle = nil
        selectedAudioOutput = .speaker
        currentAudioRoute = .speaker
        isApplyingAudioRoute = false
        suppressRouteReconcileUntil = .distantPast
        lastAudioRecoverAt = .distantPast
        screenShareStartTimeout?.cancel()
        screenShareStartTimeout = nil
        isScreenSharePreparing = false
        isScreenSharing = false
        stopScreenSharingInternal(publishUpdate: false)
        if didObserveScreenCapture {
            NotificationCenter.default.removeObserver(self, name: UIScreen.capturedDidChangeNotification, object: nil)
            didObserveScreenCapture = false
        }
        stopObservingAudioSession()
        if let engine {
            engine.muteAllRemoteAudioStreams(false)
            engine.muteAllRemoteVideoStreams(false)
            engine.stopPreview()
            engine.setupLocalVideo(nil)
            for uid in remoteUids {
                let canvas = AgoraRtcVideoCanvas()
                canvas.uid = uid
                canvas.view = nil
                engine.setupRemoteVideo(canvas)
            }
            _ = engine.setCloudProxy(.noneProxy)
            engine.leaveChannel(nil)
        }
        // Keep the engine warm for the next join — destroy only on logout.
        remoteUid = nil
        remoteUids = []
        remoteUserAccounts = [:]
        remoteVideoViews = [:]
        localUserAccount = nil
        localUid = 0
        localVideoView = nil
        remoteVideoView = nil
        systemBroadcastPicker = nil
        stopScreenShareKeepAlive()
        // Do NOT deactivate AVAudioSession here — CallKit (User B answer) owns it and
        // tearing it down before Agora re-joins breaks callee audio/video.
    }

    /// Destroy the warm engine on logout so the next user gets a clean RTC instance.
    func destroyEngine() {
        leave()
        AgoraRtcEngineKit.destroy()
        engine = nil
        boundAppId = nil
        AppLogger.debug("AgoraRtcManager: engine destroyed")
    }

    // MARK: - Screen sharing

    /// Starts Agora screen capture and presents the system broadcast picker.
    /// Call again while sharing / preparing to stop or cancel.
    func toggleScreenSharing() {
        if isScreenSharing || isScreenSharePreparing || UIScreen.main.isCaptured {
            stopScreenSharing()
            return
        }
        startScreenSharing()
    }

    func startScreenSharing() {
        guard let engine else {
            delegate?.agoraRtcManager(self, didFail: "Call not connected")
            return
        }
        guard hasJoinedChannel else {
            delegate?.agoraRtcManager(self, didFail: "Join the call before sharing screen")
            return
        }
        guard !isScreenSharePreparing, !isScreenSharing else { return }
        observeScreenCaptureIfNeeded()

        isScreenSharePreparing = true
        // Lightweight UI + stop remote decode BEFORE ReplayKit starts (prevents A-side freeze).
        prepareLocalUIForScreenShare()
        // Keep process alive before/during Broadcast picker + background app switch.
        startScreenShareKeepAlive()

        engine.enableVideo()
        engine.setScreenCaptureScenario(.document)

        let params = makeScreenCaptureParameters()
        let code = engine.startScreenCapture(params)
        if code != 0 {
            AppLogger.debug("AgoraRtcManager: startScreenCapture failed code=\(code)")
            rollbackScreenSharePrep()
            let hint: String
            switch code {
            case -157, 157:
                hint = "Screen share module missing — rebuild after linking Agora ReplayKit"
            default:
                hint = "Unable to start screen share (\(code))"
            }
            delegate?.agoraRtcManager(self, didFail: hint)
            return
        }

        // If user dismisses the picker without starting, roll back.
        screenShareStartTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isScreenSharePreparing, !UIScreen.main.isCaptured, !self.isScreenSharing {
                AppLogger.debug("AgoraRtcManager: screen share picker timed out / cancelled")
                self.stopScreenSharing()
                self.delegate?.agoraRtcManager(self, didFail: "Screen share cancelled")
            }
        }
        screenShareStartTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: timeout)

        // Give UI a beat to settle, then show the system broadcast picker.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.presentSystemBroadcastPicker()
        }
    }

    func stopScreenSharing() {
        stopScreenSharingInternal(publishUpdate: true)
    }

    private func stopScreenSharingInternal(publishUpdate: Bool) {
        let wasSharing = isScreenSharing || isScreenSharePreparing || UIScreen.main.isCaptured
        screenShareStartTimeout?.cancel()
        screenShareStartTimeout = nil
        screenShareStopDebounce?.cancel()
        screenShareStopDebounce = nil
        isScreenSharePreparing = false
        stopScreenShareKeepAlive()
        if let engine {
            engine.stopScreenCapture()
            engine.muteAllRemoteVideoStreams(false)
        }
        // Ask the Broadcast Upload Extension to end the system ReplayKit broadcast (red status bar).
        requestSystemBroadcastStop()
        isScreenSharing = false

        if publishUpdate, hasJoinedChannel {
            // Screen track needs a beat to fully release before camera can publish again.
            restoreCameraAfterScreenShare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.restoreCameraAfterScreenShare()
            }
        }
        if wasSharing {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.agoraRtcManager(self, screenSharingChanged: false)
            }
        }
    }

    /// Switch publish source from screen → camera (or idle audio) after share stops.
    private func restoreCameraAfterScreenShare() {
        guard hasJoinedChannel, !isScreenSharing, let engine else { return }

        engine.muteAllRemoteVideoStreams(false)

        if pendingWithVideo, isVideoEnabled {
            engine.enableVideo()
            engine.enableLocalVideo(true)
            engine.muteLocalVideoStream(false)
            applyVideoEncoderConfiguration(lowQuality: currentVideoQualityIsLow, engine: engine)

            let options = AgoraRtcChannelMediaOptions()
            options.publishMicrophoneTrack = true
            options.publishCameraTrack = true
            options.publishScreenCaptureVideo = false
            options.publishScreenCaptureAudio = false
            options.clientRoleType = .broadcaster
            options.channelProfile = .communication
            options.autoSubscribeAudio = true
            options.autoSubscribeVideo = true
            let code = engine.updateChannel(with: options)
            AppLogger.debug("AgoraRtcManager: restore camera after screen share code=\(code)")

            engine.startPreview()
            if let localVideoView {
                bindLocalVideo(to: localVideoView)
            }
        } else {
            let options = makeMediaOptions(withVideo: pendingWithVideo)
            engine.updateChannel(with: options)
            engine.enableLocalVideo(false)
            engine.muteLocalVideoStream(true)
        }
    }

    /// Posts a Darwin notification so `OneVibeScreenShare` SampleHandler finishes the Broadcast.
    private func requestSystemBroadcastStop() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.screenShareStopNotificationName),
            nil,
            nil,
            true
        )
        // Replay once shortly after — extension may still be connecting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(Self.screenShareStopNotificationName),
                nil,
                nil,
                true
            )
        }
    }

    private func makeScreenCaptureParameters() -> AgoraScreenCaptureParameters2 {
        let params = AgoraScreenCaptureParameters2()
        params.captureVideo = true
        params.captureAudio = false

        let videoParams = AgoraScreenVideoParameters()
        videoParams.dimensions = CGSize(width: 540, height: 960)
        videoParams.frameRate = AgoraVideoFrameRate.fps10.rawValue
        videoParams.bitrate = 800
        videoParams.contentHint = .details
        params.videoParams = videoParams
        return params
    }

    private func presentSystemBroadcastPicker() {
        if #unavailable(iOS 12.0) {
            delegate?.agoraRtcManager(self, didFail: "Screen sharing requires iOS 12+")
            return
        }
        let picker = systemBroadcastPicker ?? RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.showsMicrophoneButton = false
        picker.preferredExtension = Self.screenShareExtensionBundleId
        // Must be in a window hierarchy for the private button action to work reliably.
        if picker.superview == nil, let host = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            picker.isHidden = true
            host.addSubview(picker)
        }
        systemBroadcastPicker = picker

        for subview in picker.subviews where subview is UIButton {
            (subview as? UIButton)?.sendActions(for: .allTouchEvents)
            break
        }
    }

    private func observeScreenCaptureIfNeeded() {
        guard !didObserveScreenCapture else { return }
        didObserveScreenCapture = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenCaptureChanged),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
        observeScreenShareLifecycleIfNeeded()
    }

    private func observeScreenShareLifecycleIfNeeded() {
        guard !didObserveScreenShareLifecycle else { return }
        didObserveScreenShareLifecycle = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleAppDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleAppWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        // Audio interruption / route — registered once via `observeAudioSessionIfNeeded()` on join.
    }

    @objc private func handleScreenCaptureChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if UIScreen.main.isCaptured {
                self.screenShareStopDebounce?.cancel()
                self.screenShareStopDebounce = nil
                self.applyScreenSharingStarted()
                return
            }
            guard self.isScreenSharing || self.isScreenSharePreparing else { return }
            // App switch can briefly clear isCaptured — wait before tearing down.
            self.screenShareStopDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard !UIScreen.main.isCaptured else { return }
                AppLogger.debug("AgoraRtcManager: system screen capture ended (debounced)")
                self.stopScreenSharing()
            }
            self.screenShareStopDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }

    @objc private func handleAppDidEnterBackground() {
        guard isScreenSharing || isScreenSharePreparing || UIScreen.main.isCaptured else { return }
        AppLogger.debug("AgoraRtcManager: background during screen share — keep-alive")
        startScreenShareKeepAlive()
        keepAudioAliveForScreenShare()
        if UIScreen.main.isCaptured {
            publishScreenCaptureTracks()
        }
    }

    @objc private func handleAppWillEnterForeground() {
        guard isScreenSharing || UIScreen.main.isCaptured else { return }
        AppLogger.debug("AgoraRtcManager: foreground during screen share — reassert publish")
        keepAudioAliveForScreenShare()
        if UIScreen.main.isCaptured {
            applyScreenSharingStarted()
        }
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            AppLogger.debug("AgoraRtcManager: audio interruption began")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.agoraRtcManagerAudioInterruptionBegan(self)
            }
        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            AppLogger.debug(
                "AgoraRtcManager: audio interruption ended shouldResume=\(options.contains(.shouldResume)) screenShare=\(isScreenSharing)"
            )
            if isScreenSharing || isScreenSharePreparing {
                keepAudioAliveForScreenShare()
                publishScreenCaptureTracks()
                silentKeepAlivePlayer?.play()
            }
            if options.contains(.shouldResume) || hasJoinedChannel {
                recoverAudioSessionAfterInterrupt()
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.agoraRtcManagerAudioInterruptionEnded(self)
            }
        @unknown default:
            break
        }
    }

    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard hasJoinedChannel || isScreenSharing || UIScreen.main.isCaptured else { return }
        let reasonRaw = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
            .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if self.isScreenSharing || UIScreen.main.isCaptured {
                // ReplayKit often flips the route — restore call audio without stopping share.
                self.keepAudioAliveForScreenShare()
            }
            guard self.hasJoinedChannel else { return }

            // Applying Speaker/Earpiece/BT ourselves posts route-change (override / category).
            // Re-applying here creates an infinite main-thread loop and freezes the UI.
            if self.isApplyingAudioRoute || Date() < self.suppressRouteReconcileUntil {
                self.refreshAndPublishAudioRoute()
                return
            }

            switch reasonRaw {
            case .newDeviceAvailable, .oldDeviceUnavailable:
                self.reconcileAudioRouteAfterHardwareChange(reason: "route-change")
            default:
                // override / categoryChange / config — UI only, do not re-apply session.
                self.refreshAndPublishAudioRoute()
            }
        }
    }

    private func startScreenShareKeepAlive() {
        engine?.setParameters("{\"che.audio.keep.audiosession\":true}")
        keepAudioAliveForScreenShare()

        if screenShareBackgroundTask == .invalid {
            screenShareBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "OneVibeScreenShare") { [weak self] in
                self?.endScreenShareBackgroundTask()
            }
        }

        if silentKeepAlivePlayer == nil {
            silentKeepAlivePlayer = makeSilentKeepAlivePlayer()
        }
        silentKeepAlivePlayer?.volume = 0.01
        silentKeepAlivePlayer?.numberOfLoops = -1
        if silentKeepAlivePlayer?.isPlaying != true {
            silentKeepAlivePlayer?.play()
        }
    }

    private func stopScreenShareKeepAlive() {
        silentKeepAlivePlayer?.stop()
        silentKeepAlivePlayer = nil
        endScreenShareBackgroundTask()
    }

    private func endScreenShareBackgroundTask() {
        guard screenShareBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(screenShareBackgroundTask)
        screenShareBackgroundTask = .invalid
    }

    private func keepAudioAliveForScreenShare() {
        prepareAudioSession(isVideo: pendingWithVideo || isScreenSharing)
        engine?.enableLocalAudio(true)
        engine?.muteLocalAudioStream(isMuted)
        applySelectedAudioOutput()
        // Mic must stay published so iOS does not suspend the app (kills ReplayKit pipe).
        if hasJoinedChannel {
            let options = AgoraRtcChannelMediaOptions()
            options.publishMicrophoneTrack = true
            options.publishCameraTrack = false
            options.publishScreenCaptureVideo = UIScreen.main.isCaptured || isScreenSharing
            options.publishScreenCaptureAudio = false
            options.clientRoleType = .broadcaster
            options.autoSubscribeAudio = true
            options.autoSubscribeVideo = true
            engine?.updateChannel(with: options)
        }
    }

    /// Tiny looping silent WAV so `audio` background mode keeps the process alive for ReplayKit.
    private func makeSilentKeepAlivePlayer() -> AVAudioPlayer? {
        let sampleRate = 8_000
        let seconds = 1
        let samples = sampleRate * seconds
        var data = Data()
        func appendUInt32(_ v: UInt32) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 4))
        }
        func appendUInt16(_ v: UInt16) {
            var le = v.littleEndian
            data.append(Data(bytes: &le, count: 2))
        }
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        appendUInt32(UInt32(36 + samples * 2))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45, 0x66, 0x6D, 0x74, 0x20]) // WAVEfmt
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(1) // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        appendUInt32(UInt32(samples * 2))
        data.append(Data(count: samples * 2))
        let player = try? AVAudioPlayer(data: data)
        player?.prepareToPlay()
        return player
    }

    /// Stop camera + remote video decode/render before ReplayKit starts.
    private func prepareLocalUIForScreenShare() {
        engine?.stopPreview()
        engine?.enableLocalVideo(false)
        // Critical: keep decoding remote video while capturing screen → freezes the device.
        engine?.muteAllRemoteVideoStreams(true)
        detachAllVideoCanvases()
        // Tell UI to show static "sharing" placeholder before capture begins.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.agoraRtcManager(self, screenSharingChanged: true)
        }
    }

    private func rollbackScreenSharePrep() {
        screenShareStartTimeout?.cancel()
        screenShareStartTimeout = nil
        engine?.muteAllRemoteVideoStreams(false)
        isScreenSharePreparing = false
        isScreenSharing = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.agoraRtcManager(self, screenSharingChanged: false)
        }
    }

    private func applyScreenSharingStarted() {
        screenShareStartTimeout?.cancel()
        screenShareStartTimeout = nil
        screenShareStopDebounce?.cancel()
        screenShareStopDebounce = nil
        isScreenSharePreparing = false
        startScreenShareKeepAlive()
        if isScreenSharing {
            publishScreenCaptureTracks()
            return
        }
        isScreenSharing = true
        AppLogger.debug("AgoraRtcManager: screen sharing started — publishing screen track")

        // Do NOT muteLocalVideoStream(true) — that also mutes the screen track.
        engine?.enableVideo()
        engine?.enableLocalVideo(false)
        engine?.muteLocalVideoStream(false)
        engine?.muteAllRemoteVideoStreams(true)
        detachAllVideoCanvases()
        publishScreenCaptureTracks()

        // Restore speaker after ReplayKit may flip the route (no audio-scenario swap mid-call).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.keepAudioAliveForScreenShare()
            self.delegate?.agoraRtcManager(self, screenSharingChanged: true)
        }
    }

    private func publishScreenCaptureTracks() {
        guard hasJoinedChannel, let engine else { return }
        let options = AgoraRtcChannelMediaOptions()
        options.publishMicrophoneTrack = true
        options.publishCameraTrack = false
        options.publishScreenCaptureVideo = true
        options.publishScreenCaptureAudio = false
        options.clientRoleType = .broadcaster
        options.channelProfile = .communication
        options.autoSubscribeAudio = true
        options.autoSubscribeVideo = true
        let code = engine.updateChannel(with: options)
        AppLogger.debug("AgoraRtcManager: publish screen track updateChannel code=\(code)")
    }

    /// Detach local/remote renderers while sharing to avoid capture↔render feedback freeze.
    func detachAllVideoCanvases() {
        guard let engine else { return }
        engine.setupLocalVideo(nil)
        let uids = remoteUids.isEmpty ? Array(remoteVideoViews.keys) : remoteUids
        for uid in uids {
            let canvas = AgoraRtcVideoCanvas()
            canvas.uid = uid
            canvas.view = nil
            engine.setupRemoteVideo(canvas)
        }
        // Clear so restore/rebind always re-applies setup*Video (skip-if-same must not no-op here).
        localVideoView = nil
        remoteVideoView = nil
        remoteVideoViews = [:]
    }

    /// Re-attach canvases after screen share stops.
    func restoreVideoCanvases(localView: UIView?, remoteViews: [UInt: UIView]) {
        engine?.muteAllRemoteVideoStreams(false)
        if let localView, pendingWithVideo, isVideoEnabled, !isScreenSharing {
            bindLocalVideo(to: localView)
            engine?.startPreview()
        }
        for (uid, view) in remoteViews {
            bindRemoteVideo(to: view, uid: uid)
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        engine?.muteLocalAudioStream(muted)
    }

    func setVideoEnabled(_ enabled: Bool) {
        isVideoEnabled = enabled
        // While screen sharing, camera publish stays off.
        if isScreenSharing {
            if hasJoinedChannel {
                engine?.updateChannel(with: makeMediaOptions(withVideo: pendingWithVideo))
            }
            return
        }
        engine?.enableLocalVideo(enabled)
        engine?.muteLocalVideoStream(!enabled)
        if hasJoinedChannel {
            let options = makeMediaOptions(withVideo: pendingWithVideo)
            engine?.updateChannel(with: options)
        }
        if enabled {
            applyVideoEncoderConfiguration(tier: .standard)
            applyRemoteSubscribeStream(low: false)
            engine?.startPreview()
            if let localVideoView {
                bindLocalVideo(to: localVideoView)
            }
        } else {
            engine?.stopPreview()
        }
    }

    func setSpeakerOn(_ on: Bool) {
        userPickedAudioOutput = true
        selectedAudioOutput = on ? .speaker : .earpiece
        isSpeakerOn = on
        userForcedSpeaker = on
        applySelectedAudioOutput()
        refreshAndPublishAudioRoute(force: true)
    }

    /// WhatsApp audio sheet: Speaker → loudspeaker, Earpiece → phone, Bluetooth → headset.
    func selectAudioOutput(_ choice: AgoraCallAudioOutputChoice) {
        userPickedAudioOutput = true
        selectedAudioOutput = choice
        switch choice {
        case .speaker:
            isSpeakerOn = true
            userForcedSpeaker = true
        case .earpiece, .external:
            isSpeakerOn = false
            userForcedSpeaker = false
        }
        applySelectedAudioOutput()
        refreshAndPublishAudioRoute(force: true)
        AppLogger.debug("AgoraRtcManager: selectAudioOutput \(choice) speaker=\(isSpeakerOn)")
    }

    /// Connected Bluetooth / wired headset available for the picker.
    var hasExternalAudioDevice: Bool {
        // Earpiece mode drops `.allowBluetooth`, so the session may temporarily hide BT.
        Self.hasExternalHeadsetOutput()
            || Self.externalHeadsetDisplayName() != nil
            || rememberedExternalDeviceDuringCall
    }

    var externalAudioDeviceTitle: String {
        if Self.hasWiredHeadsetOutput(), Self.externalBluetoothDisplayName() == nil {
            return "Headphones"
        }
        if let name = Self.externalBluetoothDisplayName(), !name.isEmpty {
            return name
        }
        if let name = Self.externalHeadsetDisplayName(), !name.isEmpty {
            return name
        }
        if let remembered = rememberedExternalTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remembered.isEmpty {
            return remembered
        }
        return "Bluetooth"
    }

    /// Apply the user's Speaker / Earpiece / Bluetooth choice to Agora + AVAudioSession.
    private func applySelectedAudioOutput() {
        guard !isApplyingAudioRoute else { return }
        isApplyingAudioRoute = true
        // Ignore self-triggered route notifications briefly after we change the session.
        suppressRouteReconcileUntil = Date().addingTimeInterval(0.75)
        defer { isApplyingAudioRoute = false }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true, options: [])
        } catch {
            AppLogger.debug("AgoraRtcManager: setActive failed: \(error)")
        }

        switch selectedAudioOutput {
        case .speaker:
            // Re-enable Bluetooth ports (earpiece may have stripped them) + restore video mode.
            configureSessionAllowingBluetooth()
            clearPreferredInput()
            engine?.setDefaultAudioRouteToSpeakerphone(true)
            engine?.setEnableSpeakerphone(true)
            do {
                try session.overrideOutputAudioPort(.speaker)
            } catch {
                AppLogger.debug("AgoraRtcManager: speaker override failed: \(error)")
            }
            refreshRememberedExternalAvailability()

        case .earpiece:
            // Capture BT/headphones name before we detach them from the session.
            refreshRememberedExternalAvailability()
            // Earpiece only works if category has NO `.defaultToSpeaker` and mode is
            // `.voiceChat`. Also omit `.allowBluetooth` — otherwise iOS keeps HFP earphones
            // even when the UI says Earpiece.
            configureSessionForEarpiece()
            preferBuiltInReceiver()
            engine?.setDefaultAudioRouteToSpeakerphone(false)
            engine?.setEnableSpeakerphone(false)
            do {
                try session.overrideOutputAudioPort(.none)
            } catch {
                AppLogger.debug("AgoraRtcManager: earpiece override failed: \(error)")
            }

        case .external:
            configureSessionAllowingBluetooth()
            preferExternalHeadset()
            engine?.setDefaultAudioRouteToSpeakerphone(false)
            engine?.setEnableSpeakerphone(false)
            do {
                try session.overrideOutputAudioPort(.none)
            } catch {
                AppLogger.debug("AgoraRtcManager: external override failed: \(error)")
            }
            refreshRememberedExternalAvailability()
        }
    }

    /// Strip `.defaultToSpeaker` + Bluetooth options so iOS can route to the built-in receiver.
    private func configureSessionForEarpiece() {
        let session = AVAudioSession.sharedInstance()
        do {
            // No `.allowBluetooth` / `.allowBluetoothA2DP` — required to leave HFP earphones.
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: []
            )
            try session.setActive(true, options: [])
        } catch {
            AppLogger.debug("AgoraRtcManager: earpiece category failed: \(error)")
        }
    }

    /// Restore BT-capable category after earpiece (or after interrupt recover).
    private func configureSessionAllowingBluetooth() {
        let session = AVAudioSession.sharedInstance()
        let isVideo = pendingWithVideo || isVideoEnabled || isScreenSharing
        do {
            try session.setCategory(
                .playAndRecord,
                mode: isVideo ? .videoChat : .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: [])
        } catch {
            AppLogger.debug("AgoraRtcManager: bluetooth category restore failed: \(error)")
        }
    }

    private func preferBuiltInReceiver() {
        let session = AVAudioSession.sharedInstance()
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            do {
                try session.setPreferredInput(builtIn)
            } catch {
                AppLogger.debug("AgoraRtcManager: setPreferredInput builtIn failed: \(error)")
            }
        }
    }

    private func preferExternalHeadset() {
        let session = AVAudioSession.sharedInstance()
        let preferred = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP })
            ?? session.availableInputs?.first(where: { $0.portType == .bluetoothLE })
            ?? session.availableInputs?.first(where: { $0.portType == .headsetMic })
        if let preferred {
            do {
                try session.setPreferredInput(preferred)
            } catch {
                AppLogger.debug("AgoraRtcManager: setPreferredInput external failed: \(error)")
            }
        }
    }

    private func clearPreferredInput() {
        do {
            try AVAudioSession.sharedInstance().setPreferredInput(nil)
        } catch {
            AppLogger.debug("AgoraRtcManager: clearPreferredInput failed: \(error)")
        }
    }

    private func refreshRememberedExternalAvailability() {
        guard Self.hasExternalHeadsetOutput() else { return }
        rememberedExternalDeviceDuringCall = true
        if let name = Self.externalBluetoothDisplayName() ?? Self.externalHeadsetDisplayName(),
           !name.isEmpty {
            rememberedExternalTitle = name
        } else if Self.hasWiredHeadsetOutput() {
            rememberedExternalTitle = "Headphones"
        }
    }

    /// When headset/Bluetooth plugs or unplugs — respect explicit user pick.
    private func reconcileAudioRouteAfterHardwareChange(reason: String) {
        let external = Self.hasExternalHeadsetOutput()

        if external {
            rememberedExternalDeviceDuringCall = true
            if let name = Self.externalBluetoothDisplayName() ?? Self.externalHeadsetDisplayName(),
               !name.isEmpty {
                rememberedExternalTitle = name
            } else if Self.hasWiredHeadsetOutput() {
                rememberedExternalTitle = "Headphones"
            }
            // WhatsApp: if headset is present and user hasn't locked Speaker/Earpiece, use BT.
            // Also covers audio-call join (default `.earpiece`) where iOS already plays on BT
            // but UI used to keep showing Earpiece.
            if !userForcedSpeaker && !userPickedAudioOutput {
                selectedAudioOutput = .external
                isSpeakerOn = false
            }
        } else {
            // Session may hide BT while on earpiece — don't treat that as unplug.
            if selectedAudioOutput == .earpiece && rememberedExternalDeviceDuringCall {
                applySelectedAudioOutput()
                refreshAndPublishAudioRoute()
                AppLogger.debug(
                    "AgoraRtcManager: reconcile keep earpiece (BT detached) reason=\(reason)"
                )
                return
            }
            userForcedSpeaker = false
            rememberedExternalDeviceDuringCall = false
            rememberedExternalTitle = nil
            if selectedAudioOutput == .external {
                let preferSpeaker = pendingWithVideo || isVideoEnabled
                selectedAudioOutput = preferSpeaker ? .speaker : .earpiece
                isSpeakerOn = preferSpeaker
                userPickedAudioOutput = false
            }
            clearPreferredInput()
        }

        applySelectedAudioOutput()
        refreshAndPublishAudioRoute()
        AppLogger.debug(
            "AgoraRtcManager: reconcile route reason=\(reason) speaker=\(isSpeakerOn) forced=\(userForcedSpeaker) picked=\(userPickedAudioOutput) choice=\(selectedAudioOutput) external=\(external) ui=\(currentAudioRoute.title)"
        )
    }

    private func refreshAndPublishAudioRoute(force: Bool = false) {
        // Checkmark + label follow the explicit selection first.
        let route: AgoraCallAudioRoute
        switch selectedAudioOutput {
        case .speaker:
            route = .speaker
        case .earpiece:
            route = .earpiece
        case .external:
            if let bt = Self.externalBluetoothDisplayName() {
                route = .bluetooth(bt)
            } else if Self.hasWiredHeadsetOutput() {
                route = .wiredHeadset
            } else if let name = Self.externalHeadsetDisplayName() {
                route = .bluetooth(name)
            } else if let remembered = rememberedExternalTitle, !remembered.isEmpty {
                route = .bluetooth(remembered)
            } else {
                route = .bluetooth(nil)
            }
        }
        let routeChanged = route != currentAudioRoute
        currentAudioRoute = route
        // Avoid notifyUI storms from override-triggered route notifications.
        if force || routeChanged {
            delegate?.agoraRtcManager(self, audioRouteChanged: route, speakerOn: isSpeakerOn)
        }
    }

    static func hasExternalHeadsetOutput() -> Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let inputs = AVAudioSession.sharedInstance().availableInputs ?? []
        let fromOutputs = outputs.contains { isExternalPort($0.portType) }
        let fromInputs = inputs.contains { isExternalPort($0.portType) }
        return fromOutputs || fromInputs
    }

    static func hasWiredHeadsetOutput() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let ports = session.currentRoute.outputs.map(\.portType)
            + (session.availableInputs ?? []).map(\.portType)
        return ports.contains(.headphones) || ports.contains(.headsetMic)
    }

    static func externalBluetoothDisplayName() -> String? {
        let session = AVAudioSession.sharedInstance()
        if let out = session.currentRoute.outputs.first(where: {
            $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
        }) {
            return out.portName
        }
        if let input = session.availableInputs?.first(where: {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
        }) {
            return input.portName
        }
        return nil
    }

    static func externalHeadsetDisplayName() -> String? {
        if let bt = externalBluetoothDisplayName() { return bt }
        let session = AVAudioSession.sharedInstance()
        let wiredOut = session.currentRoute.outputs.first(where: {
            $0.portType == .headphones || $0.portType == .headsetMic
        })
        if let wiredOut { return wiredOut.portName }
        return nil
    }

    private static func isExternalPort(_ type: AVAudioSession.Port) -> Bool {
        switch type {
        case .headphones, .headsetMic,
             .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
             .carAudio:
            return true
        default:
            return false
        }
    }

    func switchCamera() {
        engine?.switchCamera()
    }

    func bindLocalVideo(to view: UIView) {
        // Same surface — skip setupLocalVideo (avoids local preview flash on iOS).
        if localVideoView === view {
            return
        }
        localVideoView = view
        guard let engine else { return }
        let canvas = AgoraRtcVideoCanvas()
        canvas.uid = 0
        canvas.view = view
        canvas.renderMode = .hidden
        engine.setupLocalVideo(canvas)
        // Resume preview when canvases move full-screen ↔ PiP (avoids black local tile).
        if isVideoEnabled, !isScreenSharing {
            engine.startPreview()
        }
    }

    func bindRemoteVideo(to view: UIView, uid: UInt) {
        // Same canvas target — skip setupRemoteVideo (repeated bind flashes remote video on iOS).
        if remoteVideoViews[uid] === view {
            if remoteUid == nil || remoteUid == uid {
                remoteVideoView = view
                remoteUid = uid
            }
            return
        }
        remoteVideoViews[uid] = view
        if remoteUid == nil || remoteUid == uid {
            remoteVideoView = view
            remoteUid = uid
        }
        guard let engine else { return }
        let canvas = AgoraRtcVideoCanvas()
        canvas.uid = uid
        canvas.view = view
        canvas.renderMode = .hidden
        engine.setupRemoteVideo(canvas)
    }

    /// True when this uid already has a non-nil canvas view assigned.
    func isRemoteVideoBound(uid: UInt) -> Bool {
        remoteVideoViews[uid] != nil
    }

    func unbindRemoteVideo(uid: UInt) {
        if let engine {
            let canvas = AgoraRtcVideoCanvas()
            canvas.uid = uid
            canvas.view = nil
            engine.setupRemoteVideo(canvas)
        }
        remoteVideoViews.removeValue(forKey: uid)
        if remoteUid == uid {
            remoteUid = remoteUids.first
            remoteVideoView = remoteUid.flatMap { remoteVideoViews[$0] }
        }
    }

    // MARK: - Permissions / audio session

    private func requestPermissions(withVideo: Bool, completion: @escaping (Bool) -> Void) {
        let micGrantedNow = Self.isMicrophoneAuthorized()
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if withVideo {
            if micGrantedNow {
                DispatchQueue.main.async { completion(true) }
                if camStatus == .denied || camStatus == .restricted {
                    delegate?.agoraRtcManagerCameraUnavailable(self)
                }
                return
            }
        } else if micGrantedNow {
            DispatchQueue.main.async { completion(true) }
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission { micGranted in
            guard micGranted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            guard withVideo else {
                DispatchQueue.main.async { completion(true) }
                return
            }
            AVCaptureDevice.requestAccess(for: .video) { camGranted in
                DispatchQueue.main.async {
                    // Allow audio-only fallback if camera denied.
                    completion(true)
                    if !camGranted {
                        AppLogger.debug("AgoraRtcManager: camera permission denied — audio continues")
                        self.delegate?.agoraRtcManagerCameraUnavailable(self)
                    } else if !Self.hasUsableCamera() {
                        self.delegate?.agoraRtcManagerCameraUnavailable(self)
                    }
                }
            }
        }
    }

    private static func isMicrophoneAuthorized() -> Bool {
        if #available(iOS 17.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        }
        return AVAudioSession.sharedInstance().recordPermission == .granted
    }

    /// Warm audio (and camera preview when possible) as soon as the user answers — before token ack.
    func prepareLocalMedia(withVideo: Bool, localView: UIView?) {
        pendingWithVideo = withVideo
        isVideoEnabled = withVideo
        if let localView {
            localVideoView = localView
        }
        requestPermissions(withVideo: withVideo) { [weak self] granted in
            guard let self, granted else { return }
            self.prepareAudioSession(isVideo: withVideo)
            guard withVideo else { return }
            if let kit = self.engine {
                kit.enableVideo()
                kit.enableLocalVideo(true)
                kit.muteLocalVideoStream(false)
                if let view = self.localVideoView {
                    self.bindLocalVideo(to: view)
                    kit.startPreview()
                }
            }
        }
    }

    private func prepareAudioSession(isVideo: Bool) {
        suppressRouteReconcileUntil = Date().addingTimeInterval(0.75)
        ensureAudioSessionCategory(isVideo: isVideo)
        applySelectedAudioOutputPortOverride()
    }

    /// Stable category — no `.defaultToSpeaker`, no per-tap mode flips (those freeze the UI).
    private func ensureAudioSessionCategory(isVideo: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            // Never deactivate first — that kills CallKit's audio session for the callee (User B).
            try session.setCategory(
                .playAndRecord,
                mode: isVideo ? .videoChat : .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: [])
        } catch {
            AppLogger.debug("AgoraRtcManager: audio session setup failed: \(error)")
        }
    }

    private func applySelectedAudioOutputPortOverride() {
        let session = AVAudioSession.sharedInstance()
        do {
            switch selectedAudioOutput {
            case .speaker:
                try session.overrideOutputAudioPort(.speaker)
            case .earpiece, .external:
                try session.overrideOutputAudioPort(.none)
            }
        } catch {
            AppLogger.debug("AgoraRtcManager: output port override failed: \(error)")
        }
    }

    private func observeAudioSessionIfNeeded() {
        guard !didObserveAudioSession else { return }
        didObserveAudioSession = true
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActiveForAudio),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func stopObservingAudioSession() {
        guard didObserveAudioSession else { return }
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        didObserveAudioSession = false
        if didObserveThermal {
            NotificationCenter.default.removeObserver(self, name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
            didObserveThermal = false
        }
    }

    @objc private func handleAppDidBecomeActiveForAudio() {
        guard hasJoinedChannel else { return }
        recoverAudioSessionAfterInterrupt()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.agoraRtcManagerDidBecomeActive(self)
        }
    }

    private func observeThermalStateIfNeeded() {
        guard !didObserveThermal else { return }
        didObserveThermal = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThermalStateChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        handleThermalStateChange()
    }

    @objc private func handleThermalStateChange() {
        let state = ProcessInfo.processInfo.thermalState
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.agoraRtcManager(self, thermalStateChanged: state)
        }
    }

    static func hasUsableCamera() -> Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    /// Instant first remote frame: subscribe HIGH; SDK falls back to low on congestion.
    private func applyFirstFrameOptimizations(to kit: AgoraRtcEngineKit, preferLowRemoteStream: Bool) {
        kit.enableInstantMediaRendering()
        _ = kit.setDualStreamMode(.enableSimulcastStream)
        kit.setRemoteDefaultVideoStreamType(preferLowRemoteStream ? .low : .high)
        _ = kit.setRemoteSubscribeFallbackOption(.videoStreamLow)
        isRemoteSubscribedLow = preferLowRemoteStream
        AppLogger.debug(
            "AgoraRtcManager: first-frame opts instantRender dualStream remote=\(preferLowRemoteStream ? "low" : "high") fallback=low"
        )
    }

    /// Drop resolution when device is overheating (call continues on audio/video low).
    func forceLowVideoQualityForThermal() {
        guard isVideoEnabled, !isScreenSharing else { return }
        if cameraVideoTier != .low {
            applyVideoEncoderConfiguration(tier: .low)
            applyRemoteSubscribeStream(low: true)
        }
    }

    private func applyVideoEncoderConfiguration(lowQuality: Bool, engine: AgoraRtcEngineKit? = nil) {
        applyVideoEncoderConfiguration(tier: lowQuality ? .low : .standard, engine: engine)
    }

    private func applyVideoEncoderConfiguration(tier: CameraVideoTier, engine: AgoraRtcEngineKit? = nil) {
        let kit = engine ?? self.engine
        guard let kit, isVideoEnabled || pendingWithVideo else { return }
        cameraVideoTier = tier
        currentVideoQualityIsLow = (tier == .low)
        var encoder: AgoraVideoEncoderConfiguration
        let label: String
        switch tier {
        case .low:
            encoder = AgoraVideoEncoderConfiguration(
                size: CGSize(width: 640, height: 360),
                frameRate: AgoraVideoFrameRate.fps15.rawValue,
                bitrate: 400,
                orientationMode: .adaptative,
                mirrorMode: .auto
            )
            label = "LOW 640x360@15/400k"
        case .standard:
            encoder = AgoraVideoEncoderConfiguration(
                size: CGSize(width: 640, height: 360),
                frameRate: AgoraVideoFrameRate.fps15.rawValue,
                bitrate: 600,
                orientationMode: .adaptative,
                mirrorMode: .auto
            )
            label = "STD 640x360@15/600k"
        case .high:
            encoder = AgoraVideoEncoderConfiguration(
                size: CGSize(width: 640, height: 480),
                frameRate: AgoraVideoFrameRate.fps15.rawValue,
                bitrate: 800,
                orientationMode: .adaptative,
                mirrorMode: .auto
            )
            label = "HIGH 640x480@15/800k"
        case .ultra:
            encoder = AgoraVideoEncoderConfiguration(
                size: CGSize(width: 960, height: 720),
                frameRate: AgoraVideoFrameRate.fps15.rawValue,
                bitrate: AgoraVideoBitrateStandard,
                orientationMode: .adaptative,
                mirrorMode: .auto
            )
            label = "ULTRA 960x720@15"
        }
        encoder.degradationPreference = .balanced
        kit.setVideoEncoderConfiguration(encoder)
        AppLogger.debug("AgoraRtcManager: video encoder \(label)")
    }

    private func applyRemoteSubscribeStream(low: Bool) {
        guard let engine else { return }
        isRemoteSubscribedLow = low
        engine.setRemoteDefaultVideoStreamType(low ? .low : .high)
        for uid in remoteUids {
            engine.setRemoteVideoStream(uid, type: low ? .low : .high)
        }
    }

    private func adaptVideoForNetworkQuality(_ quality: AgoraNetworkQuality) {
        guard isVideoEnabled, !isScreenSharing else { return }
        lastLocalTxQuality = quality
        let poor: Set<AgoraNetworkQuality> = [.poor, .bad, .vBad, .down]
        let highRttPath = CallInternationalDiagnostics.prefersForcedTCPCloudProxy || cloudProxyStage == .tcp
        let wifiUpgrade = CallInternationalDiagnostics.isExcellentWifiUpgradeAllowed && !highRttPath

        if poor.contains(quality) {
            if cameraVideoTier != .low {
                applyVideoEncoderConfiguration(tier: .low)
            }
            // Keep HIGH until the first frame paints — LOW simulcast keyframe is often 2–5s late.
            if hasDecodedRemoteVideoFrame {
                applyRemoteSubscribeStream(low: true)
            }
            return
        }

        if quality == .excellent, wifiUpgrade {
            if cameraVideoTier != .ultra {
                applyVideoEncoderConfiguration(tier: .ultra)
            }
            applyRemoteSubscribeStream(low: false)
        } else if quality == .excellent || (!highRttPath && quality == .good) {
            if cameraVideoTier < .high {
                applyVideoEncoderConfiguration(tier: .high)
            }
            applyRemoteSubscribeStream(low: false)
        } else if cameraVideoTier > .standard {
            applyVideoEncoderConfiguration(tier: .standard)
            if hasDecodedRemoteVideoFrame {
                applyRemoteSubscribeStream(low: true)
            }
        }
    }

    private func dropRemoteToLowIfUplinkPoor() {
        let poor: Set<AgoraNetworkQuality> = [.poor, .bad, .vBad, .down]
        guard poor.contains(lastLocalTxQuality) else { return }
        applyRemoteSubscribeStream(low: true)
    }

    /// Audio packets still arriving — video `.frozen` in this window is jitter, not peer offline.
    private var remoteAudioAppearsLive: Bool {
        guard !isPrimaryRemoteAudioMuted else { return false }
        guard lastRemoteAudioBitrateKbps > 0, let at = lastRemoteAudioStatsAt else { return false }
        return Date().timeIntervalSince(at) < 2.8
    }

    private func emitPeerUplinkUnstable(uid: UInt, unstable: Bool, isConfirmed: Bool) {
        delegate?.agoraRtcManager(
            self,
            remotePeerUplinkUnstable: uid,
            unstable: unstable,
            isConfirmed: isConfirmed
        )
    }

    private func trackRemoteJoined(_ uid: UInt) {
        if !remoteUids.contains(uid) {
            remoteUids.append(uid)
        }
        if remoteUid == nil {
            remoteUid = uid
        }
    }

    private func trackRemoteLeft(_ uid: UInt) {
        remoteUids.removeAll { $0 == uid }
        remoteUserAccounts.removeValue(forKey: uid)
        remoteVideoViews.removeValue(forKey: uid)
        if remoteUid == uid {
            remoteUid = remoteUids.first
            remoteVideoView = remoteUid.flatMap { remoteVideoViews[$0] }
        }
    }

    private func resolveUserAccount(for uid: UInt) -> String? {
        if let cached = remoteUserAccounts[uid], !cached.isEmpty { return cached }
        guard let engine else { return nil }
        var error = AgoraErrorCode.noError
        if let info = engine.getUserInfo(byUid: uid, withError: &error),
           let account = info.userAccount, !account.isEmpty {
            remoteUserAccounts[uid] = account
            return account
        }
        return nil
    }
}

// MARK: - AgoraRtcEngineDelegate

extension AgoraRtcManager: AgoraRtcEngineDelegate {
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        AppLogger.debug("AgoraRtcManager: error \(errorCode.rawValue)")
        // Ignore transient / non-fatal codes that fire during join.
        let fatalCodes: Set<Int> = [110, -110, 101, -101, 102, -102, 109, -109, 123, -123]
        guard fatalCodes.contains(errorCode.rawValue) else { return }

        let hint: String
        switch errorCode.rawValue {
        case 110, -110:
            hint = "Invalid token (uid/userAccount mismatch)"
        case 101, -101:
            hint = "Invalid App ID"
        case 102, -102:
            hint = "Invalid channel name"
        default:
            hint = "Agora error"
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.agoraRtcManager(self, didFail: "\(hint) (\(errorCode.rawValue))")
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        handleJoinSuccess(assignedUid: uid, withVideo: pendingWithVideo)
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didLocalUserRegisteredWithUserId uid: UInt,
        userAccount: String
    ) {
        localUid = uid
        localUserAccount = userAccount
        AppLogger.debug("AgoraRtcManager: registered userAccount=\(userAccount) uid=\(uid)")
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        trackRemoteJoined(uid)
        let account = resolveUserAccount(for: uid)
        AppLogger.debug("AgoraRtcManager: remote joined uid=\(uid) account=\(account ?? "nil") remotes=\(remoteUids.count)")
        CallInternationalDiagnostics.noteRemoteMedia(kind: "remote-uid")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let view = remoteVideoViews[uid] ?? remoteVideoView {
                self.bindRemoteVideo(to: view, uid: uid)
            }
            self.delegate?.agoraRtcManager(self, remoteUidJoined: uid, userAccount: account)
        }
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        didUserInfoUpdatedWithUserId uid: UInt,
        userInfo: AgoraUserInfo
    ) {
        let account = userInfo.userAccount?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !account.isEmpty else { return }
        remoteUserAccounts[uid] = account
        AppLogger.debug("AgoraRtcManager: userInfo updated uid=\(uid) account=\(account)")
        // If we already tracked this remote, refresh grid identity.
        guard remoteUids.contains(uid) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.agoraRtcManager(self, remoteUidJoined: uid, userAccount: account)
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        AppLogger.debug("AgoraRtcManager: remote offline uid=\(uid) reason=\(reason.rawValue)")
        // For network drops keep uid tracked until service grace expires (so UI can reconnect).
        // Hard quit / audience → remove immediately.
        let hardLeave = (reason == .quit || reason == .becomeAudience)
        if hardLeave {
            trackRemoteLeft(uid)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.agoraRtcManager(self, remoteUidLeft: uid, reason: reason)
        }
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        connectionChangedTo state: AgoraConnectionState,
        reason: AgoraConnectionChangedReason
    ) {
        AppLogger.debug("AgoraRtcManager: connection state=\(state.rawValue) reason=\(reason.rawValue) proxy=\(cloudProxyStage.rawValue)")
        CallInternationalDiagnostics.noteAgoraConnection(state: state, reason: reason)
        if state == .connected {
            cancelJoinWatchdog()
            // Soft only — full setCategory here caused iOS reconnect loops + broken audio.
            softRestorePublishedAudio()
            if isVideoEnabled, !isScreenSharing {
                engine.updateChannel(with: makeMediaOptions(withVideo: true))
            }
        }

        let shouldEscalateProxy =
            !hasJoinedChannel
            && (
                state == .failed
                || reason == .reasonJoinFailed
                || reason == .reasonInterrupted
                || reason == .reasonLost
                || reason == .reasonKeepAliveTimeout
            )

        if shouldEscalateProxy {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.retryJoinWithNextCloudProxy(reason: "connection-\(state.rawValue)-\(reason.rawValue)") {
                    return
                }
                self.delegate?.agoraRtcManager(
                    self,
                    connectionStateChanged: state,
                    reason: reason
                )
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.agoraRtcManager(self, connectionStateChanged: state, reason: reason)
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, tokenPrivilegeWillExpire token: String) {
        AppLogger.debug("AgoraRtcManager: tokenPrivilegeWillExpire — requesting renew")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.agoraRtcManagerTokenWillExpire(self)
        }
    }

    func rtcEngineRequestToken(_ engine: AgoraRtcEngineKit) {
        AppLogger.debug("AgoraRtcManager: requestToken — privilege expired")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.agoraRtcManagerTokenWillExpire(self)
        }
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        networkQuality uid: UInt,
        txQuality: AgoraNetworkQuality,
        rxQuality: AgoraNetworkQuality
    ) {
        // uid == 0 → local uplink; keep for adaptive video bitrate only (not call UI bars).
        if uid == 0 {
            adaptVideoForNetworkQuality(txQuality)
            return
        }
        // uid != 0 → remote uplink. Show primary remote's network on call UI (User A sees User B).
        guard let primary = remoteUid, primary == uid else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.agoraRtcManager(self, remoteNetworkQuality: txQuality)
            // `.down` is peer gone. `.bad` / `.vBad` fire while talking — bars only, not Poor.
            if txQuality == .down {
                self.emitPeerUplinkUnstable(uid: uid, unstable: true, isConfirmed: true)
            }
        }
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        remoteVideoStateChangedOfUid uid: UInt,
        state: AgoraVideoRemoteState,
        reason: AgoraVideoRemoteReason,
        elapsed: Int
    ) {
        // Keep tile visible through transient `.frozen` — hiding causes iOS flicker.
        // Only treat stopped/failed as camera-off.
        let hasVideo: Bool
        switch state {
        case .decoding, .starting, .frozen:
            hasVideo = true
        case .stopped, .failed:
            hasVideo = false
        @unknown default:
            hasVideo = (state == .decoding || state == .starting)
        }

        let uplinkUnstable: Bool? = {
            guard remoteUid == nil || remoteUid == uid else { return nil }
            switch state {
            case .frozen:
                return true
            case .failed:
                return true
            case .stopped:
                switch reason {
                case .remoteMuted, .localMuted:
                    return nil
                case .remoteOffline, .congestion:
                    return true
                default:
                    return nil
                }
            case .decoding, .starting:
                // Only clear on explicit recovery — intermittent `.decoding` while peer
                // network is still bad was flipping B's UI Weak → Excellent in ~1s.
                switch reason {
                case .recovery, .audioFallbackRecovery, .remoteUnmuted, .localUnmuted:
                    return false
                default:
                    return nil
                }
            @unknown default:
                return nil
            }
        }()
        let videoLossConfirmed: Bool = {
            switch state {
            case .failed: return true
            case .stopped:
                return reason == .remoteOffline || reason == .congestion
            default:
                return false
            }
        }()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if hasVideo, (state == .decoding || state == .starting) {
                let firstFrame = !self.hasDecodedRemoteVideoFrame
                self.hasDecodedRemoteVideoFrame = true
                if firstFrame {
                    self.dropRemoteToLowIfUplinkPoor()
                }
            }
            // Bind only when we have a view and aren't already on that surface.
            if hasVideo, let view = remoteVideoViews[uid] ?? remoteVideoView {
                self.bindRemoteVideo(to: view, uid: uid)
            }
            self.delegate?.agoraRtcManager(self, remoteVideoStateChanged: uid, hasVideo: hasVideo)
            if let uplinkUnstable {
                if uplinkUnstable, !videoLossConfirmed, self.remoteAudioAppearsLive {
                    // Video hitch while audio is still flowing — not a peer network drop.
                    return
                }
                self.emitPeerUplinkUnstable(
                    uid: uid,
                    unstable: uplinkUnstable,
                    isConfirmed: videoLossConfirmed
                )
            }
        }
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        remoteAudioStateChangedOfUid uid: UInt,
        state: AgoraAudioRemoteState,
        reason: AgoraAudioRemoteReason,
        elapsed: Int
    ) {
        let muteFlag: Bool?
        switch reason {
        case .remoteMuted, .localMuted:
            muteFlag = true
        case .remoteUnmuted, .localUnmuted:
            muteFlag = false
        default:
            muteFlag = nil
        }

        let uplinkUnstable: Bool? = {
            guard remoteUid == nil || remoteUid == uid else { return nil }
            switch state {
            case .frozen:
                return true
            case .failed:
                return true
            case .stopped:
                switch reason {
                case .remoteMuted, .localMuted:
                    return nil
                case .remoteOffline, .networkCongestion:
                    return true
                default:
                    return nil
                }
            case .decoding, .starting:
                switch reason {
                case .networkRecovery, .remoteUnmuted, .localUnmuted:
                    return false
                default:
                    return nil
                }
            @unknown default:
                return nil
            }
        }()
        let stoppedOrFailed = (state == .failed)
            || (state == .stopped && (reason == .remoteOffline || reason == .networkCongestion))

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let muteFlag {
                if self.remoteUid == nil || self.remoteUid == uid {
                    self.isPrimaryRemoteAudioMuted = muteFlag
                    if muteFlag {
                        self.isPrimaryRemoteAudioFrozen = false
                    }
                }
                self.delegate?.agoraRtcManager(self, remoteAudioMuted: uid, muted: muteFlag)
            }
            if let uplinkUnstable {
                if self.remoteUid == nil || self.remoteUid == uid {
                    if uplinkUnstable {
                        self.isPrimaryRemoteAudioFrozen = true
                    } else {
                        self.isPrimaryRemoteAudioFrozen = false
                    }
                }
                let confirmed = uplinkUnstable && (
                    stoppedOrFailed
                        || (
                            state == .frozen
                                && !self.isPrimaryRemoteAudioMuted
                                && !self.remoteAudioAppearsLive
                                && self.lastRemoteAudioStatsAt != nil
                        )
                )
                self.emitPeerUplinkUnstable(
                    uid: uid,
                    unstable: uplinkUnstable,
                    isConfirmed: confirmed
                )
            }
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, remoteAudioStats stats: AgoraRtcRemoteAudioStats) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.remoteUid == nil || self.remoteUid == stats.uid else { return }
            let bitrate = Int(stats.receivedBitrate)
            self.lastRemoteAudioBitrateKbps = bitrate
            self.lastRemoteAudioStatsAt = Date()
            guard !self.isPrimaryRemoteAudioMuted else { return }
            if bitrate > 0 {
                self.isPrimaryRemoteAudioFrozen = false
                self.emitPeerUplinkUnstable(uid: stats.uid, unstable: false, isConfirmed: false)
            } else if self.isPrimaryRemoteAudioFrozen {
                // Audio already frozen and bitrate hit 0 — A dropped. Show Poor now.
                self.emitPeerUplinkUnstable(uid: stats.uid, unstable: true, isConfirmed: true)
            }
        }
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        firstRemoteAudioFrameOfUid uid: UInt,
        elapsed: Int
    ) {
        AppLogger.debug("AgoraRtcManager: first remote audio uid=\(uid)")
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, firstLocalAudioFramePublished elapsed: Int) {
        AppLogger.debug("AgoraRtcManager: first local audio published elapsed=\(elapsed)")
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        localVideoStateChangedOf state: AgoraVideoLocalState,
        reason: AgoraLocalVideoStreamReason,
        sourceType: AgoraVideoSourceType
    ) {
        AppLogger.debug(
            "AgoraRtcManager: localVideo state=\(state.rawValue) reason=\(reason.rawValue) source=\(sourceType.rawValue)"
        )
        switch (state, sourceType) {
        case (.capturing, .screen), (.encoding, .screen):
            applyScreenSharingStarted()
        case (.stopped, .screen), (.failed, .screen):
            // Backgrounding often emits a transient `.stopped` — only tear down if Broadcast really ended.
            if isScreenSharing || isScreenSharePreparing {
                if UIScreen.main.isCaptured {
                    AppLogger.debug("AgoraRtcManager: transient screen stopped — republishing")
                    keepAudioAliveForScreenShare()
                    publishScreenCaptureTracks()
                } else {
                    // Debounce same as capture notification.
                    screenShareStopDebounce?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        guard !UIScreen.main.isCaptured else { return }
                        self.stopScreenSharing()
                    }
                    screenShareStopDebounce = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
                }
            }
        default:
            break
        }
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        firstLocalVideoFramePublishedWithElapsed elapsed: Int,
        sourceType: AgoraVideoSourceType
    ) {
        AppLogger.debug(
            "AgoraRtcManager: first local video published elapsed=\(elapsed) source=\(sourceType.rawValue) screenSharing=\(isScreenSharing)"
        )
        if sourceType == .screen {
            publishScreenCaptureTracks()
        }
    }

    func rtcEngine(
        _ engine: AgoraRtcEngineKit,
        firstRemoteVideoFrameOfUid uid: UInt,
        size: CGSize,
        elapsed: Int
    ) {
        AppLogger.debug("AgoraRtcManager: first remote video uid=\(uid) size=\(size)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let view = self.remoteVideoViews[uid] ?? self.remoteVideoView {
                self.bindRemoteVideo(to: view, uid: uid)
            }
            self.delegate?.agoraRtcManager(self, remoteVideoStateChanged: uid, hasVideo: true)
        }
    }
}
