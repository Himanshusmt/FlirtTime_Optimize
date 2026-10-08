//
//  BetterUserDefaults.swift
//  FlirttimeNew
//

import Foundation

/// Thin wrapper over `UserDefaults` used by the chat repositories.
final class BetterUserDefaults {
    static let standard = BetterUserDefaults(defaults: .standard)

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var user: User? { ChatAuthStore.shared.currentUser }

    func contains(key: String) -> Bool {
        defaults.object(forKey: key) != nil
    }

    func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
