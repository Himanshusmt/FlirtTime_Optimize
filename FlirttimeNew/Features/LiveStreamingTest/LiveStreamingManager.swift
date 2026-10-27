//
//  LiveStreamingManager.swift
//  FlirttimeNew
//
//  Manages Agora RTC Engine for Live Streaming with Host/Audience & Co-Hosting Request Approval
//

import Foundation
import UIKit
import AgoraRtcKit
import Combine

enum LiveStreamStatus: Equatable {
    case idle
    case joining
    case connected(uid: UInt)
    case reconnecting
    case error(message: String)
}

final class LiveStreamingManager: NSObject, ObservableObject {
    static let shared = LiveStreamingManager()

    // Connection & Role
    @Published var status: LiveStreamStatus = .idle
    @Published var role: AgoraClientRole = .audience
    @Published var isHost: Bool = false              // True if this user started as Host
    @Published var isCoHosting: Bool = false         // True if viewer was accepted as Co-Host

    // Media State
    @Published var isMuted: Bool = false
    @Published var isVideoEnabled: Bool = true
    @Published var isFrontCamera: Bool = true
    @Published var streamDuration: Int = 0

    // Participants
    @Published var localUid: UInt = 0
    @Published var remoteUids: [UInt] = []
    @Published var hostUid: UInt? = nil              // UID of the original host (if known)
    @Published var activeRemoteUid: UInt? = nil
    @Published var coHostUid: UInt? = nil            // UID of the remote user currently co-hosting

    // Co-Host Requests & Interaction
    @Published var coHostStatus: CoHostRequestStatus = .idle
    @Published var incomingCoHostRequests: [CoHostRequest] = []
    @Published var bannerNotification: String? = nil
    @Published var errorMessage: String? = nil

    private(set) var engine: AgoraRtcEngineKit?
    private var dataStreamId: Int = 0
    private var durationTimer: Timer?
    private weak var currentLocalView: UIView?
    private weak var currentRemoteView: UIView?

    private override init() {
        super.init()
    }

    // MARK: - Join Live Stream

    func joinLiveStream(
        appId: String = LiveStreamingConfig.currentAppId,
        channel: String = LiveStreamingConfig.currentChannelName,
        token: String = LiveStreamingConfig.currentToken,
        asHost: Bool = false
    ) {
        leaveLiveStream()

        self.isHost = asHost
        self.isCoHosting = false
        self.role = asHost ? .broadcaster : .audience
        self.status = .joining
        self.errorMessage = nil
        self.bannerNotification = nil
        self.coHostStatus = .idle
        self.incomingCoHostRequests.removeAll()
        self.isMuted = false
        self.isVideoEnabled = true
        self.isFrontCamera = true
        self.streamDuration = 0
        self.remoteUids.removeAll()
        self.activeRemoteUid = nil
        self.coHostUid = nil
        self.hostUid = asHost ? nil : nil

        let config = AgoraRtcEngineConfig()
        config.appId = appId
        config.channelProfile = .liveBroadcasting
        config.audioScenario = .default

        let kit = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        self.engine = kit

        kit.enableVideo()
        kit.enableAudio()

        let videoConfig = AgoraVideoEncoderConfiguration(
            size: CGSize(width: 720, height: 1280),
            frameRate: AgoraVideoFrameRate.fps30.rawValue,
            bitrate: AgoraVideoBitrateStandard,
            orientationMode: .fixedPortrait,
            mirrorMode: .auto
        )
        kit.setVideoEncoderConfiguration(videoConfig)

        kit.setClientRole(self.role)

        if asHost {
            kit.enableLocalVideo(true)
            kit.enableLocalAudio(true)
            kit.startPreview()
            if let view = currentLocalView {
                bindLocalCanvas(to: view)
            }
        } else {
            // Viewers do NOT publish video or audio
            kit.enableLocalVideo(false)
            kit.enableLocalAudio(false)
            kit.stopPreview()
        }

        let options = AgoraRtcChannelMediaOptions()
        options.publishCameraTrack = asHost
        options.publishMicrophoneTrack = asHost
        options.autoSubscribeAudio = true
        options.autoSubscribeVideo = true
        options.clientRoleType = self.role

        let joinResult = kit.joinChannel(byToken: token, channelId: channel, uid: 0, mediaOptions: options) { [weak self] _, uid, elapsed in
            DispatchQueue.main.async {
                guard let self else { return }
                self.localUid = uid
                if self.isHost {
                    self.hostUid = uid
                }
                self.status = .connected(uid: uid)
                self.startDurationTimer()
                self.createDataChannelIfNeeded()
            }
        }

        if joinResult != 0 {
            let errorMsg = "Join channel failed with code: \(joinResult)"
            self.status = .error(message: errorMsg)
            self.errorMessage = errorMsg
        }
    }

    // MARK: - Leave & Cleanup

    func leaveLiveStream() {
        durationTimer?.invalidate()
        durationTimer = nil

        if let kit = engine {
            kit.stopPreview()
            kit.setupLocalVideo(nil)
            if let activeRemoteUid {
                let canvas = AgoraRtcVideoCanvas()
                canvas.uid = activeRemoteUid
                canvas.view = nil
                kit.setupRemoteVideo(canvas)
            }
            if let coHostUid {
                let canvas = AgoraRtcVideoCanvas()
                canvas.uid = coHostUid
                canvas.view = nil
                kit.setupRemoteVideo(canvas)
            }
            kit.leaveChannel(nil)
            AgoraRtcEngineKit.destroy()
        }
        engine = nil
        status = .idle
        streamDuration = 0
        remoteUids.removeAll()
        activeRemoteUid = nil
        coHostUid = nil
        localUid = 0
        isCoHosting = false
        coHostStatus = .idle
        incomingCoHostRequests.removeAll()
        bannerNotification = nil
    }

    // MARK: - Video Canvas Binding

    func bindLocalCanvas(to view: UIView) {
        currentLocalView = view
        guard let kit = engine else { return }
        let canvas = AgoraRtcVideoCanvas()
        canvas.uid = 0
        canvas.view = view
        canvas.renderMode = .hidden
        kit.setupLocalVideo(canvas)
    }

    func bindRemoteCanvas(to view: UIView, uid: UInt) {
        currentRemoteView = view
        guard let kit = engine else { return }
        let canvas = AgoraRtcVideoCanvas()
        canvas.uid = uid
        canvas.view = view
        canvas.renderMode = .hidden
        kit.setupRemoteVideo(canvas)
    }

    // MARK: - Media Controls

    func switchCamera() {
        guard let kit = engine else { return }
        kit.switchCamera()
        isFrontCamera.toggle()
    }

    func toggleMute() {
        guard let kit = engine else { return }
        isMuted.toggle()
        kit.muteLocalAudioStream(isMuted)
    }

    func toggleVideo() {
        guard let kit = engine else { return }
        isVideoEnabled.toggle()
        kit.enableLocalVideo(isVideoEnabled)
    }

    // MARK: - Co-Host Signaling (Agora Data Stream)

    private func createDataChannelIfNeeded() {
        guard let kit = engine else { return }
        let dataConfig = AgoraDataStreamConfig()
        dataConfig.syncWithAudio = false
        dataConfig.ordered = true

        var streamId: Int = 0
        let ret = kit.createDataStream(&streamId, config: dataConfig)
        if ret == 0 {
            self.dataStreamId = streamId
        }
    }

    private func sendSignalingMessage(_ msg: LiveStreamSignalingMessage) {
        guard let kit = engine, dataStreamId != 0 else { return }
        do {
            let data = try JSONEncoder().encode(msg)
            kit.sendStreamMessage(dataStreamId, data: data)
        } catch {
            print("Failed to encode live stream message: \(error)")
        }
    }

    // MARK: - Viewer Action: Request to Co-Host

    func requestToCoHost() {
        guard !isHost && !isCoHosting else { return }
        let userName = UserDataManager.shared.displayName ?? "Viewer (\(localUid))"
        let msg = LiveStreamSignalingMessage(
            action: .requestCoHost,
            senderUid: localUid,
            targetUid: hostUid,
            senderName: userName
        )
        sendSignalingMessage(msg)
        self.coHostStatus = .pendingSent
        self.bannerNotification = "Request to go live sent to host. Waiting for approval..."
    }

    // MARK: - Host Action: Accept Request

    func acceptCoHostRequest(_ req: CoHostRequest) {
        guard isHost else { return }
        incomingCoHostRequests.removeAll { $0.uid == req.uid }
        self.coHostUid = req.uid

        let msg = LiveStreamSignalingMessage(
            action: .acceptCoHost,
            senderUid: localUid,
            targetUid: req.uid,
            senderName: UserDataManager.shared.displayName ?? "Host"
        )
        sendSignalingMessage(msg)
        self.bannerNotification = "\(req.userName) joined as Co-Host!"
    }

    // MARK: - Host Action: Reject Request

    func rejectCoHostRequest(_ req: CoHostRequest) {
        guard isHost else { return }
        incomingCoHostRequests.removeAll { $0.uid == req.uid }

        let msg = LiveStreamSignalingMessage(
            action: .rejectCoHost,
            senderUid: localUid,
            targetUid: req.uid,
            senderName: UserDataManager.shared.displayName ?? "Host"
        )
        sendSignalingMessage(msg)
    }

    // MARK: - Stop Co-Hosting (either by Host or by Co-Host)

    func stopCoHosting() {
        if isHost {
            if let remoteUid = coHostUid {
                let msg = LiveStreamSignalingMessage(
                    action: .endCoHost,
                    senderUid: localUid,
                    targetUid: remoteUid,
                    senderName: "Host"
                )
                sendSignalingMessage(msg)
                coHostUid = nil
                bannerNotification = "Co-Host removed from broadcast"
            }
        } else if isCoHosting {
            let msg = LiveStreamSignalingMessage(
                action: .endCoHost,
                senderUid: localUid,
                targetUid: hostUid,
                senderName: UserDataManager.shared.displayName
            )
            sendSignalingMessage(msg)
            downgradeToAudience()
        }
    }

    // MARK: - Role Elevation & Downgrade

    private func upgradeToBroadcaster() {
        guard let kit = engine else { return }
        self.role = .broadcaster
        self.isCoHosting = true
        self.coHostStatus = .accepted
        self.bannerNotification = "Host accepted! You are now live sharing video."

        let options = AgoraRtcChannelMediaOptions()
        options.publishCameraTrack = true
        options.publishMicrophoneTrack = true
        options.clientRoleType = .broadcaster

        kit.updateChannel(with: options)
        kit.setClientRole(.broadcaster)
        kit.enableLocalVideo(true)
        kit.enableLocalAudio(true)
        kit.startPreview()
        if let view = currentLocalView {
            bindLocalCanvas(to: view)
        }
    }

    private func downgradeToAudience() {
        guard let kit = engine else { return }
        self.role = .audience
        self.isCoHosting = false
        self.coHostStatus = .idle
        self.bannerNotification = "You returned to Viewer mode."

        let options = AgoraRtcChannelMediaOptions()
        options.publishCameraTrack = false
        options.publishMicrophoneTrack = false
        options.clientRoleType = .audience

        kit.updateChannel(with: options)
        kit.setClientRole(.audience)
        kit.stopPreview()
        kit.setupLocalVideo(nil)
        kit.enableLocalVideo(false)
        kit.enableLocalAudio(false)
    }

    // MARK: - Timer

    private func startDurationTimer() {
        durationTimer?.invalidate()
        streamDuration = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.streamDuration += 1
            }
        }
    }
}

// MARK: - AgoraRtcEngineDelegate

extension LiveStreamingManager: AgoraRtcEngineDelegate {
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        DispatchQueue.main.async {
            let msg = "Agora error: \(errorCode.rawValue)"
            self.errorMessage = msg
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        DispatchQueue.main.async {
            self.localUid = uid
            if self.isHost {
                self.hostUid = uid
            }
            self.status = .connected(uid: uid)
            self.startDurationTimer()
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        DispatchQueue.main.async {
            if !self.remoteUids.contains(uid) {
                self.remoteUids.append(uid)
            }
            if !self.isHost && self.hostUid == nil {
                // First remote broadcaster encountered is considered the host
                self.hostUid = uid
            }
            if self.activeRemoteUid == nil {
                self.activeRemoteUid = uid
            }
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        DispatchQueue.main.async {
            self.remoteUids.removeAll { $0 == uid }
            self.incomingCoHostRequests.removeAll { $0.uid == uid }
            if self.coHostUid == uid {
                self.coHostUid = nil
                self.bannerNotification = "Co-Host left the live stream"
            }
            if self.hostUid == uid {
                self.hostUid = nil
                if !self.isHost {
                    self.bannerNotification = "The host has ended the live stream."
                }
            }
            if self.activeRemoteUid == uid {
                self.activeRemoteUid = self.remoteUids.first
            }
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, firstRemoteVideoDecodedOfUid uid: UInt, size: CGSize, elapsed: Int) {
        DispatchQueue.main.async {
            if !self.isHost && self.hostUid == nil {
                self.hostUid = uid
            }
            self.activeRemoteUid = uid
            if let view = self.currentRemoteView {
                self.bindRemoteCanvas(to: view, uid: uid)
            }
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, receiveStreamMessageFromUid uid: UInt, streamId: NSInteger, data: Data) {
        guard let message = try? JSONDecoder().decode(LiveStreamSignalingMessage.self, from: data) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch message.action {
            case .requestCoHost:
                // Only host receives and handles co-host requests
                if self.isHost {
                    let reqName = message.senderName ?? "Viewer \(uid)"
                    if !self.incomingCoHostRequests.contains(where: { $0.uid == uid }) {
                        let request = CoHostRequest(uid: uid, userName: reqName)
                        self.incomingCoHostRequests.append(request)
                        self.bannerNotification = "\(reqName) requested to share video!"
                    }
                }

            case .acceptCoHost:
                // If targeted to this viewer, elevate to broadcaster!
                if message.targetUid == self.localUid && !self.isHost {
                    self.upgradeToBroadcaster()
                }

            case .rejectCoHost:
                if message.targetUid == self.localUid {
                    self.coHostStatus = .rejected
                    self.bannerNotification = "Host declined your request to go live."
                }

            case .endCoHost:
                if message.targetUid == self.localUid || (self.isCoHosting && uid == self.hostUid) {
                    self.downgradeToAudience()
                } else if self.isHost && uid == self.coHostUid {
                    self.coHostUid = nil
                    self.bannerNotification = "Co-Host stopped video sharing."
                }
            }
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, tokenPrivilegeWillExpire token: String) {
        DispatchQueue.main.async {
            self.errorMessage = "Token will expire soon. Please generate a new token."
        }
    }

    func rtcEngineRequestToken(_ engine: AgoraRtcEngineKit) {
        DispatchQueue.main.async {
            self.errorMessage = "Token expired. Please provide an updated token."
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, connectionChangedTo state: AgoraConnectionState, reason: AgoraConnectionChangedReason) {
        DispatchQueue.main.async {
            switch state {
            case .connecting:
                self.status = .joining
            case .connected:
                self.status = .connected(uid: self.localUid)
            case .reconnecting:
                self.status = .reconnecting
            case .failed:
                self.status = .error(message: "Connection failed (reason: \(reason.rawValue))")
            case .disconnected:
                break
            @unknown default:
                break
            }
        }
    }
}
