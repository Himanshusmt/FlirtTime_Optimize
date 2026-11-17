//
//  LiveStreamingConstants.swift
//  FlirttimeNew
//
//  Live Streaming Testing Configuration & Constants
//

import Foundation

enum LiveStreamingRole: String, CaseIterable, Identifiable {
    case broadcaster = "Host (Broadcaster)"
    case audience = "Viewer (Audience)"

    var id: String { rawValue }
}

enum CoHostRequestStatus: Equatable {
    case idle
    case pendingSent         // Viewer requested to co-host
    case accepted            // Host accepted, now co-hosting
    case rejected            // Host rejected
}

struct CoHostRequest: Identifiable, Equatable {
    let id: String
    let uid: UInt
    let userName: String
    let timestamp: Date

    init(uid: UInt, userName: String) {
        self.id = "\(uid)_\(Int(Date().timeIntervalSince1970))"
        self.uid = uid
        self.userName = userName
        self.timestamp = Date()
    }
}

// Low-latency in-channel signaling message over Agora DataStream
struct LiveStreamSignalingMessage: Codable {
    enum Action: String, Codable {
        case requestCoHost = "request_co_host"
        case acceptCoHost = "accept_co_host"
        case rejectCoHost = "reject_co_host"
        case endCoHost = "end_co_host"
    }

    let action: Action
    let senderUid: UInt
    let targetUid: UInt?
    let senderName: String?
}

struct LiveStreamingConfig {
    static let defaultAppId = "7905f0b344204aecc3c34a236b94b"
    static let defaultToken = "007eJxTYHieoWKyw6/5cxwXF7+FS/Cp4nML11XOD3ytlH1eL1bl904FBgszM3NLA9M0gyRjExMjA5PE1ORk42Rjk0QjY7MkS5OkHpcHWQ2BjAwP0nSZGRkgEMQXZihJLS7RzcksS40vLilKTczNzEtnYAAA8lwkig=="
    static let defaultChannelName = "test-live_streaming"

    private static let keyAppId = "LiveStreaming_AppId"
    private static let keyToken = "LiveStreaming_Token"
    private static let keyChannelName = "LiveStreaming_ChannelName"

    static var currentAppId: String {
        get {
            let saved = UserDefaults.standard.string(forKey: keyAppId)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? defaultAppId : saved
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keyAppId)
        }
    }

    static var currentToken: String {
        get {
            let saved = UserDefaults.standard.string(forKey: keyToken)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? defaultToken : saved
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keyToken)
        }
    }

    static var currentChannelName: String {
        get {
            let saved = UserDefaults.standard.string(forKey: keyChannelName)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? defaultChannelName : saved
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keyChannelName)
        }
    }

    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: keyAppId)
        UserDefaults.standard.removeObject(forKey: keyToken)
        UserDefaults.standard.removeObject(forKey: keyChannelName)
    }
}
