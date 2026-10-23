//
//  AgoraCallSignaling.swift
//  FlirttimeNew
//
//  Socket.IO + REST helpers matching Android / web CallSession contract.
//

import Foundation
import Swinject
import RxSwift

final class AgoraCallSignaling {

    static let shared = AgoraCallSignaling()

    private let timeoutSeconds: TimeInterval = 18
    private let connectTimeoutSeconds: TimeInterval = 5
    private var listenerIds: [UUID] = []
    /// callId → audio/video so decline/end/leave hit the matching REST + socket family.
    private var callTypes: [String: AgoraCallType] = [:]

    private init() {}

    // MARK: - Emit helpers

    /// REST `POST /calls/` + `GET calls/{id}` kick in when the India socket is slow or timed out.
    private static let isCallsRESTEnabled = true

    /// Kick the India socket without waiting — emit queues until connected (Dubai/UAE RTT).
    private func warmSocketAndEmit() {
        ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "agora-signaling-emit")
        ChatSocketManager.shared.ensureConnecting()
    }

    /// Audio: `POST /api/v1/calls` + `call:create`. Video: existing `/calls/video/initiate`.
    func startCall(
        conversationId: String,
        type: AgoraCallType,
        calleeId: String? = nil,
        completion: @escaping (Result<AgoraCallSession, Error>) -> Void
    ) {
        startCallViaREST(conversationId: conversationId, type: type, calleeId: calleeId, completion: completion)
    }

    private func startCallViaSocket(
        conversationId: String,
        type: AgoraCallType,
        completion: @escaping (Result<AgoraCallSession, Error>) -> Void
    ) {
        let requestId = UUID().uuidString
        waitForAck(event: AgoraCallSocketEvents.createAckEvent(for: type), requestId: requestId) { [weak self] result in
            if case .success(let session) = result {
                self?.remember(type: session.call.type, callId: session.call.id)
            }
            completion(result)
        }
        let payload: [String: Any] = [
            "conversationId": conversationId,
            "type": type.rawValue,
            "requestId": requestId
        ]
        let event = AgoraCallSocketEvents.createEvent(for: type)
        AppLogger.debug("AgoraCallSignaling: emit \(event) conversationId=\(conversationId) type=\(type.rawValue)")
        ChatSocketManager.shared.emitMessage(event, withData: [payload])
    }

    private func startCallViaREST(
        conversationId: String,
        type: AgoraCallType,
        calleeId: String?,
        completion: @escaping (Result<AgoraCallSession, Error>) -> Void
    ) {
        guard let sessionManager = Container.sharedContainer.resolve(SessionManager.self) else {
            DispatchQueue.main.async {
                completion(.failure(AgoraCallError.failed("Unable to start call (no session manager)")))
            }
            return
        }

        let peerId = (calleeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let request: Single<[String: Any]>
        let apiLabel: String
        if type == .audio {
            request = sessionManager.startUnifiedCall(
                conversationId: conversationId,
                type: AgoraCallType.audio.rawValue,
                calleeId: peerId.isEmpty ? nil : peerId
            )
            apiLabel = "POST /calls"
        } else {
            guard !peerId.isEmpty else {
                DispatchQueue.main.async {
                    completion(.failure(AgoraCallError.failed("Unable to start call (missing callee)")))
                }
                return
            }
            request = sessionManager.initiateVideoCall(calleeId: peerId, conversationId: conversationId)
            apiLabel = "POST /calls/video/initiate"
        }

        _ = request
            .subscribe(onSuccess: { [weak self] dict in
                if let session = Self.parseJoinSession(from: dict) {
                    self?.remember(type: type, callId: session.call.id)
                    DispatchQueue.main.async { completion(.success(session)) }
                } else if type == .audio, let self {
                    AppLogger.debug("AgoraCallSignaling: audio REST payload unparsed — fallback call:create")
                    self.startCallViaSocket(conversationId: conversationId, type: type, completion: completion)
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(AgoraCallError.failed("Invalid REST call session payload")))
                    }
                }
            }, onFailure: { [weak self] error in
                let message = error.localizedDescription
                CallInternationalDiagnostics.noteAPI(event: apiLabel, success: false, detail: message)
                if AgoraCallError.isBusyMessage(message) {
                    DispatchQueue.main.async { completion(.failure(AgoraCallError.busy)) }
                    return
                }
                if type == .audio, let self {
                    AppLogger.debug("AgoraCallSignaling: audio REST start failed — fallback call:create")
                    self.startCallViaSocket(conversationId: conversationId, type: type, completion: completion)
                    return
                }
                DispatchQueue.main.async {
                    completion(.failure(AgoraCallError.failed(message)))
                }
            })
    }

    func acceptCall(
        callId: String,
        type: AgoraCallType? = nil,
        completion: @escaping (Result<AgoraCallSession, Error>) -> Void
    ) {
        guard let sessionManager = Container.sharedContainer.resolve(SessionManager.self) else {
            DispatchQueue.main.async {
                completion(.failure(AgoraCallError.failed("Unable to accept call (no session manager)")))
            }
            return
        }

        let resolved = resolvedType(callId: callId, preferred: type)
        remember(type: resolved, callId: callId)

        if resolved == .audio {
            emitCallControl(
                event: AgoraCallSocketEvents.audioAccept,
                callId: callId,
                attempt: 1
            )
        }

        let request = resolved == .audio
            ? sessionManager.acceptUnifiedCall(callId: callId)
            : sessionManager.acceptVideoCall(callId: callId)

        _ = request
            .subscribe(onSuccess: { [weak self] dict in
                if let session = Self.parseJoinSession(from: dict) {
                    self?.remember(type: session.call.type, callId: session.call.id)
                    DispatchQueue.main.async { completion(.success(session)) }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(AgoraCallError.failed("Invalid REST accept payload")))
                    }
                }
            }, onFailure: { error in
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            })
    }

    private func acceptCallWithRetry(
        callId: String,
        attempt: Int,
        maxAttempts: Int,
        completion: @escaping (Result<AgoraCallSession, Error>) -> Void
    ) {
        warmSocketAndEmit()
        let connected = ChatSocketManager.shared.isSocketConnected()
        AppLogger.killCall(
            "acceptCall attempt \(attempt)/\(maxAttempts) callId=\(callId) socketConnected=\(connected) connecting=\(ChatSocketManager.shared.isSocketConnecting())"
        )

        let requestId = UUID().uuidString
        waitForAck(event: AgoraCallSocketEvents.join, requestId: requestId) { [weak self] result in
            switch result {
            case .success:
                completion(result)
            case .failure(let error):
                let shouldRetry: Bool = {
                    guard attempt < maxAttempts else { return false }
                    if let callError = error as? AgoraCallError {
                        switch callError {
                        case .busy, .failed:
                            return false
                        default:
                            return true
                        }
                    }
                    return true
                }()
                guard let self, shouldRetry else {
                    completion(result)
                    return
                }
                AppLogger.killCall("acceptCall ack failed (\(error.localizedDescription)) — retry")
                self.acceptCallWithRetry(
                    callId: callId,
                    attempt: attempt + 1,
                    maxAttempts: maxAttempts,
                    completion: completion
                )
            }
        }
        let payload: [String: Any] = [
            "callId": callId,
            "requestId": requestId
        ]
        AppLogger.killCall("emit call:accept callId=\(callId) requestId=\(requestId)")
        ChatSocketManager.shared.emitMessage(AgoraCallSocketEvents.accept, withData: [payload])
    }

    /// GET `calls/{id}` — credentials fallback when `call:join` ack is slow (cold socket / VoIP).
    func fetchJoinSessionViaREST(callId: String, completion: @escaping (Result<AgoraCallSession, Error>) -> Void) {
        guard let sessionManager = Container.sharedContainer.resolve(SessionManager.self) else {
            DispatchQueue.main.async {
                completion(.failure(AgoraCallError.failed("Unable to fetch call (no session manager)")))
            }
            return
        }
        _ = sessionManager.fetchAgoraCall(callId: callId)
            .subscribe(onSuccess: { [weak self] dict in
                CallInternationalDiagnostics.noteAPI(event: "GET calls/\(callId)", success: true)
                if let session = Self.parseJoinSession(from: dict) {
                    self?.remember(type: session.call.type, callId: session.call.id)
                    DispatchQueue.main.async { completion(.success(session)) }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(AgoraCallError.failed("Invalid REST call session payload")))
                    }
                }
            }, onFailure: { error in
                DispatchQueue.main.async {
                    CallInternationalDiagnostics.noteAPI(
                        event: "GET calls/\(callId)",
                        success: false,
                        detail: error.localizedDescription
                    )
                    completion(.failure(error))
                }
            })
    }

    private static func parseJoinSession(from dict: [String: Any]) -> AgoraCallSession? {
        if let session = AgoraCallSession(dict: dict) {
            return session
        }
        if let nested = dict["session"] as? [String: Any], let session = AgoraCallSession(dict: nested) {
            return session
        }
        if dict["id"] != nil, dict["channelName"] != nil || dict["conversationId"] != nil {
            var wrapped: [String: Any] = ["call": dict]
            wrapped["token"] = dict["token"]
            wrapped["uid"] = dict["uid"]
            wrapped["appId"] = dict["appId"]
            return AgoraCallSession(dict: wrapped)
        }
        if let call = dict["call"] as? [String: Any] {
            var wrapped: [String: Any] = ["call": call]
            wrapped["token"] = dict["token"] ?? call["token"]
            wrapped["uid"] = dict["uid"] ?? call["uid"]
            wrapped["appId"] = dict["appId"] ?? call["appId"]
            return AgoraCallSession(dict: wrapped)
        }
        return nil
    }

    func declineCall(callId: String, reason: String? = nil, type: AgoraCallType? = nil) {
        let resolved = resolvedType(callId: callId, preferred: type)
        remember(type: resolved, callId: callId)
        var extra: [String: Any] = [:]
        if let reason, !reason.isEmpty {
            extra["reason"] = reason
            extra["status"] = reason
        } else {
            // Explicit reject (web: decline without busy → reason declined).
            extra["reason"] = AgoraCallDeclineReason.declined.rawValue
            extra["status"] = AgoraCallDeclineReason.declined.rawValue
        }
        emitCallControl(
            event: AgoraCallSocketEvents.declineEvent(for: resolved),
            callId: callId,
            attempt: 1,
            extra: extra
        )
        if let sessionManager = Container.sharedContainer.resolve(SessionManager.self) {
            let request = resolved == .audio
                ? sessionManager.declineUnifiedCall(callId: callId)
                : sessionManager.rejectVideoCall(callId: callId)
            _ = request
                .subscribe(onSuccess: { _ in
                    AppLogger.killCall("REST decline OK callId=\(callId) type=\(resolved.rawValue)")
                }, onFailure: { error in
                    AppLogger.killCall("REST decline failed: \(error.localizedDescription)")
                })
        }
    }

    /// Notify caller that the callee is already on another call.
    func notifyBusy(callId: String, type: AgoraCallType? = nil) {
        let resolved = resolvedType(callId: callId, preferred: type)
        let event = resolved == .video ? AgoraCallSocketEvents.busy : AgoraCallSocketEvents.audioBusy
        emitCallControl(
            event: event,
            callId: callId,
            attempt: 1,
            extra: [
                "reason": AgoraCallDeclineReason.busy.rawValue,
                "status": AgoraCallDeclineReason.busy.rawValue
            ]
        )
    }

    /// Callee device is ringing — caller should show "Ringing…" (WhatsApp-style).
    func notifyRinging(callId: String, type: AgoraCallType? = nil) {
        let resolved = resolvedType(callId: callId, preferred: type)
        let event = resolved == .video ? AgoraCallSocketEvents.ringing : AgoraCallSocketEvents.audioRinging
        emitCallControl(
            event: event,
            callId: callId,
            attempt: 1,
            extra: ["status": "ringing", "call_id": callId]
        )
    }

    func endCall(callId: String, supersededBy: String? = nil, type: AgoraCallType? = nil) {
        let resolved = resolvedType(callId: callId, preferred: type)
        remember(type: resolved, callId: callId)
        var extra: [String: Any] = [:]
        if let supersededBy, !supersededBy.isEmpty {
            extra["supersededBy"] = supersededBy
            extra["reason"] = "switched"
            extra["status"] = "ended"
        }
        emitCallControl(
            event: AgoraCallSocketEvents.endEvent(for: resolved),
            callId: callId,
            attempt: 1,
            extra: extra
        )
        if let sessionManager = Container.sharedContainer.resolve(SessionManager.self) {
            let request = resolved == .audio
                ? sessionManager.endUnifiedCall(callId: callId)
                : sessionManager.endVideoCall(callId: callId)
            _ = request
                .subscribe(onSuccess: { _ in
                    AppLogger.killCall("REST end OK callId=\(callId) type=\(resolved.rawValue)")
                }, onFailure: { error in
                    AppLogger.killCall("REST end failed: \(error.localizedDescription)")
                })
        }
    }

    /// Leave an ongoing group call without ending it for everyone else.
    func leaveCall(callId: String, type: AgoraCallType? = nil) {
        let resolved = resolvedType(callId: callId, preferred: type)
        remember(type: resolved, callId: callId)
        emitCallControl(
            event: AgoraCallSocketEvents.leaveEvent(for: resolved),
            callId: callId,
            attempt: 1
        )
        if resolved == .audio, let sessionManager = Container.sharedContainer.resolve(SessionManager.self) {
            _ = sessionManager.leaveUnifiedCall(callId: callId)
                .subscribe(onSuccess: { _ in
                    AppLogger.killCall("REST leave OK callId=\(callId)")
                }, onFailure: { error in
                    AppLogger.killCall("REST leave failed: \(error.localizedDescription)")
                })
        }
    }

    /// Decline / end / leave must not silently fail when CallKit answers before the socket is up.
    private func emitCallControl(
        event: String,
        callId: String,
        attempt _: Int,
        maxAttempts _: Int = 3,
        extra: [String: Any] = [:]
    ) {
        warmSocketAndEmit()
        var payload: [String: Any] = [
            "callId": callId,
            "requestId": UUID().uuidString
        ]
        for (key, value) in extra {
            payload[key] = value
        }
        AppLogger.killCall(
            "emit \(event) callId=\(callId) extra=\(extra.keys.sorted()) queued=\(!ChatSocketManager.shared.isSocketConnected())"
        )
        ChatSocketManager.shared.emitMessage(event, withData: [payload])
    }

    // MARK: - Socket readiness

    /// Connects the chat socket if needed, then calls completion on the main queue.
    /// Does **not** tear down an in-flight handshake (forceReconnect added 5–8s on UAE paths).
    func ensureSocketConnected(completion: @escaping (Bool) -> Void) {
        if ChatSocketManager.shared.isSocketConnected() {
            AppLogger.killCall("ensureSocketConnected — already connected")
            DispatchQueue.main.async { completion(true) }
            return
        }

        guard ChatSocketManager.shared.hasAccessToken() else {
            AppLogger.killCall("ensureSocketConnected — NO access token (user session missing on cold start?)")
            DispatchQueue.main.async { completion(false) }
            return
        }

        AppLogger.killCall(
            "ensureSocketConnected — wait existing handshake (timeout=\(connectTimeoutSeconds)s) connecting=\(ChatSocketManager.shared.isSocketConnecting())"
        )
        var finished = false
        var observer: NSObjectProtocol?

        let finish: (Bool) -> Void = { success in
            guard !finished else { return }
            finished = true
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            AppLogger.killCall("ensureSocketConnected result=\(success)")
            DispatchQueue.main.async {
                completion(success)
            }
        }

        observer = NotificationCenter.default.addObserver(
            forName: .chatSocketDidConnect,
            object: nil,
            queue: .main
        ) { _ in
            finish(true)
        }

        ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "ensure-socket-connected")
        ChatSocketManager.shared.ensureConnecting()

        DispatchQueue.main.asyncAfter(deadline: .now() + connectTimeoutSeconds) {
            finish(ChatSocketManager.shared.isSocketConnected())
        }
    }

    // MARK: - Persistent listeners

    @discardableResult
    func onIncoming(_ handler: @escaping (AgoraCallDto) -> Void) -> UUID {
        // Video stays on video_call:incoming. Voice uses call:incoming only.
        listen(AgoraCallSocketEvents.incoming) { [weak self] data in
            self?.handleIncomingPayload(data, defaultType: .video, handler: handler)
        }
        return listen(AgoraCallSocketEvents.audioIncoming) { [weak self] data in
            self?.handleIncomingPayload(data, defaultType: .audio, handler: handler)
        }
    }

    private func handleIncomingPayload(
        _ data: [Any],
        defaultType: AgoraCallType,
        handler: @escaping (AgoraCallDto) -> Void
    ) {
        guard let dict = Self.firstDict(data) else { return }
        // Shapes: { call }, { data: { call } }, { session: { call } }, or bare CallDto
        var callDict: [String: Any]
        if let call = dict["call"] as? [String: Any] {
            callDict = call
        } else if let session = dict["session"] as? [String: Any],
                  let call = session["call"] as? [String: Any] {
            callDict = call
        } else if let nested = dict["data"] as? [String: Any],
                  let call = nested["call"] as? [String: Any] {
            callDict = call
        } else if dict["id"] != nil, dict["channelName"] != nil || dict["conversationId"] != nil {
            callDict = dict
        } else {
            return
        }
        if callDict["type"] == nil, callDict["callType"] == nil {
            let sessionType = dict["type"]
                ?? (dict["session"] as? [String: Any])?["type"]
                ?? defaultType.rawValue
            callDict["type"] = sessionType
        }
        guard let call = Self.decode(AgoraCallDto.self, from: callDict), !call.id.isEmpty else { return }
        remember(type: call.type, callId: call.id)
        handler(call)
    }

    @discardableResult
    func onJoin(_ handler: @escaping (AgoraCallSession) -> Void) -> UUID {
        listenMany([
            AgoraCallSocketEvents.join,
            AgoraCallSocketEvents.audioJoin,
            AgoraCallSocketEvents.audioAccepted
        ]) { [weak self] data in
            guard let dict = Self.firstDict(data) else { return }
            if let success = dict["success"] as? Bool, !success { return }
            if let session = Self.parseJoinSession(from: dict) {
                self?.remember(type: session.call.type, callId: session.call.id)
                handler(session)
            }
        }
    }

    @discardableResult
    func onDeclined(_ handler: @escaping (AgoraCallLifecyclePayload) -> Void) -> UUID {
        listenMany([AgoraCallSocketEvents.declined, AgoraCallSocketEvents.audioDeclined]) { data in
            guard let dict = Self.firstDict(data),
                  let payload = Self.lifecyclePayload(from: dict) else {
                AppLogger.debug("AgoraCallSignaling: call:declined missing callId")
                return
            }
            AppLogger.killCall(
                "call:declined callId=\(payload.callId) reason=\(payload.reason ?? "nil") callEnded=\(String(describing: payload.callEnded))"
            )
            handler(payload)
        }
    }

    @discardableResult
    func onBusy(_ handler: @escaping (AgoraCallLifecyclePayload) -> Void) -> UUID {
        listenMany([AgoraCallSocketEvents.busy, AgoraCallSocketEvents.audioBusy]) { data in
            guard let dict = Self.firstDict(data),
                  let payload = Self.lifecyclePayload(from: dict) else {
                AppLogger.debug("AgoraCallSignaling: call:busy missing callId keys")
                return
            }
            AppLogger.killCall(
                "call:busy callId=\(payload.callId) callEnded=\(String(describing: payload.callEnded))"
            )
            handler(payload)
        }
    }

    @discardableResult
    func onRejected(_ handler: @escaping (AgoraCallLifecyclePayload) -> Void) -> UUID {
        listenMany([AgoraCallSocketEvents.rejected, AgoraCallSocketEvents.audioRejected]) { data in
            guard let dict = Self.firstDict(data),
                  let payload = Self.lifecyclePayload(from: dict) else {
                AppLogger.debug("AgoraCallSignaling: call:rejected missing callId")
                return
            }
            AppLogger.killCall("call:rejected callId=\(payload.callId)")
            handler(payload)
        }
    }

    @discardableResult
    func onCancelled(_ handler: @escaping (AgoraCallLifecyclePayload) -> Void) -> UUID {
        listenMany([AgoraCallSocketEvents.cancelled, AgoraCallSocketEvents.audioCancelled]) { data in
            guard let dict = Self.firstDict(data),
                  let payload = Self.lifecyclePayload(from: dict) else {
                AppLogger.debug("AgoraCallSignaling: call:cancelled missing callId")
                return
            }
            AppLogger.killCall(
                "call:cancelled callId=\(payload.callId) supersededBy=\(payload.supersededBy ?? "nil")"
            )
            handler(payload)
        }
    }

    @discardableResult
    func onRinging(_ handler: @escaping (_ callId: String) -> Void) -> UUID {
        listenMany([AgoraCallSocketEvents.ringing, AgoraCallSocketEvents.audioRinging]) { data in
            if let dict = Self.firstDict(data) {
                let callId = Self.extractCallId(from: dict)
                AppLogger.killCall("call:ringing callId=\(callId.isEmpty ? "empty" : callId) keys=\(dict.keys.sorted())")
                handler(callId)
                return
            }
            if let s = data.first as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let callId = s.trimmingCharacters(in: .whitespacesAndNewlines)
                AppLogger.killCall("call:ringing callId=\(callId) (string payload)")
                handler(callId)
                return
            }
            AppLogger.debug("AgoraCallSignaling: call:ringing unparsed payload count=\(data.count)")
            handler("")
        }
    }

    @discardableResult
    func onEndAck(_ handler: @escaping (AgoraCallLifecyclePayload) -> Void) -> UUID {
        listenMany([
            AgoraCallSocketEvents.endAck,
            AgoraCallSocketEvents.audioEndAck,
            AgoraCallSocketEvents.audioLeaveAck
        ]) { data in
            guard let dict = Self.firstDict(data),
                  let payload = Self.lifecyclePayload(from: dict) else { return }
            AppLogger.killCall(
                "call:end:ack callId=\(payload.callId) reason=\(payload.reason ?? "nil") callEnded=\(String(describing: payload.callEnded)) supersededBy=\(payload.supersededBy ?? "nil")"
            )
            handler(payload)
        }
    }

    /// Remote party ended the call (`call:end` / `call:ended` — not only the emitter's ack).
    @discardableResult
    func onRemoteEnd(_ handler: @escaping (AgoraCallLifecyclePayload) -> Void) -> UUID {
        listenMany([
            AgoraCallSocketEvents.end,
            AgoraCallSocketEvents.audioEnd,
            AgoraCallSocketEvents.audioEnded
        ]) { data in
            guard let dict = Self.firstDict(data),
                  let payload = Self.lifecyclePayload(from: dict) else {
                AppLogger.killCall("call:end missing callId")
                return
            }
            AppLogger.killCall("call:end (remote) callId=\(payload.callId)")
            handler(payload)
        }
    }

    @discardableResult
    func onParticipantJoined(_ handler: @escaping (_ callId: String, _ call: AgoraCallDto?, _ userId: String?) -> Void) -> UUID {
        listen(AgoraCallSocketEvents.participantJoined) { data in
            guard let dict = Self.firstDict(data) else { return }
            let callId = Self.extractCallId(from: dict)
            guard !callId.isEmpty else { return }
            let call = Self.decodeCall(from: dict)
            let nested = dict["data"] as? [String: Any]
            let userId = Self.stringValue(dict["userId"])
                ?? Self.stringValue(dict["by"])
                ?? Self.stringValue(dict["participantId"])
                ?? Self.stringValue(nested?["userId"])
                ?? Self.stringValue(nested?["by"])
                ?? Self.stringValue(nested?["participantId"])
            handler(callId, call, userId)
        }
    }

    @discardableResult
    func onParticipantLeft(_ handler: @escaping (AgoraCallLifecyclePayload) -> Void) -> UUID {
        listen(AgoraCallSocketEvents.participantLeft) { data in
            guard let dict = Self.firstDict(data),
                  let payload = Self.lifecyclePayload(from: dict) else { return }
            AppLogger.killCall(
                "call:participant:left callId=\(payload.callId) callEnded=\(String(describing: payload.callEnded))"
            )
            handler(payload)
        }
    }

    func removeAllListeners() {
        for id in listenerIds {
            ChatSocketManager.shared.offEventById(id)
        }
        listenerIds.removeAll()
    }

    // MARK: - Private

    private func listen(_ event: String, handler: @escaping ([Any]) -> Void) -> UUID {
        let id = ChatSocketManager.shared.listenToEvent(event, completionHandler: handler)
        listenerIds.append(id)
        return id
    }

    @discardableResult
    private func listenMany(_ events: [String], handler: @escaping ([Any]) -> Void) -> UUID {
        var first: UUID?
        for event in events {
            let id = listen(event, handler: handler)
            if first == nil { first = id }
        }
        return first ?? UUID()
    }

    private func remember(type: AgoraCallType, callId: String) {
        let id = callId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        callTypes[id] = type
    }

    private func resolvedType(callId: String, preferred: AgoraCallType?) -> AgoraCallType {
        if let preferred { return preferred }
        if let cached = callTypes[callId] { return cached }
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                if let current = AgoraCallService.shared.call,
                   current.id.caseInsensitiveCompare(callId) == .orderedSame || callId.isEmpty {
                    return current.type
                }
                return .video
            }
        }
        return .video
    }

    private func waitForAck(
        event: String,
        requestId: String,
        completion: @escaping (Result<AgoraCallSession, Error>) -> Void
    ) {
        var listenerId: UUID?
        var finished = false
        let startedAt = Date()

        let timeoutWork = DispatchWorkItem {
            guard !finished else { return }
            finished = true
            if let listenerId {
                ChatSocketManager.shared.offEventById(listenerId)
            }
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            CallInternationalDiagnostics.noteSignaling(event: event, success: false, latencyMs: latencyMs)
            CallInternationalDiagnostics.noteFailure(layer: .signaling, detail: "timeout \(event)")
            DispatchQueue.main.async {
                completion(.failure(AgoraCallError.timeout))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWork)

        listenerId = ChatSocketManager.shared.listenToEvent(event) { data in
            guard let dict = Self.firstDict(data) else { return }
            if let rid = Self.stringValue(dict["requestId"]), rid != requestId { return }
            guard !finished else { return }
            finished = true
            timeoutWork.cancel()
            if let listenerId {
                ChatSocketManager.shared.offEventById(listenerId)
            }

            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let success = dict["success"] as? Bool ?? true
            guard success else {
                let errorDict = dict["error"] as? [String: Any]
                let code = Self.stringValue(errorDict?["code"])
                let message = errorDict?["message"] as? String
                    ?? dict["message"] as? String
                    ?? "Call request failed"
                let reason = Self.extractCallReason(from: dict)
                CallInternationalDiagnostics.noteSignaling(event: event, success: false, latencyMs: latencyMs)
                DispatchQueue.main.async {
                    // create:ack busy → code: BUSY (web CallRequestError).
                    if code?.uppercased() == "BUSY"
                        || AgoraCallError.isBusyMessage(message)
                        || AgoraCallError.isBusyMessage(reason ?? "") {
                        completion(.failure(AgoraCallError.busy))
                    } else {
                        completion(.failure(AgoraCallError.failed(message)))
                    }
                }
                return
            }

            guard let session = Self.parseJoinSession(from: dict) else {
                CallInternationalDiagnostics.noteSignaling(event: event, success: false, latencyMs: latencyMs)
                DispatchQueue.main.async {
                    completion(.failure(AgoraCallError.failed("Invalid call session payload")))
                }
                return
            }

            CallInternationalDiagnostics.noteSignaling(event: event, success: true, latencyMs: latencyMs)
            DispatchQueue.main.async {
                completion(.success(session))
            }
        }
    }

    private static func firstDict(_ data: [Any]) -> [String: Any]? {
        if let dict = data.first as? [String: Any] { return dict }
        // Some servers send JSON string payloads.
        if let s = data.first as? String,
           let raw = s.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
            return dict
        }
        return nil
    }

    private static func lifecyclePayload(from dict: [String: Any]) -> AgoraCallLifecyclePayload? {
        let callId = extractCallId(from: dict)
        guard !callId.isEmpty else { return nil }
        let data = dict["data"] as? [String: Any]
        let callEnded: Bool? = {
            if let b = dict["callEnded"] as? Bool { return b }
            if let b = data?["callEnded"] as? Bool { return b }
            return nil
        }()
        let disconnected: Bool? = {
            if let b = dict["disconnected"] as? Bool { return b }
            if let b = data?["disconnected"] as? Bool { return b }
            return nil
        }()
        let supersededBy = stringValue(dict["supersededBy"])
            ?? stringValue(data?["supersededBy"])
        let byUserId = stringValue(dict["by"])
            ?? stringValue(data?["by"])
            ?? stringValue(dict["userId"])
        return AgoraCallLifecyclePayload(
            callId: callId,
            reason: extractCallReason(from: dict),
            status: stringValue(dict["status"]) ?? stringValue(data?["status"]),
            callEnded: callEnded,
            supersededBy: supersededBy,
            disconnected: disconnected,
            byUserId: byUserId,
            call: decodeCall(from: dict)
        )
    }

    private static func decodeCall(from dict: [String: Any]) -> AgoraCallDto? {
        if let callDict = dict["call"] as? [String: Any] {
            return decode(AgoraCallDto.self, from: callDict)
        }
        if let data = dict["data"] as? [String: Any],
           let callDict = data["call"] as? [String: Any] {
            return decode(AgoraCallDto.self, from: callDict)
        }
        return nil
    }

    private static func extractCallId(from dict: [String: Any]) -> String {
        if let id = stringValue(dict["callId"]), !id.isEmpty { return id }
        if let id = stringValue(dict["call_id"]), !id.isEmpty { return id }
        if let id = stringValue((dict["data"] as? [String: Any])?["callId"]), !id.isEmpty { return id }
        if let id = stringValue((dict["data"] as? [String: Any])?["call_id"]), !id.isEmpty { return id }
        if let id = stringValue((dict["call"] as? [String: Any])?["id"]), !id.isEmpty { return id }
        if let id = stringValue(((dict["data"] as? [String: Any])?["call"] as? [String: Any])?["id"]), !id.isEmpty { return id }
        if let id = stringValue(dict["id"]), !id.isEmpty { return id }
        return ""
    }

    private static func extractCallReason(from dict: [String: Any]) -> String? {
        let candidates: [Any?] = [
            dict["reason"],
            dict["status"],
            (dict["error"] as? [String: Any])?["reason"],
            (dict["error"] as? [String: Any])?["code"],
            (dict["error"] as? [String: Any])?["message"],
            (dict["data"] as? [String: Any])?["reason"],
            (dict["data"] as? [String: Any])?["status"],
            (dict["call"] as? [String: Any])?["status"]
        ]
        for value in candidates {
            if let s = stringValue(value), !s.isEmpty {
                return s
            }
        }
        return nil
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String, !s.isEmpty { return s }
        if let i = any as? Int { return String(i) }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func decode<T: Decodable>(_ type: T.Type, from dict: [String: Any]) -> T? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(T.self, from: data)
    }
}
