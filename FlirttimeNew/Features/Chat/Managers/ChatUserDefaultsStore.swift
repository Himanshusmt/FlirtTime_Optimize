import Foundation

final class ChatUserDefaultsStore {
    static let shared = ChatUserDefaultsStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Keys
    private enum Keys {
        static let groupAvatarStore = "group_avatar_store"
        static let lastSyncTimestamp = "lastSyncTimestamp"
        static let backgroundSyncEnabled = "backgroundSyncEnabled"
        static let userId = "user_id"
        static let liveLocationWaitingPermission = "LiveLocation_WaitingPermissionUpgrade"
        static let viewOnceMessages = "viewOnceMessages"
        static let recentReactions = "recent_reactions"
        static let lastBackgroundSyncDate = "background_sync_last_run"
    }

    // MARK: - Group Avatar Store
    var groupAvatarStore: [String: String] {
        get { defaults.dictionary(forKey: Keys.groupAvatarStore) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Keys.groupAvatarStore) }
    }

    // MARK: - Sync Timestamps
    var lastSyncTimestamp: String? {
        get { defaults.string(forKey: Keys.lastSyncTimestamp) }
        set { defaults.set(newValue, forKey: Keys.lastSyncTimestamp) }
    }
    
    func removeLastSyncTimestamp() {
        defaults.removeObject(forKey: Keys.lastSyncTimestamp)
    }

    // MARK: - Background Sync
    var backgroundSyncEnabled: Bool {
        get { defaults.bool(forKey: Keys.backgroundSyncEnabled) }
        set { defaults.set(newValue, forKey: Keys.backgroundSyncEnabled) }
    }

    var backgroundSyncEnabledExists: Bool {
        defaults.object(forKey: Keys.backgroundSyncEnabled) != nil
    }
    
    var lastBackgroundSyncDate: Date? {
        get { defaults.object(forKey: Keys.lastBackgroundSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastBackgroundSyncDate) }
    }

    // MARK: - User
    var userId: String? {
        get { defaults.string(forKey: Keys.userId) }
        set { defaults.set(newValue, forKey: Keys.userId) }
    }

    // MARK: - Recent Mentions
    func recentMentions(for userId: String) -> [String] {
        defaults.stringArray(forKey: "recent_mentions_\(userId)") ?? []
    }

    func setRecentMentions(_ mentions: [String], for userId: String) {
        defaults.set(mentions, forKey: "recent_mentions_\(userId)")
    }

    // MARK: - Live Location
    var liveLocationWaitingPermissionUpgrade: Bool {
        get { defaults.bool(forKey: Keys.liveLocationWaitingPermission) }
        set { defaults.set(newValue, forKey: Keys.liveLocationWaitingPermission) }
    }
    
    func getLiveLocationData(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }
    
    func setLiveLocationData(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }

    // MARK: - Recent Reactions
    var recentReactions: [String] {
        get { defaults.stringArray(forKey: Keys.recentReactions) ?? [] }
        set { defaults.set(newValue, forKey: Keys.recentReactions) }
    }
    
    // MARK: - View Once
    var viewedMessageIds: [String] {
        get { defaults.stringArray(forKey: Keys.viewOnceMessages) ?? [] }
        set { defaults.set(newValue, forKey: Keys.viewOnceMessages) }
    }
    
    // MARK: - Generic
    func getDictionary(forKey key: String) -> [String: Any]? {
        defaults.dictionary(forKey: key)
    }
    
    func setDictionary(_ value: [String: Any], forKey key: String) {
        defaults.set(value, forKey: key)
    }
    func getInteger(forKey key: String) -> Int {
        defaults.integer(forKey: key)
    }
    
    func setInteger(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}
