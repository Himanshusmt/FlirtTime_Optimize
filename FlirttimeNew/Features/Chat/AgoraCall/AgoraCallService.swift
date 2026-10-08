//
//  AgoraCallService.swift
//  FlirttimeNew
//
//  Orchestrates call phases like onevibe_frontend-main CallProvider.
//

import Foundation
import UIKit
import AVFoundation
import AudioToolbox
import CallKit
import Swinject
import RxSwift
import AgoraRtcKit
import Combine
import Network

@MainActor
final class AgoraCallService: NSObject {

    static let shared = AgoraCallService()

    private(set) var phase: AgoraCallPhase = .idle {
        didSet {
            // Lets CallKit dismiss VoIP UI immediately during call-waiting (in-app popup only).
            CallKitManager.shared.hasLiveAgoraCallSession = (phase == .active || phase == .outgoing)
        }
    }
    private(set) var call: AgoraCallDto?
    private(set) var errorMessage: String?
    private(set) var muted = false
    private(set) var videoEnabled = true
    private(set) var speakerOn = true
    /// Current output: Speaker / Earpiece / Headphones / Bluetooth (control-bar icon).
    private(set) var audioRoute: AgoraCallAudioRoute = .speaker
    private(set) var isScreenSharing = false
    private(set) var elapsedSec = 0
    private(set) var hasRemoteVideo = false
    /// True for group-conversation calls (multi-party).
    private(set) var isGroupCall = false
    /// True if this device started the call (`call:create`). Owner hangup → `call:end` for everyone.
    private(set) var isCallOwner = false
    /// Fallback title (group name / peer name) before / when server DTO has none.
    private(set) var displayNameOverride: String?
    /// Peer/group avatar URL seeded from chat/profile so outgoing UI isn't blank while create ack loads.
    private(set) var avatarURLOverride: String?
    /// Remote Agora uids currently in the channel (for group grid UI).
    private(set) var remoteParticipantUids: [UInt] = []
    /// Uids that currently have remote video decoding.
    private(set) var remoteVideoUids: Set<UInt> = []
    /// Uids whose remote audio is muted (mic badge on grid tiles).
    private(set) var remoteMutedUids: Set<UInt> = []
    /// Only users who attended/joined the call (WhatsApp-style audio grid).
    private(set) var gridParticipants: [AgoraCallGridParticipant] = []
    /// After a non-owner leaves a group call, keep this until the creator ends the call.
    private(set) var rejoinableGroupCall: AgoraRejoinableGroupCall?
    /// Shown in call UI while Agora reconnects or a remote briefly drops (network blip).
    private(set) var connectionStatusText: String?
    /// True while local RTC connection is reconnecting.
    private(set) var isReconnecting = false
    /// Remote peer network quality for bars / Excellent–Poor label (active calls).
    private(set) var networkQualityLevel: AgoraCallNetworkQualityLevel = .unknown
    /// Whether the remote peer is ok / weak / unreachable (WhatsApp-style clarity).
    private(set) var peerNetworkState: AgoraPeerNetworkState = .ok
    /// True while a GSM / system call holds our audio session.
    private(set) var isAudioOnHold = false
    /// Video call but camera permission/hardware unavailable — stay on audio.
    private(set) var isCameraUnavailable = false
    /// Soft thermal warning banner.
    private(set) var thermalBannerText: String?
    /// Outgoing dial label: Calling… → Ringing… (before answer).
    private(set) var outgoingDialState: AgoraOutgoingDialState = .calling
    /// Second call while already on a call — Accept ends current / Decline keeps current (WhatsApp).
    private(set) var pendingIncomingCall: AgoraCallDto?
    /// Delay before showing "Reconnecting…" so brief Agora flaps don't flash the UI.
    private var reconnectStatusWork: DispatchWorkItem?
    private var reconnectedClearWork: DispatchWorkItem?
    private var lostConnectionWork: DispatchWorkItem?
    private var weakSignalWork: DispatchWorkItem?
    /// Debounce brief Agora freezes before showing peer-network UI on the other side.
    private var remoteUplinkUnstableWork: DispatchWorkItem?
    /// Soft-offline grace: upgrade Poor connection → Not in network after peer stays gone.
    private var remoteDropGraceBannerWork: DispatchWorkItem?
    /// Escalate sticky Poor → Not in network when peer uplink stays dead (before didOffline).
    private var peerNotInNetworkEscalateWork: DispatchWorkItem?
    /// End 1:1 ~20s after Not in network / didOffline; not reset by late didOffline.
    private var peerOfflineEndCallWork: DispatchWorkItem?
    /// First local outage (path down / RTC reconnecting). Not reset by NWPath flaps.
    private var localOutageBeganAt: Date?
    /// 1s tick — hang up once `localOutageBeganAt` is older than `localNetworkEndCallSeconds`.
    private var localNetworkEndCallTimer: Timer?
    /// Require path + RTC healthy for 2s before clearing the latched hangup clock.
    private var localOutageRecoverConfirmWork: DispatchWorkItem?
    /// True while hangup teardown is in flight — ignore RTC/path reconnect callbacks.
    private var isTearingDown = false
    /// Require sustained recovery before clearing Weak/Poor (avoids 1s Weak → Excellent flicker).
    private var remoteUplinkRecoverWork: DispatchWorkItem?
    /// True while primary remote media/quality indicates peer uplink trouble.
    private var isRemoteUplinkUnstable = false
    /// True when Poor connection / Not in network was set by peer-uplink detection (not local path).
    private var ownsRemoteUplinkBanner = false
    /// True when No internet / Reconnecting / Lost was set by local path or local RTC.
    private var ownsLocalConnectionBanner = false
    /// Last local Agora connection state — used to avoid false Reconnecting flashes.
    private var lastLocalRtcConnectionState: AgoraConnectionState = .disconnected
    /// Hysteresis: consecutive worse/better samples before changing displayed bars.
    private var qualityUpgradeCandidate: AgoraCallNetworkQualityLevel?
    private var qualityUpgradeStreak = 0
    private var lastQualityDisplayChangeAt: Date?
    private let qualityDisplayDwellSeconds: TimeInterval = 3
    private let qualityUpgradeStreakNeeded = 4
    private let qualityDowngradeStreakNeeded = 3
    /// Used to ignore stale `didOfflineOfUid` that arrives after the peer already recovered.
    private var lastRemoteUplinkHealthyAt: Date?
    /// True after callee device ack'd via `call:ringing`.
    private var didReceiveCalleeRingingAck = false
    /// `call:ringing` can beat `call:create:ack` when both users are online — buffer until we have callId.
    private var pendingRemoteRingingCallIds: Set<String> = []
    /// True if callee acked ringing without a parseable callId while we were still dialing.
    private var hasPendingRingingWithoutCallId = false
    /// Observes chat presence while outgoing so online callee can show Ringing… even if ack is delayed.
    private var outgoingPresenceCancellable: AnyCancellable?
    private var pathCancellable: AnyCancellable?
    private var lastMappedQuality: AgoraCallNetworkQualityLevel = .unknown
    /// Call-waiting vibration while a third-party incoming is pending (no CallKit ring / no ringtone).
    private var pendingIncomingHapticTimer: Timer?

    private let rtc = AgoraRtcManager()
    private var callId: String?
    private var callUI: AgoraCallViewController?
    /// Bumped on decline / hangup / dismiss so a late `present` after cut cannot leave a stuck call screen.
    private var callUIPresentGeneration: UInt = 0
    private var elapsedTimer: Timer?
    private var didStartListening = false
    private var ringtonePlayer: AVAudioPlayer?
    /// Loops system ring/dial cue while in-app ringing (fallback if custom files missing).
    private var ringtoneLoopTimer: Timer?
    private var ringtoneSoundID: SystemSoundID = 1005
    /// Which custom tone `startRingtone` last started (for resume after Agora audio-session flips).
    private var ringtoneIsIncoming: Bool?
    /// True while AudioServices system-sound loop is the active ringtone (no AVAudioPlayer).
    private var isUsingSystemSoundRingtone = false
    /// Restarts ring if CallKit silent-VoIP / session flips kill AVAudioPlayer after UI present.
    private var ringtoneWatchdogTimer: Timer?
    private var ringtoneInterruptionObserver: NSObjectProtocol?
    /// Short delayed resumes after start — covers CallKit silent-VoIP session steal before the 1s watchdog.
    private var ringtoneResumeRetryWorkItems: [DispatchWorkItem] = []
    /// WhatsApp-style vibrate pulse while in-app incoming is ringing (not call-waiting).
    private var incomingRingVibrateTimer: Timer?
    /// Per-uid grace timers — wait before removing a dropped member from a group grid.
    private var remoteDropGraceWorkItems: [UInt: DispatchWorkItem] = [:]
    /// How long to wait after Agora soft-offline before removing a member from a group grid.
    private let remoteDropGraceSeconds: TimeInterval = 30
    /// How long User A waits after "Not in network" / didOffline before ending 1:1.
    /// Agora typically reports peer media loss ~8–10s after B actually dropped; 20s remaining
    /// matches B's 30s local hangup on wall-clock.
    private let peerNotInNetworkEndCallSeconds: TimeInterval = 20
    /// Ignore brief Agora freeze/jitter while talking; only then show Poor.
    private let remoteUplinkFreezeConfirmSeconds: TimeInterval = 3.0
    /// After Poor, wait this long still frozen before "Not in network".
    private let peerNotInNetworkEscalateSeconds: TimeInterval = 8.0
    /// Brief Poor / freeze flap — wait this long of healthy media before clearing Weak.
    private let peerPoorRecoverSeconds: TimeInterval = 2.5
    /// Not in network is sticky — ignore Agora false recovery shorter than this.
    private let peerUnreachableRecoverSeconds: TimeInterval = 8.0
    /// How long local "No internet" can last before auto-ending the call (dialing or active).
    private let localNetworkEndCallSeconds: TimeInterval = 30
    /// Ignore late incoming if payload `createdAt` is older than this (caller already hung up).
    private static let maxIncomingRingAgeSeconds: TimeInterval = 45
    /// VoIP/FCM can arrive late on slow LTE — keep ringing longer than a live socket invite.
    private static let maxIncomingRingAgeFromPushSeconds: TimeInterval = 75
    /// True when this incoming was seeded from VoIP/FCM (use the slower stale window).
    private var incomingAllowsSlowPushAge = false
    private var isPrefetchingIncomingCredentials = false
    private var isRefreshingAgoraToken = false
    /// Delayed dismiss after showing "Call declined" / "Call ended" on the caller UI.
    private var remoteEndFeedbackWork: DispatchWorkItem?
    /// GET `/calls/{id}` while ringing — drops cancelled calls when callee was offline (late VoIP / missed `call:end`).
    private static let isCallLivenessRESTEnabled = true
    /// Poll GET calls/{id} while ringing — catches missed `call:declined` / `call:end` (CallKit + cold socket).
    private var callLivenessPollTimer: Timer?
    private var socketConnectObserver: NSObjectProtocol?
    /// Retry in-app call UI when unlock / foreground arrives after CallKit answer.
    private var appActiveObserver: NSObjectProtocol?
    /// When true, CallKit owns the ringing UI — do not show in-app overlay / ringtone.
    private(set) var isCallKitOwned = false
    /// Floating mini call window while user browses the app.
    private(set) var isPipActive = false
    /// Credentials from `call:create:ack` / REST — merged into later `call:join` if incomplete.
    private var pendingSession: AgoraCallSession?
    /// True after Agora channel join (may happen before UI phase becomes `.active`).
    private var didJoinRtc = false
    /// User IDs (or `agora_<uid>`) currently on the call — drives avatar grid.
    private var attendedUserIds: [String] = []
    /// Agora uid → attended key (userId / agora_uid).
    private var remoteUidToAttendeeKey: [UInt: String] = [:]
    /// Profile cache for lookup when someone joins (not shown until they attend).
    private var memberProfileCache: [String: (name: String, avatar: String?)] = [:]
    var meId: String {
        ChatAuthStore.shared.currentUser?.userId ?? ""
    }

    var callDisplayTitle: String {
        if let call {
            return call.displayTitle(relativeTo: meId, fallback: displayNameOverride)
        }
        return displayNameOverride ?? "Calling…"
    }

    /// Banner when the remote peer has dropped off the network (User A view of User B).
    private var peerNotInNetworkBannerText: String { "Not in network" }

    private var isPeerConnectionBanner: Bool {
        guard let text = connectionStatusText else { return false }
        return text == "Poor connection"
            || text == peerNotInNetworkBannerText
            || text.hasPrefix("Waiting for ")
    }

    /// 1:1 callee user id for presence checks while dialing out.
    var outgoingPeerUserId: String? {
        guard !isGroupCall, let call else { return nil }
        if !call.calleeId.isEmpty { return call.calleeId }
        if let id = call.callee?.id, !id.isEmpty { return id }
        if let id = call.peer(relativeTo: meId)?.id, !id.isEmpty { return id }
        return nil
    }

    /// True when the callee is in the live chat presence set.
    var isOutgoingPeerOnline: Bool {
        guard let peerId = outgoingPeerUserId, !peerId.isEmpty else { return false }
        return ChatListSocketService.shared.onlineUserIds.contains(where: {
            $0.caseInsensitiveCompare(peerId) == .orderedSame
        })
    }

    /// Resolve a remote Agora uid to a display name for video grid labels.
    func displayName(forRemoteUid uid: UInt) -> String {
        profile(forRemoteUid: uid).name
    }

    /// Name + avatar for WhatsApp-style video-off grid tiles.
    func profile(forRemoteUid uid: UInt) -> (name: String, avatarURL: String?) {
        guard let key = remoteUidToAttendeeKey[uid] else {
            return ("Participant", nil)
        }
        if let person = gridParticipants.first(where: { $0.userId == key }) {
            return (person.displayName, person.avatarURL)
        }
        if let cached = memberProfileCache[key] {
            return (cached.name, cached.avatar)
        }
        return ("Participant", nil)
    }

    /// Current user's avatar for local PiP / self tile when camera is off.
    var localAvatarURL: String? {
        if let selfPerson = gridParticipants.first(where: \.isSelf),
           let url = selfPerson.avatarURL, !url.isEmpty {
            return url
        }
        let sessionUser = Container.sharedContainer.resolve(SessionManager.self)?.user
        return sessionUser?.profilePictureDetails?.filePath
            ?? sessionUser?.profilePicture
    }

    /// Whether this remote uid is currently publishing camera / screen video.
    func hasRemoteVideo(uid: UInt) -> Bool {
        remoteVideoUids.contains(uid)
    }

    func isRemoteMuted(uid: UInt) -> Bool {
        remoteMutedUids.contains(uid)
    }

    /// Mute state for group audio avatar grid (self or remote by attended userId / agora key).
    func isMuted(userId: String) -> Bool {
        let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        if id.caseInsensitiveCompare(meId) == .orderedSame { return muted }
        if let uid = remoteUidToAttendeeKey.first(where: {
            $0.value.caseInsensitiveCompare(id) == .orderedSame
        })?.key {
            return remoteMutedUids.contains(uid)
        }
        return false
    }

    /// True while this service is already handling an incoming/outgoing/active call.
    var hasActiveCallSession: Bool {
        phase != .idle
    }

    /// Cellular / FaceTime / other system call — callers should see busy.
    var isOnSystemPhoneCall: Bool {
        CallKitManager.shared.isOnExternalSystemCall
    }

    var currentCallId: String? { callId }

    /// Zip-compatible: foreground / inactive → in-app. Background / kill → CallKit.
    var prefersInAppIncomingUI: Bool {
        CallKitManager.isAppInForeground
    }

    /// In-app ringing screen is already up (not CallKit-owned).
    var isPresentingInAppIncoming: Bool {
        phase == .incoming && !isCallKitOwned
    }

    func matchesCallId(_ other: String) -> Bool {
        guard let callId, !callId.isEmpty, !other.isEmpty else { return false }
        return callId.caseInsensitiveCompare(other) == .orderedSame
    }

    private override init() {
        super.init()
        rtc.delegate = self
    }

    // MARK: - Lifecycle

    func start() {
        // Always restore persisted joinable group call (survives app kill).
        restoreRejoinableGroupCallIfNeeded()

        guard !didStartListening else { return }
        didStartListening = true

        // Keep chat socket warm so incoming calls and outgoing emits work.
        ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "agora-call-service-start")

        AgoraCallSignaling.shared.onIncoming { [weak self] call in
            Task { @MainActor in
                self?.handleIncoming(call)
            }
        }
        AgoraCallSignaling.shared.onJoin { [weak self] session in
            Task { @MainActor in
                self?.handleJoin(session)
            }
        }
        AgoraCallSignaling.shared.onDeclined { [weak self] payload in
            Task { @MainActor in
                self?.handleLifecycleEnd(payload, fallback: .declined)
            }
        }
        AgoraCallSignaling.shared.onBusy { [weak self] payload in
            Task { @MainActor in
                self?.handleBusy(payload)
            }
        }
        AgoraCallSignaling.shared.onRejected { [weak self] payload in
            Task { @MainActor in
                self?.handleLifecycleEnd(payload, fallback: .rejected)
            }
        }
        AgoraCallSignaling.shared.onCancelled { [weak self] payload in
            Task { @MainActor in
                self?.handleCancelled(payload)
            }
        }
        AgoraCallSignaling.shared.onRinging { [weak self] callId in
            Task { @MainActor in
                self?.handleRemoteRinging(callId)
            }
        }
        AgoraCallSignaling.shared.onEndAck { [weak self] payload in
            Task { @MainActor in
                self?.handleEndAck(payload)
            }
        }
        // Other party hung up — server may emit `call:end` (not only `:ack`).
        AgoraCallSignaling.shared.onRemoteEnd { [weak self] payload in
            Task { @MainActor in
                self?.handleRemoteEnd(payload)
            }
        }
        AgoraCallSignaling.shared.onParticipantJoined { [weak self] callId, call, userId in
            Task { @MainActor in
                self?.handleParticipantJoined(callId: callId, call: call, userId: userId)
            }
        }
        AgoraCallSignaling.shared.onParticipantLeft { [weak self] payload in
            Task { @MainActor in
                self?.handleParticipantLeft(payload)
            }
        }

        if socketConnectObserver == nil {
            socketConnectObserver = NotificationCenter.default.addObserver(
                forName: .chatSocketDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.pollCallLiveness(reason: "socket-connect")
                    if self?.phase == .incoming, let callId = self?.callId, !callId.isEmpty {
                        self?.emitCalleeRingingIfNeeded(callId: callId)
                    }
                }
            }
        }

        if appActiveObserver == nil {
            appActiveObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.ensureCallUIVisibleAfterForeground()
                }
            }
        }
    }

    // MARK: - Public API

    func startOutgoing(
        conversationId: String,
        type: AgoraCallType,
        isGroup: Bool = false,
        displayName: String? = nil,
        avatarURL: String? = nil,
        groupMembers: [AgoraCallGridParticipant] = []
    ) async throws {
        start()
        guard phase == .idle else { throw AgoraCallError.notIdle }

        // Show ringing UI immediately with chat-seeded name/avatar (don't wait on socket).
        errorMessage = nil
        phase = .outgoing
        outgoingDialState = .calling
        didReceiveCalleeRingingAck = false
        pendingRemoteRingingCallIds.removeAll()
        hasPendingRingingWithoutCallId = false
        isGroupCall = isGroup
        isCallOwner = true
        displayNameOverride = displayName
        avatarURLOverride = avatarURL
        muted = false
        videoEnabled = (type == .video)
        // Loudspeaker while dialing so ringback + early Agora prejoin share one route.
        // Fighting speaker↔earpiece flashes the system volume HUD. enterActive applies earpiece for audio.
        speakerOn = true
        elapsedSec = 0
        hasRemoteVideo = false
        remoteParticipantUids = []
        remoteVideoUids = []
        remoteMutedUids = []
        pendingSession = nil
        didJoinRtc = false
        attendedUserIds = []
        remoteUidToAttendeeKey = [:]
        memberProfileCache = [:]
        gridParticipants = []
        CallInternationalDiagnostics.logSessionStart(reason: "outgoing-\(type.rawValue)")
        if isGroup {
            seedMemberProfileCache(from: groupMembers, conversationId: conversationId)
            // Only show yourself until others attend.
            markAttended(userId: meId, isSelf: true)
        }
        startCallPathMonitoring()
        presentCallUIIfNeeded()
        startRingtone(isIncoming: false)
        notifyUI()

        // Don't block dial on India socket handshake — create emit queues until connected.
        ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "outgoing-call")
        ChatSocketManager.shared.ensureConnecting()
        guard phase == .outgoing else { return }

        do {
            let session = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AgoraCallSession, Error>) in
                AgoraCallSignaling.shared.startCall(conversationId: conversationId, type: type) { result in
                    cont.resume(with: result)
                }
            }
            guard phase == .outgoing else { return }
            call = session.call
            callId = session.call.id
            isCallOwner = true
            pendingSession = session
            applyPendingRemoteRingingIfNeeded()
            if let peerId = outgoingPeerUserId, !peerId.isEmpty {
                ChatListSocketService.shared.subscribePresence(userIds: [peerId])
            }
            startOutgoingPresenceObservation()
            refreshOutgoingDialStateForPresence(reason: "create-ack")
            notifyUI()
            if session.call.resolvedIsGroup {
                isGroupCall = true
            }
            if let title = session.call.conversationTitle, !title.isEmpty {
                displayNameOverride = title
            }
            // Prefer server peer avatar when present; keep chat-seeded URL otherwise.
            if let peerPic = session.call.peer(relativeTo: meId)?.profilePicture, !peerPic.isEmpty {
                avatarURLOverride = peerPic
            }
            if isGroupCall {
                cacheProfilesFromCallDTO(session.call)
                seedMemberProfileCache(from: [], conversationId: session.call.conversationId.isEmpty ? conversationId : session.call.conversationId)
                markAttended(userId: meId, isSelf: true)
            }
            startCallLivenessPollingIfNeeded()
            notifyUI()

            // Join Agora as soon as create credentials arrive so Android/web can connect.
            // Group → active UI immediately. 1:1 → keep "Calling…" / "Ringing…" until call:join / remote uid.
            if session.hasJoinCredentials {
                prejoinRtc(session)
                if isGroupCall {
                    await enterActive(session)
                }
            }
        } catch {
            if phase == .outgoing {
                errorMessage = error.localizedDescription
                resetUi()
            }
            throw error
        }
    }

    func acceptIncoming() async {
        start()
        ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "agora-accept-incoming")

        // Never abort Answer because NWPath briefly looks unsatisfied — CallKit already ringing.
        // Recover from kill-state if CallKit answered before seed finished.
        if phase == .idle, let pending = PendingKillCallStore.load() {
            AppLogger.killCall("acceptIncoming recovering from PendingKillCall callId=\(pending.callId)")
            var payload = pending.payload
            payload["callId"] = pending.callId
            payload["type"] = pending.hasVideo ? "video" : "audio"
            _ = seedIncomingFromPushPayload(payload)
        }

        guard let callId, phase == .incoming else {
            AppLogger.killCall("acceptIncoming ABORT phase=\(phase) callId=\(callId ?? "nil")")
            return
        }
        AppLogger.killCall("acceptIncoming START callId=\(callId) — emit call:accept (socket may still be connecting)")
        // Answered — drop CallKit ringing ownership so we can present in-app canvases before join.
        isCallKitOwned = false
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            presentCallUIIfNeeded(animated: false) { [weak self] in
                self?.rebindRtcToFullScreenViews()
                cont.resume()
            }
        }
        guard phase == .incoming || phase == .active else { return }
        rtc.prepareLocalMedia(withVideo: videoEnabled, localView: callUI?.activeLocalVideoSurface)
        if let pending = pendingSession, pending.hasJoinCredentials {
            prejoinRtc(pending)
        }
        do {
            let session = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AgoraCallSession, Error>) in
                AgoraCallSignaling.shared.acceptCall(callId: callId) { result in
                    cont.resume(with: result)
                }
            }
            AppLogger.killCall("acceptIncoming ACK OK callId=\(callId) channel=\(session.call.channelName)")
            let merged = AgoraCallSession.merge(session, fallback: pendingSession)
            pendingSession = merged
            await enterActive(merged)
            PendingKillCallStore.clear()
        } catch {
            AppLogger.killCall("acceptIncoming FAILED: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            resetUi()
            CallKitManager.shared.endCall(reason: .failed)
        }
    }

    func declineIncoming(preferredCallId: String? = nil) {
        // Cancel any in-flight present immediately (before emit / reset).
        callUIPresentGeneration &+= 1
        stopRingtone()
        // Missed / declined group ring — keep Join banner while the room is still live.
        let rejoinSnapshot = makeRejoinableSnapshotForCurrentGroupCall()
        let id = preferredCallId ?? callId
        if let id, !id.isEmpty {
            AgoraCallSignaling.shared.declineCall(callId: id)
            AppLogger.killCall("declineIncoming emit callId=\(id)")
        } else {
            AppLogger.killCall("declineIncoming SKIPPED — no callId")
        }
        stopCallLivenessPolling()
        cleanupRtc()
        resetUi()
        CallKitManager.shared.endCall(reason: .declinedElsewhere)
        if let rejoinSnapshot {
            setRejoinableGroupCall(rejoinSnapshot)
        }
    }

    func hangUp() {
        // Cancel any in-flight present immediately (before emit / reset).
        callUIPresentGeneration &+= 1
        stopRingtone()
        // Non-owner leaving an active group call can rejoin while the creator keeps it alive.
        let rejoinSnapshot = makeRejoinableSnapshotIfLeaving()
        // Capture before resetUi — async emit must keep the id.
        let endingCallId = callId
        if let endingCallId, !endingCallId.isEmpty {
            // Call owner → call:end (sabki call band). Members → call:leave.
            if isGroupCall, phase == .active, !isCallOwner {
                AgoraCallSignaling.shared.leaveCall(callId: endingCallId)
                AppLogger.killCall("hangUp leaveCall callId=\(endingCallId)")
            } else {
                AgoraCallSignaling.shared.endCall(callId: endingCallId)
                AppLogger.killCall("hangUp endCall callId=\(endingCallId)")
                // Creator ended — nobody (including us) should see Rejoin for this call.
                clearRejoinableGroupCall(matchingCallId: endingCallId)
            }
        } else {
            AppLogger.killCall("hangUp SKIPPED emit — no callId phase=\(phase)")
        }
        stopCallLivenessPolling()
        cleanupRtc()
        resetUi()
        // Always tear down Apple CallKit (green bar / system call UI).
        CallKitManager.shared.endCall(reason: .remoteEnded)
        if let rejoinSnapshot {
            setRejoinableGroupCall(rejoinSnapshot)
        }
    }

    /// True when this conversation has a still-live group call the user can join/rejoin.
    func canRejoinGroupCall(conversationId: String) -> Bool {
        restoreRejoinableGroupCallIfNeeded()
        guard phase == .idle else { return false }
        return rejoinableInfo(for: conversationId) != nil
    }

    /// Ongoing group call for chat-list subtitle (does not require phase idle).
    func ongoingGroupCall(for conversationId: String) -> AgoraRejoinableGroupCall? {
        restoreRejoinableGroupCallIfNeeded(notify: false)
        return rejoinableInfo(for: conversationId)
    }

    func rejoinableInfo(for conversationId: String) -> AgoraRejoinableGroupCall? {
        guard !conversationId.isEmpty else { return nil }
        if let info = AgoraRejoinableGroupCallStore.load(conversationId: conversationId),
           !info.callId.isEmpty {
            return info
        }
        if let info = rejoinableGroupCall,
           info.conversationId == conversationId,
           !info.callId.isEmpty {
            return info
        }
        return nil
    }

    /// Chat open — restore from disk (no notify) and hide Join if server says call ended.
    func refreshRejoinableState(for conversationId: String) {
        restoreRejoinableGroupCallIfNeeded(notify: false)
        guard let info = rejoinableInfo(for: conversationId) else {
            // New members / cold open: no local ring history — pull `activeCall` from detail.
            fetchActiveCallFromConversationDetailIfNeeded(conversationId: conversationId)
            return
        }
        validateRejoinableGroupCallStillLive(info)
    }

    private var activeCallDetailFetchInFlight = Set<String>()
    /// Avoid re-hitting detail on every banner refresh when the server has no `activeCall`.
    private var activeCallDetailFetched = Set<String>()

    /// `GET chat/conversations/{id}` — used when Join store is empty (e.g. member added mid-call).
    private func fetchActiveCallFromConversationDetailIfNeeded(conversationId: String) {
        guard !conversationId.isEmpty else { return }
        guard rejoinableInfo(for: conversationId) == nil else { return }
        guard !activeCallDetailFetchInFlight.contains(conversationId) else { return }
        guard !activeCallDetailFetched.contains(conversationId) else { return }
        guard let session = Container.sharedContainer.resolve(SessionManager.self) else { return }

        activeCallDetailFetchInFlight.insert(conversationId)
        _ = session.getConversationDetail(conversationId: conversationId)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] chat in
                    guard let self else { return }
                    self.activeCallDetailFetchInFlight.remove(conversationId)
                    self.activeCallDetailFetched.insert(conversationId)
                    var row = chat
                    if row.id == nil || row.id?.isEmpty == true {
                        row.id = conversationId
                    }
                    if row.type == nil || row.type?.isEmpty == true {
                        row.type = "group"
                    }
                    AppLogger.debug(
                        "AgoraCallService: detail activeCall callId=\(row.activeCall?.resolvedCallId ?? "nil") live=\(row.activeCall?.isLive ?? false) conv=\(conversationId)"
                    )
                    self.syncOngoingGroupCalls(from: [row])
                },
                onFailure: { [weak self] error in
                    self?.activeCallDetailFetchInFlight.remove(conversationId)
                    AppLogger.debug(
                        "AgoraCallService: detail activeCall fetch failed conv=\(conversationId): \(error.localizedDescription)"
                    )
                }
            )
    }

    /// Apply `activeCall` from `GET chat/conversations` so list + Join banner stay in sync.
    func syncOngoingGroupCalls(from rows: [ChatMessageRow]) {
        restoreRejoinableGroupCallIfNeeded(notify: false)
        var changed = false
        for row in rows {
            guard row.isGroup, let convId = row.id, !convId.isEmpty else { continue }
            if let active = row.activeCall, active.isLive, !active.resolvedCallId.isEmpty {
                let info = AgoraRejoinableGroupCall(
                    callId: active.resolvedCallId,
                    conversationId: convId,
                    type: active.isVideo ? .video : .audio,
                    displayName: row.title,
                    groupMembers: []
                )
                let existing = AgoraRejoinableGroupCallStore.load(conversationId: convId)
                if existing?.callId != info.callId || existing?.type != info.type {
                    AgoraRejoinableGroupCallStore.save(info)
                    changed = true
                    AppLogger.debug(
                        "AgoraCallService: list activeCall upsert callId=\(info.callId) conv=\(convId)"
                    )
                }
            } else if row.activeCallKeyPresent {
                // API explicitly sent null / ended activeCall — hide list text + Join.
                if AgoraRejoinableGroupCallStore.load(conversationId: convId) != nil {
                    AgoraRejoinableGroupCallStore.remove(conversationId: convId)
                    if rejoinableGroupCall?.conversationId == convId {
                        rejoinableGroupCall = nil
                    }
                    changed = true
                    AppLogger.debug("AgoraCallService: list activeCall cleared conv=\(convId)")
                }
            }
            // Key omitted → leave client rejoin/socket state alone (older backends).
        }
        if let primary = AgoraRejoinableGroupCallStore.load() {
            rejoinableGroupCall = primary
        } else if rejoinableGroupCall != nil {
            rejoinableGroupCall = nil
            changed = true
        }
        if changed {
            NotificationCenter.default.post(name: .agoraGroupCallRejoinDidChange, object: nil)
        }
    }

    /// Rejoin a group call the user previously left (`call:accept` with stored callId).
    func rejoinGroupCall(conversationId: String) async throws {
        start()
        guard phase == .idle else { throw AgoraCallError.notIdle }
        guard let info = rejoinableInfo(for: conversationId) else {
            throw AgoraCallError.failed("No active group call to rejoin")
        }
        rejoinableGroupCall = info

        ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "agora-rejoin-group-call")

        errorMessage = nil
        phase = .outgoing
        outgoingDialState = .calling
        isGroupCall = true
        isCallOwner = false
        callId = info.callId
        displayNameOverride = info.displayName
        muted = false
        videoEnabled = (info.type == .video)
        speakerOn = (info.type == .video)
        elapsedSec = 0
        hasRemoteVideo = false
        remoteParticipantUids = []
        remoteVideoUids = []
        remoteMutedUids = []
        pendingSession = nil
        didJoinRtc = false
        attendedUserIds = []
        remoteUidToAttendeeKey = [:]
        memberProfileCache = [:]
        gridParticipants = []
        seedMemberProfileCache(from: info.groupMembers, conversationId: info.conversationId)
        markAttended(userId: meId, isSelf: true)
        presentCallUIIfNeeded()
        notifyUI()

        do {
            let session = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AgoraCallSession, Error>) in
                AgoraCallSignaling.shared.acceptCall(callId: info.callId) { result in
                    cont.resume(with: result)
                }
            }
            guard phase == .outgoing || phase == .active else { return }
            let merged = AgoraCallSession.merge(session, fallback: pendingSession)
            pendingSession = merged
            clearRejoinableGroupCall(matchingCallId: info.callId)
            await enterActive(merged)
        } catch {
            errorMessage = error.localizedDescription
            cleanupRtc()
            resetUi()
            // Keep Join if the call may still be live (network blip). Clear if server says it's gone.
            if Self.isCallGoneError(error) {
                clearRejoinableGroupCall(matchingCallId: info.callId)
            }
            throw error
        }
    }

    func toggleMute() {
        muted.toggle()
        rtc.setMuted(muted)
        notifyUI()
    }

    func toggleVideo() {
        guard call?.type == .video else { return }
        videoEnabled.toggle()
        rtc.setVideoEnabled(videoEnabled)
        notifyUI()
    }

    func toggleSpeaker() {
        speakerOn.toggle()
        rtc.setSpeakerOn(speakerOn)
        audioRoute = rtc.currentAudioRoute
        notifyUI()
    }

    /// Current WhatsApp sheet selection (checkmark source of truth).
    var selectedAudioOutput: AgoraCallAudioOutputChoice {
        rtc.selectedAudioOutput
    }

    /// True when Bluetooth / wired headset is available — show WhatsApp-style audio picker.
    var hasExternalAudioDevice: Bool {
        rtc.hasExternalAudioDevice
    }

    var externalAudioDeviceTitle: String {
        rtc.externalAudioDeviceTitle
    }

    func selectAudioOutput(_ choice: AgoraCallAudioOutputChoice) {
        rtc.selectAudioOutput(choice)
        speakerOn = rtc.isSpeakerOn
        audioRoute = rtc.currentAudioRoute
        notifyUI()
    }

    func flipCamera() {
        guard call?.type == .video, videoEnabled, !isScreenSharing else { return }
        rtc.switchCamera()
    }

    func toggleScreenShare() {
        guard phase == .active else { return }
        rtc.toggleScreenSharing()
    }

    // MARK: - Picture in Picture (in-app floating)

    /// Notification / deep-link navigation often dismisses the full-screen call VC.
    /// Shrink to floating PiP first so the call stays visible while the user browses.
    @discardableResult
    func minimizeToPipIfNeeded() -> Bool {
        guard phase == .active, !isPipActive else { return false }
        enterPictureInPicture()
        return true
    }

    /// Full-screen call was dismissed by tab switch / push navigation (not hang-up / intentional PiP).
    func handleCallUIDidDismissUnexpectedly(_ vc: AgoraCallViewController) {
        guard phase == .active, !isPipActive else {
            if callUI === vc {
                callUI = nil
            }
            return
        }
        // Keep `callUI` for the handoff thumbnail; `enterPictureInPicture` dismisses it.
        if callUI == nil {
            callUI = vc
        }
        AppLogger.debug("AgoraCallService: call UI dismissed while active — recovering to PiP")
        enterPictureInPicture()
    }

    func enterPictureInPicture() {
        guard phase == .active, !isPipActive else { return }
        isPipActive = true

        // Thumbnail of the live call — stays on top while canvases move to PiP.
        let thumbnail = Self.makeHandoffThumbnail(from: callUI?.view)

        AgoraCallPipWindowController.shared.show(service: self, startFullScreen: true)
        if let thumbnail {
            AgoraCallPipWindowController.shared.installHandoffCover(thumbnail)
        }
        AgoraCallPipWindowController.shared.overlay?.layoutIfNeeded()
        rebindRtcToPipViews()

        callUI?.view.isHidden = true
        dismissCallUI(animated: false)

        // One frame so PiP canvases can paint under the thumbnail, then shrink.
        DispatchQueue.main.async { [weak self] in
            AgoraCallPipWindowController.shared.animateShrinkToPip {
                self?.notifyUI()
            }
        }
    }

    func exitPictureInPicture() {
        guard isPipActive else { return }
        isPipActive = false

        presentCallUIIfNeeded(animated: false) { [weak self] in
            guard let self else {
                AgoraCallPipWindowController.shared.hide()
                return
            }
            guard self.phase == .active, !self.isPipActive, self.callUI != nil else {
                AgoraCallPipWindowController.shared.hide()
                return
            }
            if self.callUI?.presentingViewController == nil {
                self.callUI = nil
                AgoraCallPipWindowController.shared.hide()
                self.presentCallUIIfNeeded(animated: false) { [weak self] in
                    self?.finishExitPictureInPictureHandoff()
                }
                return
            }
            self.finishExitPictureInPictureHandoff()
        }
    }

    private func finishExitPictureInPictureHandoff() {
        guard phase == .active, !isPipActive, callUI != nil else {
            AgoraCallPipWindowController.shared.hide()
            return
        }

        // Full-screen VC ready under PiP, but video hidden until handoff.
        callUI?.view.isHidden = true
        callUI?.setVideoSurfacesAlpha(0)
        callUI?.view.setNeedsLayout()
        callUI?.view.layoutIfNeeded()
        callUI?.reloadFromService()
        callUI?.setVideoSurfacesAlpha(0)

        // Capture while PiP still has live Agora frames (after rebind, snapshots are often black).
        let earlyThumb = AgoraCallPipWindowController.shared.snapshotOverlay()
            ?? Self.makeHandoffThumbnail(from: AgoraCallPipWindowController.shared.overlay)

        AgoraCallPipWindowController.shared.animateExpandToFullScreen { [weak self] in
            guard let self else {
                AgoraCallPipWindowController.shared.hide()
                return
            }
            guard self.phase == .active, !self.isPipActive, let callView = self.callUI?.view else {
                AgoraCallPipWindowController.shared.hide()
                return
            }

            // Prefer a full-size freeze frame; fall back to the pre-expand PiP thumb.
            let fullThumb = AgoraCallPipWindowController.shared.snapshotOverlay()
                ?? Self.makeHandoffThumbnail(from: AgoraCallPipWindowController.shared.overlay)
                ?? earlyThumb
            if let fullThumb {
                AgoraCallPipWindowController.shared.installHandoffCover(fullThumb)
            }

            // Start full-screen video UNDER the thumbnail (invisible until painted).
            callView.isHidden = false
            self.callUI?.setVideoSurfacesAlpha(0)
            callView.layoutIfNeeded()
            self.rebindRtcToFullScreenViews(reloadChrome: false)
            self.callUI?.setVideoSurfacesAlpha(0)

            // Wait for Agora to paint behind the thumbnail, then hide cover → show video.
            DispatchQueue.main.async { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self else {
                        AgoraCallPipWindowController.shared.hide()
                        return
                    }
                    AgoraCallPipWindowController.shared.revealFullScreenHidingCover(
                        fadeInVideo: { [weak self] in
                            self?.callUI?.setVideoSurfacesAlpha(1)
                        },
                        completion: { [weak self] in
                            self?.callUI?.setVideoSurfacesAlpha(1)
                            self?.callUI?.updateElapsedDisplay()
                        }
                    )
                }
            }
        }
    }

    /// Still-frame cover for PiP handoff (UIView snapshot, with image-render fallback).
    private static func makeHandoffThumbnail(from view: UIView?) -> UIView? {
        guard let view, view.bounds.width > 1, view.bounds.height > 1 else { return nil }
        view.layoutIfNeeded()
        if let snap = view.snapshotView(afterScreenUpdates: false) {
            return snap
        }
        if let snap = view.snapshotView(afterScreenUpdates: true) {
            return snap
        }
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { ctx in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        let imageView = UIImageView(image: image)
        imageView.frame = view.bounds
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        return imageView
    }

    private func rebindRtcToPipViews() {
        guard let overlay = AgoraCallPipWindowController.shared.overlay else { return }
        // While screen sharing, keep canvases detached (avoids freeze + lets user browse/share other apps).
        if isScreenSharing {
            rtc.detachAllVideoCanvases()
            return
        }
        let isVideo = call?.type == .video
        guard isVideo else { return }

        rtc.bindLocalVideo(to: overlay.localVideoView)
        // Group with 2+ remotes → WhatsApp mini grid (all remotes). Else single remote surface.
        if isGroupCall, remoteParticipantUids.count > 1 {
            overlay.syncRemoteVideoTiles(uids: remoteParticipantUids, binder: { [weak self] uid, view in
                self?.rtc.bindRemoteVideo(to: view, uid: uid)
            })
        } else if let uid = remoteParticipantUids.first ?? rtc.remoteUid {
            rtc.bindRemoteVideo(to: overlay.remoteVideoView, uid: uid)
        }
        // Avoid full overlay.reload() here — it re-layouts the mini-grid and flashes remotes.
        overlay.refreshTileMetadataOnly()
    }

    private func rebindRtcToFullScreenViews(reloadChrome: Bool = true) {
        guard let ui = callUI else { return }
        if isScreenSharing {
            rtc.detachAllVideoCanvases()
            return
        }
        let isVideo = call?.type == .video
        if isVideo {
            // Sync remotes (+ embed self when remotes ≥ 3) before binding local canvas.
            ui.syncRemoteVideoTiles(
                uids: remoteParticipantUids,
                binder: { [weak self] uid, view in
                    self?.rtc.bindRemoteVideo(to: view, uid: uid)
                },
                reloadChromeIfNeeded: reloadChrome
            )
            // Respect WhatsApp-style 1:1 tap-to-swap and group grid embedding.
            rtc.bindLocalVideo(to: ui.activeLocalVideoSurface)
        }
    }

    /// Re-apply local/remote canvases after the call UI swaps full-screen ↔ PiP.
    func rebindActiveCallVideoSurfaces() {
        guard !isPipActive else { return }
        rebindRtcToFullScreenViews()
    }

    /// Bind local preview to the current full-screen target (PiP, swap surface, or grid tile).
    func bindLocalToActiveCallSurface() {
        guard call?.type == .video, videoEnabled, !isScreenSharing else { return }
        if isPipActive {
            guard let overlay = AgoraCallPipWindowController.shared.overlay else { return }
            rtc.bindLocalVideo(to: overlay.localVideoView)
            return
        }
        guard let ui = callUI else { return }
        rtc.bindLocalVideo(to: ui.activeLocalVideoSurface)
    }

    /// Bind a remote tile created by the call UI for a newly joined participant.
    func bindRemoteVideoView(_ view: UIView, uid: UInt) {
        rtc.bindRemoteVideo(to: view, uid: uid)
    }

    // MARK: - CallKit / killed-app entry points

    /// CallKit is showing the system incoming UI — hide any in-app call UI / ringtone.
    func adoptCallKitOwnership() {
        isCallKitOwned = true
        stopRingtone()
        dismissCallUI()
        notifyUI()
    }

    /// Seed incoming state from a VoIP/FCM push so CallKit answer can call `acceptIncoming()`.
    /// - Parameter takeCallKitOwnership: false when foreground keeps the in-app ringing UI.
    func seedIncomingFromPush(call: AgoraCallDto, takeCallKitOwnership: Bool = true) {
        start()
        if shouldSuppressStaleOrEndedIncoming(call, allowSlowPush: true) {
            suppressStaleOrEndedIncoming(callId: call.id, reason: "seedIncoming")
            return
        }
        if phase == .idle, isOnSystemPhoneCall {
            AppLogger.killCall("seedIncoming busy — on system/cellular call new=\(call.id)")
            rejectIncomingAsBusy(callId: call.id)
            return
        }
        guard phase == .idle || matchesCallId(call.id) else {
            AppLogger.killCall("seedIncoming skip — phase=\(phase) existing=\(callId ?? "nil") new=\(call.id)")
            if !matchesCallId(call.id) {
                if isOnSystemPhoneCall || phase == .incoming {
                    rejectIncomingAsBusy(callId: call.id)
                } else {
                    offerPendingIncoming(call)
                }
            }
            return
        }
        // Already ringing in-app for this call — do not steal UI for CallKit in foreground.
        if matchesCallId(call.id), phase == .incoming {
            if takeCallKitOwnership, !prefersInAppIncomingUI {
                adoptCallKitOwnership()
            }
            AppLogger.killCall(
                "seedIncoming already ringing callId=\(call.id) takeCallKit=\(takeCallKitOwnership) inApp=\(isPresentingInAppIncoming)"
            )
            emitCalleeRingingIfNeeded(callId: call.id)
            return
        }
        self.call = call
        callId = call.id
        phase = .incoming
        isCallOwner = false
        isGroupCall = call.resolvedIsGroup || isGroupCall
        if let title = call.conversationTitle, !title.isEmpty {
            displayNameOverride = title
        }
        applyLocalConversationHints(for: call)
        videoEnabled = (call.type == .video)
        muted = false
        speakerOn = (call.type == .video)
        hasRemoteVideo = false
        remoteParticipantUids = []
        remoteVideoUids = []
        remoteMutedUids = []
        attendedUserIds = []
        remoteUidToAttendeeKey = [:]
        gridParticipants = []
        if takeCallKitOwnership {
            adoptCallKitOwnership()
        } else {
            isCallKitOwned = false
        }
        incomingAllowsSlowPushAge = true
        prefetchIncomingJoinCredentials(callId: call.id)
        // Group ring — remember so miss / kill during ring still offers Join.
        if isGroupCall {
            rememberJoinableGroupCall(from: call)
        }
        startCallLivenessPollingIfNeeded()
        syncIdleTimerDisabled()
        startCallPathMonitoring()
        AppLogger.killCall(
            "seedIncoming OK callId=\(call.id) type=\(call.type.rawValue) conv=\(call.conversationId) callKitOwned=\(takeCallKitOwnership)"
        )
        CallInternationalDiagnostics.noteIncomingPresented(
            source: takeCallKitOwnership ? "push-callkit" : "push-inapp",
            callId: call.id
        )
        emitCalleeRingingIfNeeded(callId: call.id)
    }

    /// Seed from a raw VoIP dictionary when full CallDto decoding isn't available.
    /// Supports backend flat payload: `type=incoming_call` + `callType=audio|video`.
    @discardableResult
    func seedIncomingFromPushPayload(_ payload: [String: Any]) -> Bool {
        if let callDict = payload["call"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: callDict),
           let decoded = try? JSONDecoder().decode(AgoraCallDto.self, from: data) {
            seedIncomingFromPush(call: decoded)
            return true
        }

        let callId = (payload["callId"] as? String)
            ?? (payload["call_id"] as? String)
            ?? (payload["id"] as? String)
            ?? ""
        guard !callId.isEmpty else {
            AppLogger.killCall("seedIncomingFromPushPayload FAILED — no callId keys=\(payload.keys.sorted())")
            return false
        }

        // Prefer callType — `type` is often the event name "incoming_call", not media.
        let mediaType = Self.mediaCallType(fromFlatPush: payload)
        let conversationId = (payload["conversationId"] as? String)
            ?? (payload["conversation_id"] as? String)
            ?? ""
        let callerId = (payload["callerId"] as? String)
            ?? (payload["caller_id"] as? String)
            ?? ""
        let callerName = (payload["callerName"] as? String)
            ?? (payload["caller"] as? String)
            ?? ""
        let callerAvatar = (payload["callerAvatar"] as? String)
            ?? (payload["caller_avatar"] as? String)
            ?? ""
        let conversationTitle = (payload["conversationTitle"] as? String)
            ?? (payload["conversation_title"] as? String)
            ?? (payload["title"] as? String)
        let conversationType = ((payload["conversationType"] as? String)
            ?? (payload["conversation_type"] as? String)
            ?? "").lowercased()
        let isGroup = (payload["isGroup"] as? Bool)
            ?? (conversationType == "group" || conversationType == "group_call")

        var minimal: [String: Any] = [
            "id": callId,
            "conversationId": conversationId,
            "type": mediaType.rawValue,
            "status": "ringing",
            "channelName": payload["channelName"] as? String
                ?? payload["channel_name"] as? String
                ?? "",
            "callerId": callerId,
            "calleeId": payload["calleeId"] as? String
                ?? payload["callee_id"] as? String
                ?? "",
            "appId": payload["appId"] as? String ?? payload["app_id"] as? String ?? "",
            "isGroup": isGroup
        ]
        // Prefer server status when present (late VoIP after caller cancelled).
        if let status = (payload["status"] as? String) ?? (payload["callStatus"] as? String),
           !status.isEmpty {
            minimal["status"] = status
        }
        if let createdAt = (payload["createdAt"] as? String) ?? (payload["created_at"] as? String),
           !createdAt.isEmpty {
            minimal["createdAt"] = createdAt
        } else if let createdAtNum = payload["createdAt"] as? Double {
            minimal["createdAt"] = String(createdAtNum)
        } else if let createdAtNum = payload["created_at"] as? Double {
            minimal["createdAt"] = String(createdAtNum)
        }
        if let endedAt = (payload["endedAt"] as? String) ?? (payload["ended_at"] as? String),
           !endedAt.isEmpty {
            minimal["endedAt"] = endedAt
        }
        if let conversationTitle, !conversationTitle.isEmpty {
            minimal["conversationTitle"] = conversationTitle
        }
        if !conversationType.isEmpty {
            minimal["conversationType"] = conversationType
        }
        if !callerId.isEmpty || !callerName.isEmpty {
            var caller: [String: Any] = ["id": callerId]
            if !callerName.isEmpty { caller["fullName"] = callerName }
            if !callerAvatar.isEmpty { caller["profilePicture"] = callerAvatar }
            minimal["caller"] = caller
        }

        guard let data = try? JSONSerialization.data(withJSONObject: minimal),
              let decoded = try? JSONDecoder().decode(AgoraCallDto.self, from: data) else {
            AppLogger.killCall("seedIncomingFromPushPayload decode FAILED callId=\(callId)")
            return false
        }
        AppLogger.killCall(
            "seedIncomingFromPushPayload OK callId=\(callId) media=\(mediaType.rawValue) conv=\(conversationId) group=\(isGroup)"
        )
        seedIncomingFromPush(call: decoded)
        return true
    }

    private static func mediaCallType(fromFlatPush payload: [String: Any]) -> AgoraCallType {
        if let callType = payload["callType"] as? String {
            return callType.lowercased().contains("video") ? .video : .audio
        }
        if let callType = payload["call_type"] as? String {
            return callType.lowercased().contains("video") ? .video : .audio
        }
        let type = (payload["type"] as? String ?? "").lowercased()
        if type.contains("video") { return .video }
        if type == "audio" || type.contains("audio") || type.contains("voice") { return .audio }
        return .audio
    }

    /// Foreground fallback: show in-app incoming UI (no CallKit).
    func presentIncomingInApp(call: AgoraCallDto) {
        start()
        if shouldSuppressStaleOrEndedIncoming(call) {
            suppressStaleOrEndedIncoming(callId: call.id, reason: "presentIncomingInApp")
            return
        }
        if phase == .idle, isOnSystemPhoneCall {
            AppLogger.killCall("presentIncomingInApp busy — on system/cellular call new=\(call.id)")
            rejectIncomingAsBusy(callId: call.id)
            return
        }
        guard phase == .idle || callId == call.id else {
            if !matchesCallId(call.id) {
                if isOnSystemPhoneCall || phase == .incoming {
                    rejectIncomingAsBusy(callId: call.id)
                } else {
                    offerPendingIncoming(call)
                }
            }
            return
        }
        isCallKitOwned = false
        self.call = call
        callId = call.id
        phase = .incoming
        isCallOwner = false
        isGroupCall = call.resolvedIsGroup || isGroupCall
        if let title = call.conversationTitle, !title.isEmpty {
            displayNameOverride = title
        }
        applyLocalConversationHints(for: call)
        videoEnabled = (call.type == .video)
        muted = false
        speakerOn = (call.type == .video)
        hasRemoteVideo = false
        remoteParticipantUids = []
        remoteVideoUids = []
        remoteMutedUids = []
        attendedUserIds = []
        remoteUidToAttendeeKey = [:]
        // Incoming ring: show caller only (they started / are on the call).
        if isGroupCall {
            let callerId = call.callerId.isEmpty ? (call.caller?.id ?? "") : call.callerId
            if !callerId.isEmpty {
                markAttended(userId: callerId)
            }
        } else {
            gridParticipants = []
        }
        startRingtone(isIncoming: true)
        CallInternationalDiagnostics.noteIncomingPresented(source: "in-app", callId: call.id)
        // Present can race with:
        // 1) FG VoIP silent-CallKit session steal
        // 2) Home/Reels/Explore viewWillDisappear → STOP_REELS_AUDIO
        // 3) User decline/hangup before present finishes (must not re-show idle UI)
        let presentGeneration = callUIPresentGeneration
        presentCallUIIfNeeded { [weak self] in
            guard let self else { return }
            guard self.callUIPresentGeneration == presentGeneration else { return }
            guard self.phase == .incoming else { return }
            // Soft reclaim only — forceRestart would cut a healthy loop (~1s audible restart).
            self.resumeRingtoneIfNeeded()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.callUIPresentGeneration == presentGeneration else { return }
                guard self.phase == .incoming else { return }
                self.resumeRingtoneIfNeeded()
            }
            self.ringtoneResumeRetryWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        startCallLivenessPollingIfNeeded()
        startCallPathMonitoring()
        prefetchIncomingJoinCredentials(callId: call.id)
        notifyUI()
        // Group ring — remember so miss / kill during ring still offers Join.
        if isGroupCall {
            rememberJoinableGroupCall(from: call)
        }
        emitCalleeRingingIfNeeded(callId: call.id)
    }

    /// CallKit / PushKit may flip AVAudioSession while in-app is already ringing — restart tone.
    func resumeInAppRingtoneIfNeeded() {
        resumeRingtoneIfNeeded()
    }

    /// Stronger than soft resume — used after silent VoIP CallKit end. Does not change CallKit/BG routing.
    /// If the in-app tone is already looping, only soft-reclaim (hard restart causes ~1s audible cut).
    func forceRestartInAppIncomingRingtone() {
        guard phase == .incoming, !isCallKitOwned, pendingIncomingCall == nil else { return }
        if isRingtoneHealthy(isIncoming: true) {
            AppLogger.killCall("forceRestart skipped — ringtone already healthy callId=\(callId ?? "nil")")
            return
        }
        if let player = ringtonePlayer, player.isPlaying {
            AppLogger.killCall("forceRestart → soft resume (still playing) callId=\(callId ?? "nil")")
            resumeRingtoneIfNeeded()
            return
        }
        AppLogger.killCall("forceRestartInAppIncomingRingtone callId=\(callId ?? "nil")")
        startRingtone(isIncoming: true, scheduleResumeRetries: true)
    }

    /// Foreground: seed from push dict and show in-app UI (never CallKit).
    @discardableResult
    func presentIncomingFromPushPayload(_ payload: [String: Any]) -> Bool {
        if let callDict = payload["call"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: callDict),
           let decoded = try? JSONDecoder().decode(AgoraCallDto.self, from: data) {
            presentIncomingInApp(call: decoded)
            return true
        }

        let id = (payload["callId"] as? String) ?? (payload["id"] as? String) ?? ""
        guard !id.isEmpty else { return false }
        let typeRaw = (payload["type"] as? String) ?? (payload["callType"] as? String) ?? "audio"
        let normalizedType = typeRaw.lowercased().contains("video") ? "video" : "audio"
        let minimal: [String: Any] = [
            "id": id,
            "conversationId": payload["conversationId"] as? String ?? "",
            "type": normalizedType,
            "status": "ringing",
            "channelName": payload["channelName"] as? String ?? "",
            "callerId": payload["callerId"] as? String ?? "",
            "calleeId": payload["calleeId"] as? String ?? "",
            "appId": payload["appId"] as? String ?? ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: minimal),
              let decoded = try? JSONDecoder().decode(AgoraCallDto.self, from: data) else {
            return false
        }
        presentIncomingInApp(call: decoded)
        return true
    }

    func handleCallKitAnswer() async {
        // Answered via CallKit — show in-app active call UI after accept.
        AppLogger.killCall("handleCallKitAnswer phase=\(phase) callId=\(callId ?? "nil")")
        isCallKitOwned = false
        await acceptIncoming()
    }

    /// Claim audio + present in-app UI before CallKit is dismissed (lock-screen Answer handoff).
    func prepareForCallKitHandoff() async {
        guard phase == .active || phase == .outgoing else { return }
        isCallKitOwned = false
        AppLogger.killCall("prepareForCallKitHandoff phase=\(phase) callUI=\(callUI != nil)")
        presentCallUIIfNeeded()
        // Own the session before CallKit tears it down on End.
        rtc.recoverAudioSessionAfterInterrupt()
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard phase == .active || phase == .outgoing else { return }
        rtc.recoverAudioSessionAfterInterrupt()
        // Window may not exist yet while locked — foreground observer retries.
        if callUI == nil {
            presentCallUIIfNeeded()
        }
    }

    /// CallKit released the audio session — reclaim if our Agora call is still live.
    func reclaimAudioSessionIfCallActive() {
        guard phase == .active || phase == .outgoing else { return }
        AppLogger.killCall("reclaimAudioSessionIfCallActive phase=\(phase)")
        rtc.recoverAudioSessionAfterInterrupt()
    }

    /// After unlock / foreground — present call UI if CallKit answer ran while backgrounded.
    func ensureCallUIVisibleAfterForeground() {
        guard phase == .active || phase == .outgoing || phase == .incoming else {
            CallKitManager.shared.completeDeferredCallKitHandoffIfNeeded()
            return
        }
        if isCallKitOwned, phase == .incoming {
            CallKitManager.shared.completeDeferredCallKitHandoffIfNeeded()
            return
        }
        if isPipActive {
            CallKitManager.shared.completeDeferredCallKitHandoffIfNeeded()
            return
        }
        if callUI == nil {
            AppLogger.killCall("ensureCallUIVisibleAfterForeground — presenting phase=\(phase)")
            presentCallUIIfNeeded()
        }
        if phase == .active || phase == .outgoing {
            rtc.recoverAudioSessionAfterInterrupt()
        }
        // Locked-audio Answer kept CallKit until Face ID / unlock — finish handoff like video.
        CallKitManager.shared.completeDeferredCallKitHandoffIfNeeded()
    }

    /// CallKit End/Decline. `preferredCallId` covers cold-start before `seedIncoming` finishes.
    func handleCallKitDeclineOrEnd(preferredCallId: String? = nil) {
        if let preferredCallId, !preferredCallId.isEmpty, callId == nil {
            callId = preferredCallId
        }
        AppLogger.killCall(
            "handleCallKitDeclineOrEnd phase=\(phase) callId=\(callId ?? "nil") preferred=\(preferredCallId ?? "nil")"
        )
        switch phase {
        case .incoming:
            declineIncoming(preferredCallId: preferredCallId)
        case .outgoing, .active:
            // Outgoing cancel / active hangup must emit `call:end`, not `call:decline`.
            hangUp()
        case .idle:
            // Seed still in-flight — decline with CallKit's id so caller stops ringing.
            if let id = preferredCallId ?? callId, !id.isEmpty {
                AgoraCallSignaling.shared.declineCall(callId: id)
            }
            stopCallLivenessPolling()
            resetUi()
            CallKitManager.shared.endCall(reason: .declinedElsewhere)
        }
    }

    /// Background → CallKit. Foreground (user inside the app) → in-app only.
    private func shouldUseCallKitForIncoming() -> Bool {
        !prefersInAppIncomingUI
    }

    // MARK: - Socket handlers

    private func handleIncoming(_ incoming: AgoraCallDto) {
        // Caller already cancelled while we were offline — don't ring on late socket/push.
        if shouldSuppressStaleOrEndedIncoming(incoming, allowSlowPush: incomingAllowsSlowPushAge) {
            suppressStaleOrEndedIncoming(callId: incoming.id, reason: "handleIncoming")
            return
        }

        // Already ringing / active for this (or another) call.
        if phase != .idle {
            if callId == incoming.id, isCallKitOwned {
                emitCalleeRingingIfNeeded(callId: incoming.id)
                adoptCallKitOwnership()
                return
            }
            if matchesCallId(incoming.id) {
                emitCalleeRingingIfNeeded(callId: incoming.id)
                return
            }

            // Cellular / FaceTime — still auto-busy.
            if isOnSystemPhoneCall {
                AppLogger.killCall("handleIncoming busy — on system/cellular call new=\(incoming.id)")
                rejectIncomingAsBusy(callId: incoming.id)
                return
            }

            // Already on an incoming ring for someone else — can't show two full ring UIs.
            if phase == .incoming {
                rejectIncomingAsBusy(callId: incoming.id)
                return
            }

            // Outgoing / active (1:1 or group) — WhatsApp Accept / Decline switch.
            offerPendingIncoming(incoming)
            return
        }

        // On cellular / FaceTime — do not ring Agora; caller sees busy.
        if isOnSystemPhoneCall {
            AppLogger.killCall("handleIncoming busy — on system/cellular call new=\(incoming.id)")
            rejectIncomingAsBusy(callId: incoming.id)
            return
        }

        applyLocalConversationHints(for: incoming)

        // Background / kill → CallKit. Foreground → in-app only.
        // First-wins: socket `call:incoming` OR VoIP/FCM (deduped by callId). Don't wait on the other.
        if shouldUseCallKitForIncoming() {
            seedIncomingFromPush(call: incoming)
            let name = callDisplayTitle.isEmpty
                ? (incoming.caller?.displayName ?? "Incoming Call")
                : callDisplayTitle
            CallKitManager.shared.reportIncomingAgoraCall(
                callerName: name,
                hasVideo: incoming.type == .video,
                callId: incoming.id,
                call: incoming
            )
            return
        }

        AppLogger.killCall("handleIncoming FG in-app callId=\(incoming.id)")
        presentIncomingInApp(call: incoming)
    }

    /// Auto-reject a new incoming call while this device cannot take it (cellular / double-ring).
    func rejectIncomingAsBusy(callId: String) {
        guard !callId.isEmpty else { return }
        if pendingIncomingCall?.id == callId {
            pendingIncomingCall = nil
            stopPendingIncomingHaptics()
            notifyUI()
        }
        AppLogger.killCall(
            "rejectIncomingAsBusy new=\(callId) current=\(self.callId ?? "nil") phase=\(phase) group=\(isGroupCall)"
        )
        AgoraCallSignaling.shared.notifyBusy(callId: callId)
        AgoraCallSignaling.shared.declineCall(callId: callId, reason: "busy")
    }

    /// Offer Accept / Decline while already on another OneVibe call (does not busy-reject).
    func offerPendingIncoming(_ call: AgoraCallDto) {
        guard !call.id.isEmpty else { return }
        if shouldSuppressStaleOrEndedIncoming(call) {
            AppLogger.killCall("offerPendingIncoming suppress stale/ended callId=\(call.id)")
            if pendingIncomingCall?.id == call.id {
                pendingIncomingCall = nil
                stopPendingIncomingHaptics()
                notifyUI()
            }
            return
        }
        if pendingIncomingCall?.id == call.id {
            notifyUI()
            startPendingIncomingHapticsIfNeeded()
            return
        }
        // Replace a previous waiting third call — busy-decline the older one.
        if let previous = pendingIncomingCall, previous.id != call.id {
            AgoraCallSignaling.shared.notifyBusy(callId: previous.id)
            AgoraCallSignaling.shared.declineCall(callId: previous.id, reason: "busy")
        }
        pendingIncomingCall = call
        AppLogger.killCall(
            "offerPendingIncoming callId=\(call.id) while phase=\(phase) current=\(callId ?? "nil")"
        )
        // Waiting = vibrate only — never play the normal ringtone over the live call.
        stopRingtone()
        if isPipActive {
            exitPictureInPicture()
        }
        presentCallUIIfNeeded()
        notifyUI()
        startPendingIncomingHapticsIfNeeded()
    }

    func declinePendingIncoming() {
        guard let pending = pendingIncomingCall else { return }
        pendingIncomingCall = nil
        stopPendingIncomingHaptics()
        AgoraCallSignaling.shared.declineCall(callId: pending.id, reason: "declined")
        AppLogger.killCall("declinePendingIncoming callId=\(pending.id)")
        notifyUI()
    }

    /// Accept second call: end/leave current, then answer the pending one.
    func acceptPendingIncoming() async {
        guard let pending = pendingIncomingCall else { return }
        pendingIncomingCall = nil
        stopPendingIncomingHaptics()
        let next = pending
        AppLogger.killCall("acceptPendingIncoming drop current=\(callId ?? "nil") → \(next.id)")

        dropCurrentCallForReplace(replacedBy: next.id)

        // Agora leave + previous channel teardown need a beat before the next join.
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Seed the new incoming call explicitly (avoid presentIncoming early-return races).
        applyLocalConversationHints(for: next)
        call = next
        callId = next.id
        phase = .incoming
        isCallOwner = false
        isGroupCall = next.resolvedIsGroup || isGroupCall
        if let title = next.conversationTitle, !title.isEmpty {
            displayNameOverride = title
        }
        videoEnabled = (next.type == .video)
        muted = false
        speakerOn = (next.type == .video)
        hasRemoteVideo = false
        remoteParticipantUids = []
        remoteVideoUids = []
        remoteMutedUids = []
        attendedUserIds = []
        remoteUidToAttendeeKey = [:]
        gridParticipants = []
        pendingSession = nil
        didJoinRtc = false
        isCallKitOwned = false
        errorMessage = nil
        presentCallUIIfNeeded()
        notifyUI()

        AppLogger.killCall("acceptPendingIncoming accepting callId=\(next.id)")
        await acceptIncoming()
    }

    private func startPendingIncomingHapticsIfNeeded() {
        // Only while already on another OneVibe call (A–B active/outgoing + C waiting).
        guard pendingIncomingCall != nil else { return }
        guard phase == .active || phase == .outgoing else {
            stopPendingIncomingHaptics()
            return
        }
        if pendingIncomingHapticTimer != nil {
            // Already pulsing — fire one extra beat so a re-offer is felt.
            pulsePendingIncomingHaptic()
            return
        }
        pulsePendingIncomingHaptic()
        let timer = Timer(timeInterval: 1.6, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.pendingIncomingCall != nil,
                      self.phase == .active || self.phase == .outgoing else {
                    self?.stopPendingIncomingHaptics()
                    return
                }
                self.pulsePendingIncomingHaptic()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingIncomingHapticTimer = timer
    }

    private func pulsePendingIncomingHaptic() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        // System vibrate — works even when Taptic is subtle / silent switch quirks.
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    private func stopPendingIncomingHaptics() {
        pendingIncomingHapticTimer?.invalidate()
        pendingIncomingHapticTimer = nil
    }

    /// Hang up current call quietly so we can answer another (WhatsApp switch).
    private func dropCurrentCallForReplace(replacedBy nextCallId: String) {
        let endingCallId = callId
        if let endingCallId, !endingCallId.isEmpty {
            if isGroupCall, phase == .active, !isCallOwner {
                AgoraCallSignaling.shared.leaveCall(callId: endingCallId)
            } else {
                // Peer on this call should see "Call ended" (supersededBy helps clients map switch).
                AgoraCallSignaling.shared.endCall(callId: endingCallId, supersededBy: nextCallId)
                clearRejoinableGroupCall(matchingCallId: endingCallId)
            }
        }
        stopCallLivenessPolling()
        cleanupRtc()
        // End CallKit for the call we're leaving — mark as app-driven so End doesn't decline the next call.
        CallKitManager.shared.endCall(reason: .answeredElsewhere)
        // Soft reset — keep socket listeners; clear UI state for the next accept.
        remoteEndFeedbackWork?.cancel()
        remoteEndFeedbackWork = nil
        cancelAllRemoteDropGraceTimers()
        cancelLocalNetworkEndCall()
        clearConnectionStatus()
        stopElapsedTimer()
        stopRingtone()
        phase = .idle
        call = nil
        callId = nil
        errorMessage = nil
        muted = false
        videoEnabled = true
        speakerOn = true
        audioRoute = .speaker
        isScreenSharing = false
        networkQualityLevel = .unknown
        lastMappedQuality = .unknown
        peerNetworkState = .ok
        isAudioOnHold = false
        isCameraUnavailable = false
        thermalBannerText = nil
        outgoingDialState = .calling
        didReceiveCalleeRingingAck = false
        pendingRemoteRingingCallIds.removeAll()
        hasPendingRingingWithoutCallId = false
        // Keep pendingIncomingCall nil (already consumed by accept).
        stopCallPathMonitoring()
        stopOutgoingPresenceObservation()
        clearRemoteUplinkUnstableTracking()
        ownsLocalConnectionBanner = false
        qualityUpgradeCandidate = nil
        qualityUpgradeStreak = 0
        lastQualityDisplayChangeAt = nil
        lastLocalRtcConnectionState = .disconnected
        isTearingDown = false
        weakSignalWork?.cancel()
        weakSignalWork = nil
        lostConnectionWork?.cancel()
        lostConnectionWork = nil
        elapsedSec = 0
        hasRemoteVideo = false
        isGroupCall = false
        isCallOwner = false
        displayNameOverride = nil
        remoteParticipantUids = []
        remoteVideoUids = []
        remoteMutedUids = []
        gridParticipants = []
        attendedUserIds = []
        remoteUidToAttendeeKey = [:]
        memberProfileCache = [:]
        pendingSession = nil
        didJoinRtc = false
        isCallKitOwned = false
        isPipActive = false
        isRefreshingAgoraToken = false
        AgoraCallPipWindowController.shared.hide()
        dismissCallUI(animated: false)
        syncIdleTimerDisabled()
    }

    /// Clear swap banner if that call ended remotely.
    private func clearPendingIncomingIfNeeded(callId endedId: String) {
        guard pendingIncomingCall?.id == endedId else { return }
        pendingIncomingCall = nil
        stopPendingIncomingHaptics()
        notifyUI()
    }

    /// Callee phone is ringing — flip caller status to "Ringing…".
    /// When both users are online, this can arrive before `call:create:ack` sets `callId`.
    private func handleRemoteRinging(_ ringingCallId: String) {
        guard phase == .outgoing else { return }
        let trimmed = ringingCallId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if let callId, !callId.isEmpty {
                didReceiveCalleeRingingAck = true
                markOutgoingRinging(reason: "call:ringing")
            } else {
                hasPendingRingingWithoutCallId = true
                AppLogger.killCall("call:ringing buffered — empty callId, waiting for create-ack")
            }
            return
        }
        if callId == nil || callId?.isEmpty == true {
            pendingRemoteRingingCallIds.insert(trimmed)
            AppLogger.killCall("call:ringing buffered until create-ack id=\(trimmed)")
            return
        }
        guard matchesCallId(trimmed) else { return }
        didReceiveCalleeRingingAck = true
        markOutgoingRinging(reason: "call:ringing")
    }

    private func applyPendingRemoteRingingIfNeeded() {
        guard phase == .outgoing, let callId, !callId.isEmpty else { return }
        let matched = hasPendingRingingWithoutCallId
            || pendingRemoteRingingCallIds.contains(where: {
                $0.caseInsensitiveCompare(callId) == .orderedSame
            })
        pendingRemoteRingingCallIds.removeAll()
        hasPendingRingingWithoutCallId = false
        guard matched else { return }
        didReceiveCalleeRingingAck = true
        markOutgoingRinging(reason: "call:ringing-buffered")
    }

    /// Ringing… when the callee device acks, or when 1:1 presence shows they are on the network.
    /// Offline / unknown presence stays Calling… (do not guess after create-ack).
    private func refreshOutgoingDialStateForPresence(reason: String) {
        guard phase == .outgoing else { return }
        if didReceiveCalleeRingingAck {
            markOutgoingRinging(reason: "ack+\(reason)")
            return
        }
        guard !isGroupCall, isOutgoingPeerOnline else { return }
        markOutgoingRinging(reason: "presence-online:\(reason)")
    }

    /// WhatsApp-style: Calling… until callee is reachable / reports `call:ringing`, then Ringing….
    private func markOutgoingRinging(reason: String) {
        guard phase == .outgoing, outgoingDialState != .ringing else { return }
        outgoingDialState = .ringing
        AppLogger.killCall("outgoing dial → Ringing (\(reason)) callId=\(callId ?? "nil")")
        notifyUI()
    }

    private func startOutgoingPresenceObservation() {
        stopOutgoingPresenceObservation()
        ChatListSocketService.shared.requestOnlineUsers()
        outgoingPresenceCancellable = ChatListSocketService.shared.$onlineUserIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.phase == .outgoing else { return }
                self.refreshOutgoingDialStateForPresence(reason: "presence")
            }
    }

    private func stopOutgoingPresenceObservation() {
        outgoingPresenceCancellable?.cancel()
        outgoingPresenceCancellable = nil
    }

    /// Tell the caller our device is showing the incoming ring UI.
    private func emitCalleeRingingIfNeeded(callId: String) {
        guard !callId.isEmpty else { return }
        AgoraCallSignaling.shared.notifyRinging(callId: callId)
    }

    /// If server payload omits group flags, infer from local conversation cache.
    private func applyLocalConversationHints(for incoming: AgoraCallDto) {
        guard !incoming.conversationId.isEmpty else { return }
        if incoming.resolvedIsGroup {
            isGroupCall = true
            if displayNameOverride == nil, let title = incoming.conversationTitle, !title.isEmpty {
                displayNameOverride = title
            }
            seedMemberProfileCache(from: [], conversationId: incoming.conversationId)
            cacheProfilesFromCallDTO(incoming)
            return
        }
        if let row = ConversationRepository().getConversationListSync()
            .first(where: { $0.id == incoming.conversationId }),
           row.isGroup {
            isGroupCall = true
            if displayNameOverride == nil {
                let title = (row.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { displayNameOverride = title }
            }
            seedMemberProfileCache(from: [], conversationId: incoming.conversationId)
            cacheProfilesFromCallDTO(incoming)
        }
    }

    // MARK: - Attended-only avatar grid

    private func seedMemberProfileCache(from seeded: [AgoraCallGridParticipant], conversationId: String) {
        for person in seeded {
            let id = person.userId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            memberProfileCache[id] = (person.displayName, person.avatarURL)
        }
        guard !conversationId.isEmpty,
              let row = ConversationRepository().getConversationListSync().first(where: { $0.id == conversationId }),
              let members = row.participants else {
            return
        }
        for member in members {
            let uid = (member.userId ?? member.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uid.isEmpty else { continue }
            let details = member.user?.userDetails?.first
            let name = (member.user?.fullName ?? details?.fullName ?? member.user?.username ?? details?.userName ?? "Member")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let avatar = member.user?.profileImage
                ?? details?.profilePictureDetails?.filePath
                ?? details?.profilePicture
            if memberProfileCache[uid] == nil {
                memberProfileCache[uid] = (name.isEmpty ? "Member" : name, avatar)
            }
        }
        // Async enrich profiles only (does not add to grid until they attend).
        Task { [weak self] in
            guard let self else { return }
            guard let rich = try? await ConversationRepository().getConversationWithParticipants(id: conversationId),
                  let members = rich.participants else { return }
            await MainActor.run {
                guard self.isGroupCall, self.phase != .idle else { return }
                for member in members {
                    let uid = (member.userId ?? member.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !uid.isEmpty else { continue }
                    let details = member.user?.userDetails?.first
                    let name = (member.user?.fullName ?? details?.fullName ?? member.user?.username ?? details?.userName ?? "Member")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let avatar = member.user?.profileImage
                        ?? details?.profilePictureDetails?.filePath
                        ?? details?.profilePicture
                    self.memberProfileCache[uid] = (name.isEmpty ? "Member" : name, avatar)
                }
                self.rebuildAttendedGrid()
                self.notifyUI()
            }
        }
    }

    private func cacheProfilesFromCallDTO(_ call: AgoraCallDto) {
        if let caller = call.caller {
            let id = caller.id.isEmpty ? call.callerId : caller.id
            if !id.isEmpty {
                memberProfileCache[id] = (caller.displayName, caller.profilePicture)
            }
        }
        if let participants = call.participants {
            for p in participants where !p.id.isEmpty {
                memberProfileCache[p.id] = (p.displayName, p.profilePicture)
            }
        }
    }

    /// Add someone to the grid only after they join/attend the call.
    private func markAttended(userId: String, isSelf: Bool = false) {
        let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, isGroupCall else { return }
        if !attendedUserIds.contains(id) {
            attendedUserIds.append(id)
        }
        rebuildAttendedGrid()
        if !isSelf {
            startGroupCallTimerIfNeeded()
        }
    }

    private func markRemoteAttended(agoraUid: UInt, userAccount: String?) {
        guard isGroupCall else { return }
        let account = userAccount?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key: String
        if !account.isEmpty {
            key = account
        } else if let existing = remoteUidToAttendeeKey[agoraUid] {
            key = existing
        } else {
            key = "agora_\(agoraUid)"
        }
        // Upgrade placeholder → real userId when account arrives later.
        if let previous = remoteUidToAttendeeKey[agoraUid], previous != key, previous.hasPrefix("agora_") {
            attendedUserIds.removeAll { $0 == previous }
        }
        remoteUidToAttendeeKey[agoraUid] = key
        markAttended(userId: key)
    }

    private func markRemoteLeft(agoraUid: UInt) {
        guard let key = remoteUidToAttendeeKey.removeValue(forKey: agoraUid) else { return }
        attendedUserIds.removeAll { $0 == key }
        rebuildAttendedGrid()
    }

    private func rebuildAttendedGrid() {
        guard isGroupCall else {
            gridParticipants = []
            return
        }
        let me = meId
        let sessionUser = Container.sharedContainer.resolve(SessionManager.self)?.user
        let myName = {
            let full = sessionUser?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !full.isEmpty { return full }
            let user = sessionUser?.userName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return user.isEmpty ? "You" : user
        }()
        let myAvatar = sessionUser?.profilePictureDetails?.filePath
            ?? sessionUser?.profilePicture

        gridParticipants = attendedUserIds.compactMap { id -> AgoraCallGridParticipant? in
            let isSelf = (id == me)
            if isSelf {
                return AgoraCallGridParticipant(
                    userId: id,
                    displayName: myName,
                    avatarURL: myAvatar,
                    isSelf: true,
                    isConnected: true
                )
            }
            if id.hasPrefix("agora_") {
                return AgoraCallGridParticipant(
                    userId: id,
                    displayName: "Participant",
                    avatarURL: nil,
                    isSelf: false,
                    isConnected: true
                )
            }
            let cached = memberProfileCache[id]
            return AgoraCallGridParticipant(
                userId: id,
                displayName: cached?.name ?? "Member",
                avatarURL: cached?.avatar,
                isSelf: false,
                isConnected: true
            )
        }
        .sorted { a, b in
            if a.isSelf != b.isSelf { return a.isSelf && !b.isSelf }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    private func handleJoin(_ session: AgoraCallSession) {
        // Outgoing: callee accepted → enter active.
        // Incoming accept already joins via acceptCall ack; ignore duplicates for same call.
        // Accept may supersede another live call — only join if ids match current/pending.
        let merged = AgoraCallSession.merge(session, fallback: pendingSession)
        guard merged.call.id == callId || callId == nil || pendingSession?.call.id == merged.call.id else { return }
        if callId == nil { callId = merged.call.id }
        pendingSession = merged
        if phase == .outgoing || phase == .incoming {
            Task { await enterActive(merged) }
        }
    }

    private func handleBusy(_ payload: AgoraCallLifecyclePayload) {
        clearPendingIncomingIfNeeded(callId: payload.callId)
        guard matchesCurrentCall(payload.callId) || CallKitManager.shared.isReportingAgoraCall(payload.callId) else {
            return
        }
        // Partial group busy — keep Calling… / active for others.
        if payload.callEnded == false { return }
        if payload.callEnded != true, isGroupCall { return }
        finishFromRemote(endedCallId: payload.callId, reason: .busy)
    }

    /// `call:declined` / `call:rejected` — reason busy | declined | rejected.
    private func handleLifecycleEnd(
        _ payload: AgoraCallLifecyclePayload,
        fallback: RemoteCallEndReason
    ) {
        clearPendingIncomingIfNeeded(callId: payload.callId)
        guard matchesCurrentCall(payload.callId) || CallKitManager.shared.isReportingAgoraCall(payload.callId) else {
            AppLogger.killCall("lifecycle ignore callId=\(payload.callId) current=\(callId ?? "nil")")
            return
        }
        if payload.callEnded == true {
            let mapped = mapRemoteReason(payload.reason ?? payload.status, fallback: fallback)
            finishFromRemote(endedCallId: payload.callId, reason: mapped)
            return
        }
        // Group: someone else declined — keep UI; refresh DTO if present.
        if isGroupCall {
            if let by = payload.byUserId, by != meId {
                if let call = payload.call { self.call = call; notifyUI() }
                AppLogger.debug("AgoraCallService: group member declined — continuing")
                return
            }
            if payload.callEnded == false { return }
            // One member decline without callEnded — continue.
            AppLogger.debug("AgoraCallService: group decline without callEnded — continuing")
            return
        }
        let mapped = mapRemoteReason(payload.reason ?? payload.status, fallback: fallback)
        finishFromRemote(endedCallId: payload.callId, reason: mapped)
    }

    private func handleCancelled(_ payload: AgoraCallLifecyclePayload) {
        clearPendingIncomingIfNeeded(callId: payload.callId)
        guard matchesCurrentCall(payload.callId) || CallKitManager.shared.isReportingAgoraCall(payload.callId) else {
            return
        }
        // We accepted another call — this one was superseded; UI already advancing.
        if payload.supersededBy != nil, phase == .incoming || phase == .outgoing {
            // Incoming ring for superseded call — just dismiss without "cancelled" toast.
            if phase == .incoming {
                finishFromRemote(endedCallId: payload.callId, reason: .cancelled, showFeedback: false)
            }
            return
        }
        if phase == .incoming {
            // Caller cancelled — hide ring (no toast).
            finishFromRemote(endedCallId: payload.callId, reason: .cancelled, showFeedback: false)
            return
        }
        finishFromRemote(endedCallId: payload.callId, reason: .cancelled)
    }

    private func handleEndAck(_ payload: AgoraCallLifecyclePayload) {
        clearPendingIncomingIfNeeded(callId: payload.callId)
        clearRejoinableGroupCall(matchingCallId: payload.callId)
        guard matchesCurrentCall(payload.callId) || callId == nil || CallKitManager.shared.isReportingAgoraCall(payload.callId) else {
            return
        }
        // Own hangup already reset UI — only tear down CallKit / leftover state.
        if phase == .idle {
            CallKitManager.shared.endCall(reason: .remoteEnded)
            return
        }

        // Group: peer left but call still live — stay connected (no END_ACK teardown).
        if payload.callEnded == false { return }

        if phase == .incoming {
            let r = (payload.reason ?? payload.status ?? "").lowercased()
            if r == "cancelled" || r == "canceled" || r == "missed" {
                finishFromRemote(endedCallId: payload.callId, reason: .cancelled, showFeedback: false)
                return
            }
        }

        if phase == .outgoing {
            let mapped = mapRemoteReason(payload.reason ?? payload.status, fallback: .ended)
            if mapped == .busy || mapped == .rejected || mapped == .declined || mapped == .cancelled || mapped == .missed {
                finishFromRemote(endedCallId: payload.callId, reason: mapped)
                return
            }
        }

        // Peer switched to another call, or hung up while we were still connected.
        if let superseded = payload.supersededBy, !superseded.isEmpty {
            finishFromRemote(endedCallId: payload.callId, reason: .ended)
            return
        }

        // Group safety: ignore bare END_ACK without callEnded while still ongoing.
        if isGroupCall,
           phase == .active,
           payload.callEnded != true,
           call?.status == .ongoing || call?.status == .ringing {
            return
        }

        if phase == .active {
            finishFromRemote(endedCallId: payload.callId, reason: .ended)
            return
        }

        AppLogger.killCall("handleEndAck callId=\(payload.callId)")
        finishFromRemote(endedCallId: payload.callId, reason: .ended)
    }

    private func handleRemoteEnd(_ payload: AgoraCallLifecyclePayload) {
        clearPendingIncomingIfNeeded(callId: payload.callId)
        // Creator ended the call — hide Rejoin even if we already left (phase idle).
        clearRejoinableGroupCall(matchingCallId: payload.callId)
        let matchesCallKit = CallKitManager.shared.isReportingAgoraCall(payload.callId)
        let matches = matchesCurrentCall(payload.callId) || (callId == nil && phase != .idle) || matchesCallKit
        guard matches else {
            AppLogger.killCall("handleRemoteEnd ignore callId=\(payload.callId) current=\(callId ?? "nil") phase=\(phase)")
            return
        }
        if payload.callEnded == false { return }
        AppLogger.killCall("handleRemoteEnd callId=\(payload.callId) phase=\(phase) callKit=\(matchesCallKit)")
        let mapped = mapRemoteReason(payload.reason ?? payload.status, fallback: .ended)
        finishFromRemote(endedCallId: payload.callId, reason: mapped)
    }

    private func handleParticipantJoined(callId joinedId: String, call: AgoraCallDto?, userId: String?) {
        guard matchesCurrentCall(joinedId) else { return }
        if let call {
            self.call = call
            notifyUI()
        }
        // Group: another member attended (not self) → start the initiator duration clock.
        if isGroupCall, let userId, !userId.isEmpty, userId.caseInsensitiveCompare(meId) != .orderedSame {
            markAttended(userId: userId, isSelf: false)
            notifyUI()
        }
        // Outgoing 1:1 / group: first join while still dialing → go active (web promoteToActiveUi).
        if phase == .outgoing, let pending = pendingSession {
            Task { await enterActive(pending) }
        }
    }

    private func handleParticipantLeft(_ payload: AgoraCallLifecyclePayload) {
        guard matchesCurrentCall(payload.callId) else { return }
        // Group leave without END_ACK — only tear down if callEnded.
        if payload.callEnded == true {
            finishFromRemote(endedCallId: payload.callId, reason: .ended, showFeedback: false)
            return
        }
        if let call = payload.call {
            self.call = call
            notifyUI()
        }
    }

    private enum RemoteCallEndReason {
        case declined
        case rejected
        case busy
        case cancelled
        case missed
        case ended
    }

    private func mapRemoteReason(_ raw: String?, fallback: RemoteCallEndReason) -> RemoteCallEndReason {
        let r = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if r == "busy" || AgoraCallError.isBusyMessage(r) { return .busy }
        if r == "rejected" { return .rejected }
        if r == "declined" { return .declined }
        if r == "cancelled" || r == "canceled" { return .cancelled }
        if r == "missed" { return .missed }
        return fallback
    }

    /// Ends CallKit + in-app UI when the other party declines / hangs up.
    private func finishFromRemote(
        endedCallId: String,
        reason: RemoteCallEndReason,
        showFeedback: Bool = true
    ) {
        remoteEndFeedbackWork?.cancel()
        stopCallLivenessPolling()
        stopRingtone()
        cleanupRtc()

        let message: String
        let cxReason: CXCallEndedReason
        switch reason {
        case .declined, .rejected:
            message = "Call declined"
            cxReason = .declinedElsewhere
        case .busy:
            message = "User is busy"
            cxReason = .declinedElsewhere
        case .cancelled:
            message = "Call cancelled"
            cxReason = .remoteEnded
        case .missed:
            message = "Missed call"
            cxReason = .unanswered
        case .ended:
            message = "Call ended"
            cxReason = .remoteEnded
        }

        // Stop the other party's CallKit ring / green bar immediately.
        CallKitManager.shared.endCall(reason: cxReason)

        if showFeedback, reason == .busy {
            GlobalToast.shared.show("User is busy")
        }

        let hadVisibleInAppUI = (phase == .outgoing || phase == .incoming || phase == .active) && !isCallKitOwned
        if showFeedback, hadVisibleInAppUI {
            errorMessage = message
            clearConnectionStatus()
            notifyUI()
            let work = DispatchWorkItem { [weak self] in
                self?.resetUi()
            }
            remoteEndFeedbackWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
        } else {
            resetUi()
        }
    }

    private func matchesCurrentCall(_ otherCallId: String) -> Bool {
        guard let callId, !callId.isEmpty, !otherCallId.isEmpty else { return false }
        return callId.caseInsensitiveCompare(otherCallId) == .orderedSame
    }

    // MARK: - Stale / cancelled incoming (callee was offline when caller hung up)

    /// True when payload already says the invite is dead, or `createdAt` is too old.
    private func shouldSuppressStaleOrEndedIncoming(_ call: AgoraCallDto, allowSlowPush: Bool = false) -> Bool {
        if let endedAt = call.endedAt, !endedAt.isEmpty {
            return true
        }
        if let status = call.status {
            switch status {
            case .ended, .missed, .declined, .cancelled, .busy, .rejected:
                return true
            case .ringing, .ongoing:
                break
            }
        }
        if let createdAt = call.createdAt,
           let date = Self.parseCallTimestamp(createdAt) {
            let maxAge = allowSlowPush ? Self.maxIncomingRingAgeFromPushSeconds : Self.maxIncomingRingAgeSeconds
            if Date().timeIntervalSince(date) > maxAge {
                return true
            }
        }
        return false
    }

    /// Drop CallKit / in-app ring without emitting decline (caller already ended the call).
    private func suppressStaleOrEndedIncoming(callId: String, reason: String) {
        AppLogger.killCall("suppress stale/ended incoming (\(reason)) callId=\(callId)")
        if matchesCallId(callId) {
            finishFromRemote(endedCallId: callId, reason: .cancelled, showFeedback: false)
            return
        }
        if pendingIncomingCall?.id == callId {
            pendingIncomingCall = nil
            stopPendingIncomingHaptics()
            notifyUI()
        }
        // VoIP often reports CallKit before seed — end it while still idle.
        if phase == .idle, CallKitManager.shared.isReportingAgoraCall(callId) {
            CallKitManager.shared.endCall(reason: .remoteEnded)
            PendingKillCallStore.clear()
        }
    }

    private static func parseCallTimestamp(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: trimmed) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: trimmed) { return date }
        // Epoch seconds / ms (some push payloads).
        if let value = Double(trimmed) {
            if value > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: value / 1000.0)
            }
            if value > 1_000_000_000 {
                return Date(timeIntervalSince1970: value)
            }
        }
        return nil
    }

    // MARK: - Ringing liveness (missed decline/end while CallKit / socket cold)

    private func startCallLivenessPollingIfNeeded() {
        guard Self.isCallLivenessRESTEnabled else { return }
        stopCallLivenessPolling()
        guard let id = callId, !id.isEmpty else { return }
        guard phase == .outgoing || phase == .incoming else { return }
        AppLogger.killCall("start call liveness poll callId=\(id) phase=\(phase)")
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollCallLiveness(reason: "timer")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        callLivenessPollTimer = timer
        // Immediate check — caller may have already cancelled.
        pollCallLiveness(reason: "start")
    }

    private func stopCallLivenessPolling() {
        callLivenessPollTimer?.invalidate()
        callLivenessPollTimer = nil
    }

    private func pollCallLiveness(reason: String) {
        guard Self.isCallLivenessRESTEnabled else { return }
        guard let id = callId, !id.isEmpty else { return }
        let ringing = phase == .outgoing || phase == .incoming
        let callKitRinging = CallKitManager.shared.isReportingAgoraCall(id)
        guard ringing || callKitRinging else {
            stopCallLivenessPolling()
            return
        }
        guard let sessionManager = Container.sharedContainer.resolve(SessionManager.self) else { return }
        _ = sessionManager.fetchAgoraCall(callId: id)
            .subscribe(onSuccess: { [weak self] dict in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.matchesCurrentCall(id) || CallKitManager.shared.isReportingAgoraCall(id) else { return }
                    guard Self.isEndedCallPayload(dict) else { return }
                    AppLogger.killCall("liveness poll ended (\(reason)) callId=\(id) phase=\(self.phase)")
                    let status = Self.callStatus(from: dict)
                    let remoteReason: RemoteCallEndReason
                    let showFeedback: Bool
                    if AgoraCallError.isBusyMessage(status) {
                        remoteReason = .busy
                        showFeedback = true
                    } else if status == "cancelled" || status == "canceled" {
                        remoteReason = .cancelled
                        // Incoming: silent (caller already left). Outgoing: show cancelled.
                        showFeedback = (self.phase == .outgoing)
                    } else if self.phase == .outgoing {
                        // Prefer declined wording while we were still outgoing (callee cut).
                        remoteReason = .declined
                        showFeedback = true
                    } else {
                        // Incoming / CallKit — caller hung up while we were offline.
                        remoteReason = .cancelled
                        showFeedback = false
                    }
                    self.finishFromRemote(endedCallId: id, reason: remoteReason, showFeedback: showFeedback)
                }
            }, onFailure: { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    // Only tear down incoming/CallKit on hard "gone" — keep ringing on transient errors.
                    guard self.phase == .incoming || CallKitManager.shared.isReportingAgoraCall(id) else { return }
                    guard Self.isCallGoneError(error) else { return }
                    AppLogger.killCall(
                        "liveness poll gone (\(reason)) callId=\(id) err=\(error.localizedDescription)"
                    )
                    self.finishFromRemote(endedCallId: id, reason: .cancelled, showFeedback: false)
                }
            })
    }

    // MARK: - Group rejoin / join (persist across kill + miss)

    private func makeRejoinableSnapshotIfLeaving() -> AgoraRejoinableGroupCall? {
        guard isGroupCall, phase == .active, !isCallOwner else { return nil }
        return makeRejoinableSnapshotForCurrentGroupCall()
    }

    /// Snapshot for leave / decline / kill-recovery (incoming or active group call).
    private func makeRejoinableSnapshotForCurrentGroupCall() -> AgoraRejoinableGroupCall? {
        guard isGroupCall,
              phase == .active || phase == .incoming,
              let callId = callId ?? call?.id, !callId.isEmpty else { return nil }
        let conversationId = call?.conversationId
            ?? rejoinableGroupCall?.conversationId
            ?? ""
        guard !conversationId.isEmpty else { return nil }
        return AgoraRejoinableGroupCall(
            callId: callId,
            conversationId: conversationId,
            type: call?.type ?? .audio,
            displayName: displayNameOverride ?? call?.conversationTitle,
            groupMembers: gridParticipants
        )
    }

    private func rememberJoinableGroupCall(from call: AgoraCallDto) {
        guard call.resolvedIsGroup || isGroupCall,
              !call.id.isEmpty,
              !call.conversationId.isEmpty else { return }
        // Don't overwrite a different live call with a stale ring for another conversation.
        if let current = AgoraRejoinableGroupCallStore.load(conversationId: call.conversationId),
           current.callId != call.id,
           phase != .idle,
           call.conversationId == (self.call?.conversationId ?? "") {
            return
        }
        let info = AgoraRejoinableGroupCall(
            callId: call.id,
            conversationId: call.conversationId,
            type: call.type,
            displayName: displayNameOverride ?? call.conversationTitle,
            groupMembers: gridParticipants
        )
        setRejoinableGroupCall(info)
    }

    private func setRejoinableGroupCall(_ info: AgoraRejoinableGroupCall) {
        rejoinableGroupCall = info
        AgoraRejoinableGroupCallStore.save(info)
        NotificationCenter.default.post(name: .agoraGroupCallRejoinDidChange, object: nil)
        AppLogger.debug("AgoraCallService: rejoin available callId=\(info.callId) conversation=\(info.conversationId)")
    }

    /// Persist while still in the call (Join banner stays hidden until phase is idle; list shows ongoing).
    private func persistRejoinableGroupCall(_ info: AgoraRejoinableGroupCall) {
        rejoinableGroupCall = info
        AgoraRejoinableGroupCallStore.save(info)
        NotificationCenter.default.post(name: .agoraGroupCallRejoinDidChange, object: nil)
    }

    private func clearRejoinableGroupCall(matchingCallId callId: String? = nil) {
        if let callId, !callId.isEmpty {
            let matching = AgoraRejoinableGroupCallStore.all().filter {
                $0.callId.caseInsensitiveCompare(callId) == .orderedSame
            }
            let had = !matching.isEmpty
            guard had || rejoinableGroupCall?.callId.caseInsensitiveCompare(callId) == .orderedSame else { return }
            for info in matching {
                activeCallDetailFetched.remove(info.conversationId)
            }
            if let conv = rejoinableGroupCall?.conversationId,
               rejoinableGroupCall?.callId.caseInsensitiveCompare(callId) == .orderedSame {
                activeCallDetailFetched.remove(conv)
            }
            AgoraRejoinableGroupCallStore.remove(callId: callId)
            if rejoinableGroupCall?.callId.caseInsensitiveCompare(callId) == .orderedSame {
                rejoinableGroupCall = AgoraRejoinableGroupCallStore.load()
            }
            NotificationCenter.default.post(name: .agoraGroupCallRejoinDidChange, object: nil)
            AppLogger.debug("AgoraCallService: rejoin cleared callId=\(callId)")
            return
        }
        // Clear everything (rare).
        guard rejoinableGroupCall != nil || !AgoraRejoinableGroupCallStore.all().isEmpty else { return }
        rejoinableGroupCall = nil
        AgoraRejoinableGroupCallStore.clear()
        activeCallDetailFetched.removeAll()
        NotificationCenter.default.post(name: .agoraGroupCallRejoinDidChange, object: nil)
        AppLogger.debug("AgoraCallService: rejoin cleared all")
    }

    private func restoreRejoinableGroupCallIfNeeded(notify: Bool = true) {
        let stored = AgoraRejoinableGroupCallStore.load()
        if rejoinableGroupCall == nil, let stored {
            rejoinableGroupCall = stored
            AppLogger.debug(
                "AgoraCallService: restored rejoin callId=\(stored.callId) conversation=\(stored.conversationId)"
            )
            if notify {
                NotificationCenter.default.post(name: .agoraGroupCallRejoinDidChange, object: nil)
            }
        }
    }

    /// Soft-validate via REST — only clear when the server explicitly says the call ended.
    private func validateRejoinableGroupCallStillLive(_ info: AgoraRejoinableGroupCall) {
        guard Self.isCallLivenessRESTEnabled else { return }
        guard let sessionManager = Container.sharedContainer.resolve(SessionManager.self) else { return }
        _ = sessionManager.fetchAgoraCall(callId: info.callId)
            .subscribe(onSuccess: { [weak self] dict in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.rejoinableInfo(for: info.conversationId)?.callId == info.callId else { return }
                    if Self.isEndedCallPayload(dict) {
                        self.clearRejoinableGroupCall(matchingCallId: info.callId)
                    }
                }
            }, onFailure: { _ in
                // Network / missing route — keep Join; failed rejoin will clear if truly gone.
            })
    }

    private static func callStatus(from dict: [String: Any]) -> String {
        (
            dict["status"] as? String
                ?? (dict["call"] as? [String: Any])?["status"] as? String
                ?? (dict["data"] as? [String: Any])?["status"] as? String
                ?? ((dict["data"] as? [String: Any])?["call"] as? [String: Any])?["status"] as? String
                ?? dict["reason"] as? String
                ?? ""
        ).lowercased()
    }

    private static func isEndedCallPayload(_ dict: [String: Any]) -> Bool {
        let status = callStatus(from: dict)
        if ["ended", "missed", "declined", "busy", "cancelled", "canceled", "rejected"].contains(status) { return true }
        if AgoraCallError.isBusyMessage(status) { return true }
        if let endedAt = dict["endedAt"] as? String ?? (dict["call"] as? [String: Any])?["endedAt"] as? String,
           !endedAt.isEmpty {
            return true
        }
        if let success = dict["success"] as? Bool, !success {
            let message = (dict["message"] as? String ?? "").lowercased()
            return message.contains("end")
                || message.contains("not found")
                || message.contains("expired")
                || AgoraCallError.isBusyMessage(message)
        }
        return false
    }

    private static func isCallGoneError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("end")
            || message.contains("not found")
            || message.contains("ended")
            || message.contains("expired")
            || message.contains("invalid")
            || message.contains("no longer")
            || message.contains("does not exist")
            || message.contains("finished")
    }

    // MARK: - Active media

    private func enterActive(_ session: AgoraCallSession) async {
        guard phase == .outgoing || phase == .incoming || (phase == .active && !didJoinRtc) else {
            // Already active with RTC — just refresh metadata.
            if phase == .active {
                call = session.call
                notifyUI()
            }
            return
        }
        let merged = AgoraCallSession.merge(session, fallback: pendingSession)
        stopRingtone()
        stopCallLivenessPolling()
        stopOutgoingPresenceObservation()
        pendingRemoteRingingCallIds.removeAll()
        hasPendingRingingWithoutCallId = false
        // Active call UI is always in-app (CallKit ringing is done).
        isCallKitOwned = false
        call = merged.call
        callId = merged.call.id
        pendingSession = merged
        // Keep owner if we started the call; otherwise trust callerId from server.
        if !isCallOwner {
            isCallOwner = (!merged.call.callerId.isEmpty && merged.call.callerId == meId)
        }
        if merged.call.resolvedIsGroup {
            isGroupCall = true
        }
        if let title = merged.call.conversationTitle, !title.isEmpty {
            displayNameOverride = title
        }
        let wasAlreadyJoined = didJoinRtc
        phase = .active
        outgoingDialState = .calling
        didReceiveCalleeRingingAck = false
        hasRemoteVideo = !remoteVideoUids.isEmpty
        videoEnabled = (merged.call.type == .video)
        // Answered audio → earpiece (proximity blank). Dial kept speaker on for stable ringback.
        if merged.call.type == .audio {
            speakerOn = false
            if wasAlreadyJoined {
                rtc.setSpeakerOn(false)
            }
        }
        if isGroupCall {
            cacheProfilesFromCallDTO(merged.call)
            seedMemberProfileCache(from: [], conversationId: merged.call.conversationId)
            markAttended(userId: meId, isSelf: true)
            // Persist while connected so app-kill → relaunch can still show Join.
            if let snap = makeRejoinableSnapshotForCurrentGroupCall() {
                persistRejoinableGroupCall(snap)
            }
        }
        startCallPathMonitoring()
        if elapsedTimer == nil {
            elapsedSec = 0
            // 1:1: enterActive already means the peer answered — start immediately.
            // Group callee / rejoin: this device just joined an ongoing call — start immediately.
            // Group initiator: wait until at least one other person attends.
            let waitForFirstGroupPeer = isGroupCall && isCallOwner && !hasGroupPeerJoined
            if !waitForFirstGroupPeer {
                startElapsedTimer()
            }
        }
        notifyUI()

        presentCallUIIfNeeded { [weak self] in
            self?.rebindRtcToFullScreenViews()
        }

        if !wasAlreadyJoined {
            prejoinRtc(merged)
        }
    }

    /// Join Agora channel without flipping UI to `.active` (1:1 ringing / early media).
    private func prejoinRtc(_ session: AgoraCallSession) {
        let merged = AgoraCallSession.merge(session, fallback: pendingSession)
        guard merged.hasJoinCredentials else { return }
        pendingSession = merged
        call = merged.call
        callId = merged.call.id

        if didJoinRtc {
            AppLogger.debug("AgoraCallService: RTC already joined — skip rejoin")
            return
        }

        let ui = callUI
        let withVideo = merged.call.type == .video
        let appId = merged.appId.isEmpty ? (merged.call.appId ?? "") : merged.appId
        AppLogger.debug(
            "AgoraCallService: prejoinRtc group=\(isGroupCall) appId=\(appId) channel=\(merged.call.channelName) uid=\(merged.uid) video=\(withVideo)"
        )
        didJoinRtc = true
        rtc.join(
            appId: appId,
            channel: merged.call.channelName,
            token: merged.token,
            uid: merged.uid,
            withVideo: withVideo,
            speakerOn: speakerOn,
            localView: withVideo ? ui?.activeLocalVideoSurface : nil,
            remoteView: withVideo ? ui?.primaryRemoteVideoView : nil
        )
        // Agora `setCategory` can interrupt AVAudioPlayer ringback — resume while still dialing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            Task { @MainActor in
                self?.resumeRingtoneIfNeeded()
            }
        }
    }

    // MARK: - UI presentation

    private func presentCallUIIfNeeded(animated: Bool = true, completion: (() -> Void)? = nil) {
        // CallKit is the ringing UI — never stack the default Agora overlay on top.
        if isCallKitOwned, phase == .incoming {
            completion?()
            return
        }
        // PiP owns the UI — don't present full-screen until expanded.
        if isPipActive {
            completion?()
            return
        }
        if callUI != nil {
            completion?()
            return
        }
        // Prefer the main-app window. While PiP is visible, keyWindow can be the PiP host —
        // presenting there is wiped when the PiP window is torn down.
        guard let presenter = AgoraCallPipWindowController.mainAppTopViewController()
            ?? UIApplication.shared.topViewController() else {
            completion?()
            return
        }

        let generation = callUIPresentGeneration
        let presentBlock = { [weak self] in
            guard let self else {
                completion?()
                return
            }
            // Decline / hangup / dismiss happened while dismiss-then-present was in flight.
            guard self.callUIPresentGeneration == generation else {
                AppLogger.killCall("presentCallUI cancelled — generation changed (user cut)")
                completion?()
                return
            }
            guard self.phase == .incoming || self.phase == .outgoing || self.phase == .active else {
                AppLogger.killCall("presentCallUI cancelled — phase=\(self.phase)")
                completion?()
                return
            }
            // Another present may have won while we were dismissing leftovers.
            if self.callUI != nil || self.isPipActive {
                completion?()
                return
            }
            if self.isCallKitOwned, self.phase == .incoming {
                completion?()
                return
            }
            let vc = AgoraCallViewController(service: self)
            vc.modalPresentationStyle = .fullScreen
            self.callUI = vc
            presenter.view.window?.makeKey()
            presenter.present(vc, animated: animated, completion: completion)
        }

        // Clear any leftover presented VC (e.g. PiP dismiss raced) before presenting.
        if let existing = presenter.presentedViewController {
            existing.dismiss(animated: false, completion: presentBlock)
        } else {
            presentBlock()
        }
    }

    func notifyUI() {
        syncIdleTimerDisabled()
        syncProximityMonitoring()
        callUI?.reloadFromService()
        AgoraCallPipWindowController.shared.reload()
    }

    /// Keep the display awake for the entire video-call session (including PiP / camera-off).
    private func syncIdleTimerDisabled() {
        let isVideoCall: Bool
        if let call {
            isVideoCall = call.type == .video
        } else {
            // Outgoing / rejoin before the call DTO arrives — `videoEnabled` mirrors the requested type.
            isVideoCall = videoEnabled
        }
        let keepAwake = phase != .idle && isVideoCall
        if UIApplication.shared.isIdleTimerDisabled != keepAwake {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
    }

    /// Audio + earpiece: blank the display when the phone is against the ear (system proximity).
    private func syncProximityMonitoring() {
        let isVideoCall: Bool
        if let call {
            isVideoCall = call.type == .video
        } else {
            isVideoCall = videoEnabled
        }
        // Prefer speakerOn flag — `audioRoute` can lag briefly after join/toggle.
        let onEarpiece = !speakerOn && !audioRoute.isExternalHeadset
        let enable = phase == .active && !isVideoCall && onEarpiece
        if UIDevice.current.isProximityMonitoringEnabled != enable {
            UIDevice.current.isProximityMonitoringEnabled = enable
            AppLogger.debug("AgoraCallService: proximityMonitoring=\(enable) route=\(audioRoute) speaker=\(speakerOn)")
        }
    }

    private func dismissCallUI(animated: Bool = true) {
        // Invalidate any in-flight present (Home present is slow; cut must win the race).
        callUIPresentGeneration &+= 1
        let ui = callUI
        callUI = nil
        // Always dismiss even if `presentingViewController` is nil (child / race / already moving).
        ui?.dismiss(animated: animated)
        // Orphan fullscreen call VC (present completed after we cleared `callUI`).
        if let orphan = Self.findPresentedAgoraCallViewController(), orphan !== ui {
            AppLogger.killCall("dismissCallUI — dismissing orphan AgoraCallViewController")
            orphan.dismiss(animated: animated)
        }
    }

    private static func findPresentedAgoraCallViewController() -> AgoraCallViewController? {
        if let top = UIApplication.shared.topViewController() as? AgoraCallViewController {
            return top
        }
        if let top = AgoraCallPipWindowController.mainAppTopViewController() as? AgoraCallViewController {
            return top
        }
        var root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        while let presented = root?.presentedViewController {
            if let call = presented as? AgoraCallViewController {
                return call
            }
            root = presented
        }
        return nil
    }

    // MARK: - Cleanup

    private func cleanupRtc() {
        cancelAllRemoteDropGraceTimers()
        clearConnectionStatus()
        stopElapsedTimer()
        stopRingtone()
        didJoinRtc = false
        pendingSession = nil
        isRefreshingAgoraToken = false
        rtc.leave()
    }

    /// Tear down RTC + listeners on logout so the next session gets a fresh engine.
    func shutdownForLogout() {
        if phase != .idle {
            hangUp()
        }
        rtc.destroyEngine()
        AgoraCallSignaling.shared.removeAllListeners()
        didStartListening = false
        incomingAllowsSlowPushAge = false
        isPrefetchingIncomingCredentials = false
        AppLogger.killCall("AgoraCallService.shutdownForLogout")
    }

    /// GET calls/{id} while ringing (VoIP/cold socket) so Answer can join without waiting for call:join ack.
    func prefetchIncomingJoinCredentials(callId: String) {
        let id = callId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        if let pending = pendingSession, pending.call.id == id, pending.hasJoinCredentials {
            return
        }
        guard !isPrefetchingIncomingCredentials else { return }
        isPrefetchingIncomingCredentials = true
        AgoraCallSignaling.shared.fetchJoinSessionViaREST(callId: id) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isPrefetchingIncomingCredentials = false
                guard self.matchesCallId(id) || self.callId == id else { return }
                if case .success(let session) = result {
                    let merged = AgoraCallSession.merge(session, fallback: self.pendingSession)
                    self.pendingSession = merged
                    AppLogger.killCall(
                        "prefetch credentials callId=\(id) hasJoin=\(merged.hasJoinCredentials)"
                    )
                }
            }
        }
    }

    private func resetUi() {
        remoteEndFeedbackWork?.cancel()
        remoteEndFeedbackWork = nil
        stopCallLivenessPolling()
        cancelAllRemoteDropGraceTimers()
        cancelLocalNetworkEndCall()
        clearConnectionStatus()
        stopElapsedTimer()
        stopRingtone()
        phase = .idle
        call = nil
        callId = nil
        errorMessage = nil
        muted = false
        videoEnabled = true
        speakerOn = true
        audioRoute = .speaker
        isScreenSharing = false
        networkQualityLevel = .unknown
        lastMappedQuality = .unknown
        peerNetworkState = .ok
        isAudioOnHold = false
        isCameraUnavailable = false
        thermalBannerText = nil
        outgoingDialState = .calling
        didReceiveCalleeRingingAck = false
        pendingRemoteRingingCallIds.removeAll()
        hasPendingRingingWithoutCallId = false
        pendingIncomingCall = nil
        stopPendingIncomingHaptics()
        stopCallPathMonitoring()
        stopOutgoingPresenceObservation()
        clearRemoteUplinkUnstableTracking()
        ownsLocalConnectionBanner = false
        qualityUpgradeCandidate = nil
        qualityUpgradeStreak = 0
        lastQualityDisplayChangeAt = nil
        lastLocalRtcConnectionState = .disconnected
        isTearingDown = false
        weakSignalWork?.cancel()
        weakSignalWork = nil
        lostConnectionWork?.cancel()
        lostConnectionWork = nil
        elapsedSec = 0
        hasRemoteVideo = false
        isGroupCall = false
        isCallOwner = false
        displayNameOverride = nil
        avatarURLOverride = nil
        remoteParticipantUids = []
        remoteVideoUids = []
        remoteMutedUids = []
        gridParticipants = []
        attendedUserIds = []
        remoteUidToAttendeeKey = [:]
        memberProfileCache = [:]
        pendingSession = nil
        didJoinRtc = false
        isCallKitOwned = false
        isPipActive = false
        isRefreshingAgoraToken = false
        incomingAllowsSlowPushAge = false
        isPrefetchingIncomingCredentials = false
        AgoraCallPipWindowController.shared.hide()
        dismissCallUI()
        CallKitManager.shared.markCallSessionEnded()
        syncIdleTimerDisabled()
        syncProximityMonitoring()
        // Ensure proximity is never left on after call teardown.
        if UIDevice.current.isProximityMonitoringEnabled {
            UIDevice.current.isProximityMonitoringEnabled = false
        }
    }

    private func clearConnectionStatus() {
        reconnectStatusWork?.cancel()
        reconnectStatusWork = nil
        reconnectedClearWork?.cancel()
        reconnectedClearWork = nil
        lostConnectionWork?.cancel()
        lostConnectionWork = nil
        isReconnecting = false
        ownsLocalConnectionBanner = false
        // Keep peer weak/unreachable if uplink still bad (local Reconnected must not wipe it).
        if isRemoteUplinkUnstable {
            ownsRemoteUplinkBanner = true
            if peerNetworkState == .unreachable {
                connectionStatusText = peerNotInNetworkBannerText
            } else {
                peerNetworkState = .weak
                connectionStatusText = "Poor connection"
            }
            networkQualityLevel = .poor
        } else {
            connectionStatusText = nil
            ownsRemoteUplinkBanner = false
            peerNetworkState = .ok
            if networkQualityLevel == .reconnecting || networkQualityLevel == .lost {
                networkQualityLevel = lastMappedQuality == .unknown ? .good : lastMappedQuality
            }
        }
    }

    /// Local path / local RTC banners only.
    private func setLocalConnectionStatus(_ text: String) {
        ownsLocalConnectionBanner = true
        ownsRemoteUplinkBanner = false
        connectionStatusText = text
        isReconnecting = (text == "Reconnecting…" || text == "No internet" || text == "Lost Connection")
        if text == "Reconnecting…" || text == "No internet" {
            networkQualityLevel = .reconnecting
            scheduleLocalNetworkEndCallIfNeeded()
        } else if text == "Lost Connection" {
            networkQualityLevel = .lost
            scheduleLocalNetworkEndCallIfNeeded()
        }
        notifyUI()
    }

    /// Peer quality banner — never used for local RTC flaps.
    private func setPeerWeakBanner() {
        // Local No internet / Lost / active local Reconnecting wins.
        if ownsLocalConnectionBanner,
           let text = connectionStatusText,
           text == "No internet" || text == "Lost Connection" || text == "Reconnecting…" {
            peerNetworkState = .weak
            networkQualityLevel = .poor
            notifyUI()
            return
        }
        // Don't downgrade Not in network back to Poor while peer is still gone.
        if peerNetworkState == .unreachable, ownsRemoteUplinkBanner {
            networkQualityLevel = .poor
            notifyUI()
            return
        }
        ownsRemoteUplinkBanner = true
        ownsLocalConnectionBanner = false
        peerNetworkState = .weak
        connectionStatusText = "Poor connection"
        isReconnecting = false
        networkQualityLevel = .poor
        schedulePeerNotInNetworkEscalateIfNeeded()
        notifyUI()
    }

    private func setPeerUnreachableBanner() {
        peerNotInNetworkEscalateWork?.cancel()
        peerNotInNetworkEscalateWork = nil
        if ownsLocalConnectionBanner,
           let text = connectionStatusText,
           text == "No internet" || text == "Lost Connection" || text == "Reconnecting…" {
            peerNetworkState = .unreachable
            networkQualityLevel = .poor
            notifyUI()
            return
        }
        ownsRemoteUplinkBanner = true
        ownsLocalConnectionBanner = false
        peerNetworkState = .unreachable
        connectionStatusText = peerNotInNetworkBannerText
        isReconnecting = false
        networkQualityLevel = .poor
        schedulePeerOfflineEndCallIfNeeded()
        notifyUI()
    }

    /// After sustained peer uplink failure, User A shows "Not in network" (even before didOffline).
    private func schedulePeerNotInNetworkEscalateIfNeeded() {
        guard peerNotInNetworkEscalateWork == nil else { return }
        guard peerNetworkState != .unreachable else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .active else { return }
            guard self.isRemoteUplinkUnstable || !self.remoteDropGraceWorkItems.isEmpty else { return }
            guard self.peerNetworkState == .weak else { return }
            self.setPeerUnreachableBanner()
        }
        peerNotInNetworkEscalateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + peerNotInNetworkEscalateSeconds, execute: work)
    }

    /// End 1:1 if peer stays gone after Not in network / didOffline. Clock is not reset by later Agora offline.
    private func schedulePeerOfflineEndCallIfNeeded() {
        guard !isGroupCall else { return }
        guard peerOfflineEndCallWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.peerOfflineEndCallWork = nil
                guard self.phase == .active, !self.isGroupCall else { return }
                guard self.peerNetworkState == .unreachable || self.isRemoteUplinkUnstable else { return }
                AppLogger.killCall("1:1 peer outage timeout — ending call")
                self.clearRemoteUplinkUnstableTracking()
                self.isTearingDown = true
                self.callUIPresentGeneration &+= 1
                self.stopCallPathMonitoring()
                if let id = self.callId {
                    self.finishFromRemote(endedCallId: id, reason: .ended, showFeedback: false)
                } else {
                    self.cleanupRtc()
                    self.resetUi()
                    CallKitManager.shared.endCall(reason: .remoteEnded)
                }
            }
        }
        peerOfflineEndCallWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + peerNotInNetworkEndCallSeconds, execute: work)
        AppLogger.debug(
            "AgoraCallService: 1:1 peer outage — end call in \(Int(peerNotInNetworkEndCallSeconds))s"
        )
    }

    private func cancelPeerOfflineEndCall() {
        peerOfflineEndCallWork?.cancel()
        peerOfflineEndCallWork = nil
    }

    private func setConnectionStatus(_ text: String?) {
        // Legacy entry — treat as local unless peer banners.
        if text == "Weak signal" || text == "Poor connection" {
            setPeerWeakBanner()
            return
        }
        if let text {
            setLocalConnectionStatus(text)
        } else {
            clearConnectionStatus()
            notifyUI()
        }
    }

    /// Priority banner for call UI (hold > lost > reconnect > weak > thermal).
    var activeCallBannerText: String? {
        if isAudioOnHold { return "Call on hold" }
        if let connectionStatusText, !connectionStatusText.isEmpty {
            return connectionStatusText
        }
        if let thermalBannerText, !thermalBannerText.isEmpty {
            return thermalBannerText
        }
        return nil
    }

    private var isLocalRtcUnstable: Bool {
        switch lastLocalRtcConnectionState {
        case .reconnecting, .failed, .disconnected:
            return true
        default:
            return false
        }
    }

    private var isLocalOutageBannerVisible: Bool {
        guard ownsLocalConnectionBanner else { return false }
        switch connectionStatusText {
        case "No internet", "Lost Connection", "Reconnecting…":
            return true
        default:
            return false
        }
    }

    /// Path down, local RTC dead, or still showing a local-outage banner.
    private var hasSustainedLocalOutage: Bool {
        !NetworkMonitor.shared.isConnected || isLocalRtcUnstable || isLocalOutageBannerVisible
    }

    private var hasRecoveredFromLocalOutage: Bool {
        NetworkMonitor.shared.isConnected && !isLocalRtcUnstable
    }

    /// Show reconnect banner only if local RTC/path still bad after debounce (WhatsApp-style).
    private func scheduleReconnectingStatus() {
        reconnectStatusWork?.cancel()
        reconnectedClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.phase == .active || self.phase == .outgoing else { return }
            guard !self.isTearingDown else { return }
            // Re-check — brief Agora flaps must not flash Reconnecting.
            let pathDown = !NetworkMonitor.shared.isConnected
            guard pathDown || self.isLocalRtcUnstable else { return }
            // Don't steal peer Poor connection unless this is a real local outage.
            if self.ownsRemoteUplinkBanner,
               self.isPeerConnectionBanner,
               !pathDown,
               !self.isLocalRtcUnstable {
                return
            }
            self.setLocalConnectionStatus("Reconnecting…")
            self.scheduleLostConnectionIfNeeded()
            self.scheduleLocalNetworkEndCallIfNeeded()
        }
        reconnectStatusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    /// After prolonged disconnect, show Lost Connection instead of endless Reconnecting.
    private func scheduleLostConnectionIfNeeded() {
        lostConnectionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.phase == .active || self.phase == .outgoing || self.phase == .incoming else { return }
            guard self.ownsLocalConnectionBanner else { return }
            guard self.connectionStatusText == "Reconnecting…" || self.connectionStatusText == "No internet" else { return }
            self.setLocalConnectionStatus("Lost Connection")
        }
        lostConnectionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: work)
    }

    private func handleRtcConnectedStatus() {
        guard !isTearingDown else { return }
        reconnectStatusWork?.cancel()
        reconnectStatusWork = nil
        if ownsLocalConnectionBanner {
            lostConnectionWork?.cancel()
            lostConnectionWork = nil
        }
        if hasRecoveredFromLocalOutage {
            scheduleLocalOutageRecoverConfirmIfNeeded()
        } else {
            cancelLocalOutageRecoverConfirm()
        }
        // Soft restore only — never full setCategory (that breaks iOS↔iOS audio).
        rtc.softRestorePublishedAudio()

        // Peer still in drop-grace / Weak — don't wipe peer banner with "Reconnected".
        if ownsRemoteUplinkBanner || !remoteDropGraceWorkItems.isEmpty {
            notifyUI()
            return
        }

        if ownsLocalConnectionBanner, connectionStatusText != nil {
            setLocalConnectionStatus("Reconnected")
            reconnectedClearWork?.cancel()
            let clear = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.ownsLocalConnectionBanner {
                    self.clearConnectionStatus()
                }
                self.notifyUI()
            }
            reconnectedClearWork = clear
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: clear)
        } else if ownsLocalConnectionBanner {
            clearConnectionStatus()
            notifyUI()
        } else {
            notifyUI()
        }
    }

    // MARK: - Path / quality / hold / thermal

    private func startCallPathMonitoring() {
        stopCallPathMonitoring()
        pathCancellable = NetworkMonitor.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.handlePathConnectivity(connected)
            }
    }

    private func stopCallPathMonitoring() {
        pathCancellable?.cancel()
        pathCancellable = nil
    }

    private func handlePathConnectivity(_ connected: Bool) {
        guard !isTearingDown else { return }
        guard phase == .active || phase == .outgoing || phase == .incoming else { return }
        if !connected {
            cancelLocalOutageRecoverConfirm()
            setLocalConnectionStatus("No internet")
            scheduleLostConnectionIfNeeded()
            scheduleLocalNetworkEndCallIfNeeded()
        } else {
            // NWPath often flaps to satisfied while Agora is still dead — don't kill the hangup clock.
            if hasRecoveredFromLocalOutage {
                scheduleLocalOutageRecoverConfirmIfNeeded()
                // Don't leave a stuck "No internet" banner after a false path-up.
                if isLocalOutageBannerVisible {
                    handleRtcConnectedStatus()
                }
            } else {
                cancelLocalOutageRecoverConfirm()
                if ownsLocalConnectionBanner,
                   connectionStatusText == "No internet" || connectionStatusText == "Lost Connection" {
                    scheduleReconnectingStatus()
                }
            }
        }
    }

    /// Sustained local outage → auto hang up (Calling / Ringing / active).
    /// Clock latches at first detection and is not reset by NWPath flaps.
    private func scheduleLocalNetworkEndCallIfNeeded() {
        guard !isTearingDown else { return }
        guard phase == .outgoing || phase == .incoming || phase == .active else { return }
        if localOutageBeganAt == nil {
            localOutageBeganAt = Date()
            AppLogger.debug(
                "AgoraCallService: local outage latched — end call in \(Int(localNetworkEndCallSeconds))s"
            )
        }
        guard localNetworkEndCallTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickLocalNetworkEndCall()
            }
        }
        localNetworkEndCallTimer = timer
        tickLocalNetworkEndCall()
    }

    private func tickLocalNetworkEndCall() {
        guard !isTearingDown else { return }
        guard phase == .outgoing || phase == .incoming || phase == .active else { return }
        guard let began = localOutageBeganAt else { return }
        guard Date().timeIntervalSince(began) >= localNetworkEndCallSeconds else { return }
        guard hasSustainedLocalOutage else { return }
        // Group: live media can survive brief path flaps — hang up only if Agora is also dead.
        // 1:1: 30s of local outage is not a flap; hang up even if Agora still reports connected.
        let rtcHoldingCall = rtc.hasJoinedChannel && !isLocalRtcUnstable
        if phase == .active, isGroupCall, rtcHoldingCall {
            AppLogger.debug("AgoraCallService: path down but Agora still holding — skip hangup")
            return
        }
        AppLogger.killCall(
            "local outage timeout (\(Int(localNetworkEndCallSeconds))s) — ending call phase=\(phase)"
        )
        endCallDueToLocalNetworkLoss()
    }

    private func scheduleLocalOutageRecoverConfirmIfNeeded() {
        guard localOutageRecoverConfirmWork == nil else { return }
        guard localOutageBeganAt != nil || localNetworkEndCallTimer != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.localOutageRecoverConfirmWork = nil
            guard self.hasRecoveredFromLocalOutage else { return }
            self.cancelLocalNetworkEndCall()
        }
        localOutageRecoverConfirmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func cancelLocalOutageRecoverConfirm() {
        localOutageRecoverConfirmWork?.cancel()
        localOutageRecoverConfirmWork = nil
    }

    private func cancelLocalNetworkEndCall() {
        localNetworkEndCallTimer?.invalidate()
        localNetworkEndCallTimer = nil
        localOutageBeganAt = nil
        cancelLocalOutageRecoverConfirm()
    }

    private func endCallDueToLocalNetworkLoss() {
        guard !isTearingDown, phase != .idle else { return }
        isTearingDown = true
        callUIPresentGeneration &+= 1
        stopCallPathMonitoring()
        cancelLocalNetworkEndCall()
        remoteEndFeedbackWork?.cancel()
        remoteEndFeedbackWork = nil
        stopRingtone()
        stopCallLivenessPolling()

        let endingCallId = callId
        if let endingCallId, !endingCallId.isEmpty {
            if isGroupCall, phase == .active, !isCallOwner {
                AgoraCallSignaling.shared.leaveCall(callId: endingCallId)
            } else {
                AgoraCallSignaling.shared.endCall(callId: endingCallId)
                clearRejoinableGroupCall(matchingCallId: endingCallId)
            }
        }

        cleanupRtc()
        resetUi()
        CallKitManager.shared.endCall(reason: .failed)
    }

    private static func qualityRank(_ level: AgoraCallNetworkQualityLevel) -> Int {
        switch level {
        case .excellent: return 4
        case .good: return 3
        case .fair: return 2
        case .poor: return 1
        case .reconnecting, .lost, .unknown: return 0
        }
    }

    /// Both-way hysteresis + min dwell so bars don't bounce on noisy Agora samples.
    private func applyQualityWithHysteresis(_ mapped: AgoraCallNetworkQualityLevel) {
        let current = networkQualityLevel
        let mappedRank = Self.qualityRank(mapped)
        let currentRank = Self.qualityRank(current)

        if mappedRank == currentRank {
            qualityUpgradeCandidate = nil
            qualityUpgradeStreak = 0
            return
        }

        // After recover `.unknown` — seed bars from the first real sample (no Excellent text).
        if currentRank == 0, mappedRank > 0 {
            commitDisplayedQuality(mapped)
            return
        }

        if qualityUpgradeCandidate == mapped {
            qualityUpgradeStreak += 1
        } else {
            qualityUpgradeCandidate = mapped
            qualityUpgradeStreak = 1
        }

        let needed = mappedRank < currentRank ? qualityDowngradeStreakNeeded : qualityUpgradeStreakNeeded
        guard qualityUpgradeStreak >= needed else { return }
        if let last = lastQualityDisplayChangeAt,
           Date().timeIntervalSince(last) < qualityDisplayDwellSeconds {
            return
        }
        commitDisplayedQuality(mapped)
    }

    private func commitDisplayedQuality(_ level: AgoraCallNetworkQualityLevel) {
        networkQualityLevel = level
        lastQualityDisplayChangeAt = Date()
        qualityUpgradeCandidate = nil
        qualityUpgradeStreak = 0
    }

    private func applyNetworkQuality(_ quality: AgoraNetworkQuality) {
        guard phase == .active else { return }
        // Don't override reconnect / hold banners with quality labels.
        if isAudioOnHold { return }
        if ownsLocalConnectionBanner,
           let text = connectionStatusText,
           text == "Reconnecting…" || text == "Lost Connection" || text == "No internet" || text == "Reconnected" {
            // Don't poison lastMapped with stale Excellent while local reconnecting.
            let mappedWhileDown = AgoraCallNetworkQualityLevel.from(agoraQuality: quality)
            if mappedWhileDown == .fair || mappedWhileDown == .poor {
                lastMappedQuality = mappedWhileDown
            }
            return
        }

        let mapped = AgoraCallNetworkQualityLevel.from(agoraQuality: quality)

        // While peer is marked down, ignore stale Excellent/Good for bars.
        // Recovery is driven by media `unstable=false`, not leftover Excellent samples.
        if isRemoteUplinkUnstable || peerNetworkState == .unreachable {
            let optimistic: Set<AgoraCallNetworkQualityLevel> = [.excellent, .good]
            if optimistic.contains(mapped) {
                return
            }
            if mapped == .unknown {
                return
            }
            // Unreachable is sticky — don't let a Fair/Poor quality sample cancel the 8s recover.
            if peerNetworkState == .unreachable {
                notifyUI()
                return
            }
            lastMappedQuality = mapped
            if mapped == .poor {
                remoteUplinkRecoverWork?.cancel()
                remoteUplinkRecoverWork = nil
                qualityUpgradeCandidate = nil
                qualityUpgradeStreak = 0
                networkQualityLevel = .poor
                if !ownsLocalConnectionBanner {
                    setPeerWeakBanner()
                } else {
                    notifyUI()
                }
            }
            return
        }

        lastMappedQuality = mapped

        // `.down` is peer gone — Poor now. `.bad` / `.vBad` only move bars (talking can be bad).
        if quality == .down {
            applyConfirmedPeerUplinkLoss()
            return
        }

        applyQualityWithHysteresis(mapped)

        // Quality bars never raise the Poor / Not in network label. Media freeze / .down / didOffline do.
        if networkQualityLevel != .poor {
            weakSignalWork?.cancel()
            weakSignalWork = nil
            // Do not clear Not in network / hangup clock from stale Excellent samples.
            if ownsRemoteUplinkBanner,
               !isRemoteUplinkUnstable,
               peerNetworkState == .weak,
               connectionStatusText == "Poor connection" {
                peerNotInNetworkEscalateWork?.cancel()
                peerNotInNetworkEscalateWork = nil
                ownsRemoteUplinkBanner = false
                connectionStatusText = nil
                isReconnecting = false
                peerNetworkState = .ok
            }
        }
        notifyUI()
    }

    /// User B sees peer network drop early — before Agora `didOfflineOfUid` (often many seconds late).
    /// Brief freeze while talking is jitter. Real drop (`isConfirmed`) shows Poor immediately.
    private func handleRemotePeerUplinkUnstable(_ unstable: Bool, isConfirmed: Bool) {
        guard phase == .active else { return }
        if isAudioOnHold { return }

        if unstable {
            if peerNetworkState != .ok {
                // Already Poor / Not in network — freeze again cancels recover, keep banner.
                remoteUplinkRecoverWork?.cancel()
                remoteUplinkRecoverWork = nil
                isRemoteUplinkUnstable = true
                lastRemoteUplinkHealthyAt = nil
                if peerNetworkState == .weak {
                    schedulePeerNotInNetworkEscalateIfNeeded()
                }
                return
            }
            if isConfirmed {
                applyConfirmedPeerUplinkLoss()
            } else {
                scheduleRemoteUplinkFreezeConfirmIfNeeded()
            }
        } else {
            // Talking again: drop the freeze wait. If Poor/NIN is showing, confirm recover.
            scheduleRemoteUplinkRecoverConfirmation()
        }
    }

    /// Audio dead / quality down / remote offline — User B must see User A's drop now.
    private func applyConfirmedPeerUplinkLoss() {
        remoteUplinkUnstableWork?.cancel()
        remoteUplinkUnstableWork = nil
        remoteUplinkRecoverWork?.cancel()
        remoteUplinkRecoverWork = nil
        weakSignalWork?.cancel()
        weakSignalWork = nil
        isRemoteUplinkUnstable = true
        lastRemoteUplinkHealthyAt = nil
        qualityUpgradeCandidate = nil
        qualityUpgradeStreak = 0
        networkQualityLevel = .poor
        lastQualityDisplayChangeAt = Date()
        if ownsLocalConnectionBanner {
            notifyUI()
        } else {
            setPeerWeakBanner()
        }
    }

    /// First Agora freeze is not Poor. Only show Poor if media stays frozen for several seconds.
    private func scheduleRemoteUplinkFreezeConfirmIfNeeded() {
        guard remoteUplinkUnstableWork == nil else { return }
        guard peerNetworkState == .ok else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .active else { return }
            self.remoteUplinkUnstableWork = nil
            guard self.peerNetworkState == .ok else { return }
            self.applyConfirmedPeerUplinkLoss()
        }
        remoteUplinkUnstableWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + remoteUplinkFreezeConfirmSeconds, execute: work)
    }

    /// Peer media may flap `.decoding` while uplink is still bad; only clear after it stays healthy.
    private func scheduleRemoteUplinkRecoverConfirmation() {
        remoteUplinkUnstableWork?.cancel()
        remoteUplinkUnstableWork = nil
        // Talking again — don't escalate Poor → Not in network while media is decoding.
        peerNotInNetworkEscalateWork?.cancel()
        peerNotInNetworkEscalateWork = nil
        // Don't reset the recover clock on every bitrate/decode sample.
        guard remoteUplinkRecoverWork == nil else { return }

        // If we never marked unstable, nothing to clear (avoid accidental Excellent).
        guard isRemoteUplinkUnstable || ownsRemoteUplinkBanner || !remoteDropGraceWorkItems.isEmpty else {
            return
        }

        let delay = peerNetworkState == .unreachable ? peerUnreachableRecoverSeconds : peerPoorRecoverSeconds
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .active else { return }
            self.applyRemoteUplinkRecovered()
        }
        remoteUplinkRecoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        AppLogger.debug(
            "AgoraCallService: peer recover confirm in \(Int(delay))s unreachable=\(peerNetworkState == .unreachable)"
        )
    }

    private func applyRemoteUplinkRecovered() {
        remoteUplinkRecoverWork = nil
        remoteDropGraceBannerWork?.cancel()
        remoteDropGraceBannerWork = nil
        peerNotInNetworkEscalateWork?.cancel()
        peerNotInNetworkEscalateWork = nil
        cancelPeerOfflineEndCall()

        let wasUnstable = isRemoteUplinkUnstable
        let hadDropGrace = !remoteDropGraceWorkItems.isEmpty
        let hadPeerBanner = ownsRemoteUplinkBanner
        isRemoteUplinkUnstable = false
        ownsRemoteUplinkBanner = false
        peerNetworkState = .ok
        lastRemoteUplinkHealthyAt = Date()
        qualityUpgradeCandidate = nil
        qualityUpgradeStreak = 0
        lastQualityDisplayChangeAt = nil
        // Drop stale Excellent/Good from before the outage — wait for a fresh sample.
        lastMappedQuality = .unknown

        // Peer media is flowing again — never let a soft-offline grace kill the 1:1 call.
        if hadDropGrace {
            cancelAllRemoteDropGraceTimers()
            AppLogger.debug("AgoraCallService: cancelled drop grace — peer uplink recovered")
        }

        guard wasUnstable || hadDropGrace || hadPeerBanner else {
            notifyUI()
            return
        }

        // Keep local device offline banners (our path monitor).
        if ownsLocalConnectionBanner {
            notifyUI()
            return
        }

        connectionStatusText = nil
        isReconnecting = false
        networkQualityLevel = .unknown
        notifyUI()
    }

    private func clearRemoteUplinkUnstableTracking() {
        remoteUplinkUnstableWork?.cancel()
        remoteUplinkUnstableWork = nil
        remoteDropGraceBannerWork?.cancel()
        remoteDropGraceBannerWork = nil
        peerNotInNetworkEscalateWork?.cancel()
        peerNotInNetworkEscalateWork = nil
        cancelPeerOfflineEndCall()
        remoteUplinkRecoverWork?.cancel()
        remoteUplinkRecoverWork = nil
        isRemoteUplinkUnstable = false
        ownsRemoteUplinkBanner = false
        peerNetworkState = .ok
        lastRemoteUplinkHealthyAt = nil
        qualityUpgradeCandidate = nil
        qualityUpgradeStreak = 0
        lastQualityDisplayChangeAt = nil
    }

    func handleAudioInterruptionBegan() {
        guard phase == .active || phase == .outgoing else { return }
        isAudioOnHold = true
        notifyUI()
    }

    func handleAudioInterruptionEnded() {
        isAudioOnHold = false
        notifyUI()
    }

    func handleCameraUnavailable() {
        isCameraUnavailable = true
        if call?.type == .video || videoEnabled {
            videoEnabled = false
            GlobalToast.shared.show("Camera unavailable")
        }
        notifyUI()
    }

    func handleThermalState(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .serious, .critical:
            thermalBannerText = "Device warming up"
            rtc.forceLowVideoQualityForThermal()
        case .fair:
            thermalBannerText = nil
        case .nominal:
            thermalBannerText = nil
        @unknown default:
            thermalBannerText = nil
        }
        notifyUI()
    }

    func recheckPermissionsOnForeground() {
        guard phase == .active else { return }
        let mic = AVAudioSession.sharedInstance().recordPermission
        if mic == .denied {
            GlobalToast.shared.show("Microphone permission required")
            hangUp()
            return
        }
        if call?.type == .video {
            let cam = AVCaptureDevice.authorizationStatus(for: .video)
            if cam == .denied || cam == .restricted {
                isCameraUnavailable = true
                if videoEnabled {
                    videoEnabled = false
                    rtc.setVideoEnabled(false)
                    GlobalToast.shared.show("Camera permission revoked")
                }
                notifyUI()
            }
        }
    }

    private func cancelRemoteDropGrace(for uid: UInt) {
        remoteDropGraceWorkItems[uid]?.cancel()
        remoteDropGraceWorkItems.removeValue(forKey: uid)
        if remoteDropGraceWorkItems.isEmpty {
            remoteDropGraceBannerWork?.cancel()
            remoteDropGraceBannerWork = nil
        }
    }

    private func cancelAllRemoteDropGraceTimers() {
        remoteDropGraceWorkItems.values.forEach { $0.cancel() }
        remoteDropGraceWorkItems.removeAll()
        remoteDropGraceBannerWork?.cancel()
        remoteDropGraceBannerWork = nil
    }

    /// Soft leave (network drop) — 1:1 uses the first-detection hangup clock; group waits then removes the tile.
    private func beginRemoteDropGrace(for uid: UInt) {
        cancelRemoteDropGrace(for: uid)
        isRemoteUplinkUnstable = true
        lastRemoteUplinkHealthyAt = nil
        qualityUpgradeCandidate = nil
        qualityUpgradeStreak = 0
        lastQualityDisplayChangeAt = nil
        remoteUplinkUnstableWork?.cancel()
        remoteUplinkUnstableWork = nil
        remoteUplinkRecoverWork?.cancel()
        remoteUplinkRecoverWork = nil
        networkQualityLevel = .poor

        // WhatsApp-style: Poor first; Not in network if peer still gone after ~8s.
        if !ownsLocalConnectionBanner {
            setPeerWeakBanner()
        } else {
            peerNetworkState = .weak
            schedulePeerNotInNetworkEscalateIfNeeded()
        }

        if !isGroupCall {
            // 1:1 hangup clock starts at first detection and must not restart on late didOffline.
            schedulePeerOfflineEndCallIfNeeded()
            AppLogger.debug("AgoraCallService: 1:1 peer drop — hangup clock from first detection")
            return
        }

        remoteDropGraceBannerWork?.cancel()
        let bannerWork = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .active else { return }
            guard self.remoteDropGraceWorkItems[uid] != nil else { return }
            guard self.isRemoteUplinkUnstable else { return }
            // Prolonged peer absence — Not in network (not local RTC Reconnecting).
            self.setPeerUnreachableBanner()
        }
        remoteDropGraceBannerWork = bannerWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: bannerWork)

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.phase == .active else { return }
                self.remoteDropGraceWorkItems.removeValue(forKey: uid)
                self.finalizeRemoteDrop(uid: uid)
            }
        }
        remoteDropGraceWorkItems[uid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + remoteDropGraceSeconds, execute: work)
        AppLogger.debug("AgoraCallService: drop grace \(Int(remoteDropGraceSeconds))s for uid=\(uid)")
    }

    private func finalizeRemoteDrop(uid: UInt) {
        // Race: peer already publishing again (media recovered / rejoined) while timer fired.
        if !isRemoteUplinkUnstable {
            AppLogger.debug("AgoraCallService: skip finalizeRemoteDrop uid=\(uid) — peer uplink healthy")
            if !ownsLocalConnectionBanner, ownsRemoteUplinkBanner || isPeerConnectionBanner {
                connectionStatusText = nil
                isReconnecting = false
                ownsRemoteUplinkBanner = false
                peerNetworkState = .ok
                networkQualityLevel = lastMappedQuality == .unknown ? .good : lastMappedQuality
            }
            notifyUI()
            return
        }
        if let healthyAt = lastRemoteUplinkHealthyAt,
           Date().timeIntervalSince(healthyAt) < 5 {
            AppLogger.debug("AgoraCallService: skip finalizeRemoteDrop uid=\(uid) — peer recovered recently")
            clearRemoteUplinkUnstableTracking()
            if !ownsLocalConnectionBanner {
                connectionStatusText = nil
                isReconnecting = false
                peerNetworkState = .ok
                networkQualityLevel = lastMappedQuality == .unknown ? .good : lastMappedQuality
            }
            notifyUI()
            return
        }
        rtc.finalizeRemoteLeft(uid)
        applyRemoteLeftSideEffects(uid: uid, endOneToOneIfNeeded: true)
        clearRemoteUplinkUnstableTracking()
        if remoteDropGraceWorkItems.isEmpty, !ownsLocalConnectionBanner {
            connectionStatusText = nil
            isReconnecting = false
            ownsRemoteUplinkBanner = false
            peerNetworkState = .ok
            notifyUI()
        }
    }

    private func applyRemoteLeftSideEffects(uid: UInt, endOneToOneIfNeeded: Bool) {
        remoteParticipantUids.removeAll { $0 == uid }
        remoteVideoUids.remove(uid)
        remoteMutedUids.remove(uid)
        hasRemoteVideo = !remoteVideoUids.isEmpty
        if isGroupCall {
            markRemoteLeft(agoraUid: uid)
        }
        if isPipActive {
            rebindRtcToPipViews()
        } else {
            callUI?.syncRemoteVideoTiles(uids: remoteParticipantUids, binder: { [weak self] tileUid, view in
                self?.rtc.bindRemoteVideo(to: view, uid: tileUid)
            })
        }
        notifyUI()

        guard endOneToOneIfNeeded, !isGroupCall else {
            AppLogger.debug("AgoraCallService: remote left uid=\(uid) remaining=\(remoteParticipantUids.count)")
            return
        }
        AppLogger.killCall("1:1 remote gone — ending call uid=\(uid)")
        if let id = callId {
            finishFromRemote(endedCallId: id, reason: .ended)
        } else {
            cleanupRtc()
            resetUi()
            CallKitManager.shared.endCall(reason: .remoteEnded)
        }
    }

    /// Best-effort mid-call token refresh via `call:accept` (returns fresh token on some backends).
    private func refreshAgoraTokenFromServer() {
        guard phase == .active, let callId, !callId.isEmpty, !isRefreshingAgoraToken else { return }
        isRefreshingAgoraToken = true
        AppLogger.debug("AgoraCallService: refreshing Agora token for callId=\(callId)")
        AgoraCallSignaling.shared.acceptCall(callId: callId) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isRefreshingAgoraToken = false
                switch result {
                case .success(let session):
                    let merged = AgoraCallSession.merge(session, fallback: self.pendingSession)
                    self.pendingSession = merged
                    if !merged.token.isEmpty {
                        self.rtc.renewToken(merged.token)
                        AppLogger.debug("AgoraCallService: Agora token renewed")
                    }
                case .failure(let error):
                    AppLogger.debug("AgoraCallService: token refresh via accept failed: \(error.localizedDescription)")
                    AgoraCallSignaling.shared.fetchJoinSessionViaREST(callId: callId) { rest in
                        Task { @MainActor in
                            guard self.phase == .active else { return }
                            if case .success(let session) = rest {
                                let merged = AgoraCallSession.merge(session, fallback: self.pendingSession)
                                self.pendingSession = merged
                                if !merged.token.isEmpty {
                                    self.rtc.renewToken(merged.token)
                                    AppLogger.debug("AgoraCallService: Agora token renewed via REST")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// True once the duration ticker is running. Group initiator stays false until the first peer attends.
    var hasStartedCallTimer: Bool { elapsedTimer != nil }

    private var hasGroupPeerJoined: Bool {
        !remoteParticipantUids.isEmpty
            || attendedUserIds.contains { !$0.isEmpty && $0.caseInsensitiveCompare(meId) != .orderedSame }
    }

    private func startGroupCallTimerIfNeeded() {
        guard isGroupCall, phase == .active, elapsedTimer == nil else { return }
        guard hasGroupPeerJoined else { return }
        elapsedSec = 0
        startElapsedTimer()
        callUI?.updateElapsedDisplay()
        AgoraCallPipWindowController.shared.updateElapsedDisplay()
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .active else { return }
                self.elapsedSec += 1
                // Timer label only — full notifyUI re-layouts the video grid every second (iOS flash).
                self.callUI?.updateElapsedDisplay()
                AgoraCallPipWindowController.shared.updateElapsedDisplay()
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Ringtone (WhatsApp-style FG incoming: continuous tone + vibrate)

    /// Home / Reels / Explore AVPlayers own the shared session and drown the in-app ring.
    /// Chat list / conversation have no competing players — that is why ring worked only there.
    private func silenceConflictingInAppMediaForRingtone() {
        NotificationCenter.default.post(name: Notification.Name("STOP_REELS_AUDIO"), object: nil)
    }

    private func startRingtone(isIncoming: Bool, scheduleResumeRetries: Bool = true) {
        stopRingtone(clearIntent: false)
        // Call-waiting uses vibration only — never ring over an active call.
        guard pendingIncomingCall == nil else {
            ringtoneIsIncoming = nil
            return
        }
        guard phase == .incoming || phase == .outgoing else {
            ringtoneIsIncoming = nil
            return
        }
        guard !isCallKitOwned else {
            ringtoneIsIncoming = nil
            return
        }

        ringtoneIsIncoming = isIncoming
        observeRingtoneAudioInterruptionsIfNeeded()

        // Pause feed/reel video BEFORE claiming the session (order matters).
        silenceConflictingInAppMediaForRingtone()

        // WhatsApp-style: vibrate while the incoming ring UI is up.
        if isIncoming {
            startIncomingRingVibrateIfNeeded()
        }

        let resource = isIncoming ? "incoming_ringtone" : "outgoing_ringback"
        // Prefer CAF for reliable infinite loop (mp3 + numberOfLoops is flaky on some iOS builds).
        let url: URL? = {
            if isIncoming {
                return Bundle.main.url(forResource: "incoming_ringtone", withExtension: "caf")
                    ?? Bundle.main.url(forResource: "incoming_ringtone", withExtension: "mp3")
            }
            return Bundle.main.url(forResource: resource, withExtension: "caf")
        }()

        func finishStarted() {
            startRingtoneWatchdog()
            if scheduleResumeRetries {
                scheduleRingtoneResumeRetries()
            }
        }

        guard let url else {
            AppLogger.killCall("ringtone missing \(resource) — alertSound fallback")
            startSystemSoundRingtoneFallback(isIncoming: isIncoming)
            finishStarted()
            return
        }

        do {
            // Never setActive(false) — fights silent CallKit / Agora and kills audibility.
            configureRingtoneAudioSession(isIncoming: isIncoming)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 1.0
            player.delegate = self
            player.prepareToPlay()
            ringtonePlayer = player
            guard player.play() else {
                ringtonePlayer = nil
                AppLogger.killCall("ringtone play() false — alertSound fallback incoming=\(isIncoming)")
                startSystemSoundRingtoneFallback(isIncoming: isIncoming)
                finishStarted()
                return
            }
            AppLogger.killCall(
                "ringtone playing mode=avPlayer incoming=\(isIncoming) file=\(url.lastPathComponent) category=\(AVAudioSession.sharedInstance().category.rawValue)"
            )
            finishStarted()
        } catch {
            AppLogger.killCall("custom ringtone failed: \(error.localizedDescription)")
            ringtonePlayer = nil
            startSystemSoundRingtoneFallback(isIncoming: isIncoming)
            finishStarted()
        }
    }

    /// True when in-app ring/ringback is actually audible (not a CallKit-zombie player).
    private func isRingtoneHealthy(isIncoming: Bool) -> Bool {
        if isUsingSystemSoundRingtone, ringtoneLoopTimer != nil {
            return true
        }
        guard let player = ringtonePlayer, player.isPlaying else { return false }
        // Incoming must stay on .playback — CallKit silent-VoIP often flips category while
        // leaving isPlaying == true (silent "zombie" player after ~1–2s).
        if isIncoming {
            return AVAudioSession.sharedInstance().category == .playback
        }
        return true
    }

    /// Soft reclaim / AlertSound fallback — does not tear down CallKit or Agora sessions.
    private func resumeRingtoneIfNeeded() {
        guard let isIncoming = ringtoneIsIncoming else { return }
        guard pendingIncomingCall == nil else { return }
        guard phase == .incoming || phase == .outgoing else { return }
        guard !isCallKitOwned else { return }

        // After early Agora join, RTC owns AVAudioSession — never reclaim category/route here
        // (speaker↔earpiece thrash shows as volume HUD bouncing during dial).
        let rtcOwnsSession = didJoinRtc && !isIncoming

        if isIncoming, incomingRingVibrateTimer == nil {
            startIncomingRingVibrateIfNeeded()
        }

        // AlertSound / system-sound loop already covering the tone.
        if isUsingSystemSoundRingtone, ringtoneLoopTimer != nil {
            return
        }
        if isRingtoneHealthy(isIncoming: isIncoming) {
            return
        }

        // Still playing — only reclaim the session. Seeking to 0 restarts the loop (~1s glitch).
        if let player = ringtonePlayer, player.isPlaying {
            if rtcOwnsSession {
                return
            }
            silenceConflictingInAppMediaForRingtone()
            configureRingtoneAudioSession(isIncoming: isIncoming)
            if isRingtoneHealthy(isIncoming: isIncoming) {
                AppLogger.killCall("ringtone soft-reclaim OK (no seek) incoming=\(isIncoming)")
                return
            }
            // Category still wrong but tone is audible — leave it alone; watchdog will retry.
            return
        }

        let category = AVAudioSession.sharedInstance().category.rawValue
        let playing = ringtonePlayer?.isPlaying ?? false
        let reason: String
        if !playing {
            reason = "notPlaying"
        } else if isIncoming, AVAudioSession.sharedInstance().category != .playback {
            reason = "wrongCategory"
        } else {
            reason = "unhealthy"
        }
        AppLogger.killCall(
            "resume ringtone incoming=\(isIncoming) reason=\(reason) playing=\(playing) category=\(category)"
        )

        // Feed/reel may have stolen the session again (Home VWDisappear / autoplay).
        silenceConflictingInAppMediaForRingtone()

        // Soft path first — reclaim .playback without setActive(false).
        if let player = ringtonePlayer {
            if !rtcOwnsSession {
                configureRingtoneAudioSession(isIncoming: isIncoming)
            }
            // Seek only when stopped — never cut a playing loop back to 0.
            if !player.isPlaying {
                player.currentTime = 0
            }
            player.volume = 1.0
            if player.play(), isRingtoneHealthy(isIncoming: isIncoming) {
                AppLogger.killCall("ringtone soft-play OK incoming=\(isIncoming)")
                return
            }
        }

        if isIncoming || rtcOwnsSession {
            // Incoming: avoid CallKit fight. Outgoing+RTC: avoid setCategory vs Agora (volume HUD flicker).
            AppLogger.killCall(
                "ringtone soft-play failed — alertSound fallback incoming=\(isIncoming) rtcOwns=\(rtcOwnsSession)"
            )
            ringtonePlayer?.delegate = nil
            ringtonePlayer?.stop()
            ringtonePlayer = nil
            startSystemSoundRingtoneFallback(isIncoming: isIncoming)
            startRingtoneWatchdog()
            return
        }

        startRingtone(isIncoming: false, scheduleResumeRetries: false)
    }

    /// Incoming: `.playback` + duck/mix (survives silent CallKit). Outgoing: playAndRecord for Agora.
    /// Never deactivates the shared session (would break CallKit / RTC).
    private func configureRingtoneAudioSession(isIncoming: Bool) {
        // Agora already set voiceChat/videoChat + route — reclaiming .defaultToSpeaker fights it.
        if !isIncoming, didJoinRtc {
            AppLogger.killCall("ringtone session skip — RTC owns session")
            return
        }
        let session = AVAudioSession.sharedInstance()
        let before = session.category.rawValue
        do {
            if isIncoming {
                try session.setCategory(.playback, options: [.duckOthers, .mixWithOthers])
                try session.setActive(true)
            } else {
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.allowBluetooth, .mixWithOthers, .defaultToSpeaker]
                )
                try session.setActive(true)
                try session.overrideOutputAudioPort(.speaker)
            }
            AppLogger.killCall(
                "ringtone session OK before=\(before) after=\(session.category.rawValue) incoming=\(isIncoming)"
            )
        } catch {
            AppLogger.killCall(
                "ringtone audio session failed before=\(before): \(error.localizedDescription)"
            )
        }
    }

    /// Covers silent FG VoIP CallKit report/end (~1–2s) that silences AVAudioPlayer.
    private func scheduleRingtoneResumeRetries() {
        cancelRingtoneResumeRetries()
        let delays: [TimeInterval] = [0.15, 0.5, 1.0, 2.0, 3.0]
        for delay in delays {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // After typical CallKit silent-fulfill window, force a fresh start only if still unhealthy.
                if delay >= 2.0,
                   self.ringtoneIsIncoming == true,
                   !self.isRingtoneHealthy(isIncoming: true) {
                    self.forceRestartInAppIncomingRingtone()
                } else {
                    self.resumeRingtoneIfNeeded()
                }
            }
            ringtoneResumeRetryWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func cancelRingtoneResumeRetries() {
        ringtoneResumeRetryWorkItems.forEach { $0.cancel() }
        ringtoneResumeRetryWorkItems.removeAll()
    }

    private func startRingtoneWatchdog() {
        stopRingtoneWatchdog()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.resumeRingtoneIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ringtoneWatchdogTimer = timer
    }

    private func stopRingtoneWatchdog() {
        ringtoneWatchdogTimer?.invalidate()
        ringtoneWatchdogTimer = nil
    }

    private func startIncomingRingVibrateIfNeeded() {
        guard phase == .incoming, !isCallKitOwned, pendingIncomingCall == nil else { return }
        if incomingRingVibrateTimer != nil {
            pulseIncomingRingVibrate()
            return
        }
        pulseIncomingRingVibrate()
        let timer = Timer(timeInterval: 1.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.phase == .incoming, !self.isCallKitOwned, self.pendingIncomingCall == nil else {
                    self.stopIncomingRingVibrate()
                    return
                }
                self.pulseIncomingRingVibrate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        incomingRingVibrateTimer = timer
    }

    private func pulseIncomingRingVibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    private func stopIncomingRingVibrate() {
        incomingRingVibrateTimer?.invalidate()
        incomingRingVibrateTimer = nil
    }

    private func observeRingtoneAudioInterruptionsIfNeeded() {
        guard ringtoneInterruptionObserver == nil else { return }
        ringtoneInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                self.handleRingtoneAudioInterruption(notification)
            }
        }
    }

    private func handleRingtoneAudioInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            break
        case .ended:
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            if options.contains(.shouldResume) || ringtoneIsIncoming != nil {
                resumeRingtoneIfNeeded()
            }
        @unknown default:
            break
        }
    }

    /// AlertSound / SystemSound loop — CallKit-safe backup when AVAudioPlayer goes silent.
    private func startSystemSoundRingtoneFallback(isIncoming: Bool) {
        isUsingSystemSoundRingtone = true
        ringtoneLoopTimer?.invalidate()
        ringtoneLoopTimer = nil
        if ringtoneSoundID > 2000 {
            AudioServicesDisposeSystemSoundID(ringtoneSoundID)
            ringtoneSoundID = 1005
        }

        let resource = isIncoming ? "incoming_ringtone" : "outgoing_ringback"
        if let url = Bundle.main.url(forResource: resource, withExtension: "caf") {
            var soundID: SystemSoundID = 0
            let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
            if status == kAudioServicesNoError, soundID != 0 {
                ringtoneSoundID = soundID
                playRingtoneSystemSound(isIncoming: isIncoming)
                // Re-trigger often enough that CallKit steal never leaves a long quiet gap.
                let interval: TimeInterval = isIncoming ? 2.0 : 2.8
                let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        guard self.pendingIncomingCall == nil else {
                            self.stopRingtone()
                            return
                        }
                        guard self.phase == .incoming || self.phase == .outgoing else {
                            self.stopRingtone()
                            return
                        }
                        guard !self.isCallKitOwned else {
                            self.stopRingtone()
                            return
                        }
                        self.playRingtoneSystemSound(isIncoming: isIncoming)
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                ringtoneLoopTimer = timer
                AppLogger.killCall("ringtone mode=alertSound caf interval=\(interval) incoming=\(isIncoming)")
                return
            }
        }

        ringtoneSoundID = isIncoming ? 1005 : 1007
        playRingtoneSystemSound(isIncoming: isIncoming)
        let interval: TimeInterval = isIncoming ? 2.0 : 2.4
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.pendingIncomingCall == nil else {
                    self.stopRingtone()
                    return
                }
                guard self.phase == .incoming || self.phase == .outgoing else {
                    self.stopRingtone()
                    return
                }
                guard !self.isCallKitOwned else {
                    self.stopRingtone()
                    return
                }
                self.playRingtoneSystemSound(isIncoming: isIncoming)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ringtoneLoopTimer = timer
        AppLogger.killCall("ringtone mode=alertSound builtIn interval=\(interval) incoming=\(isIncoming)")
    }

    private func playRingtoneSystemSound(isIncoming: Bool) {
        // AlertSound is louder / better for ring intent; SystemSound for outgoing cue.
        if isIncoming {
            AudioServicesPlayAlertSound(ringtoneSoundID)
        } else {
            AudioServicesPlaySystemSound(ringtoneSoundID)
        }
    }

    private func stopRingtone(clearIntent: Bool = true) {
        stopRingtoneWatchdog()
        stopIncomingRingVibrate()
        if clearIntent {
            cancelRingtoneResumeRetries()
        }
        ringtoneLoopTimer?.invalidate()
        ringtoneLoopTimer = nil
        ringtonePlayer?.delegate = nil
        ringtonePlayer?.stop()
        ringtonePlayer = nil
        isUsingSystemSoundRingtone = false
        // Dispose custom SystemSoundIDs we created from caf (not the built-in 1005/1007).
        if ringtoneSoundID > 2000 {
            AudioServicesDisposeSystemSoundID(ringtoneSoundID)
        }
        ringtoneSoundID = 1005
        if clearIntent {
            ringtoneIsIncoming = nil
        }
        // Do not deactivate AVAudioSession — Agora / CallKit may own it.
    }
}

extension AgoraCallService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            // Infinite loop failed (often mp3) or session interrupted mid-file — restart while still ringing.
            guard self.ringtonePlayer === player || self.ringtonePlayer == nil else { return }
            self.resumeRingtoneIfNeeded()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            AppLogger.debug(
                "AgoraCallService: ringtone decode error \(error?.localizedDescription ?? "nil")"
            )
            self.resumeRingtoneIfNeeded()
        }
    }
}

extension AgoraCallService: AgoraRtcManagerDelegate {
    nonisolated func agoraRtcManagerDidJoinChannel(_ manager: AgoraRtcManager) {
        Task { @MainActor in
            AppLogger.debug("AgoraCallService: joined Agora channel")
            // RTC already reconciled headset vs speaker — sync flags for UI.
            self.speakerOn = self.rtc.isSpeakerOn
            self.audioRoute = self.rtc.currentAudioRoute
            self.notifyUI()
        }
    }

    nonisolated func agoraRtcManager(_ manager: AgoraRtcManager, didFail error: String) {
        Task { @MainActor in
            self.errorMessage = error
            self.notifyUI()
        }
    }

    nonisolated func agoraRtcManager(_ manager: AgoraRtcManager, remoteUidJoined uid: UInt, userAccount: String?) {
        Task { @MainActor in
            AppLogger.debug("AgoraCallService: remote uid \(uid) account=\(userAccount ?? "nil") joined")
            // Cancel drop-grace — peer came back after a network blip.
            self.cancelRemoteDropGrace(for: uid)
            // Also clear any other soft-drop timers (uid can change across reconnect on some paths).
            if !self.remoteDropGraceWorkItems.isEmpty {
                self.cancelAllRemoteDropGraceTimers()
            }
            // 1:1: Agora often rebuilds the remote uid on a drop (same as treating `.quit` as
            // a soft leave). Don't wipe Not in network / Poor instantly.
            let peerLooksGone = self.peerNetworkState != .ok
                || self.isRemoteUplinkUnstable
                || self.ownsRemoteUplinkBanner
                || self.peerOfflineEndCallWork != nil
            if !self.isGroupCall, peerLooksGone {
                self.scheduleRemoteUplinkRecoverConfirmation()
            } else {
                self.applyRemoteUplinkRecovered()
            }
            if !self.remoteParticipantUids.contains(uid) {
                self.remoteParticipantUids.append(uid)
            }
            if self.isGroupCall {
                self.markRemoteAttended(agoraUid: uid, userAccount: userAccount)
                self.startGroupCallTimerIfNeeded()
            }
            // 1:1: Android may join Agora before call:join arrives — flip to active on first remote.
            if self.phase == .outgoing, let pending = self.pendingSession {
                await self.enterActive(pending)
            }
            if self.isPipActive {
                self.rebindRtcToPipViews()
            } else if let ui = self.callUI {
                ui.syncRemoteVideoTiles(uids: self.remoteParticipantUids, binder: { [weak self] tileUid, view in
                    self?.rtc.bindRemoteVideo(to: view, uid: tileUid)
                })
            }
            self.notifyUI()
        }
    }

    nonisolated func agoraRtcManager(_ manager: AgoraRtcManager, remoteUidLeft uid: UInt, reason: AgoraUserOfflineReason) {
        Task { @MainActor in
            guard self.phase == .active else { return }
            let hardLeave = (reason == .quit || reason == .becomeAudience)
            AppLogger.debug(
                "AgoraCallService: remoteUidLeft uid=\(uid) reason=\(reason.rawValue) hardLeave=\(hardLeave)"
            )
            if hardLeave {
                self.cancelRemoteDropGrace(for: uid)
                // Group: remove tile immediately.
                if self.isGroupCall {
                    self.rtc.finalizeRemoteLeft(uid)
                    self.applyRemoteLeftSideEffects(uid: uid, endOneToOneIfNeeded: true)
                    return
                }
                // 1:1: Agora often reports `.quit` when the peer's RTC session is rebuilt on
                // reconnect. Real hangup is delivered via socket `call:end` — use soft grace
                // so a network blip does not instantly kill User B's call.
                AppLogger.debug(
                    "AgoraCallService: 1:1 treating hardLeave as soft drop uid=\(uid) reason=\(reason.rawValue)"
                )
                self.beginRemoteDropGrace(for: uid)
                return
            }
            // Stale soft-offline after peer already recovered (media decoding again).
            // Starting grace here would end the 1:1 call ~12s later even though A is back.
            if let healthyAt = self.lastRemoteUplinkHealthyAt,
               Date().timeIntervalSince(healthyAt) < 4 {
                AppLogger.debug(
                    "AgoraCallService: ignore stale soft offline uid=\(uid) — peer recovered \(Int(Date().timeIntervalSince(healthyAt)))s ago"
                )
                return
            }
            // Network drop / temporary offline — wait for reconnect before ending the call.
            self.beginRemoteDropGrace(for: uid)
        }
    }

    nonisolated func agoraRtcManager(
        _ manager: AgoraRtcManager,
        connectionStateChanged state: AgoraConnectionState,
        reason: AgoraConnectionChangedReason
    ) {
        Task { @MainActor in
            guard !self.isTearingDown else { return }
            guard self.phase == .active || self.phase == .outgoing else { return }
            self.lastLocalRtcConnectionState = state
            switch state {
            case .connecting:
                // Initial join — do not flash "Reconnecting…".
                break
            case .reconnecting:
                self.scheduleReconnectingStatus()
                self.scheduleLocalNetworkEndCallIfNeeded()
            case .connected:
                self.handleRtcConnectedStatus()
            case .failed:
                self.scheduleReconnectingStatus()
                self.scheduleLocalNetworkEndCallIfNeeded()
                AppLogger.debug("AgoraCallService: RTC connection failed reason=\(reason.rawValue) — waiting for SDK retry")
            case .disconnected:
                if self.phase == .active {
                    self.scheduleReconnectingStatus()
                    self.scheduleLocalNetworkEndCallIfNeeded()
                }
            @unknown default:
                break
            }
        }
    }

    nonisolated func agoraRtcManagerTokenWillExpire(_ manager: AgoraRtcManager) {
        Task { @MainActor in
            self.refreshAgoraTokenFromServer()
        }
    }

    nonisolated func agoraRtcManager(_ manager: AgoraRtcManager, remoteNetworkQuality quality: AgoraNetworkQuality) {
        Task { @MainActor in
            self.applyNetworkQuality(quality)
        }
    }

    nonisolated func agoraRtcManager(
        _ manager: AgoraRtcManager,
        remotePeerUplinkUnstable uid: UInt,
        unstable: Bool,
        isConfirmed: Bool
    ) {
        Task { @MainActor in
            // 1:1: any remote; group: only react for tracked participants.
            if self.isGroupCall, !self.remoteParticipantUids.contains(uid), unstable {
                return
            }
            self.handleRemotePeerUplinkUnstable(unstable, isConfirmed: isConfirmed)
        }
    }

    nonisolated func agoraRtcManagerAudioInterruptionBegan(_ manager: AgoraRtcManager) {
        Task { @MainActor in
            self.handleAudioInterruptionBegan()
        }
    }

    nonisolated func agoraRtcManagerAudioInterruptionEnded(_ manager: AgoraRtcManager) {
        Task { @MainActor in
            self.handleAudioInterruptionEnded()
        }
    }

    nonisolated func agoraRtcManagerCameraUnavailable(_ manager: AgoraRtcManager) {
        Task { @MainActor in
            self.handleCameraUnavailable()
        }
    }

    nonisolated func agoraRtcManager(_ manager: AgoraRtcManager, thermalStateChanged state: ProcessInfo.ThermalState) {
        Task { @MainActor in
            self.handleThermalState(state)
        }
    }

    nonisolated func agoraRtcManagerDidBecomeActive(_ manager: AgoraRtcManager) {
        Task { @MainActor in
            self.recheckPermissionsOnForeground()
        }
    }

    nonisolated func agoraRtcManager(_ manager: AgoraRtcManager, remoteVideoStateChanged uid: UInt, hasVideo: Bool) {
        Task { @MainActor in
            if hasVideo {
                let isNewVideoUid = !self.remoteVideoUids.contains(uid)
                self.remoteVideoUids.insert(uid)
                // Group / audio calls: turn on decode so remote screen-share is visible.
                self.rtc.ensureRemoteVideoReceiveEnabled()
                // Bind only when video first appears or this uid has no canvas yet.
                // Re-binding every decoding/frozen callback flashes remote video on iOS.
                let needsBind = isNewVideoUid || !self.rtc.isRemoteVideoBound(uid: uid)
                if needsBind {
                    if self.isPipActive {
                        self.rebindRtcToPipViews()
                    } else if let ui = self.callUI {
                        // WhatsApp-style: 1 remote → full-screen; 2+ remotes → equal tile grid.
                        let gridUids = self.isGroupCall
                            ? self.remoteParticipantUids
                            : Array(self.remoteVideoUids).sorted()
                        if gridUids.count <= 1 {
                            self.rtc.bindRemoteVideo(to: ui.primaryRemoteVideoView, uid: uid)
                        } else {
                            ui.syncRemoteVideoTiles(uids: gridUids, binder: { [weak self] tileUid, view in
                                self?.rtc.bindRemoteVideo(to: view, uid: tileUid)
                            })
                        }
                    }
                }
                let wasShowingRemote = self.hasRemoteVideo
                self.hasRemoteVideo = true
                // Skip full UI reload when nothing structural changed (stops 1Hz-style flash).
                if isNewVideoUid || !wasShowingRemote || needsBind {
                    self.notifyUI()
                } else if self.isPipActive {
                    AgoraCallPipWindowController.shared.overlay?.refreshTileMetadataOnly()
                } else {
                    self.callUI?.refreshRemoteTileMetadataOnly()
                }
            } else {
                guard self.remoteVideoUids.contains(uid) else { return }
                self.remoteVideoUids.remove(uid)
                self.hasRemoteVideo = !self.remoteVideoUids.isEmpty
                self.notifyUI()
            }
        }
    }

    nonisolated func agoraRtcManager(_ manager: AgoraRtcManager, remoteAudioMuted uid: UInt, muted: Bool) {
        Task { @MainActor in
            if muted {
                self.remoteMutedUids.insert(uid)
            } else {
                self.remoteMutedUids.remove(uid)
            }
            // Mute badge only — avoid full video grid reload.
            self.callUI?.refreshRemoteTileMetadataOnly()
            AgoraCallPipWindowController.shared.reload()
        }
    }

    nonisolated func agoraRtcManager(
        _ manager: AgoraRtcManager,
        audioRouteChanged route: AgoraCallAudioRoute,
        speakerOn: Bool
    ) {
        Task { @MainActor in
            self.speakerOn = speakerOn
            self.audioRoute = route
            self.notifyUI()
        }
    }

    nonisolated func agoraRtcManager(_ manager: AgoraRtcManager, screenSharingChanged isSharing: Bool) {
        Task { @MainActor in
            self.isScreenSharing = isSharing
            self.rtc.setSpeakerOn(self.speakerOn)
            if isSharing {
                // Avoid capture↔render freeze: don't draw remote/local video while sharing.
                self.rtc.detachAllVideoCanvases()
                self.notifyUI()
                return
            }

            // After share stops, re-enable camera publish + UI binding for video calls.
            if self.call?.type == .video {
                self.videoEnabled = true
                self.rtc.setVideoEnabled(true)
            }
            self.notifyUI()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, !self.isScreenSharing else { return }
                if self.call?.type == .video {
                    self.rtc.setVideoEnabled(true)
                }
                self.rebindVideoViewsAfterScreenShare()
                self.notifyUI()
            }
        }
    }

    private func rebindVideoViewsAfterScreenShare() {
        let showLocal = call?.type == .video && videoEnabled
        if isPipActive, let overlay = AgoraCallPipWindowController.shared.overlay {
            var remoteViews: [UInt: UIView] = [:]
            if isGroupCall, remoteParticipantUids.count > 1 {
                overlay.syncRemoteVideoTiles(uids: remoteParticipantUids, binder: { uid, view in
                    remoteViews[uid] = view
                })
            } else if let uid = remoteParticipantUids.first ?? rtc.remoteUid {
                remoteViews[uid] = overlay.remoteVideoView
            }
            rtc.restoreVideoCanvases(
                localView: showLocal ? overlay.localVideoView : nil,
                remoteViews: remoteViews
            )
            overlay.reload()
            return
        }
        guard let ui = callUI else { return }
        var remoteViews: [UInt: UIView] = [:]
        let gridUids = isGroupCall && call?.type == .video
            ? remoteParticipantUids
            : Array(remoteVideoUids).sorted()
        if gridUids.count > 1 {
            ui.syncRemoteVideoTiles(uids: gridUids, binder: { uid, view in
                remoteViews[uid] = view
            })
        } else if let uid = gridUids.first ?? remoteParticipantUids.first {
            remoteViews[uid] = ui.primaryRemoteVideoView
        }
        rtc.restoreVideoCanvases(
            localView: showLocal ? ui.activeLocalVideoSurface : nil,
            remoteViews: remoteViews
        )
    }
}
