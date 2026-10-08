//
//  BlockedManager.swift
//  FlirttimeNew
//
//  Created by Aasif on 11/05/26.
//

import Foundation
final class BlockedUsersManager {
    
    static let shared = BlockedUsersManager()
    
    private init() {}
    
    private let blockedUsersKey = "blocked_users_key"
    
    var blockedUserIDs: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: blockedUsersKey) ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: blockedUsersKey)
        }
    }
    
    func blockUser(id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var ids = blockedUserIDs
        ids.insert(trimmed)
        blockedUserIDs = ids

        // Home may not be listening yet — flag a feed refresh on next appear
        UserDefaults.standard.set(true, forKey: "blockUserId")

        NotificationCenter.default.post(
            name: .userBlocked,
            object: trimmed
        )
    }
    
    func unblockUser(id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var ids = blockedUserIDs
        ids.remove(trimmed)
        blockedUserIDs = ids
        
        NotificationCenter.default.post(
            name: .userUnblocked,
            object: trimmed
        )
    }
    
    func isBlocked(id: String) -> Bool {
        blockedUserIDs.contains(id)
    }
}

extension Notification.Name {
    static let userBlocked = Notification.Name("userBlocked")
    static let userUnblocked = Notification.Name("userUnblocked")
}
