//
//  AppTokenStore.swift
//  FlirttimeNew
//

import Foundation
import KeychainAccess

/// Thread-safe source of truth for the FlirtTime session tokens.
/// Memory is the live copy used on the request path; Keychain survives relaunch.
final class AppTokenStore {

    static let shared = AppTokenStore()

    private let keychain = Keychain()
    private let lock = NSLock()
    private var accessTokenValue = ""
    private var refreshTokenValue = ""

    private init() {
        accessTokenValue = Self.sanitized(keychain[AppConfig.accessTokenKey])
        refreshTokenValue = Self.sanitized(keychain[AppConfig.refreshTokenKey])
    }

    var accessToken: String {
        lock.lock()
        defer { lock.unlock() }
        return accessTokenValue
    }

    var refreshToken: String {
        lock.lock()
        defer { lock.unlock() }
        return refreshTokenValue
    }

    var hasAccessToken: Bool { !accessToken.isEmpty }

    /// An empty `accessToken` clears both tokens. A nil/empty `refreshToken` keeps the existing one.
    func update(accessToken: String, refreshToken: String? = nil) {
        let newAccess = Self.sanitized(accessToken)

        lock.lock()
        if newAccess.isEmpty {
            accessTokenValue = ""
            refreshTokenValue = ""
        } else {
            accessTokenValue = newAccess
            let newRefresh = Self.sanitized(refreshToken)
            if !newRefresh.isEmpty {
                refreshTokenValue = newRefresh
            }
        }
        let persistAccess = accessTokenValue
        let persistRefresh = refreshTokenValue
        lock.unlock()

        persist(access: persistAccess, refresh: persistRefresh)
    }

    func clear() {
        update(accessToken: "")
    }

    private func persist(access: String, refresh: String) {
        do {
            if access.isEmpty {
                try keychain.remove(AppConfig.accessTokenKey)
            } else {
                try keychain.set(access, key: AppConfig.accessTokenKey)
            }
            if refresh.isEmpty {
                try keychain.remove(AppConfig.refreshTokenKey)
            } else {
                try keychain.set(refresh, key: AppConfig.refreshTokenKey)
            }
        } catch {
            print("AppTokenStore persist error: \(error.localizedDescription)")
        }
    }

    private static func sanitized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
