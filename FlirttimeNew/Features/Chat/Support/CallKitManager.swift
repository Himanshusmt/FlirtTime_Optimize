import Foundation
import CallKit
import AVFoundation
import UIKit
import Swinject

struct IncomingDyteCallContext {
    let meetingId: String
    let isVideo: Bool
    let title: String?
    let rawPayload: [String: Any]
}

struct IncomingAgoraCallContext {
    let callId: String
    let isVideo: Bool
    let callerName: String
    let call: AgoraCallDto?
    let rawPayload: [String: Any]
}

private enum IncomingCallKind {
    case dyte(IncomingDyteCallContext)
    case agora(IncomingAgoraCallContext)
}

/// Kill/background path matches the proven OneVibe-SMT zip:
/// report CallKit synchronously on the PushKit stack for idle incoming.
/// Call-waiting (third person while already on a call): still report VoIP (Apple),
/// then dismiss CallKit immediately and show only the in-app Accept/Decline popup.
class CallKitManager: NSObject {
    static let shared = CallKitManager()
    private let provider: CXProvider
    private let callController = CXCallController()
    /// Observes cellular / FaceTime / other CallKit calls (not only ours).
    private let systemCallObserver = CXCallObserver()
    private var currentCallUUID: UUID?
    private var incomingKind: IncomingCallKind?
    private var isJoining = false
    private var hasJoinedMeeting = false
    private var joinCallTimeoutWorkItem: DispatchWorkItem?
    private var reportedAgoraCallId: String?
    /// True while we are programmatically dismissing CallKit (remote hangup) — skip re-emit.
    private var isEndingFromApp = false
    /// UUIDs we are ending ourselves — race-safe vs clearing `isEndingFromApp` before `CXEndCallAction`.
    private var endingFromAppUUIDs = Set<UUID>()
    /// Audio Answer while still locked/background — keep CallKit until app becomes `.active` (video unlocks immediately).
    private var pendingCallKitHandoffUUID: UUID?
    /// PushKit-only UUIDs for call-waiting fulfill (report + instant end). Ignore End callbacks.
    private var silentVoIPFulfillUUIDs = Set<UUID>()
    /// CallKit UI is for a third-person call while already on an Agora call.
    private var isCallWaitingReport = false
    /// Set from AgoraCallService (active/outgoing). Used to dismiss CallKit immediately
    /// on VoIP call-waiting so only the in-app Accept/Decline popup is shown.
    private let liveSessionLock = NSLock()
    private var _hasLiveAgoraCallSession = false
    var hasLiveAgoraCallSession: Bool {
        get { liveSessionLock.lock(); defer { liveSessionLock.unlock() }; return _hasLiveAgoraCallSession }
        set { liveSessionLock.lock(); _hasLiveAgoraCallSession = newValue; liveSessionLock.unlock() }
    }
    /// Dyte join-call listener id — must remove by id so we don't nuke Agora `call:join` listeners.
    private var dyteJoinCallListenerId: UUID?

    /// True when the user is on a native phone / FaceTime / other-app call that is not OneVibe's CallKit UUID.
    var isOnExternalSystemCall: Bool {
        let ours = currentCallUUID
        let silent = silentVoIPFulfillUUIDs
        return systemCallObserver.calls.contains { call in
            guard !call.hasEnded else { return false }
            if silent.contains(call.uuid) { return false }
            // Our own incoming/active CallKit UUID must never look like cellular.
            if let ours, call.uuid == ours { return false }
            return true
        }
    }

    private var isCallKitAllowed: Bool {
        Locale.current.regionCode != "CN"
    }

    /// Zip-compatible: anything except `.background` prefers in-app UI.
    /// Kill wake / suspended → `.background` → CallKit (required for bg/kill ringing).
    static var isAppInForeground: Bool {
        if Thread.isMainThread {
            return UIApplication.shared.applicationState != .background
        }
        return DispatchQueue.main.sync {
            UIApplication.shared.applicationState != .background
        }
    }

    /// Legacy accessor used by Dyte path.
    private var incomingContext: IncomingDyteCallContext? {
        if case .dyte(let ctx) = incomingKind { return ctx }
        return nil
    }

    override init() {
        let config = CXProviderConfiguration(localizedName: "OneVibe")
        // Keep 1 like the working zip — after Answer we release CallKit so a waiting
        // VoIP can report a fresh incoming without replacing an active CallKit UUID.
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportsVideo = true
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = true
        config.iconTemplateImageData = nil
        // Bundle resource (Sounds/incoming_ringtone.caf) — used by system CallKit UI in background/kill.
        config.ringtoneSound = "incoming_ringtone.caf"
        provider = CXProvider(configuration: config)
        super.init()
        if isCallKitAllowed {
            provider.setDelegate(self, queue: .main)
            setupSocketListeners()
            AppLogger.killCall("CallKit provider ready (region=\(Locale.current.regionCode ?? "?"))")
        } else {
            AppLogger.killCall("CallKit disabled for China region")
        }
    }

    private func setupSocketListeners() {
        if let existing = dyteJoinCallListenerId {
            ChatSocketManager.shared.offEventById(existing)
            dyteJoinCallListenerId = nil
        }
        dyteJoinCallListenerId = ChatSocketManager.shared.listenToEvent(SocketEvent.joinCall.rawValue) { [weak self] data in
            guard let self = self,
                  !self.hasJoinedMeeting,
                  let callData = data.first as? [String: Any],
                  let meetingId = callData["id"] as? String,
                  let context = self.incomingContext,
                  context.meetingId == meetingId else {
                return
            }

            print("CallKitManager: join-call received for meeting \(meetingId), joining now")
            self.joinCallTimeoutWorkItem?.cancel()
            DispatchQueue.main.async {
                self.joinMeetingDirectly(context: context)
            }
        }
    }

    // MARK: - Report incoming

    func reportIncomingCall(callerName: String,
                            hasVideo: Bool = true,
                            handleValue: String? = nil,
                            meetingInfo: [String: Any]? = nil,
                            completion: (() -> Void)? = nil) {

        guard isCallKitAllowed else {
            print("CallKitManager: Skipping CallKit UI (China region)")
            completion?()
            return
        }
        let uuid = UUID()
        currentCallUUID = uuid
        if let meetingInfo = meetingInfo, let meetingId = meetingInfo["id"] as? String {
            incomingKind = .dyte(
                IncomingDyteCallContext(
                    meetingId: meetingId,
                    isVideo: hasVideo,
                    title: meetingInfo["title"] as? String,
                    rawPayload: meetingInfo
                )
            )
        }

        setupSocketListeners()
        reportCallKit(uuid: uuid, callerName: callerName, hasVideo: hasVideo, handleValue: handleValue, completion: completion)
    }

    /// - Parameter fromVoIP: VoIP must always `reportNewIncomingCall` (Apple) on this call stack.
    func reportIncomingAgoraCall(
        callerName: String,
        hasVideo: Bool,
        callId: String,
        call: AgoraCallDto? = nil,
        rawPayload: [String: Any] = [:],
        fromVoIP: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        guard isCallKitAllowed else {
            AppLogger.killCall("Skip CallKit UI (China region) callId=\(callId)")
            Task { @MainActor in
                guard UserDefaults.standard.bool(forKey: "isUserLogIn") else {
                    AppLogger.killCall("Skip in-app incoming — not logged in callId=\(callId)")
                    completion?()
                    return
                }
                self.routeInAppOrWaiting(
                    callId: callId,
                    hasVideo: hasVideo,
                    call: call,
                    payload: rawPayload
                )
            }
            completion?()
            return
        }

        // Deduplicate socket-background + VoIP for the same call.
        if reportedAgoraCallId == callId, currentCallUUID != nil {
            AppLogger.killCall("Dedup CallKit report callId=\(callId)")
            completion?()
            return
        }

        var payload = rawPayload
        if payload["callId"] == nil { payload["callId"] = callId }
        if payload["type"] == nil { payload["type"] = hasVideo ? "video" : "audio" }

        // Zip rule: only `.background` uses CallKit as primary UI.
        let appState = UIApplication.shared.applicationState
        let preferInApp = appState != .background
        let loggedIn = UserDefaults.standard.bool(forKey: "isUserLogIn")

        // —— Call-waiting FIRST (before any full CallKit report) ——
        if loggedIn, isInLiveOneVibeCall {
            handleIncomingWhileOnCall(
                fromVoIP: fromVoIP,
                callerName: callerName,
                hasVideo: hasVideo,
                callId: callId,
                call: call,
                payload: payload,
                completion: completion
            )
            return
        }

        // Foreground / inactive → same path as AppDelegate early-exit (silent + in-app).
        if preferInApp {
            if fromVoIP {
                handleForegroundVoIPIncoming(
                    callerName: callerName,
                    hasVideo: hasVideo,
                    callId: callId,
                    call: call,
                    payload: payload,
                    loggedIn: loggedIn,
                    completion: completion
                )
            } else {
                AppLogger.killCall(
                    "Prefer in-app incoming (non-VoIP) callId=\(callId) appState=\(appState.rawValue) loggedIn=\(loggedIn)"
                )
                completion?()
                Task { @MainActor in
                    guard loggedIn else {
                        AppLogger.killCall("Skip in-app incoming — not logged in callId=\(callId)")
                        return
                    }
                    self.routeInAppOrWaiting(
                        callId: callId,
                        hasVideo: hasVideo,
                        call: call,
                        payload: payload
                    )
                }
            }
            return
        }

        // —— Background / kill (zip path) — ONLY when NOT already on a call ——
        isCallWaitingReport = false
        reportedAgoraCallId = callId

        let uuid = UUID()
        currentCallUUID = uuid
        incomingKind = .agora(
            IncomingAgoraCallContext(
                callId: callId,
                isVideo: hasVideo,
                callerName: callerName,
                call: call,
                rawPayload: payload
            )
        )

        if loggedIn {
            PendingKillCallStore.save(payload: payload, callId: callId, callerName: callerName, hasVideo: hasVideo)
        }

        AppLogger.killCall(
            "Report CallKit agora callId=\(callId) caller=\(callerName) agoraVideo=\(hasVideo) uuid=\(uuid) appState=\(appState.rawValue) voip=\(fromVoIP) preferInApp=\(preferInApp) loggedIn=\(loggedIn)"
        )

        // Real media type for lock-screen Audio/Video label. Unlock is handled inside
        // reportCallKit (video seed + audio label) and again on CXAnswer.
        reportCallKit(uuid: uuid, callerName: callerName, hasVideo: hasVideo, handleValue: callerName) { [weak self] in
            // Zip: finish PushKit completion quickly after report — do not block on Agora seed.
            DispatchQueue.main.async {
                guard let self else {
                    completion?()
                    return
                }
                if !loggedIn {
                    AppLogger.killCall("Ending CallKit after report — logged out callId=\(callId)")
                    self.endCall(reason: .failed)
                }
                completion?()
            }
        }

        // Seed AFTER report is kicked off (parallel with report callback).
        Task { @MainActor in
            guard loggedIn else {
                AppLogger.killCall("Skip Agora seed — not logged in callId=\(callId)")
                return
            }
            let service = AgoraCallService.shared
            service.start()
            ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "callkit-incoming")

            // Safety net if live-flag raced: hide CallKit ASAP + in-app waiting only.
            if (service.phase == .active || service.phase == .outgoing),
               !service.matchesCallId(callId) {
                self.hasLiveAgoraCallSession = true
                self.isCallWaitingReport = false
                self.offerCallWaitingInApp(
                    callId: callId,
                    hasVideo: hasVideo,
                    callerName: callerName,
                    call: call,
                    payload: payload
                )
                // .failed dismisses native UI fastest.
                self.endCall(reason: .failed)
                AppLogger.killCall("Call-waiting safety net — force-hide CallKit callId=\(callId)")
                return
            }

            if service.phase == .incoming, !service.matchesCallId(callId) {
                service.rejectIncomingAsBusy(callId: callId)
                self.endCall(reason: .failed)
                AppLogger.killCall("Post-report busy (already ringing) callId=\(callId)")
                return
            }

            if service.phase == .idle, self.isOnExternalSystemCall {
                service.rejectIncomingAsBusy(callId: callId)
                self.endCall(reason: .failed)
                AppLogger.killCall("Post-report busy (system phone) callId=\(callId)")
                return
            }

            if let call {
                service.seedIncomingFromPush(call: call, takeCallKitOwnership: true)
            } else {
                _ = service.seedIncomingFromPushPayload(payload)
                service.adoptCallKitOwnership()
            }
            AppLogger.killCall(
                "Seeded Agora from CallKit report callId=\(callId) phase=\(String(describing: service.phase)) keepCallKit=true"
            )
        }
    }

    /// Satisfies PushKit (report) then ends in the same callback so CallKit UI never paints.
    /// Used for foreground VoIP and call-waiting — kill/background still uses full CallKit.
    private func fulfillVoIPPushWithoutShowingUI(
        callerName: String,
        hasVideo: Bool,
        completion: (() -> Void)?
    ) {
        let tempUUID = UUID()
        silentVoIPFulfillUUIDs.insert(tempUUID)
        isEndingFromApp = true
        // Do not touch currentCallUUID — keeps full CallKit path / endCall() isolated.
        _ = hasVideo // PushKit payload may be video; silent UI stays audio-looking to reduce chrome.

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName.isEmpty ? "OneVibe" : callerName)
        update.localizedCallerName = callerName.isEmpty ? "OneVibe" : callerName
        // Audio-looking update reduces full-screen video CallKit chrome during the tiny window.
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        provider.reportNewIncomingCall(with: tempUUID, update: update) { [weak self] error in
            guard let self else {
                completion?()
                return
            }
            if let error {
                AppLogger.killCall("Silent VoIP report FAILED: \(error.localizedDescription)")
            } else {
                AppLogger.killCall("Silent VoIP report OK uuid=\(tempUUID) — end sync (no UI)")
            }
            // End in the SAME callback before PushKit completion — critical to avoid ~1s flash.
            // .failed dismisses fastest; do not wait on CXEndCallAction.
            self.provider.reportCall(with: tempUUID, endedAt: nil, reason: .failed)
            completion?()

            let end = CXEndCallAction(call: tempUUID)
            self.callController.request(CXTransaction(action: end)) { _ in
                DispatchQueue.main.async {
                    self.silentVoIPFulfillUUIDs.remove(tempUUID)
                    self.isEndingFromApp = false
                    // Silent report can stop in-app ringtone — restore if still ringing.
                    AgoraCallService.shared.forceRestartInAppIncomingRingtone()
                }
            }
        }
    }

    /// Live OneVibe call (talking / dialing) — call-waiting must not show CallKit.
    var isInLiveOneVibeCall: Bool {
        hasLiveAgoraCallSession || hasJoinedMeeting
    }

    /// VoIP/FCM while already on A–B: in-app Accept/Decline only.
    /// VoIP still does a PushKit-required report that is ended in the same callback
    /// (cannot legally skip report — that breaks kill-state VoIP).
    func handleIncomingWhileOnCall(
        fromVoIP: Bool,
        callerName: String,
        hasVideo: Bool,
        callId: String,
        call: AgoraCallDto?,
        payload: [String: Any],
        completion: (() -> Void)? = nil
    ) {
        AppLogger.killCall(
            "handleIncomingWhileOnCall voip=\(fromVoIP) callId=\(callId) live=\(hasLiveAgoraCallSession) joined=\(hasJoinedMeeting)"
        )
        if fromVoIP {
            fulfillVoIPPushWithoutShowingUI(
                callerName: callerName,
                hasVideo: hasVideo,
                completion: completion
            )
        } else {
            completion?()
        }
        Task { @MainActor in
            self.offerCallWaitingInApp(
                callId: callId,
                hasVideo: hasVideo,
                callerName: callerName,
                call: call,
                payload: payload
            )
        }
    }

    /// Unexpected VoIP while app is foreground/inactive.
    /// Treat as a first-class ring path (socket may be slow on UAE → India). Show in-app immediately,
    /// then silent-fulfill PushKit so CallKit UI never paints.
    func handleForegroundVoIPIncoming(
        callerName: String,
        hasVideo: Bool,
        callId: String,
        call: AgoraCallDto?,
        payload: [String: Any],
        loggedIn: Bool,
        completion: (() -> Void)? = nil
    ) {
        var p = payload
        if p["callId"] == nil { p["callId"] = callId }
        if p["type"] == nil { p["type"] = hasVideo ? "video" : "audio" }

        AppLogger.killCall(
            "handleForegroundVoIPIncoming callId=\(callId) loggedIn=\(loggedIn) — in-app first, then silent PushKit fulfill"
        )

        // Show ring on this call stack before silent CallKit report (same-runloop, no 7–8s socket wait).
        if loggedIn {
            let present: @MainActor () -> Void = { [weak self] in
                guard let self else { return }
                let service = AgoraCallService.shared
                if service.isPresentingInAppIncoming, service.matchesCallId(callId) {
                    AppLogger.killCall("FG VoIP — in-app already up callId=\(callId)")
                    service.forceRestartInAppIncomingRingtone()
                    return
                }
                self.routeInAppOrWaiting(
                    callId: callId,
                    hasVideo: hasVideo,
                    call: call,
                    payload: p
                )
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated(present)
            } else {
                Task { @MainActor in present() }
            }
        }

        fulfillVoIPPushWithoutShowingUI(
            callerName: callerName,
            hasVideo: hasVideo,
            completion: completion
        )
    }

    /// Unexpected Dyte VoIP while app is foreground — satisfy PushKit without CallKit UI.
    func fulfillForegroundVoIPPush(
        callerName: String,
        hasVideo: Bool,
        completion: (() -> Void)? = nil
    ) {
        AppLogger.killCall("fulfillForegroundVoIPPush caller=\(callerName) — silent only (FG should skip VoIP)")
        fulfillVoIPPushWithoutShowingUI(
            callerName: callerName,
            hasVideo: hasVideo,
            completion: completion
        )
    }

    @MainActor
    private func offerCallWaitingInApp(
        callId: String,
        hasVideo: Bool,
        callerName: String,
        call: AgoraCallDto?,
        payload: [String: Any]
    ) {
        let service = AgoraCallService.shared
        service.start()
        if let call {
            service.offerPendingIncoming(call)
        } else if let decoded = Self.minimalCallDto(
            callId: callId,
            hasVideo: hasVideo,
            callerName: callerName,
            payload: payload
        ) {
            service.offerPendingIncoming(decoded)
        } else {
            routeInAppOrWaiting(
                callId: callId,
                hasVideo: hasVideo,
                call: call,
                payload: payload
            )
        }
    }

    @MainActor
    private func routeInAppOrWaiting(
        callId: String,
        hasVideo: Bool,
        call: AgoraCallDto?,
        payload: [String: Any]
    ) {
        let service = AgoraCallService.shared
        service.start()
        ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "in-app-incoming")

        // Already on a live OneVibe call → Accept/Decline banner (socket / FCM path).
        if (service.phase == .active || service.phase == .outgoing), !service.matchesCallId(callId) {
            if let call {
                service.offerPendingIncoming(call)
            } else if let decoded = Self.minimalCallDto(
                callId: callId,
                hasVideo: hasVideo,
                callerName: (payload["callerName"] as? String)
                    ?? (payload["caller"] as? String)
                    ?? "Incoming Call",
                payload: payload
            ) {
                service.offerPendingIncoming(decoded)
            }
            return
        }

        if service.isPresentingInAppIncoming, service.matchesCallId(callId) {
            AppLogger.killCall("Keep existing in-app incoming callId=\(callId)")
            // Silent VoIP / session flips can kill AVAudioPlayer — restart tone while UI stays up.
            service.forceRestartInAppIncomingRingtone()
            return
        }
        if let call {
            service.presentIncomingInApp(call: call)
        } else {
            var p = payload
            p["callId"] = callId
            if p["type"] == nil { p["type"] = hasVideo ? "video" : "audio" }
            _ = service.presentIncomingFromPushPayload(p)
        }
    }

    @MainActor
    private static func minimalCallDto(
        callId: String,
        hasVideo: Bool,
        callerName: String,
        payload: [String: Any]
    ) -> AgoraCallDto? {
        let conversationId = (payload["conversationId"] as? String)
            ?? (payload["conversation_id"] as? String)
            ?? ""
        let callerId = (payload["callerId"] as? String)
            ?? (payload["caller_id"] as? String)
            ?? ""
        let minimal: [String: Any] = [
            "id": callId,
            "conversationId": conversationId,
            "type": hasVideo ? "video" : "audio",
            "status": "ringing",
            "channelName": payload["channelName"] as? String ?? "",
            "callerId": callerId,
            "calleeId": payload["calleeId"] as? String ?? "",
            "appId": payload["appId"] as? String ?? ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: minimal),
              let decoded = try? JSONDecoder().decode(AgoraCallDto.self, from: data) else {
            return nil
        }
        return decoded
    }

    func isReportingAgoraCall(_ callId: String) -> Bool {
        guard currentCallUUID != nil, let reported = reportedAgoraCallId, !callId.isEmpty else { return false }
        return reported.caseInsensitiveCompare(callId) == .orderedSame
    }

    private func reportCallKit(
        uuid: UUID,
        callerName: String,
        hasVideo: Bool,
        handleValue: String?,
        completion: (() -> Void)?
    ) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handleValue ?? callerName)
        update.localizedCallerName = callerName
        // Always seed video so Answer can Face ID unlock + open the app (audio-only CallKit
        // stays on the lock screen). For audio we immediately retarget the subtitle to Audio.
        update.hasVideo = true
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error = error {
                AppLogger.killCall("reportNewIncomingCall FAILED: \(error.localizedDescription)")
                completion?()
                return
            }
            AppLogger.killCall(
                "reportNewIncomingCall OK caller=\(callerName) uuid=\(uuid) agoraVideo=\(hasVideo)"
            )
            if !hasVideo {
                // Let CallKit finish registering the video incoming (unlock entitlement),
                // then retarget subtitle to Audio for the lock-screen label.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self, self.currentCallUUID == uuid else { return }
                    let audioLabel = CXCallUpdate()
                    audioLabel.hasVideo = false
                    self.provider.reportCall(with: uuid, updated: audioLabel)
                    AppLogger.killCall("CallKit subtitle → Audio after video seed")
                }
            }
            completion?()
        }
    }

    /// Re-assert hasVideo before Answer fulfill so iOS unlocks / foregrounds for audio.
    private func boostCallKitUnlockIfAudio(for uuid: UUID) {
        let isAudio: Bool = {
            switch incomingKind {
            case .agora(let ctx): return !ctx.isVideo
            case .dyte(let ctx): return !ctx.isVideo
            case .none: return false
            }
        }()
        guard isAudio else { return }
        let update = CXCallUpdate()
        update.hasVideo = true
        provider.reportCall(with: uuid, updated: update)
        AppLogger.killCall("CallKit hasVideo=true boost for audio Answer unlock uuid=\(uuid)")
    }

    func endCall() {
        endCall(reason: .remoteEnded)
    }

    /// Dismisses Apple CallKit UI. Safe to call repeatedly.
    func endCall(reason: CXCallEndedReason) {
        guard isCallKitAllowed else {
            clearCallKitState()
            return
        }
        guard let uuid = currentCallUUID else {
            clearCallKitState()
            return
        }

        print("CallKitManager: Ending CallKit call \(uuid) reason=\(reason.rawValue)")

        isEndingFromApp = true
        endingFromAppUUIDs.insert(uuid)
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)

        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        callController.request(transaction) { [weak self] error in
            if let error {
                print("CallKitManager: CXEndCallAction request failed: \(error.localizedDescription)")
            } else {
                print("CallKitManager: CXEndCallAction requested")
            }
            DispatchQueue.main.async {
                // Keep `endingFromAppUUIDs` until `perform CXEndCallAction` consumes it —
                // clearing `isEndingFromApp` here alone used to race into hangUp after Answer.
                self?.clearCallKitState()
                self?.isEndingFromApp = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.currentCallUUID == uuid else { return }
            self.clearCallKitState()
            self.isEndingFromApp = false
            self.endingFromAppUUIDs.remove(uuid)
        }
    }

    private func clearCallKitState() {
        currentCallUUID = nil
        incomingKind = nil
        reportedAgoraCallId = nil
        isCallWaitingReport = false
        isJoining = false
        pendingCallKitHandoffUUID = nil
        // Do NOT clear hasJoinedMeeting / hasLiveAgoraCallSession here.
        // After Answer we dismiss CallKit while the Agora call stays live — clearing
        // those flags made the next VoIP take the full CallKit path (~1s flash).
        joinCallTimeoutWorkItem?.cancel()
        joinCallTimeoutWorkItem = nil
        if let id = dyteJoinCallListenerId {
            ChatSocketManager.shared.offEventById(id)
            dyteJoinCallListenerId = nil
        }
    }

    /// Call when the in-app Agora/Dyte session is fully idle again.
    func markCallSessionEnded() {
        hasJoinedMeeting = false
        hasLiveAgoraCallSession = false
    }

    func requestEndCall() {
        endCall(reason: .remoteEnded)
    }

    // MARK: - Answer

    func answerCall() {
        guard isCallKitAllowed else { return }
        guard let kind = incomingKind else {
            print("CallKitManager: No incoming context to join")
            return
        }
        if isJoining { return }
        isJoining = true

        switch kind {
        case .dyte(let context):
            answerDyte(context: context)
        case .agora(let context):
            answerAgora(context: context)
        }
    }

    private func answerDyte(context: IncomingDyteCallContext) {
        print("CallKitManager: Answering Dyte meeting \(context.meetingId)")
        print("CallKitManager: Sending accept-call signal with full payload")
        ChatSocketManager.shared.emitMessage(SocketEvent.acceptCall.rawValue, withData: [context.rawPayload])

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isJoining, self.incomingContext?.meetingId == context.meetingId else { return }
            print("CallKitManager: ⚠️ join-call timeout, falling back to direct join")
            self.joinMeetingDirectly(context: context)
        }
        joinCallTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: timeoutWorkItem)
    }

    private func answerAgora(context: IncomingAgoraCallContext) {
        AppLogger.killCall(
            "Answer tapped — Agora callId=\(context.callId) video=\(context.isVideo) waiting=\(isCallWaitingReport)"
        )
        let isWaiting = isCallWaitingReport
        Task { @MainActor in
            AgoraCallService.shared.start()
            ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "callkit-answer")

            // Third-person CallKit Answer → switch to pending call.
            if isWaiting {
                AppLogger.killCall("CallKit Answer → acceptPendingIncoming callId=\(context.callId)")
                if AgoraCallService.shared.pendingIncomingCall == nil {
                    if let call = context.call {
                        AgoraCallService.shared.offerPendingIncoming(call)
                    } else if let decoded = Self.minimalCallDto(
                        callId: context.callId,
                        hasVideo: context.isVideo,
                        callerName: context.callerName,
                        payload: context.rawPayload
                    ) {
                        AgoraCallService.shared.offerPendingIncoming(decoded)
                    }
                }
                await AgoraCallService.shared.acceptPendingIncoming()
                self.isJoining = false
                self.isCallWaitingReport = false
                let phase = AgoraCallService.shared.phase
                if phase == .active {
                    await self.finishAnswerHandoff(isVideo: context.isVideo)
                } else if self.currentCallUUID != nil {
                    AppLogger.killCall("Call-waiting answer incomplete phase=\(phase) — ending CallKit")
                    self.endCall(reason: .failed)
                }
                return
            }

            // Cold start: seed from CallKit context or persisted VoIP payload.
            if AgoraCallService.shared.phase == .idle {
                AppLogger.killCall("Answer while phase=idle — re-seeding from CallKit/pending store")
                if let call = context.call {
                    AgoraCallService.shared.seedIncomingFromPush(call: call)
                } else {
                    var payload = context.rawPayload
                    if payload.isEmpty, let stored = PendingKillCallStore.load()?.payload {
                        payload = stored
                    }
                    payload["callId"] = context.callId
                    payload["type"] = context.isVideo ? "video" : "audio"
                    let seeded = AgoraCallService.shared.seedIncomingFromPushPayload(payload)
                    AppLogger.killCall("Re-seed from payload success=\(seeded) keys=\(payload.keys.sorted())")
                }
            }

            await AgoraCallService.shared.handleCallKitAnswer()
            PendingKillCallStore.clear()
            self.isJoining = false

            let phase = AgoraCallService.shared.phase
            if phase == .active {
                // Video (or already unlocked): hand off now — Face ID already brought app forward.
                // Audio while locked/kill: keep CallKit until `.active`, then hand off like video.
                await self.finishAnswerHandoff(isVideo: context.isVideo)
            } else if self.currentCallUUID != nil {
                AppLogger.killCall("Agora answer incomplete phase=\(phase) — ending CallKit failed")
                self.hasJoinedMeeting = false
                self.endCall(reason: .failed)
            }
        }
    }

    /// After Answer succeeds: if app already unlocked/active → hand off now; else wait for unlock.
    @MainActor
    private func finishAnswerHandoff(isVideo: Bool) async {
        hasJoinedMeeting = true
        hasLiveAgoraCallSession = true

        // Ensure CallKit still advertises video so iOS completes Face ID unlock + app open
        // for audio answers (Agora media remains audio via context.isVideo).
        if let uuid = currentCallUUID, !isVideo {
            let update = CXCallUpdate()
            update.hasVideo = true
            provider.reportCall(with: uuid, updated: update)
            AppLogger.killCall("CallKit update hasVideo=true after audio Answer (force unlock/open)")
        }

        // Unlock / scene activation can lag a beat behind CXAnswer.
        for _ in 0..<8 {
            if UIApplication.shared.applicationState == .active { break }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        let appActive = UIApplication.shared.applicationState == .active
        if !appActive, let uuid = currentCallUUID {
            pendingCallKitHandoffUUID = uuid
            AppLogger.killCall(
                "Defer CallKit handoff until unlock/active — appState=\(UIApplication.shared.applicationState.rawValue) agoraVideo=\(isVideo)"
            )
            return
        }

        pendingCallKitHandoffUUID = nil
        await AgoraCallService.shared.prepareForCallKitHandoff()
        if currentCallUUID != nil {
            AppLogger.killCall("Handoff — dismiss CallKit after Agora owns audio/UI agoraVideo=\(isVideo)")
            endCall(reason: .answeredElsewhere)
        }
    }

    /// Called when app becomes active after a deferred locked-audio Answer (Face ID / unlock).
    @MainActor
    func completeDeferredCallKitHandoffIfNeeded() {
        guard let uuid = pendingCallKitHandoffUUID else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        guard currentCallUUID == uuid else {
            AppLogger.killCall("Deferred handoff drop — UUID mismatch")
            pendingCallKitHandoffUUID = nil
            return
        }
        let phase = AgoraCallService.shared.phase
        guard phase == .active || phase == .outgoing else {
            AppLogger.killCall("Deferred handoff drop — phase=\(phase)")
            pendingCallKitHandoffUUID = nil
            return
        }

        pendingCallKitHandoffUUID = nil
        AppLogger.killCall("Deferred handoff — app active, presenting UI + dismissing CallKit")
        Task { @MainActor in
            await AgoraCallService.shared.prepareForCallKitHandoff()
            if self.currentCallUUID == uuid {
                self.endCall(reason: .answeredElsewhere)
            }
        }
    }

    private func joinMeetingDirectly(context: IncomingDyteCallContext) {
        guard !hasJoinedMeeting else {
            print("CallKitManager: Already joining/joined meeting, skipping duplicate join")
            return
        }
        hasJoinedMeeting = true

        // Dyte meetings are not supported in FlirtTime; only Agora 1:1 calls are handled.
        AppLogger.debug("CallKitManager: ignoring Dyte meeting \(context.meetingId)")
        hasJoinedMeeting = false
        isJoining = false
        endCall()
    }

    private func topViewController(from root: UIViewController) -> UIViewController {
        if let nav = root as? UINavigationController { return topViewController(from: nav.visibleViewController ?? nav) }
        if let tab = root as? UITabBarController { return topViewController(from: tab.selectedViewController ?? tab) }
        if let presented = root.presentedViewController { return topViewController(from: presented) }
        return root
    }
}

extension CallKitManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        print("CallKitManager: Provider reset")
        clearCallKitState()
        isEndingFromApp = false
        endingFromAppUUIDs.removeAll()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        if silentVoIPFulfillUUIDs.contains(action.callUUID) {
            AppLogger.killCall("CXAnswerCallAction ignored — silent VoIP fulfill")
            action.fail()
            return
        }
        AppLogger.killCall("CXAnswerCallAction — fulfilling + joining Agora/Dyte waiting=\(isCallWaitingReport)")

        let isAudio: Bool = {
            switch incomingKind {
            case .agora(let ctx): return !ctx.isVideo
            case .dyte(let ctx): return !ctx.isVideo
            case .none: return false
            }
        }()

        // Before fulfill: audio must look like video to CallKit or Face ID / app-open won't run.
        if isAudio {
            boostCallKitUnlockIfAudio(for: action.callUUID)
        }
        answerCall()
        if isAudio {
            // Let CallKit apply hasVideo=true before Answer completes (unlock / foreground).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                action.fulfill()
            }
        } else {
            action.fulfill()
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let endingFromApp = isEndingFromApp || endingFromAppUUIDs.contains(action.callUUID)
        endingFromAppUUIDs.remove(action.callUUID)
        AppLogger.killCall("CXEndCallAction fromApp=\(endingFromApp) waiting=\(isCallWaitingReport)")

        // Silent call-waiting fulfill — must not hang up / decline the live Agora call.
        if silentVoIPFulfillUUIDs.contains(action.callUUID) {
            silentVoIPFulfillUUIDs.remove(action.callUUID)
            isEndingFromApp = false
            action.fulfill()
            return
        }

        let agoraCallId: String? = {
            if case .agora(let ctx) = incomingKind { return ctx.callId }
            return reportedAgoraCallId
        }()
        let wasCallWaiting = isCallWaitingReport

        if !endingFromApp {
            if wasCallWaiting {
                AppLogger.killCall("CXEndCallAction → declinePendingIncoming callId=\(agoraCallId ?? "?")")
                Task { @MainActor in
                    AgoraCallService.shared.declinePendingIncoming()
                }
            } else if let agoraCallId {
                Task { @MainActor in
                    AgoraCallService.shared.handleCallKitDeclineOrEnd(preferredCallId: agoraCallId)
                }
            }
        }

        PendingKillCallStore.clear()
        clearCallKitState()
        isEndingFromApp = false
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // Silent PushKit fulfill must not steal the in-app ringtone audio session.
        if !silentVoIPFulfillUUIDs.isEmpty {
            AppLogger.killCall("didActivate skipped — silent VoIP fulfill")
            Task { @MainActor in
                AgoraCallService.shared.forceRestartInAppIncomingRingtone()
            }
            return
        }
        let isVideo: Bool = {
            switch incomingKind {
            case .agora(let ctx): return ctx.isVideo
            case .dyte(let ctx): return ctx.isVideo
            case .none: return false
            }
        }()
        AppLogger.killCall("didActivate AVAudioSession video=\(isVideo)")
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: isVideo ? .videoChat : .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true)
        } catch {
            AppLogger.killCall("audio session activate failed: \(error.localizedDescription)")
        }
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        AppLogger.killCall("didDeactivate AVAudioSession")
        // If CallKit released audio but Agora is still live (e.g. after a prior
        // dismiss-on-answer path), reclaim so locked-screen audio does not die.
        Task { @MainActor in
            AgoraCallService.shared.reclaimAudioSessionIfCallActive()
        }
    }
}

// MARK: - Pending VoIP call (kill-state recovery)

enum PendingKillCallStore {
    private static let key = "pendingKillCall.v1"

    static func save(payload: [String: Any], callId: String, callerName: String, hasVideo: Bool) {
        var box: [String: Any] = [
            "callId": callId,
            "callerName": callerName,
            "hasVideo": hasVideo,
            "savedAt": Date().timeIntervalSince1970
        ]
        if JSONSerialization.isValidJSONObject(payload) {
            box["payload"] = payload
        }
        UserDefaults.standard.set(box, forKey: key)
        AppLogger.killCall("PendingKillCall saved callId=\(callId)")
    }

    static func load() -> (payload: [String: Any], callId: String, callerName: String, hasVideo: Bool)? {
        guard let box = UserDefaults.standard.dictionary(forKey: key) else { return nil }
        if let savedAt = box["savedAt"] as? TimeInterval, Date().timeIntervalSince1970 - savedAt > 90 {
            clear()
            return nil
        }
        let callId = box["callId"] as? String ?? ""
        guard !callId.isEmpty else { return nil }
        return (
            payload: box["payload"] as? [String: Any] ?? [:],
            callId: callId,
            callerName: box["callerName"] as? String ?? "Incoming Call",
            hasVideo: box["hasVideo"] as? Bool ?? false
        )
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
 
