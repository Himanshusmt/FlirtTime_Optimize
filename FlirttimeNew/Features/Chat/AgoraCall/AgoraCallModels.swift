//
//  AgoraCallModels.swift
//  FlirttimeNew
//
//  Mirrors onevibe_frontend-main/src/lib/call.ts
//

import Foundation
import AgoraRtcKit

enum AgoraCallType: String, Codable {
    case audio
    case video
}

enum AgoraCallStatus: String, Codable {
    case ringing
    case ongoing
    case ended
    case missed
    case declined
    case cancelled
    case busy
    case rejected
}

enum AgoraCallPhase: Equatable {
    case idle
    case outgoing
    case incoming
    case active
}

/// Outgoing 1:1 status line (WhatsApp-style Calling → Ringing → timer).
enum AgoraOutgoingDialState: Equatable {
    case calling
    case ringing
}

/// Remote peer reachability (separate from local No internet / Reconnecting).
enum AgoraPeerNetworkState: Equatable {
    /// Peer uplink looks fine.
    case ok
    /// Peer network weak / media freezing — still on the call.
    case weak
    /// Peer soft-offline / prolonged silence — not in network.
    case unreachable
}

/// Remote peer uplink / connection quality shown as bars + label on the call UI.
enum AgoraCallNetworkQualityLevel: Equatable {
    case excellent
    case good
    case fair
    case poor
    case reconnecting
    case lost
    case unknown

    var title: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .reconnecting: return "Reconnecting"
        case .lost: return "Lost Connection"
        case .unknown: return ""
        }
    }

    /// Filled bars out of 4 (WhatsApp-style).
    var filledBars: Int {
        switch self {
        case .excellent: return 4
        case .good: return 3
        case .fair: return 2
        case .poor: return 1
        case .reconnecting, .lost, .unknown: return 0
        }
    }

    var prefersOrangeStatus: Bool {
        switch self {
        case .fair, .poor, .reconnecting, .lost: return true
        default: return false
        }
    }

    static func from(agoraQuality: AgoraNetworkQuality) -> AgoraCallNetworkQualityLevel {
        switch agoraQuality {
        case .excellent: return .excellent
        case .good: return .good
        case .poor: return .fair
        case .bad, .vBad: return .poor
        case .down: return .poor
        default: return .unknown
        }
    }
}

/// Where call audio is currently playing (loudspeaker / earpiece / headset / Bluetooth).
enum AgoraCallAudioRoute: Equatable {
    case speaker
    case earpiece
    case wiredHeadset
    case bluetooth(String?)
    case other

    var title: String {
        switch self {
        case .speaker: return "Speaker"
        case .earpiece: return "Earpiece"
        case .wiredHeadset: return "Headphones"
        case .bluetooth(let name):
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty { return "Bluetooth" }
            // Keep control-bar label short.
            if trimmed.count <= 10 { return trimmed }
            return String(trimmed.prefix(9)) + "…"
        case .other: return "Audio"
        }
    }

    var systemImageName: String {
        switch self {
        case .speaker: return "speaker.wave.2.fill"
        case .earpiece: return "ear"
        case .wiredHeadset: return "headphones"
        case .bluetooth: return "wave.3.right"
        case .other: return "speaker.wave.2.fill"
        }
    }

    /// True when audio is on an external headset (wired or Bluetooth).
    var isExternalHeadset: Bool {
        switch self {
        case .wiredHeadset, .bluetooth: return true
        default: return false
        }
    }
}

/// Explicit user pick from WhatsApp-style audio output sheet.
enum AgoraCallAudioOutputChoice: Equatable {
    case speaker
    case earpiece
    case external
}

/// Tile shown in WhatsApp-style group audio/video participant grid.
struct AgoraCallGridParticipant: Equatable, Codable {
    let userId: String
    let displayName: String
    let avatarURL: String?
    let isSelf: Bool
    /// True when this person is considered on the call (self always; remotes when joined).
    var isConnected: Bool
}

/// Snapshot of a live group call the user can join/rejoin (left, missed, or app-killed).
struct AgoraRejoinableGroupCall: Equatable, Codable {
    let callId: String
    let conversationId: String
    let type: AgoraCallType
    let displayName: String?
    let groupMembers: [AgoraCallGridParticipant]
    /// Wall-clock time when this snapshot was saved (survives process death).
    var savedAt: TimeInterval

    init(
        callId: String,
        conversationId: String,
        type: AgoraCallType,
        displayName: String?,
        groupMembers: [AgoraCallGridParticipant],
        savedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.callId = callId
        self.conversationId = conversationId
        self.type = type
        self.displayName = displayName
        self.groupMembers = groupMembers
        self.savedAt = savedAt
    }
}

/// Persists joinable / ongoing group-call snapshots (multi-conversation) across app kill.
enum AgoraRejoinableGroupCallStore {
    private static let keyV2 = "agora.rejoinableGroupCalls.v2"
    private static let legacyKey = "agora.rejoinableGroupCall.v1"
    /// Safety TTL — stale banners must not linger forever if `call:end` was missed.
    private static let maxAgeSeconds: TimeInterval = 6 * 60 * 60

    /// Upsert by `conversationId`.
    static func save(_ info: AgoraRejoinableGroupCall) {
        var copy = info
        copy.savedAt = Date().timeIntervalSince1970
        var map = loadMap()
        map[copy.conversationId] = copy
        persist(map)
    }

    static func load(conversationId: String) -> AgoraRejoinableGroupCall? {
        let map = loadMap()
        return map[conversationId]
    }

    /// Most recently saved entry (legacy callers / single-banner fallback).
    static func load() -> AgoraRejoinableGroupCall? {
        let map = loadMap()
        return map.values.max(by: { $0.savedAt < $1.savedAt })
    }

    static func all() -> [AgoraRejoinableGroupCall] {
        Array(loadMap().values)
    }

    static func remove(callId: String) {
        var map = loadMap()
        let before = map.count
        map = map.filter { $0.value.callId.caseInsensitiveCompare(callId) != .orderedSame }
        guard map.count != before else { return }
        persist(map)
    }

    static func remove(conversationId: String) {
        var map = loadMap()
        guard map.removeValue(forKey: conversationId) != nil else { return }
        persist(map)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: keyV2)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    private static func persist(_ map: [String: AgoraRejoinableGroupCall]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: keyV2)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    private static func loadMap() -> [String: AgoraRejoinableGroupCall] {
        if let data = UserDefaults.standard.data(forKey: keyV2),
           let map = try? JSONDecoder().decode([String: AgoraRejoinableGroupCall].self, from: data) {
            return pruneExpired(map)
        }
        // Migrate singular v1 → v2
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let info = try? JSONDecoder().decode(AgoraRejoinableGroupCall.self, from: data) {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            if Date().timeIntervalSince1970 - info.savedAt <= maxAgeSeconds {
                let map = [info.conversationId: info]
                persist(map)
                return map
            }
        }
        return [:]
    }

    private static func pruneExpired(_ map: [String: AgoraRejoinableGroupCall]) -> [String: AgoraRejoinableGroupCall] {
        let now = Date().timeIntervalSince1970
        let kept = map.filter { now - $0.value.savedAt <= maxAgeSeconds }
        if kept.count != map.count {
            persist(kept)
        }
        return kept
    }
}

struct AgoraCallUserSummary: Decodable, Equatable {
    let id: String
    let username: String?
    let fullName: String?
    let profilePicture: String?
    let isVerified: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, fullName, profilePicture, isVerified
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        profilePicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
        if let b = try c.decodeIfPresent(Bool.self, forKey: .isVerified) {
            isVerified = b
        } else if let i = try c.decodeIfPresent(Int.self, forKey: .isVerified) {
            isVerified = i != 0
        } else {
            isVerified = nil
        }
    }

    var displayName: String {
        let name = fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        let user = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !user.isEmpty { return user }
        return "Unknown"
    }
}

struct AgoraCallDto: Decodable, Equatable {
    let id: String
    let conversationId: String
    let type: AgoraCallType
    let status: AgoraCallStatus?
    let channelName: String
    let callerId: String
    let calleeId: String
    let caller: AgoraCallUserSummary?
    let callee: AgoraCallUserSummary?
    let participants: [AgoraCallUserSummary]?
    let appId: String?
    let startedAt: String?
    let endedAt: String?
    let createdAt: String?
    /// Group / channel title when provided by server.
    let conversationTitle: String?
    /// Explicit group flag from server (`isGroup` / `conversationType`).
    let isGroup: Bool?

    enum CodingKeys: String, CodingKey {
        case id, conversationId, type, status, channelName, callerId, calleeId
        case caller, callee, participants, appId, startedAt, endedAt, createdAt
        case conversationTitle, title, isGroup, conversationType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.decodeString(c, forKey: .id) ?? ""
        conversationId = Self.decodeString(c, forKey: .conversationId) ?? ""
        if let raw = try c.decodeIfPresent(String.self, forKey: .type),
           let parsed = AgoraCallType(rawValue: raw.lowercased()) {
            type = parsed
        } else {
            type = .audio
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .status)?.lowercased() {
            status = AgoraCallStatus(rawValue: raw)
        } else {
            status = nil
        }
        channelName = Self.decodeString(c, forKey: .channelName) ?? ""
        callerId = Self.decodeString(c, forKey: .callerId) ?? ""
        calleeId = Self.decodeString(c, forKey: .calleeId) ?? ""
        caller = try c.decodeIfPresent(AgoraCallUserSummary.self, forKey: .caller)
        callee = try c.decodeIfPresent(AgoraCallUserSummary.self, forKey: .callee)
        participants = try c.decodeIfPresent([AgoraCallUserSummary].self, forKey: .participants)
        appId = Self.decodeString(c, forKey: .appId)
        startedAt = try c.decodeIfPresent(String.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(String.self, forKey: .endedAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        conversationTitle = try c.decodeIfPresent(String.self, forKey: .conversationTitle)
            ?? c.decodeIfPresent(String.self, forKey: .title)

        if let flag = try c.decodeIfPresent(Bool.self, forKey: .isGroup) {
            isGroup = flag
        } else if let raw = try c.decodeIfPresent(String.self, forKey: .conversationType) {
            let normalized = raw.lowercased()
            isGroup = (normalized == "group" || normalized == "group_call")
        } else if let participants, participants.count > 2 {
            isGroup = true
        } else if calleeId.isEmpty, !callerId.isEmpty {
            // Group payloads often omit a single callee.
            isGroup = conversationTitle != nil || (participants?.isEmpty == false)
        } else {
            isGroup = nil
        }
    }

    /// Accepts String / Int / UUID-ish numbers from Android/server JSON.
    private static func decodeString(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key), !s.isEmpty { return s }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return String(Int(d)) }
        return nil
    }

    var resolvedIsGroup: Bool {
        if let isGroup { return isGroup }
        if let participants, participants.count > 2 { return true }
        return false
    }

    func peer(relativeTo meId: String) -> AgoraCallUserSummary? {
        if callerId == meId { return callee }
        return caller
    }

    func displayTitle(relativeTo meId: String, fallback: String? = nil) -> String {
        if resolvedIsGroup {
            let title = conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty { return title }
            if let fallback, !fallback.isEmpty { return fallback }
            return "Group Call"
        }
        if let peer = peer(relativeTo: meId) {
            return peer.displayName
        }
        if let fallback, !fallback.isEmpty { return fallback }
        return "Calling…"
    }
}

struct AgoraCallSession: Equatable {
    let call: AgoraCallDto
    let token: String
    let uid: String
    let appId: String

    var hasJoinCredentials: Bool {
        !token.isEmpty && !appId.isEmpty && !call.channelName.isEmpty
    }

    init(call: AgoraCallDto, token: String, uid: String, appId: String) {
        self.call = call
        self.token = token
        self.uid = uid
        self.appId = appId
    }

    /// Parses Android/web CallSession:
    /// `{ success, requestId, data: { call, token, uid, appId } }` or bare `{ call, token, uid, appId }`.
    init?(dict: [String: Any]) {
        let root = Self.unwrapSessionDict(dict)
        guard let callDict = root["call"] as? [String: Any],
              let callData = try? JSONSerialization.data(withJSONObject: callDict),
              let call = try? JSONDecoder().decode(AgoraCallDto.self, from: callData),
              !call.id.isEmpty else {
            return nil
        }
        let token = Self.stringValue(root["token"]) ?? ""
        let uid = Self.stringValue(root["uid"]) ?? ""
        let appId = Self.stringValue(root["appId"])
            ?? Self.stringValue(callDict["appId"])
            ?? call.appId
            ?? ""
        self.call = call
        self.token = token
        self.uid = uid
        self.appId = appId
    }

    /// Prefer non-empty fields from `primary`, fill gaps from `fallback` (create:ack → call:join).
    static func merge(_ primary: AgoraCallSession, fallback: AgoraCallSession?) -> AgoraCallSession {
        guard let fallback else { return primary }
        let token = primary.token.isEmpty ? fallback.token : primary.token
        let uid = primary.uid.isEmpty ? fallback.uid : primary.uid
        let appId = primary.appId.isEmpty ? fallback.appId : primary.appId
        // call:join may omit channel/token; keep create:ack call media fields when needed.
        let call = primary.call.channelName.isEmpty ? fallback.call : primary.call
        return AgoraCallSession(call: call, token: token, uid: uid, appId: appId)
    }

    private static func unwrapSessionDict(_ dict: [String: Any]) -> [String: Any] {
        if let data = dict["data"] as? [String: Any] {
            if data["call"] != nil { return data }
            if let nested = data["data"] as? [String: Any], nested["call"] != nil { return nested }
        }
        return dict
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String, !s.isEmpty { return s }
        if let i = any as? Int { return String(i) }
        if let i = any as? Int64 { return String(i) }
        if let n = any as? NSNumber { return n.stringValue }
        if let d = any as? Double { return String(Int(d)) }
        return nil
    }
}

enum AgoraCallSocketEvents {
    static let create = "call:create"
    static let createAck = "call:create:ack"
    static let incoming = "call:incoming"
    static let accept = "call:accept"
    static let join = "call:join"
    static let decline = "call:decline"
    static let declined = "call:declined"
    /// Receiver explicitly rejected (distinct from generic declined fan-out).
    static let rejected = "call:rejected"
    /// Caller cancelled before pickup.
    static let cancelled = "call:cancelled"
    static let busy = "call:busy"
    static let ringing = "call:ringing"
    static let leave = "call:leave"
    static let leaveAck = "call:leave:ack"
    static let end = "call:end"
    static let endAck = "call:end:ack"
    static let participantJoined = "call:participant:joined"
    static let participantLeft = "call:participant:left"
}

/// Shared payload fields for decline / busy / reject / cancel / end:ack (mirrors web `call-context`).
struct AgoraCallLifecyclePayload {
    let callId: String
    let reason: String?
    let status: String?
    let callEnded: Bool?
    let supersededBy: String?
    let disconnected: Bool?
    let byUserId: String?
    let call: AgoraCallDto?

    /// Caller-facing toast / status line.
    var displayMessage: String {
        AgoraCallLifecyclePayload.endMessage(reason: reason, status: status)
    }

    static func endMessage(reason: String?, status: String?) -> String {
        let r = (reason ?? status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if r == "busy" { return "User is busy" }
        if r == "cancelled" || r == "canceled" { return "Call cancelled" }
        if r == "rejected" || r == "declined" { return "Call declined" }
        if r == "missed" { return "Missed call" }
        return "Call ended"
    }
}

enum AgoraCallDeclineReason: String {
    case busy
    case declined
}

enum AgoraCallError: LocalizedError {
    case timeout
    case failed(String)
    case notIdle
    case busy
    case noInternet
    case missingCall
    case joinFailed(String)
    case socketNotConnected

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Call request timed out"
        case .failed(let message):
            return message
        case .notIdle:
            return "Already in a call"
        case .busy:
            return "User is busy"
        case .noInternet:
            return "No internet connection"
        case .missingCall:
            return "No active call"
        case .joinFailed(let message):
            return message
        case .socketNotConnected:
            return "Chat socket is not connected. Please try again."
        }
    }

    static func isBusyMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("busy")
            || lower.contains("on another call")
            || lower.contains("already on a call")
            || lower.contains("user is on a call")
    }
}
