//
//  ChatConstants.swift
//  FlirttimeNew
//

import Foundation

// MARK: - Chat Notification Names
extension NSNotification.Name {
    static let ChatHasUnreadMessages = NSNotification.Name("ChatHasUnreadMessages")
    static let ChatUnreadCleared = NSNotification.Name("ChatUnreadCleared")
    static let ChatBlockStatusChanged = NSNotification.Name("ChatBlockStatusChanged")
    static let ChatLastMessageDeleted = NSNotification.Name("ChatLastMessageDeleted")
    /// Android `CHAT_MESSAGE_REACTED` / socket `chat:message:reacted`
    static let ChatMessageReacted = NSNotification.Name("ChatMessageReacted")
}

enum ChatConstants {
    // MARK: - Pagination
    enum Pagination {
        static let initialDisplayCount = 20
        static let silentPreloadCount = 40
        static let paginationBatchSize = 40
        static let messageLoadLimit = 100
        static let mediaRefreshLimit = 50
        static let forwardConversationsPageSize = 20
    }

    // MARK: - Timers & Intervals
    enum Timing {
        static let conversationStatusPollInterval: TimeInterval = 15.0
        static let toastDuration: TimeInterval = 2.0
        static let audioWaveformThrottleMs: Int = 60
        static let scrollDebounce: TimeInterval = 0.15
        static let scrollAnimation: TimeInterval = 0.25
        static let highlightDelay: TimeInterval = 0.3
        static let loadMoreCooldown: TimeInterval = 1.0
        static let loadMoreSettling: TimeInterval = 0.5
        static let viewOnceControlsHideDelay: TimeInterval = 3.0
        static let statusEmitDelay: TimeInterval = 3.0
        static let searchDebounce: TimeInterval = 0.25
        static let recordingTimerInterval: TimeInterval = 1.0
    }

    // MARK: - Scroll Thresholds
    enum Scroll {
        static let autoScrollDistanceThreshold: CGFloat = 150
        static let loadMoreOffsetThreshold: CGFloat = 300
    }

    // MARK: - Cache Limits
    enum Cache {
        static let maxDiskCacheSizeMB: Int = 200
        static let maxMemoryCacheCount = 50
        static let maxMediaCacheCount = 50
        static let maxOfflineQueueSize = 100
        static let cacheExpirationDays = 7
        static let maxTotalCacheSizeMB: Int = 100
    }

    // MARK: - Audio
    enum Audio {
        static let maxConcurrentDownloads = 3
        static let waveAmplitudeBars = 34
        static let defaultWaveAmplitude: CGFloat = 0.12
    }

    // MARK: - Assets
    enum Assets {
        static let chatBackgroundImage = ChatAssets.background
    }
}
