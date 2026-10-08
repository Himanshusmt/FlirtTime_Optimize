//
//  ChatSyncService.swift
//  FlirttimeNew
//
//  Created by Awais on 29/09/2025.
//

import Foundation
import Combine

@MainActor
class ChatSyncService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingArchived = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasMorePages = true

    // MARK: - Cache Policy

    enum CachePolicy {
        case never
        case ifStale
        case always
    }

    // MARK: - Private Properties

    private let sessionManager: SessionManager
    private let chatDataService: ChatDataService

    private let pageSize = 20
    private let archivedPageSize = 30
    private var isFetching = false
    private var isFetchingArchived = false
    private var nextPageCursor: String? = nil
    private var lastSyncRequestTime = Date.distantPast
    private var lastSuccessfulSync: Date?
    private var lastSyncFailure: Date?
    private let minSyncInterval: TimeInterval = 1.0
    private let syncSuccessCooldown: TimeInterval = 30.0
    private let syncFailureCooldown: TimeInterval = 5.0
    private var lastCacheLoadTime: Date?
    private let cacheReloadInterval: TimeInterval = 5.0
    private let lastSyncTimestampKey = "lastSyncTimestamp"
    private var hasCompletedFullRefreshThisSession = false

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Initialization

    init(sessionManager: SessionManager, chatDataService: ChatDataService) {
        self.sessionManager = sessionManager
        self.chatDataService = chatDataService
        setupNotificationListeners()
    }

    private func setupNotificationListeners() {
        // Listen for requests to refresh a specific conversation's participants
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RefreshConversationParticipants"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let conversationId = notification.userInfo?["conversationId"] as? String else { return }
            AppLogger.debug("ChatSyncService: Received request to refresh participants for \(conversationId)")
            // Force a full refresh to get participants
            self.startApiSync(forceRefresh: true)
        }
    }

    // MARK: - Public Methods

    func syncChats(loadPolicy: CachePolicy = .ifStale, forceRefresh: Bool = false, bypassCooldown: Bool = false) {
        if !chatDataService.chats.isEmpty {
            if forceRefresh || shouldStartSync(forceRefresh: forceRefresh, bypassCooldown: bypassCooldown) {
                startApiSync(forceRefresh: forceRefresh, bypassCooldown: bypassCooldown)
            }
            return
        }

        // Use async loading properly to ensure cached chats are displayed
        Task { [weak self] in
            guard let self = self else { return }
            let startTime = Date()
            let cachedChats = await self.chatDataService.loadCachedChats()
            let duration = Date().timeIntervalSince(startTime)

            if !cachedChats.isEmpty {
                self.chatDataService.updateChats(cachedChats)
                self.lastCacheLoadTime = Date()
                ChatDataPreloader.shared.updatePreloadedChats(cachedChats)
            }

            if forceRefresh || self.shouldStartSync(forceRefresh: forceRefresh, bypassCooldown: bypassCooldown) {
                self.startApiSync(forceRefresh: forceRefresh, bypassCooldown: bypassCooldown)
            }
        }
    }

    func loadNextPage() {
        guard !isFetching, hasMorePages, !ChatMockSeeder.isMockMode else { return }

        isFetching = true
        isLoading = true

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await self.fetchConversations(
                    limit: self.pageSize,
                    before: self.nextPageCursor
                )
                await self.handleApiResponse(response, isPagination: true, isFullRefresh: false)
            } catch {
                await self.handleApiError(error)
            }
        }
    }

    func preloadCache(policy: CachePolicy = .ifStale) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.loadCacheIfNeeded(policy: policy)
        }
    }

    /// FE — GET `/api/v1/chat/conversations?limit=30&archived=true`
    /// Loads archived inbox when the Archived tab is opened. Merges into Core Data
    /// without pruning the main (non-archived) inbox.
    func loadArchivedConversations() {
        guard !isFetchingArchived else { return }
        guard sessionManager.isNetworkReachable() else {
            AppLogger.debug("ChatSyncService: Archived load skipped — offline")
            return
        }

        isFetchingArchived = true
        isLoadingArchived = true
        AppLogger.debug("ChatSyncService: ▶ GET chat/conversations?limit=\(archivedPageSize)&archived=true")

        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.fetchConversations(
                    limit: self.archivedPageSize,
                    showArchived: true
                )
                await self.handleArchivedApiResponse(response)
            } catch {
                await MainActor.run {
                    self.isFetchingArchived = false
                    self.isLoadingArchived = false
                    self.errorMessage = error.localizedDescription
                    AppLogger.debug("ChatSyncService: Archived load failed — \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Private Methods

    @MainActor
    private func loadCacheIfNeeded(policy: CachePolicy) async {
        if !chatDataService.chats.isEmpty {
            return
        }

        let shouldLoad: Bool
        switch policy {
        case .never:
            shouldLoad = false
        case .always:
            shouldLoad = true
        case .ifStale:
            if let last = lastCacheLoadTime, Date().timeIntervalSince(last) < cacheReloadInterval {
                shouldLoad = false
            } else {
                shouldLoad = true
            }
        }
        guard shouldLoad else { return }

        let cachedChats = await chatDataService.loadCachedChatsFast()
        chatDataService.updateChats(cachedChats)
        lastCacheLoadTime = Date()

        ChatDataPreloader.shared.updatePreloadedChats(cachedChats)

        if !cachedChats.isEmpty {
            lastSuccessfulSync = Date()
        }

        Task.detached { [weak self] in
            guard let self = self else { return }
            let fullChats = await self.chatDataService.loadCachedChats()
            await MainActor.run {
                guard !fullChats.isEmpty else { return }
                self.chatDataService.updateChats(fullChats)
                ChatDataPreloader.shared.updatePreloadedChats(fullChats)
            }
        }
    }

    private func startApiSync(forceRefresh: Bool, bypassCooldown: Bool = false) {
        guard !ChatMockSeeder.isMockMode else { return }
        guard shouldStartSync(forceRefresh: forceRefresh, bypassCooldown: bypassCooldown) else { return }

        isFetching = true
        isLoading = true
        nextPageCursor = nil
        hasMorePages = true
        lastSyncRequestTime = Date()

        syncWithAPI(forceRefresh: forceRefresh)
    }

    private func shouldStartSync(forceRefresh: Bool, bypassCooldown: Bool = false) -> Bool {
        if isFetching {
            return false
        }

        if bypassCooldown {
            return true
        }

        let now = Date()
        if !forceRefresh && now.timeIntervalSince(lastSyncRequestTime) < minSyncInterval {
            return false
        }

        if !forceRefresh, let lastSuccess = lastSuccessfulSync, now.timeIntervalSince(lastSuccess) < syncSuccessCooldown {
            return false
        }

        if !forceRefresh, let lastFailure = lastSyncFailure, now.timeIntervalSince(lastFailure) < syncFailureCooldown {
            return false
        }

        return true
    }

    private func syncWithAPI(forceRefresh: Bool) {
        guard sessionManager.isNetworkReachable() else {
            Task { [weak self] in
                guard let self else { return }
                await self.handleOfflineState()
            }
            return
        }

        let hasCachedChats = !chatDataService.chats.isEmpty
        // Always do a full refresh on the first sync of each app session so that
        let needsFullRefresh = forceRefresh || !hasCachedChats || !hasCompletedFullRefreshThisSession
        let lastSync = needsFullRefresh ? nil : loadLastSyncTimestamp()
        let isFullRefresh = (lastSync == nil)

        if !hasCachedChats {
            clearLastSyncTimestamp()
        }

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await self.fetchConversations(
                    limit: self.pageSize,
                    lastSync: lastSync
                )
                await self.handleApiResponse(response, isPagination: false, isFullRefresh: isFullRefresh)
            } catch {
                await self.handleApiError(error)
            }
        }
    }

    // MARK: - API Calls (Async wrappers for RxSwift)

    private func fetchConversations(
        limit: Int,
        search: String = "",
        showArchived: Bool = false,
        showPinned: Bool = false,
        lastSync: String? = nil,
        before: String? = nil
    ) async throws -> ChatMessageUserData {
        try await withCheckedThrowingContinuation { continuation in
            sessionManager.getConversations(
                page: 1,
                limit: limit,
                search: search,
                showArchived: showArchived,
                showPinned: showPinned,
                lastSync: lastSync,
                before: before
            )
            .subscribe(onSuccess: { response in
                continuation.resume(returning: response)
            }, onFailure: { error in
                continuation.resume(throwing: error)
            })
        }
    }

    // MARK: - Response Handling

    private func handleApiResponse(_ response: ChatMessageUserData, isPagination: Bool, isFullRefresh: Bool) async {
        isFetching = false
        isLoading = false

        let apiChats = response.rows ?? []
        applyDeltaMetadata(from: response)
        // Drive chat-list “Group call ongoing” + Join banner from `activeCall` on each row.
        await MainActor.run {
            AgoraCallService.shared.syncOngoingGroupCalls(from: apiChats)
        }

        AppLogger.debug("ChatSyncService: API returned \(apiChats.count) chats (isPagination=\(isPagination), isFullRefresh=\(isFullRefresh))")

        if apiChats.count < pageSize {
            hasMorePages = false
        }

        if isPagination || isFullRefresh {
            nextPageCursor = apiChats
                .compactMap { $0.lastMessageAt }
                .sorted()
                .first
        }

        await chatDataService.saveChatsToDatabase(apiChats)

        // Always prune on a full refresh — even when the server returns zero rows
        // (all chats deleted). Skipping prune here was the root cause of phantom
        // "Unknown" chats surviving in Core Data after the user deleted everything.
        if isFullRefresh {
            let returnedIds = Set(apiChats.compactMap { $0.id })
            await chatDataService.pruneStaleConversations(keepingIds: returnedIds)
        }

        ChatDataPreloader.shared.updatePreloadedChats(apiChats)

        for chat in apiChats where chat.participants?.isEmpty == false {
            NotificationCenter.default.post(
                name: NSNotification.Name("ConversationParticipantsUpdated"),
                object: nil,
                userInfo: ["conversationId": chat.id ?? ""]
            )
        }

        if isFullRefresh {
            hasCompletedFullRefreshThisSession = true
        }
        persistLastSyncTimestamp(response.serverTime)
        lastSuccessfulSync = Date()
        lastSyncFailure = nil
        AppLogger.debug("ChatSyncService: Sync complete (\(apiChats.count) chats)")
    }

    private func handleArchivedApiResponse(_ response: ChatMessageUserData) async {
        isFetchingArchived = false
        isLoadingArchived = false

        var apiChats = response.rows ?? []
        // Ensure archived flag is set so the Archived tab filter picks them up
        // even if the API omits `settings.isArchived` on some rows.
        for index in apiChats.indices {
            var settings = apiChats[index].settings ?? ConversationSettings()
            settings.isArchived = true
            apiChats[index].settings = settings
        }

        AppLogger.debug("ChatSyncService: Archived API returned \(apiChats.count) chats")
        await MainActor.run {
            AgoraCallService.shared.syncOngoingGroupCalls(from: apiChats)
        }
        // Merge only — never prune the main inbox from an archived fetch.
        await chatDataService.saveChatsToDatabase(apiChats)

        for chat in apiChats where chat.participants?.isEmpty == false {
            NotificationCenter.default.post(
                name: NSNotification.Name("ConversationParticipantsUpdated"),
                object: nil,
                userInfo: ["conversationId": chat.id ?? ""]
            )
        }
    }

    private func handleApiError(_ error: Error) async {
        isFetching = false
        isLoading = false

        let errorDescription = (parseError(error) as String?) ?? error.localizedDescription
        errorMessage = errorDescription
        lastSyncFailure = Date()

        // If we have no chats in memory, fall back to cached data from CoreData
        if chatDataService.chats.isEmpty {
            let cachedChats = await chatDataService.loadCachedChats()
            if !cachedChats.isEmpty {
                chatDataService.updateChats(cachedChats)
                ChatDataPreloader.shared.updatePreloadedChats(cachedChats)
                AppLogger.debug("ChatSyncService: API failed, loaded \(cachedChats.count) chats from cache as fallback")
            }
        }

        if SessionExpiredManager.shared.handleIfNeeded(error) {
            return
        }
    }

    private func handleOfflineState() async {
        isFetching = false
        isLoading = false
        lastSyncFailure = Date()

        if chatDataService.chats.isEmpty {
            let cachedChats = await chatDataService.loadCachedChats()
            if !cachedChats.isEmpty {
                chatDataService.updateChats(cachedChats)
                ChatDataPreloader.shared.updatePreloadedChats(cachedChats)
            }
        }
    }

    private func handleAuthenticationError() {
        NotificationCenter.default.post(name: NSNotification.Name("AuthenticationError"), object: nil)
    }

    // MARK: - Delta Metadata

    private func applyDeltaMetadata(from response: ChatMessageUserData) {
        if let deletedIds = response.deletedConversationIds, !deletedIds.isEmpty {
            for id in deletedIds where !id.isEmpty {
                chatDataService.removeChat(id, deleteFromStore: true)
            }
        }

        if let pinnedIds = response.pinnedConversationIds {
            pinnedIds.forEach { applyConversationSetting($0, key: "isPinned", value: true) }
        }
        if let unpinnedIds = response.unpinnedConversationIds {
            unpinnedIds.forEach { applyConversationSetting($0, key: "isPinned", value: false) }
        }

        if let archivedIds = response.archivedConversationIds {
            archivedIds.forEach { applyConversationSetting($0, key: "isArchived", value: true) }
        }
        if let unarchivedIds = response.unarchivedConversationIds {
            unarchivedIds.forEach { applyConversationSetting($0, key: "isArchived", value: false) }
        }

        if let mutedIds = response.mutedConversationIds {
            mutedIds.forEach { applyConversationSetting($0, key: "isMuted", value: true) }
        }
        if let unmutedIds = response.unmutedConversationIds {
            unmutedIds.forEach { applyConversationSetting($0, key: "isMuted", value: false) }
        }

        if let blockedIds = response.blockedConversationIds {
            blockedIds.forEach { applyConversationSetting($0, key: "isBlocked", value: true) }
        }
        if let unblockedIds = response.unblockedConversationIds {
            unblockedIds.forEach { applyConversationSetting($0, key: "isBlocked", value: false) }
        }
    }

    private func applyConversationSetting(_ conversationId: String, key: String, value: Bool) {
        guard !conversationId.isEmpty else { return }
        chatDataService.updateChatSettings(conversationId: conversationId, settings: [key: value])
        if key == "isBlocked" {
            NotificationCenter.default.post(
                name: .ChatBlockStatusChanged,
                object: nil,
                userInfo: ["conversationId": conversationId, "isBlocked": value]
            )
        }
    }

    // MARK: - Timestamp Persistence

    private func loadLastSyncTimestamp() -> String? {
        ChatUserDefaultsStore.shared.lastSyncTimestamp
    }

    private func clearLastSyncTimestamp() {
        ChatUserDefaultsStore.shared.removeLastSyncTimestamp()
        AppLogger.debug("ChatSync: Cleared stale lastSync timestamp (no cached chats)")
    }

    private func persistLastSyncTimestamp(_ serverTime: String?) {
        if let serverTime = serverTime, !serverTime.isEmpty {
            ChatUserDefaultsStore.shared.lastSyncTimestamp = serverTime
            return
        }
        let value = isoFormatter.string(from: Date().addingTimeInterval(-2))
        ChatUserDefaultsStore.shared.lastSyncTimestamp = value
    }
}
