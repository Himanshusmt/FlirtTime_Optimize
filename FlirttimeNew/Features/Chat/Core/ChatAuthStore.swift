//
//  ChatAuthStore.swift
//  FlirttimeNew
//

import Foundation
import KeychainAccess

/// Thread-safe holder of the chat session: tokens (Keychain) and the signed-in chat user.
///
/// FlirtTime's login flow calls `signIn(...)` once the FlirtTime backend returns chat credentials.
final class ChatAuthStore {

    static let shared = ChatAuthStore()

    private let keychain = Keychain()
    private let lock = NSLock()
    private var accessTokenValue = ""
    private var refreshTokenValue = ""
    private let userDefaultsKey = "flirttimeChatUser"

    private init() {
        accessTokenValue = Self.sanitized(keychain[ChatConfig.accessTokenKey])
        refreshTokenValue = Self.sanitized(keychain[ChatConfig.refreshTokenKey])
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
    var hasRefreshToken: Bool { !refreshToken.isEmpty }

    var currentUser: User? {
        get {
            if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
               let user = try? JSONDecoder().decode(User.self, from: data) {
                return user
            }
            return fallbackUser()
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }

    var currentUserId: String { currentUser?.userId ?? "" }

    /// Call after FlirtTime login once the chat backend has issued tokens for this user.
    func signIn(accessToken: String, refreshToken: String?, user: User) {
        update(accessToken: accessToken, refreshToken: refreshToken)
        currentUser = user
        ChatSocketSessionCoordinator.shared.start()
    }

    /// - Empty `accessToken` clears both tokens.
    /// - Nil or empty `refreshToken` keeps the stored refresh token.
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

    /// Clears tokens, disconnects the socket, ends calls and wipes the local chat database.
    func logout() {
        ChatSocketSessionCoordinator.shared.shutdownForLogout()
        ConversationDraftStore.shared.clearAll()
        DispatchQueue.main.async {
            Task { @MainActor in
                AgoraCallService.shared.shutdownForLogout()
            }
            ChatNotificationState.clearAllChatNotifications()
            MessageStatusManager.shared.clearAllStatuses()
            ChatDataPreloader.shared.clearCache()
        }
        ChatDatabaseManager.shared.clearAllChatData { success in
            AppLogger.debug("ChatAuthStore.logout chat DB clear success=\(success)")
        }
        CoreDataManager.shared.clearAllEntities()
        MediaStorageManager.shared.resetForNewSession()
        ChatMockSeeder.shared.reset()
        currentUser = nil
        update(accessToken: "", refreshToken: "")
    }

    private func fallbackUser() -> User? {
        let id = UserDataManager.shared.userID ?? MockDataStore.shared.currentUserID
        return User(
            userId: String(id),
            fullName: UserDataManager.shared.displayName,
            userName: UserDataManager.shared.displayName,
            profilePicture: UserDataManager.shared.userAvtarImage
        )
    }

    private func persist(access: String, refresh: String) {
        do {
            if access.isEmpty {
                try keychain.remove(ChatConfig.accessTokenKey)
            } else {
                try keychain.set(access, key: ChatConfig.accessTokenKey)
            }
            if refresh.isEmpty {
                try keychain.remove(ChatConfig.refreshTokenKey)
            } else {
                try keychain.set(refresh, key: ChatConfig.refreshTokenKey)
            }
        } catch {
            AppLogger.debug("ChatAuthStore persist error: \(error.localizedDescription)")
        }
    }

    private static func sanitized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
