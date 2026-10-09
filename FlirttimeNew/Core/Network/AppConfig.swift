//
//  AppConfig.swift
//  FlirttimeNew
//

import Foundation

/// FlirtTime backend settings. `AppBaseURL` is read from Info.plist.
enum AppConfig {

    static let accessTokenKey = "flirttimeAccessToken"
    static let refreshTokenKey = "flirttimeRefreshToken"

    static var baseURL: URL? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "AppBaseURL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: value)
    }
}
