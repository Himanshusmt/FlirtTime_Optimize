//
//  ChatConfig.swift
//  FlirttimeNew
//

import Foundation

/// Chat backend settings. Values come from the `CHAT_BASE_URL`, `CHAT_SOCKET_URL`,
/// `CHAT_SOCKET_PATH` and `CHAT_MEDIA_BASE_URL` build settings via Info.plist.
enum ChatConfig {

    static let accessTokenKey = "flirttimeChatAccessToken"
    static let refreshTokenKey = "flirttimeChatRefreshToken"

    static var baseURL: URL? {
        URL(string: infoValue("ChatBaseURL"))
    }

    static var publicWebHost: String {
        baseURL?.host ?? ""
    }

    static var socketURL: String {
        infoValue("ChatSocketURL")
    }

    static var socketPath: String {
        let path = infoValue("ChatSocketPath")
        return path.isEmpty ? "/socket.io/" : path
    }

    /// Prefix for relative media keys returned by the chat API.
    static var mediaBaseURL: String {
        let value = infoValue("ChatMediaBaseURL")
        return value.isEmpty ? ApiName.imgBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) : value
    }

    static var googleMapsAPIKey: String {
        infoValue("GoogleMapsAPIKey")
    }

    static var isConfigured: Bool {
        baseURL != nil && !socketURL.isEmpty
    }

    static func profileShareUsername(from url: URL) -> String? {
        nil
    }

    static func isAppShareLinkHost(_ host: String?) -> Bool {
        false
    }

    private static func infoValue(_ key: String) -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
