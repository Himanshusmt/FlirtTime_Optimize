//
//  IncomingCallPushRouter.swift
//  FlirttimeNew
//
//  OneVibe-compatible VoIP + FCM incoming-call routing.
//  Visible app → in-app ring. Background / killed / inactive wake → CallKit.
//

import Foundation
import UIKit
import UserNotifications

enum CallPushAuth {
    static var isLoggedIn: Bool {
        AppTokenStore.shared.hasAccessToken || ChatAuthStore.shared.hasAccessToken
    }
}

enum IncomingCallPushRouter {

    static let callNotificationCategoryId = "INCOMING_CALL"
    static let callAcceptActionId = "CALL_ACCEPT"
    static let callDeclineActionId = "CALL_DECLINE"

    static func registerCallNotificationCategory() {
        let accept = UNNotificationAction(
            identifier: callAcceptActionId,
            title: "Accept",
            options: [.foreground]
        )
        let decline = UNNotificationAction(
            identifier: callDeclineActionId,
            title: "Decline",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: callNotificationCategoryId,
            actions: [accept, decline],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - VoIP (PushKit)

    static func handleVoIPPush(root: [String: Any], completion: @escaping () -> Void) {
        let dict = unwrapCallDictionary(from: root)
        let loggedIn = CallPushAuth.isLoggedIn
        AppLogger.killCall(
            "VoIP PUSH RECEIVED loggedIn=\(loggedIn) appState=\(UIApplication.shared.applicationState.rawValue) keys=\(dict.keys.sorted())"
        )

        if loggedIn, CallKitManager.shared.isInLiveOneVibeCall {
            let parsed = parseAgoraCallPayload(dict)
            AppLogger.killCall("VoIP while on live call — call-waiting in-app only callId=\(parsed.callId)")
            CallKitManager.shared.handleIncomingWhileOnCall(
                fromVoIP: true,
                callerName: parsed.callerName,
                hasVideo: parsed.hasVideo,
                callId: parsed.callId,
                call: parsed.call,
                payload: dict
            ) {
                ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "voip-call-waiting")
                AppLogger.killCall("VoIP call-waiting completion called")
                completion()
            }
            return
        }

        if CallKitManager.isAppInForeground {
            let parsed = parseAgoraCallPayload(dict)
            AppLogger.killCall("VoIP in foreground — in-app ring + silent fulfill callId=\(parsed.callId)")
            CallKitManager.shared.handleForegroundVoIPIncoming(
                callerName: parsed.callerName,
                hasVideo: parsed.hasVideo,
                callId: parsed.callId,
                call: parsed.call,
                payload: dict,
                loggedIn: loggedIn
            ) {
                if loggedIn {
                    ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "voip-fg-safety")
                    Task { @MainActor in
                        AgoraCallService.shared.start()
                        if !parsed.callId.isEmpty {
                            AgoraCallService.shared.prefetchIncomingJoinCredentials(callId: parsed.callId)
                        }
                    }
                }
                AppLogger.killCall("VoIP foreground safety completion — no CallKit UI")
                completion()
            }
            return
        }

        let parsed = parseAgoraCallPayload(dict)
        let hasRealCallId = !(
            (dict["callId"] as? String)
            ?? (dict["call_id"] as? String)
            ?? (dict["id"] as? String)
            ?? ""
        ).isEmpty
        if !hasRealCallId {
            AppLogger.killCall("VoIP WARNING — missing callId keys=\(dict.keys.sorted())")
        }
        AppLogger.killCall(
            "VoIP→CallKit Agora callId=\(parsed.callId) caller=\(parsed.callerName) video=\(parsed.hasVideo) loggedIn=\(loggedIn)"
        )
        CallKitManager.shared.reportIncomingAgoraCall(
            callerName: parsed.callerName,
            hasVideo: parsed.hasVideo,
            callId: parsed.callId,
            call: parsed.call,
            rawPayload: dict,
            fromVoIP: true
        ) {
            if loggedIn {
                ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "voip-incoming-push")
                Task { @MainActor in
                    AgoraCallService.shared.start()
                    if !parsed.callId.isEmpty {
                        AgoraCallService.shared.prefetchIncomingJoinCredentials(callId: parsed.callId)
                    }
                }
            } else {
                AppLogger.killCall("VoIP logged-out — ending CallKit immediately")
                CallKitManager.shared.endCall(reason: .failed)
            }
            AppLogger.killCall("VoIP completion (Agora) called — CallKit reported")
            completion()
        }
    }

    // MARK: - FCM / APNs fallback

    @discardableResult
    static func handleIncomingCallPushIfNeeded(userInfo: [AnyHashable: Any], source: String) -> Bool {
        let root = normalizeUserInfo(userInfo)
        let dict = unwrapCallDictionary(from: root)
        let loggedIn = CallPushAuth.isLoggedIn
        AppLogger.killCall(
            "CallPush[\(source)] keys=\(dict.keys.sorted()) type=\(dict["type"] ?? dict["callType"] ?? "nil") loggedIn=\(loggedIn)"
        )

        guard isAgoraCallPayload(dict) else { return false }

        let parsed = parseAgoraCallPayload(dict)
        if !loggedIn {
            let useInAppOnly = CallKitManager.isAppInForeground
            AppLogger.killCall("CallPush[\(source)] SUPPRESS logged-out Agora callId=\(parsed.callId)")
            if !useInAppOnly {
                CallKitManager.shared.reportIncomingAgoraCall(
                    callerName: parsed.callerName,
                    hasVideo: parsed.hasVideo,
                    callId: parsed.callId,
                    call: parsed.call,
                    rawPayload: dict,
                    fromVoIP: false
                ) {
                    CallKitManager.shared.endCall(reason: .failed)
                }
            }
            clearDeliveredCallNotifications()
            return true
        }

        if CallKitManager.shared.isInLiveOneVibeCall {
            AppLogger.killCall("FCM/APNs call-waiting in-app only source=\(source) callId=\(parsed.callId)")
            CallKitManager.shared.handleIncomingWhileOnCall(
                fromVoIP: false,
                callerName: parsed.callerName,
                hasVideo: parsed.hasVideo,
                callId: parsed.callId,
                call: parsed.call,
                payload: dict
            )
            clearDeliveredCallNotifications()
            return true
        }

        if CallKitManager.isAppInForeground {
            AppLogger.killCall("FCM/APNs in-app path source=\(source) callId=\(parsed.callId)")
            presentInApp(parsed: parsed, dict: dict)
            clearDeliveredCallNotifications()
            return true
        }

        AppLogger.killCall(
            "FCM/APNs CALLKIT PATH source=\(source) callId=\(parsed.callId) appState=\(UIApplication.shared.applicationState.rawValue)"
        )
        ChatSocketSessionCoordinator.shared.activateSessionIfNeeded(reason: "fcm-call-push-\(source)")
        CallKitManager.shared.reportIncomingAgoraCall(
            callerName: parsed.callerName,
            hasVideo: parsed.hasVideo,
            callId: parsed.callId,
            call: parsed.call,
            rawPayload: dict,
            fromVoIP: false
        )
        clearDeliveredCallNotifications()
        return true
    }

    static func handleNotificationAction(_ response: UNNotificationResponse) -> Bool {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier
        let root = normalizeUserInfo(userInfo)
        let dict = unwrapCallDictionary(from: root)
        guard isAgoraCallPayload(dict) else { return false }

        if actionId == callDeclineActionId {
            let parsed = parseAgoraCallPayload(dict)
            Task { @MainActor in
                var payload = dict
                payload["callId"] = parsed.callId
                payload["type"] = parsed.hasVideo ? "video" : "audio"
                if let call = parsed.call {
                    AgoraCallService.shared.seedIncomingFromPush(call: call)
                } else {
                    _ = AgoraCallService.shared.seedIncomingFromPushPayload(payload)
                }
                AgoraCallService.shared.declineIncoming()
                CallKitManager.shared.endCall(reason: .declinedElsewhere)
            }
            return true
        }

        _ = handleIncomingCallPushIfNeeded(userInfo: userInfo, source: "notificationTap")
        if actionId == callAcceptActionId {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                CallKitManager.shared.answerCall()
            }
        }
        return true
    }

    // MARK: - Parse

    static func normalizeUserInfo(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        var dict: [String: Any] = [:]
        for (key, value) in userInfo {
            dict[String(describing: key)] = value
        }
        return dict
    }

    static func unwrapCallDictionary(from root: [String: Any]) -> [String: Any] {
        var dict = root

        if let data = root["data"] as? [String: Any] {
            dict.merge(data) { _, new in new }
        } else if let dataString = root["data"] as? String,
                  let data = dataString.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict.merge(parsed) { _, new in new }
        }

        if let meta = dict["meta"] as? [String: Any] {
            dict.merge(meta) { current, _ in current }
        } else if let metaString = dict["meta"] as? String,
                  let data = metaString.data(using: .utf8),
                  let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict.merge(meta) { current, _ in current }
        }

        if let call = dict["call"] as? [String: Any] {
            for (k, v) in call where dict[k] == nil {
                dict[k] = v
            }
            if dict["callId"] == nil, let id = call["id"] as? String {
                dict["callId"] = id
            }
        } else if let callString = dict["call"] as? String,
                  let data = callString.data(using: .utf8),
                  let call = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict["call"] = call
            for (k, v) in call where dict[k] == nil {
                dict[k] = v
            }
            if dict["callId"] == nil, let id = call["id"] as? String {
                dict["callId"] = id
            }
        }

        return dict
    }

    static func isAgoraCallPayload(_ dict: [String: Any]) -> Bool {
        let typeCandidates: [String] = [
            dict["type"] as? String,
            dict["callType"] as? String,
            dict["event"] as? String,
            dict["notificationType"] as? String,
            dict["notify_type"] as? String,
            dict["messageType"] as? String,
            dict["gcm.notification.type"] as? String
        ].compactMap { $0 }.map {
            $0.lowercased().replacingOccurrences(of: "-", with: "_")
        }

        let chatTypes: Set<String> = [
            "message", "new_message", "chat_message", "chat",
            "image", "photo", "video", "audio", "text", "gif",
            "location", "contact", "sticker", "file", "document"
        ]
        let missedCallTypes: Set<String> = [
            "missed_call", "missedcall", "call_missed", "missed_video_call", "missed_audio_call"
        ]
        if typeCandidates.contains(where: { chatTypes.contains($0) || missedCallTypes.contains($0) }) {
            return hasExplicitCallIdentifiers(dict)
        }

        if hasExplicitCallIdentifiers(dict) { return true }

        let agoraTypes: Set<String> = [
            "agora_call", "agora", "call", "incoming_call", "call_incoming",
            "audio_call", "video_call", "incoming_audio_call", "incoming_video_call"
        ]
        if typeCandidates.contains(where: { agoraTypes.contains($0) }) { return true }

        if looksLikeCallObject(dict["call"]) { return true }

        if let aps = dict["aps"] as? [String: Any] {
            let texts: [String] = {
                if let s = aps["alert"] as? String { return [s] }
                if let alert = aps["alert"] as? [String: Any] {
                    return [alert["title"] as? String, alert["body"] as? String].compactMap { $0 }
                }
                return []
            }()
            for text in texts {
                let lower = text.lowercased()
                if lower.contains("incoming call")
                    || lower.contains("video call")
                    || lower.contains("audio call")
                    || lower.contains("voice call")
                    || lower.hasPrefix("call from")
                    || lower.contains(" is calling") {
                    return true
                }
            }
        }

        return false
    }

    private static func hasExplicitCallIdentifiers(_ dict: [String: Any]) -> Bool {
        if let callId = dict["callId"] as? String, !callId.isEmpty { return true }
        if let callId = dict["call_id"] as? String, !callId.isEmpty { return true }
        if looksLikeCallObject(dict["call"]) { return true }
        let hasChannel = ((dict["channelName"] as? String) ?? (dict["channel_name"] as? String) ?? "").isEmpty == false
        let hasCallType = ((dict["callType"] as? String) ?? (dict["call_type"] as? String) ?? "").isEmpty == false
        return hasChannel && hasCallType
    }

    private static func looksLikeCallObject(_ value: Any?) -> Bool {
        let call: [String: Any]
        if let dict = value as? [String: Any] {
            call = dict
        } else if let string = value as? String,
                  let data = string.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            call = dict
        } else {
            return false
        }
        let id = ((call["id"] as? String) ?? (call["callId"] as? String) ?? "").isEmpty == false
        let channel = ((call["channelName"] as? String) ?? (call["channel_name"] as? String) ?? "").isEmpty == false
        let type = ((call["type"] as? String) ?? (call["callType"] as? String) ?? "").lowercased()
        let isCallType = type == "audio" || type == "video" || type.contains("call")
        return (id && (channel || isCallType)) || (channel && isCallType)
    }

    static func parseAgoraCallPayload(_ dict: [String: Any]) -> (callerName: String, hasVideo: Bool, callId: String, call: AgoraCallDto?) {
        var call: AgoraCallDto?
        if let callDict = dict["call"] as? [String: Any] {
            let sanitized = sanitizeCallDict(callDict)
            if let data = try? JSONSerialization.data(withJSONObject: sanitized),
               let decoded = try? JSONDecoder().decode(AgoraCallDto.self, from: data) {
                call = decoded
            }
        }
        if call == nil, let built = buildCallDtoDictionary(fromFlatPush: dict),
           let data = try? JSONSerialization.data(withJSONObject: built),
           let decoded = try? JSONDecoder().decode(AgoraCallDto.self, from: data) {
            call = decoded
        }

        let callId = call?.id
            ?? (dict["callId"] as? String)
            ?? (dict["call_id"] as? String)
            ?? (dict["id"] as? String)
            ?? UUID().uuidString

        let mediaType = mediaCallType(from: dict, fallbackCall: call)
        let hasVideo = mediaType == .video

        var callerName = "Incoming Call"
        if let n = dict["callerName"] as? String, !n.isEmpty { callerName = n }
        else if let n = dict["caller"] as? String, !n.isEmpty { callerName = n }
        else if let n = dict["conversationTitle"] as? String, !n.isEmpty { callerName = n }
        else if let n = dict["title"] as? String, !n.isEmpty { callerName = n }
        else if let n = call?.caller?.displayName, n != "Unknown" { callerName = n }
        else if let callerDict = dict["caller"] as? [String: Any] {
            let full = (callerDict["fullName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let user = (callerDict["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !full.isEmpty { callerName = full }
            else if !user.isEmpty { callerName = user }
        } else if let aps = dict["aps"] as? [String: Any] {
            if let alert = aps["alert"] as? String, !alert.isEmpty {
                callerName = alert
            } else if let alert = aps["alert"] as? [String: Any] {
                callerName = (alert["title"] as? String) ?? (alert["body"] as? String) ?? callerName
            }
        }

        return (callerName, hasVideo, callId, call)
    }

    // MARK: - Private

    private static func presentInApp(
        parsed: (callerName: String, hasVideo: Bool, callId: String, call: AgoraCallDto?),
        dict: [String: Any]
    ) {
        let work: @MainActor () -> Void = {
            let service = AgoraCallService.shared
            if service.isPresentingInAppIncoming, service.matchesCallId(parsed.callId) {
                return
            }
            if service.phase == .active || service.phase == .outgoing {
                if let call = parsed.call {
                    service.offerPendingIncoming(call)
                } else {
                    var payload = dict
                    payload["callId"] = parsed.callId
                    payload["type"] = parsed.hasVideo ? "video" : "audio"
                    _ = service.presentIncomingFromPushPayload(payload)
                }
                return
            }
            if let call = parsed.call {
                service.presentIncomingInApp(call: call)
            } else {
                var payload = dict
                payload["callId"] = parsed.callId
                payload["type"] = parsed.hasVideo ? "video" : "audio"
                _ = service.presentIncomingFromPushPayload(payload)
            }
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            Task { @MainActor in work() }
        }
    }

    private static func clearDeliveredCallNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notes in
            let callIds = notes.compactMap { note -> String? in
                let info = normalizeUserInfo(note.request.content.userInfo)
                let dict = unwrapCallDictionary(from: info)
                return isAgoraCallPayload(dict) ? note.request.identifier : nil
            }
            guard !callIds.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: callIds)
        }
    }

    private static func sanitizeCallDict(_ dict: [String: Any]) -> [String: Any] {
        var out = dict
        if let caller = dict["caller"] as? [String: Any] {
            var user = AgoraCallUserSummary.sanitizedDictionary(caller)
            if let n = caller["isVerified"] as? NSNumber { user["isVerified"] = n.boolValue }
            out["caller"] = user
        }
        if let callee = dict["callee"] as? [String: Any] {
            var user = AgoraCallUserSummary.sanitizedDictionary(callee)
            if let n = callee["isVerified"] as? NSNumber { user["isVerified"] = n.boolValue }
            out["callee"] = user
        }
        return out
    }

    private static func buildCallDtoDictionary(fromFlatPush dict: [String: Any]) -> [String: Any]? {
        let callId = (dict["callId"] as? String)
            ?? (dict["call_id"] as? String)
            ?? (dict["id"] as? String)
            ?? ""
        guard !callId.isEmpty else { return nil }

        let media = mediaCallType(from: dict, fallbackCall: nil)
        let conversationId = (dict["conversationId"] as? String)
            ?? (dict["conversation_id"] as? String)
            ?? ""
        var callerId = (dict["callerId"] as? String)
            ?? (dict["caller_id"] as? String)
            ?? ""
        var callerName = (dict["callerName"] as? String)
            ?? (dict["caller"] as? String)
            ?? ""
        var callerAvatar = (dict["callerAvatar"] as? String)
            ?? (dict["caller_avatar"] as? String)
            ?? ""
        if let callerDict = dict["caller"] as? [String: Any] {
            let fields = AgoraCallUserSummary.resolvedFields(from: callerDict)
            if callerId.isEmpty { callerId = fields.id }
            if callerName.isEmpty { callerName = fields.name }
            if callerAvatar.isEmpty { callerAvatar = fields.avatar }
        }
        let conversationTitle = (dict["conversationTitle"] as? String)
            ?? (dict["conversation_title"] as? String)
            ?? (dict["title"] as? String)
        let conversationType = ((dict["conversationType"] as? String)
            ?? (dict["conversation_type"] as? String)
            ?? "").lowercased()
        let isGroup = (dict["isGroup"] as? Bool)
            ?? (conversationType == "group" || conversationType == "group_call")

        var built: [String: Any] = [
            "id": callId,
            "conversationId": conversationId,
            "type": media.rawValue,
            "status": "ringing",
            "channelName": (dict["channelName"] as? String) ?? (dict["channel_name"] as? String) ?? "",
            "callerId": callerId,
            "calleeId": (dict["calleeId"] as? String) ?? (dict["callee_id"] as? String) ?? "",
            "appId": (dict["appId"] as? String) ?? (dict["app_id"] as? String) ?? "",
            "isGroup": isGroup
        ]
        if let conversationTitle, !conversationTitle.isEmpty {
            built["conversationTitle"] = conversationTitle
        }
        if !conversationType.isEmpty {
            built["conversationType"] = conversationType
        }
        if !callerId.isEmpty || !callerName.isEmpty {
            var caller: [String: Any] = ["id": callerId]
            if !callerName.isEmpty { caller["fullName"] = callerName }
            if !callerAvatar.isEmpty { caller["profilePicture"] = callerAvatar }
            built["caller"] = caller
        }
        return built
    }

    private static func mediaCallType(from dict: [String: Any], fallbackCall: AgoraCallDto?) -> AgoraCallType {
        if let callType = dict["callType"] as? String {
            return callType.lowercased().contains("video") ? .video : .audio
        }
        if let callType = dict["call_type"] as? String {
            return callType.lowercased().contains("video") ? .video : .audio
        }
        if let fallbackCall { return fallbackCall.type }
        let type = (dict["type"] as? String ?? "").lowercased()
        if type.contains("video") { return .video }
        if type == "audio" || type.contains("audio") || type.contains("voice") { return .audio }
        return .audio
    }
}
