//
//  AgoraCallSignaling.swift
//  FlirttimeNew
//
//  Socket.IO + REST helpers matching Android / web CallSession contract.
//

import Foundation
import Swinject

final class AgoraCallSignaling {

    static let shared = AgoraCallSignaling()

    private let timeoutSeconds: TimeInterval = 18
    private let connectTimeoutSeconds: TimeInterval = 5
    private var listenerIds: [UUID] = []

    private init() {}

    // MARK: - Emit helpers

    /// REST `POST /calls/` + `GET calls/{id}` kick in when the India socket is slow or timed out.
    private static let isCallsRESTEnabled = true

    /// Kick the India socket without waiting — emit queues until connected (Dubai/UAE RTT).
    private func warmSocketAndEmit() {
        ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "agora-signaling-emit")
        ChatSocketManager.shared.ensureConnecting()
    }

    /// Primary: socket `call:create`. Do not block on handshake — queued emit flushes on connect.
    func startCall(conversationId: String, type: AgoraCallType, completion: @escaping (Result<AgoraCallSession, Error>) -> Void) {
        warmSocketAndEmit()
        if !ChatSocketManager.shared.isSocketConnected() {
            AppLogger.killCall("startCall emit while socket connecting (India RTT path)")
        }

        var finished = false
        var socketFailed = false
        var restFailed = false
        let finish: (Result<AgoraCallSession, Error>) -> Void = { result in
            guard !finished else { return }
            finished = true
            completion(result)
        }

        startCallViaSocket(conversationId: conversationId, type: type) { [weak self] result in
            switch result {
            case .success:
                finish(result)
            case .failure(let error):
                socketFailed = true
                guard Self.isCallsRESTEnabled, let self else {
                    finish(result)
                    return
                }
                if restFailed {
                    finish(result)
                    return
                }
                AppLogger.debug("AgoraCallSignaling: socket create failed (\(error.localizedDescription)) — waiting/trying REST")
                self.startCallViaREST(conversationId: conversationId, type: type) { rest in
                    switch rest {
                    case .success:
                        finish(rest)
                    case .failure:
                        restFailed = true
                        if socketFailed { finish(result) }
                    }
                }
            }
        }

        if Self.isCallsRESTEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, !finished else { return }
                AppLogger.debug("AgoraCallSignaling: racing REST POST calls/ after 2.5s socket wait")
                self.startCallViaREST(conversationId: conversationId, type: type) { rest in
                    switch rest {
                    case .success:
                        finish(rest)
                    case .failure:
                        restFailed = true
                        if socketFailed { finish(rest) }
                    }
                }
            }
        }
    }

    private func startCallViaSocket(
        conversationId: String,
        type: AgoraCallType,
        completion: @escaping (Result<AgoraCallSession, Error>) -> Void
    ) {
        let requestId = UUID().uuidString
        waitForAck(event: AgoraCallSocketEvents.createAck, requestId: requestId, completion: completion)
        let payload: [String: Any] = [
            "conversationId": conversationId,
            "type": type.rawValue,
            "requestId": requestId
        ]
        AppLogger.debug("AgoraCallSignaling: emit call:create conversationId=\(conversationId) type=\(type.rawValue)")
        ChatSocketManager.shared.emitMessage(AgoraCallSocketEvents.create, withData: [payload])
    }

    private func startCallViaREST(
        conversationId: String,
        type: AgoraCallType,
        completion: @escaping (Result<AgoraCallSession, Error>) -> Void
    ) {
        guard let sessionManager = Container.sharedContainer.resolve(SessionManager.self) else {
            DispatchQueue.main.async {
                completion(.failure(AgoraCallError.failed("Unable to start call (no session manager)")))
            }
            return
        }

        _ = sessionManager.startAgoraCall(conversationId: conversationId, type: type.rawValue)
            .subscribe(onSuccess: { dict in
                if let session = AgoraCallSession(dict: dict) {
                    DispatchQueue.main.async { completion(.success(session)) }
                } else if let nested = dict["data"] as? [String: Any],
                          let session = AgoraCallSession(dict: nested) {
                    DispatchQueue.main.async { completion(.success(session)) }
                } else {
                    // Wrap as { data: dict } already unwrapped by SessionManager — try full envelope.
                    DispatchQueue.main.async {
                        completion(.failure(AgoraCallError.failed("Invalid REST call session payload")))
                    }
                }
            }, onFailure: { error in
                DispatchQueue.main.async {
                    let message = error.localizedDescription
                    CallInternationalDiagnostics.noteAPI(event: "POST calls/", success: false, detail: message)
                    if AgoraCallError.isBusyMessage(message) {
                        completion(.failure(AgoraCallError.busy))
                    } else {
                        completion(.failure(AgoraCallError.failed(message)))
                    }
                }
            })
    }

    func acceptCall(callId: String, completion: @escaping (Result<AgoraCallSession, Error>) -> Void) {
        // Don't wait 5–8s for India socket before Answer — queue the emit if still connecting.
        var finished = false
        let finish: (Result<AgoraCallSession, Error>) -> Void = { result in
            guard !finished else { return }
            finished = true
            completion(result)
        }

        acceptCallWithRetry(callId: callId, attempt: 1, maxAttempts: 2) { [weak self] result in
            switch result {
            case .success:
                finish(result)
            case .failure(let error):
                guard Self.isCallsRESTEnabled, let self else {
                    finish(result)
                    return
                }
                AppLogger.killCall("acceptCall socket failed (\(error.localizedDescription)) — REST GET calls/\(callId)")
                self.fetchJoinSessionViaREST(callId: callId) { rest in
                    switch rest {
                    case .success(let session) where session.hasJoinCredentials:
                        finish(.success(session))
                    default:
                        finish(result)
                    }
                }
            }
        }

        if Self.isCallsRESTEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, !finished else { return }
                AppLogger.killCall("acceptCall racing REST GET calls/\(callId) after 2s")
                self.fetchJoinSessionViaREST(callId: callId) { rest in
                    if case .success(let session) = rest, session.hasJoinCredentials {
                        finish(.success(session))
                    }
                }
            }
        }
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
            .subscribe(onSuccess: { dict in
                CallInternationalDiagnostics.noteAPI(event: "GET calls/\(callId)", success: true)
                if let session = Self.parseJoinSession(from: dict) {
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

    func declineCall(callId: String, reason: String? = nil) {
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
            event: AgoraCallSocketEvents.decline,
            callId: callId,
            attempt: 1,
            extra: extra
        )
    }

    /// Notify caller that the callee is already on another call.
    func notifyBusy(callId: String) {
        emitCallControl(
            event: AgoraCallSocketEvents.busy,
            callId: callId,
            attempt: 1,
            extra: [
                "reason": AgoraCallDeclineReason.busy.rawValue,
                "status": AgoraCallDeclineReason.busy.rawValue
            ]
        )
    }

    /// Callee device is ringing — caller should show "Ringing…" (WhatsApp-style).
    func notifyRinging(callId: String) {
        emitCallControl(
            event: AgoraCallSocketEvents.ringing,
            callId: callId,
            attempt: 1,
            extra: ["status": "ringing", "call_id": callId]
        )
    }

    func endCall(callId: String, supersededBy: String? = nil) {
        var extra: [String: Any] = [:]
        if let supersededBy, !supersededBy.isEmpty {
            extra["supersededBy"] = supersededBy
            extra["reason"] = "switched"
            extra["status"] = "ended"
        }
        emitCallControl(event: AgoraCallSocketEvents.end, callId: callId, attempt: 1, extra: extra)
    }

    /// Leave an ongoing group call without ending it for everyone else.
    func leaveCall(callId: String) {
        emitCallControl(event: AgoraCallSocketEvents.leave, callId: callId, attempt: 1)
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
        listen(AgoraCallSocketEvents.incoming) { data in
            guard let dict = Self.firstDict(data) else { return }
            // Shapes: { call }, { data: { call } }, or bare CallDto
            let callDict: [String: Any]
            if let call = dict["call"] as? [String: Any] {
                callDict = call
            } else if let data = dict["data"] as? [String: Any],
                      let call = data["call"] as? [String: Any] {
                callDict = call
            } else if dict["id"] != nil, dict["channelName"] != nil || dict["conversationId"] != nil {
                callDict = dict
            } else {
                return
            }
            guard let call = Self.decode(AgoraCallDto.self, from: callDict), !call.id.isEmpty else { return }
            handler(call)
        }
    }

    @discardableResult
    func onJoin(_ handler: @escaping (AgoraCallSession) -> Void) -> UUID {
        listen(AgoraCallSocketEvents.join) { data in
            guard let dict = Self.firstDict(data) else { return }
            if let success = dict["success"] as? Bool, !success { return }
            guard let session = AgoraCallSession(dict: dict) else { return }
            handler(session)
        }
    }

    @discardableResult
    func onDeclined(_ handler: @escaping (AgoraCallLifecyclePayload) -> Void) -> UUID {
        listen(AgoraCallSocketEvents.declined) { data in
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
        listen(AgoraCallSocketEvents.busy) { data in
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
        listen(AgoraCallSocketEvents.rejected) { data in
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
        listen(AgoraCallSocketEvents.cancelled) { data in
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
        listen(AgoraCallSocketEvents.ringing) { data in
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
        listen(AgoraCallSocketEvents.endAck) { data in
            guard let dict = Self.firstDict(data),
                  let payload = Self.lifecyclePayload(from: dict) else { return }
            AppLogger.killCall(
                "call:end:ack callId=\(payload.callId) reason=\(payload.reason ?? "nil") callEnded=\(String(describing: payload.callEnded)) supersededBy=\(payload.supersededBy ?? "nil")"
            )
            handler(payload)
        }
    }

    /// Remote party ended the call (`call:end` broadcast — not only the emitter's ack).
    @discardableResult
    func onRemoteEnd(_ handler: @escaping (AgoraCallLifecyclePayload) -> Void) -> UUID {
        listen(AgoraCallSocketEvents.end) { data in
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

            guard let session = AgoraCallSession(dict: dict) else {
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
