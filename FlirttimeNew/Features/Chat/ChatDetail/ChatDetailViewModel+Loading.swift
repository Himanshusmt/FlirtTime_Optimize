//
//  ChatDetailViewModel+Loading.swift
//  FlirttimeNew
//
//  Created by Awais on 30/09/25.
//

import Foundation
import Combine
import CoreData
import UIKit
import Swinject

// MARK: - Constants

extension ChatDetailViewModel {
    private var initialDisplayCount: Int { ChatConstants.Pagination.initialDisplayCount }
    private var silentPreloadCount: Int { ChatConstants.Pagination.silentPreloadCount }
    private var paginationBatchSize: Int { ChatConstants.Pagination.paginationBatchSize }

    fileprivate func normalizeMessagesForDisplay(
        _ messages: [ConversationMessage],
        allowSystemPinInference: Bool
    ) -> [ConversationMessage] {
        return messages
    }
}

// MARK: - Single Entry Point

extension ChatDetailViewModel {

    func loadMessages() {
        guard !hasInitialLoadStarted else { return }
        hasInitialLoadStarted = true
        AppLogger.debug("[ChatFlow] loadMessages start conversation=\(selectedId) inMemoryCount=\(messages.count)")

        if let cachedEntry = ChatDataPreloader.shared.cachedPinState(for: selectedId) {
            currentPinnedMessage = cachedEntry
            isPinStateRestoredFromCache = true
            AppLogger.debug("[PinnedSync] Restored pin from cache for conversation=\(selectedId) id=\(cachedEntry?.id ?? "nil")")
        }

        if !messages.isEmpty {
            AppLogger.debug("[ChatFlow] using in-memory messages count=\(messages.count), scheduling background sync")
            scheduleBackgroundSync()
            return
        }

        let pendingMessages = collectPendingMessages()

        let fetchLimit = initialDisplayCount + silentPreloadCount

        if selectedId.isEmpty {
            AppLogger.debug("[ChatFlow] selectedId empty, falling back to API page=1")
            loadMessagesFromAPI(page: 1)
            return
        }

        if let repo = messageRepository as? MessageRepository {
            // Use the async metadata path — no semaphore, no main-thread stall.
            Task { [weak self] in
                guard let self = self else { return }
                let metadata = await repo.getConversationSyncMetadataAsync(for: self.selectedId)
                await self.continueLoadMessages(with: metadata, fetchLimit: fetchLimit, pendingMessages: pendingMessages)
            }
        } else {
            // Fallback for test doubles that don't implement the async path.
            let metadata = messageRepository.getConversationSyncMetadata(for: selectedId)
            Task { [weak self] in
                guard let self = self else { return }
                await self.continueLoadMessages(with: metadata, fetchLimit: fetchLimit, pendingMessages: pendingMessages)
            }
        }
    }

    @MainActor
    private func continueLoadMessages(
        with metadata: ConversationSyncMetadata?,
        fetchLimit: Int,
        pendingMessages: [ConversationMessage]
    ) async {
        let minPreloadThreshold = 5

        if let metadata = metadata, metadata.hasCachedMessages {
            AppLogger.debug("[ChatFlow] cache metadata count=\(metadata.messageCount) newest=\(debugTimestamp(metadata.newestMessageDate)) oldest=\(debugTimestamp(metadata.oldestMessageDate)) lastSync=\(debugTimestamp(metadata.lastSyncAt))")
            do {
                let cached = try await messageRepository.getMessagesSnapshot(
                    for: selectedId,
                    limit: fetchLimit,
                    offset: 0
                )
                guard messages.isEmpty else { return }
                if cached.isEmpty {
                    AppLogger.debug("[ChatFlow] cache metadata existed but snapshot empty, silent API load")
                    displayInitialMessages([])
                    loadMessagesFromAPI(page: 1, showLoadingState: false)
                    return
                }
                AppLogger.debug("[ChatFlow] displaying cached snapshot count=\(cached.count) pending=\(pendingMessages.count)")
                let combined = normalizeMessagesForDisplay(cached + pendingMessages, allowSystemPinInference: true)
                displayInitialMessages(combined)
                // Always delta-sync — even when cached count < 20, a page 1 replacement
                // causes a scroll jump. Delta sync fetches newer messages; scrolling up
                // triggers pagination for older ones.
                scheduleBackgroundSync()
                refreshPresignedURLsInBackground()
                checkAndLoadPinnedMessage()
            } catch {
                AppLogger.debug("[ChatFlow] cache snapshot load failed: \(error), silent API load")
                displayInitialMessages([])
                loadMessagesFromAPI(page: 1, showLoadingState: false)
            }
        } else {
            if let preloaded = ChatDataPreloader.shared.getPreloadedMessages(for: selectedId),
               preloaded.count >= minPreloadThreshold {
                AppLogger.debug("[ChatFlow] no cache metadata; using preload fallback count=\(preloaded.count)")
                let combined = normalizeMessagesForDisplay(preloaded + pendingMessages, allowSystemPinInference: true)
                ChatDataPreloader.shared.consumePreloadedMessages(for: selectedId)
                displayInitialMessages(combined)
                // Always delta-sync — avoids page 1 scroll jump (see cached path above).
                scheduleBackgroundSync()
                refreshPresignedURLsInBackground()
                checkAndLoadPinnedMessage()
                return
            }

            AppLogger.debug("[ChatFlow] no cache metadata and no preload fallback for conversation=\(selectedId), silent API load")
            displayInitialMessages([])
            loadMessagesFromAPI(page: 1, showLoadingState: false)
        }
    }

    func loadMessages(page: Int) {
        if page == 1 { loadMessages() }
        else { loadMessagesFromAPI(page: page) }
    }

    func refreshMessages(scrollToLatest: Bool = true) {
        currentPage = 1
        hasMorePages = true
        hasPreloadedCachedMessages = false
        hasInitialLoadStarted = false
        hasEmittedMarkSeen = false

        isInitialLoad = scrollToLatest ? messages.isEmpty : false
        initialScrollSettledAt = scrollToLatest ? nil : Date()

        if Self.useFRC, !messages.isEmpty {
            hasInitialLoadStarted = true

            let pendingMessages = collectPendingMessages()
            if !pendingMessages.isEmpty {
                let merged = messages + pendingMessages
                let sorted = merged.sorted { ($0.createdAt) < ($1.createdAt) }
                stateManager.setMessages(sorted)
                let groups = stateManager.getGroupedMessagesSnapshot()
                if groupedMessages != groups {
                    groupedMessages = groups
                    handleMessageListUpdate(groups.flatMap { $0.messages })
                }
                retryPendingMessagesAfterReconnect()
                AppLogger.debug("[ChatFocusRefresh] FRC fast path: merged \(pendingMessages.count) pending messages for conversation=\(selectedId)")
            }

            emitMarkConversationMessagesSeen()
            startConversationStatusPolling()
            scheduleBackgroundSync()
            checkAndLoadPinnedMessage()
            isLoadingMessages = false
            stateManager.setLoadingState(false)
            AppLogger.debug("[ChatFocusRefresh] FRC fast path: skipped cache re-read, \(messages.count) msgs already loaded for conversation=\(selectedId)")
            return
        }

        if !scrollToLatest, !messages.isEmpty {
            hasInitialLoadStarted = true
            scheduleBackgroundSync()
            checkAndLoadPinnedMessage()
            isLoadingMessages = false
            stateManager.setLoadingState(false)
            AppLogger.debug("[ChatFocusRefresh] fast path: skipped cache/page1 hydration, scheduled delta sync only for conversation=\(selectedId)")
            return
        }

        if selectedId.isEmpty {
            loadMessagesFromAPI(page: 1)
            return
        }

        let pendingMessages = collectPendingMessages()
        let fetchLimit = initialDisplayCount + silentPreloadCount

        if let repo = messageRepository as? MessageRepository {
            let syncMessages = repo.getMessagesSnapshotSync(
                for: selectedId, limit: fetchLimit, offset: 0
            )
            let syncCombined = normalizeMessagesForDisplay(
                syncMessages + pendingMessages, allowSystemPinInference: true
            )
            if !syncCombined.isEmpty {
                displayInitialMessages(syncCombined, scrollToLatest: scrollToLatest)
                hasInitialLoadStarted = true

                scheduleBackgroundSync()
                refreshPresignedURLsInBackground()
                checkAndLoadPinnedMessage()
                isLoadingMessages = false
                stateManager.setLoadingState(false)
                AppLogger.debug("[ChatFocusRefresh] sync fast path: displayed \(syncMessages.count) msgs instantly for conversation=\(selectedId)")
                return
            }
        }

        Task { [weak self] in
            guard let self = self else { return }

            do {
                let cachedMessages = try await self.messageRepository.getMessagesSnapshot(
                    for: self.selectedId,
                    limit: fetchLimit,
                    offset: 0
                )

                await MainActor.run {
                    let combined = self.normalizeMessagesForDisplay(cachedMessages + pendingMessages, allowSystemPinInference: true)
                    if !combined.isEmpty {
                        self.displayInitialMessages(combined, scrollToLatest: scrollToLatest)
                        self.hasInitialLoadStarted = true

                        self.scheduleBackgroundSync()
                        self.refreshPresignedURLsInBackground()
                        self.checkAndLoadPinnedMessage()
                    } else {
                        self.stateManager.setMessages([])
                        self.loadMessagesFromAPI(page: 1)
                    }

                    AppLogger.debug("[ChatFocusRefresh] hydrated cache count=\(cachedMessages.count) pending=\(pendingMessages.count) conversation=\(self.selectedId)")
                    self.isLoadingMessages = false
                    self.stateManager.setLoadingState(false)
                }
            } catch {
                await MainActor.run {
                    AppLogger.debug("[ChatFocusRefresh] cache hydrate failed for conversation=\(self.selectedId): \(error)")

                    if !pendingMessages.isEmpty {
                        self.stateManager.setMessages(pendingMessages)
                    }

                    self.isLoadingMessages = false
                    self.stateManager.setLoadingState(false)
                    self.loadMessagesFromAPI(page: 1)
                }
            }
        }
    }

    func preloadCachedMessagesIfAvailable() {
        loadMessages()
    }

    @discardableResult
    func injectPreloadedMessages() -> Bool {
        guard !selectedId.isEmpty else { return false }

        // FRC already provides cached messages — skip preloader injection to avoid
        // the flash of: FRC messages → preloaded subset → delta sync messages
        if Self.useFRC, !messages.isEmpty {
            ChatDataPreloader.shared.consumePreloadedMessages(for: selectedId)
            return false
        }

        guard let preloaded = ChatDataPreloader.shared.getPreloadedMessages(for: selectedId),
              !preloaded.isEmpty else { return false }

        let preloadedIds = Set(preloaded.map { $0.id })
        let inFlightMessages = tempMessageMapping.values.filter { msg in
            let status = msg.status ?? ""
            return (status == "sending" || status == "pending") && !preloadedIds.contains(msg.id)
        }

        let pendingMessages = collectPendingMessages()
        let displayMessages = Array(preloaded.suffix(initialDisplayCount))
        let combined = displayMessages + inFlightMessages + pendingMessages
        ChatDataPreloader.shared.consumePreloadedMessages(for: selectedId)
        applyInjectedMessages(combined, source: "preloader")
        return true
    }

    private func applyInjectedMessages(_ messages: [ConversationMessage], source: String) {
        hasPreloadedCachedMessages = true

        if let cachedEntry = ChatDataPreloader.shared.cachedPinState(for: selectedId) {
            currentPinnedMessage = cachedEntry
            isPinStateRestoredFromCache = true
            AppLogger.debug("[PinnedSync] Restored pin from cache (injection) conversation=\(selectedId) id=\(cachedEntry?.id ?? "nil")")
        }

        var mergedMessages = normalizeMessagesForDisplay(messages, allowSystemPinInference: true)

        // Same in-memory status overlay as displayInitialMessages.
        mergedMessages = mergedMessages.map { msg in
            let cached = MessageStatusManager.shared.status(for: msg.id)
            guard cached != .unknown else { return msg }
            let current = MessageDeliveryStatus.from(
                status: msg.status,
                sentAt: msg.sentAt,
                deliveredAt: msg.deliveredAt,
                seenAt: msg.seenAt
            )
            return cached > current ? msg.withStatus(cached) : msg
        }

        stateManager.setMessages(mergedMessages)

        let groups = stateManager.getGroupedMessagesSnapshot()
        self.groupedMessages = groups
        let flatMessages = groups.flatMap { $0.messages }
        self.handleMessageListUpdate(flatMessages)
        self.checkAndLoadPinnedMessage()

        emitMarkConversationMessagesSeen()
        AppLogger.debug("[ChatFlow] injectPreloadedMessages: instant display count=\(messages.count) conversation=\(selectedId) source=\(source)")

        reschedulePendingTimeoutsAfterInject()
        retryPendingMessagesAfterReconnect()
    }

    func scheduleBackgroundSyncAfterInjection() {
        hasInitialLoadStarted = true
        if messages.count < initialDisplayCount {
            backgroundTasks["_silent_hydrate"]?.cancel()
            let hydrateTask = Task { [weak self] in
                guard let self = self else { return }
                // Just do a delta sync after the layout settles.
            }
            backgroundTasks["_silent_hydrate"] = hydrateTask

            // Single delta sync after layout settles — wait past the settling window.
            backgroundTasks["_sync"]?.cancel()
            let delayedSync = Task { [weak self] in
                guard let self = self else { return }
                guard !Task.isCancelled else { return }
                self.syncNewMessagesFromAPI()
            }
            backgroundTasks["_sync"] = delayedSync
        } else {
            scheduleBackgroundSync()
        }
        refreshPresignedURLsInBackground()
    }

    private func reschedulePendingTimeoutsAfterInject() {
        for (tempId, message) in tempMessageMapping {
            let status = message.status ?? ""
            guard status != "failed" else { continue }
            // Timeout task is already running — nothing to do
            if backgroundTasks[tempId] != nil { continue }
            // For media: if an upload is already in flight, the callback reschedules on completion
            if activeMediaUploads.contains(tempId) { continue }
            AppLogger.debug("[InjectRetry] Rescheduling failure timeout for tempId=\(tempId)")
            scheduleFailureTimeout(for: tempId)
        }
    }

    func prepareForReuse() {
        if isChannel, !channelId.isEmpty {
            socketService.emitLeaveChannel(channelId)
        } else if !selectedId.isEmpty {
            socketService.emitLeaveConversation(selectedId)
        }
        backgroundTasks.values.forEach { $0.cancel() }
        backgroundTasks.removeAll()

        hasInitialLoadStarted = false
        isInitialLoad = true
        hasMorePages = true
        currentPage = 1
        lastLoadMoreTime = nil
        lastOlderPrefetchTime = nil
        inFlightOlderBeforeDate = nil
        isSyncingNewMessages = false
        isPrefetchingOlderMessages = false
        isLoadingMessages = false
        isLoadingOlderMessages = false
        isLoadingHistory = false
        initialScrollSettledAt = nil
        stateManager.setLoadingState(false)
    }
}

// MARK: - Initial Display (Single Snapshot)

extension ChatDetailViewModel {

    private func displayInitialMessages(_ messages: [ConversationMessage], scrollToLatest: Bool = true) {
        hasPreloadedCachedMessages = true
        isInHistoricalWindow = false

        var mergedMessages = normalizeMessagesForDisplay(messages, allowSystemPinInference: true)

        mergedMessages = mergedMessages.map { msg in
            let cached = MessageStatusManager.shared.status(for: msg.id)
            guard cached != .unknown else { return msg }
            let current = MessageDeliveryStatus.from(
                status: msg.status,
                sentAt: msg.sentAt,
                deliveredAt: msg.deliveredAt,
                seenAt: msg.seenAt
            )
            return cached > current ? msg.withStatus(cached) : msg
        }

        // Ensure deterministic chronological order so "latest" targeting is stable.
        mergedMessages.sort { ($0.createdAt ?? "") < ($1.createdAt ?? "") }

        deferredPrependMessages = []

        stateManager.setMessages(mergedMessages)

        // Bypass the 150ms Combine throttle: set groupedMessages synchronously
        let groups = stateManager.getGroupedMessagesSnapshot()
        self.groupedMessages = groups
        let flatMessages = groups.flatMap { $0.messages }
        self.handleMessageListUpdate(flatMessages)

        emitMarkConversationMessagesSeen()
        retryPendingMessagesAfterReconnect()
    }

    func performSilentPrepend() {
        guard !deferredPrependMessages.isEmpty else { return }
        let older = deferredPrependMessages
        deferredPrependMessages = []

        stateManager.prependMessages(older)

        // Bypass throttle
        let groups = stateManager.getGroupedMessagesSnapshot()
        self.groupedMessages = groups
        let flatMessages = groups.flatMap { $0.messages }
        self.handleMessageListUpdate(flatMessages)

        AppLogger.debug("[SilentPrepend] prepended \(older.count) older, total now \(flatMessages.count)")
    }

    private func collectPendingMessages() -> [ConversationMessage] {
        let conversationKey = isChannel ? channelId : selectedId
        guard !conversationKey.isEmpty else { return [] }
        let pending = PendingMessageStore.shared.pendingMessages(for: conversationKey)
        guard !pending.isEmpty else { return [] }

        var collected: [ConversationMessage] = []
        for entry in pending where tempMessageMapping[entry.tempId] == nil {
            tempMessageMapping[entry.tempId] = entry.message
            collected.append(entry.message)
        }
        return collected
    }

    func returnToLatestMessages() {
        guard isInHistoricalWindow else { return }

        AppLogger.debug(
            "[HistoricalWindow] return requested conversation=\(selectedId) displayedCount=\(messages.count) prefetchedCount=\(prefetchedLiveWindow?.count ?? 0) isPrefetching=\(isPrefetchingLiveWindow)"
        )

        if let cached = prefetchedLiveWindow, !cached.isEmpty {
            isInHistoricalWindow = false
            isPrefetchingLiveWindow = false
            prefetchedLiveWindow = nil
            pendingReturnToLatest = false
            let pending = collectPendingMessages()
            let combined = normalizeMessagesForDisplay(cached + pending, allowSystemPinInference: true)
            AppLogger.debug("[HistoricalWindow] return using prefetched live cache count=\(combined.count)")
            displayInitialMessages(combined, scrollToLatest: true)
            shouldScrollToBottomAfterWindowChange = true
            return
        }

        if isPrefetchingLiveWindow {
            AppLogger.debug("[HistoricalWindow] return deferred — queuing for prefetch completion")
            pendingReturnToLatest = true
            return
        }

        prefetchedLiveWindow = nil

        let convId = selectedId
        let fetchLimit = initialDisplayCount + silentPreloadCount

        Task { [weak self] in
            guard let self, self.selectedId == convId else { return }
            do {
                let cached = try await self.messageRepository.getMessagesSnapshot(
                    for: convId,
                    limit: fetchLimit,
                    offset: 0
                )
                let pending = self.collectPendingMessages()
                let combined = self.normalizeMessagesForDisplay(cached + pending, allowSystemPinInference: true)
                if !combined.isEmpty {
                    await MainActor.run {
                        guard self.selectedId == convId, self.isInHistoricalWindow else { return }
                        self.isInHistoricalWindow = false
                        self.isPrefetchingLiveWindow = false
                        self.prefetchedLiveWindow = nil
                        self.pendingReturnToLatest = false
                        AppLogger.debug("[HistoricalWindow] return using repository snapshot count=\(combined.count)")
                        self.displayInitialMessages(combined, scrollToLatest: true)
                        self.shouldScrollToBottomAfterWindowChange = true
                    }
                } else {
                    await MainActor.run {
                        guard self.selectedId == convId, self.isInHistoricalWindow else { return }
                        self.isPrefetchingLiveWindow = false
                        self.prefetchedLiveWindow = nil
                        AppLogger.debug("[HistoricalWindow] return blocked: snapshot empty; staying in historical window and prefetching live page")
                        self.prefetchLiveWindowIfNeeded(forceNetworkFallback: true)
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.selectedId == convId, self.isInHistoricalWindow else { return }
                    self.isPrefetchingLiveWindow = false
                    self.prefetchedLiveWindow = nil
                    AppLogger.debug("[HistoricalWindow] return failed to read snapshot: \(error.localizedDescription). Staying historical and retrying prefetch")
                    self.prefetchLiveWindowIfNeeded(forceNetworkFallback: true)
                }
            }
        }
    }

    func prefetchLiveWindowIfNeeded(forceNetworkFallback: Bool = false) {
        guard isInHistoricalWindow, !isPrefetchingLiveWindow else { return }
        guard prefetchedLiveWindow == nil || forceNetworkFallback else { return }
        isPrefetchingLiveWindow = true

        AppLogger.debug(
            "[HistoricalWindow] prefetch start conversation=\(selectedId) forceNetworkFallback=\(forceNetworkFallback)"
        )

        let convId = selectedId
        let fetchLimit = initialDisplayCount + silentPreloadCount

        Task { [weak self] in
            guard let self, self.selectedId == convId else { return }

            var cached: [ConversationMessage] = []
            do {
                cached = try await self.messageRepository.getMessagesSnapshot(
                    for: convId,
                    limit: fetchLimit,
                    offset: 0
                )
            } catch {
                AppLogger.debug("[HistoricalWindow] prefetch cache snapshot failed: \(error.localizedDescription)")
            }

            if !cached.isEmpty {
                await MainActor.run {
                    guard self.isInHistoricalWindow, self.selectedId == convId else { return }
                    self.prefetchedLiveWindow = cached
                    self.isPrefetchingLiveWindow = false
                    AppLogger.debug("[HistoricalWindow] prefetch ready from cache count=\(cached.count)")
                    if self.pendingReturnToLatest {
                        self.pendingReturnToLatest = false
                        self.returnToLatestMessages()
                    }
                }
                return
            }

            guard forceNetworkFallback else {
                await MainActor.run {
                    guard self.isInHistoricalWindow, self.selectedId == convId else { return }
                    self.prefetchedLiveWindow = nil
                    self.isPrefetchingLiveWindow = false
                    AppLogger.debug("[HistoricalWindow] prefetch cache empty; waiting for explicit network fallback")
                }
                return
            }

            do {
                let response = try await self.messageService.loadMessagesAsync(
                    conversationId: convId,
                    page: 1,
                    limit: fetchLimit
                )

                let rawNetworkMessages = response.data.data.messages.filter { $0.isDeleted != true }
                let networkMessages = self.normalizeMessagesForDisplay(
                    rawNetworkMessages,
                    allowSystemPinInference: true
                )
                .sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }

                if !networkMessages.isEmpty {
                    try? await self.messageRepository.saveMessages(networkMessages, conversationId: convId)
                }

                await MainActor.run {
                    guard self.isInHistoricalWindow, self.selectedId == convId else { return }
                    self.prefetchedLiveWindow = networkMessages.isEmpty ? nil : networkMessages
                    self.isPrefetchingLiveWindow = false
                    AppLogger.debug("[HistoricalWindow] prefetch ready from network count=\(networkMessages.count)")
                    if self.pendingReturnToLatest, !networkMessages.isEmpty {
                        self.pendingReturnToLatest = false
                        self.returnToLatestMessages()
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.selectedId == convId else { return }
                    self.prefetchedLiveWindow = nil
                    self.isPrefetchingLiveWindow = false
                    AppLogger.debug("[HistoricalWindow] prefetch network fallback failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Background Presigned URL Refresh

extension ChatDetailViewModel {

    private func shouldRefreshPresignedURLs() -> Bool {
        guard !selectedId.isEmpty else { return false }

        return messages.contains { message in
            let type = (message.messageType ?? message.type ?? "").lowercased()
            guard ["image", "photo", "video", "audio"].contains(type) else { return false }

            let mediaURL = message.media?.first?.url ?? message.content ?? ""
            guard mediaURL.hasPrefix("http") else { return false }

            if type == "image" || type == "photo" {
                if InMemoryMediaCache.shared.getCachedImage(for: message.id) != nil {
                    return false
                }
            }

            return true
        }
    }

    private func refreshPresignedURLsInBackground() {
        AppLogger.debug("[URLRefresh] skipped — delta sync handles URL refresh for conversation=\(selectedId)")
    }
}

// MARK: - Background Sync (Cancellable Tasks)

extension ChatDetailViewModel {

    private func scheduleBackgroundSync() {
        backgroundTasks["_sync"]?.cancel()
        let syncTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            guard !Task.isCancelled else { return }
            self.syncNewMessagesFromAPI()
        }
        backgroundTasks["_sync"] = syncTask
    }

    func syncNewMessagesFromAPI() {
        guard !isSyncingNewMessages, !ChatMockSeeder.isMockMode else { return }
        if !isChannelMode() && selectedId.isEmpty { return }
        isSyncingNewMessages = true

        let syncAnchor = messages.last.flatMap { parseDate($0.createdAt) }
        AppLogger.debug("[ChatSync] start conversation=\(selectedId) channelId=\(channelId) anchor=\(debugTimestamp(syncAnchor))")

        let publisher: AnyPublisher<ConversationMessagesResponse, Error>
        if isChannelMode() {
            if let anchor = syncAnchor {
                publisher = messageService.loadChannelMessagesAfter(
                    channelId: channelId,
                    afterDate: anchor,
                    limit: pageSize
                )
            } else {
                publisher = messageService.loadChannelMessages(channelId: channelId, page: 1, limit: pageSize)
            }
        } else if let anchor = syncAnchor {
            publisher = messageService.loadMessagesAfter(
                conversationId: selectedId,
                afterDate: anchor,
                limit: pageSize
            )
        } else {
            publisher = messageService.loadMessages(conversationId: selectedId, page: 1, limit: pageSize)
        }

        publisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] _ in
                    self?.isSyncingNewMessages = false
                },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }
                    self.isSyncingNewMessages = false
                    if !isChannel, let profileData = response.data.data.userProfileData {
                        applyUserProfileToHeader(profileData)
                        AppLogger.debug("[ChatProfile] API response assigned userProfileData=\(profileData)")
                    }
                    // Always apply server-authoritative pinned messages, even if the delta is empty.
                    self.applyServerPinnedMessages(response.data.data.pinnedMessages)
                    let allMessages = response.data.data.messages.filter { $0.isDeleted != true }
                    AppLogger.debug("[ChatSync] network delta received count=\(allMessages.count)")
                    guard !allMessages.isEmpty else { return }

                    Task { [weak self] in
                        guard let self = self else { return }
                        do {
                            try await self.messageRepository.saveMessages(allMessages, conversationId: self.selectedId)
                            AppLogger.debug("[ChatSync] saved delta to cache count=\(allMessages.count)")

                            if let anchor = syncAnchor {
                                AppLogger.debug("[ChatSync] hydrating delta from cache after=\(self.debugTimestamp(anchor))")
                                await self.appendOnlyNewMessagesFromCache(after: anchor)
                            } else {
                                await MainActor.run {
                                    self.appendOnlyNewMessages(allMessages)
                                }
                            }
                        } catch {
                            AppLogger.debug("[ChatSync] cache save failed, appending network delta directly: \(error)")
                            await MainActor.run {
                                self.appendOnlyNewMessages(allMessages)
                            }
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func appendOnlyNewMessagesFromCache(after date: Date) async {
        do {
            let cached = try await messageRepository.getMessagesAfter(
                conversationId: selectedId,
                afterDate: date,
                limit: max(pageSize, 50)
            ).filter { $0.isDeleted != true }

            AppLogger.debug("[ChatSync] cache delta query after=\(debugTimestamp(date)) count=\(cached.count)")

            guard !cached.isEmpty else { return }

            await MainActor.run {
                self.appendOnlyNewMessages(cached)
            }
        } catch {
            AppLogger.debug("[ChatSync] cache delta query failed: \(error)")
            // Non-critical: next regular sync will reconcile.
        }
    }

    /// Compares incoming messages with displayed messages and only adds truly new ones.
    private func appendOnlyNewMessages(_ incoming: [ConversationMessage]) {
        let existingIds = Set(self.messages.map { $0.id })

        var trulyNew: [ConversationMessage] = []
        for msg in incoming {
            guard !existingIds.contains(msg.id) else { continue }

            // If this server message matches a pending temp message (user sent + left before ack),
            // replace the temp bubble instead of appending a duplicate beside it.
            let clientTempId = msg.metadata?["clientTempId"]?.value as? String ?? ""
            if !clientTempId.isEmpty, tempMessageMapping[clientTempId] != nil {
                AppLogger.debug("[ChatSync] delta matched pending temp \(clientTempId) → replacing with server id \(msg.id)")
                replaceTemporaryMessage(tempId: clientTempId, with: msg)
                continue
            }

            trulyNew.append(msg)
        }

        AppLogger.debug("[ChatSync] appendOnly incoming=\(incoming.count) trulyNew=\(trulyNew.count) existing=\(existingIds.count)")

        guard !trulyNew.isEmpty else { return }

        stateManager.addMessages(trulyNew)
        if let lastId = trulyNew.last?.id, shouldAutoScroll {
            pendingScrollToMessageId = lastId
        }

        for msg in trulyNew {
            MediaStorageManager.shared.autoDownloadIfNeeded(message: msg)
        }
    }

    /// Saves truly new messages to CoreData and appends to state.
    private func saveAndAppendNewMessages(_ newMessages: [ConversationMessage]) {
        let existingIds = Set(self.messages.map { $0.id })
        let trulyNew = newMessages.filter { msg in
            return !existingIds.contains(msg.id)
        }

        guard !trulyNew.isEmpty else { return }

        Task { [weak self] in
            guard let self = self else { return }
            try? await self.messageRepository.saveMessages(trulyNew, conversationId: self.selectedId)

            await MainActor.run {
                self.stateManager.addMessages(trulyNew)
                if let lastId = trulyNew.last?.id, self.shouldAutoScroll {
                    self.pendingScrollToMessageId = lastId
                }
            }

            for msg in trulyNew {
                MediaStorageManager.shared.autoDownloadIfNeeded(message: msg)
            }
        }
    }
}

// MARK: - Background Cache Prefetch

extension ChatDetailViewModel {

    private func preloadOlderPagesInBackground() {
        guard let oldestDate = messages.first.flatMap({ parseDate($0.createdAt) }) else { return }

        let repoId = isChannelMode() ? channelId : selectedId

        Task { [weak self] in
            guard let self = self else { return }

            let cached = try? await self.messageRepository.getMessagesBefore(
                conversationId: repoId,
                beforeDate: oldestDate,
                limit: self.paginationBatchSize
            )
            if let cached, cached.count >= self.paginationBatchSize { return }

            let safeDate = oldestDate.addingTimeInterval(0.001)
            let publisher: AnyPublisher<ConversationMessagesResponse, Error>
            if self.isChannelMode() {
                publisher = self.messageService.loadChannelMessagesBefore(
                    channelId: self.channelId,
                    beforeDate: safeDate,
                    page: 1,
                    limit: self.paginationBatchSize
                )
            } else {
                publisher = self.messageService.loadMessagesBefore(
                    conversationId: self.selectedId,
                    beforeDate: safeDate,
                    page: 1,
                    limit: self.paginationBatchSize
                )
            }
            publisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }
                    if !isChannel, let profileData = response.data.data.userProfileData {
                        applyUserProfileToHeader(profileData)
                        AppLogger.debug("[ChatProfile] API response assigned userProfileData=\(profileData)")
                    }
                    let older = response.data.data.messages.filter { $0.isDeleted != true }
                    guard !older.isEmpty else { return }
                    Task { [weak self] in
                        guard let self = self else { return }
                        try? await self.messageRepository.saveMessages(older, conversationId: self.isChannelMode() ? self.channelId : self.selectedId)
                        AppLogger.debug("[Preload] Saved \(older.count) older messages to cache")
                    }
                }
            )
            .store(in: &self.cancellables)
        }
    }

    private func prefetchNextPageIntoCache() {
        guard !isPrefetchingOlderMessages else { return }
        guard !isLoadingOlderMessages, !isLoadingHistory else { return }
        guard let oldestDisplayedDate = messages.first.flatMap({ parseDate($0.createdAt) }) else { return }

        let repoId = isChannelMode() ? channelId : selectedId

        let prefetchTask = Task { [weak self] in
            guard let self = self else { return }

            // Check if cache already has a full page ahead — skip API if so
            let cached = try? await self.messageRepository.getMessagesBefore(
                conversationId: repoId,
                beforeDate: oldestDisplayedDate,
                limit: self.paginationBatchSize
            )
            if let cached, cached.count >= self.paginationBatchSize {
                AppLogger.debug("[Prefetch] Cache already has \(cached.count) older messages — skipping API")
                return
            }

            // Cache empty or partial — single API call with larger batch
            let safeAnchor = oldestDisplayedDate.addingTimeInterval(0.001)
            let publisher: AnyPublisher<ConversationMessagesResponse, Error>
            if self.isChannelMode() {
                publisher = self.messageService.loadChannelMessagesBefore(
                    channelId: self.channelId,
                    beforeDate: safeAnchor,
                    page: 1,
                    limit: self.paginationBatchSize
                )
            } else {
                publisher = self.messageService.loadMessagesBefore(
                    conversationId: self.selectedId,
                    beforeDate: safeAnchor,
                    page: 1,
                    limit: self.paginationBatchSize
                )
            }
            publisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }
                    if !isChannel, let profileData = response.data.data.userProfileData {
                        applyUserProfileToHeader(profileData)
                        AppLogger.debug("[ChatProfile] API response assigned userProfileData=\(profileData)")
                    }
                    let older = response.data.data.messages.filter { $0.isDeleted != true }
                    guard !older.isEmpty else { return }
                    Task { [weak self] in
                        guard let self = self else { return }
                        try? await self.messageRepository.saveMessages(older, conversationId: self.isChannelMode() ? self.channelId : self.selectedId)
                        AppLogger.debug("[Prefetch] Saved \(older.count) older messages to cache")
                    }
                }
            )
            .store(in: &self.cancellables)
        }
        // Cancel any previous prefetch and replace with the new task using a stable key.
        backgroundTasks["_prefetch"]?.cancel()
        backgroundTasks["_prefetch"] = prefetchTask
    }
}

// MARK: - Silent Media URL Refresh

extension ChatDetailViewModel {

    func refreshMediaURLs() {
        guard !messages.isEmpty else { return }
        let convId = isChannelMode() ? channelId : selectedId
        mediaService.refreshMediaURLs(for: messages, conversationId: convId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        AppLogger.debug("Failed to refresh media URLs: \(error)")
                    }
                },
                receiveValue: { [weak self] freshMessages in
                    self?.updateExistingMessagesWithFreshMedia(freshMessages)
                }
            )
            .store(in: &cancellables)
    }
}

extension ChatDetailViewModel {

    func prefetchOlderMessagesIfNeeded() {
        guard hasMorePages,
              !isLoadingMessages,
              !isLoadingOlderMessages,
              !isLoadingHistory,
              !isPrefetchingOlderMessages,
              !(isChannelMode() ? channelId.isEmpty : selectedId.isEmpty),
              !messages.isEmpty,
              let oldestDisplayedDate = messages.first.flatMap({ parseDate($0.createdAt) }) else {
            return
        }

        if let lastPrefetch = lastOlderPrefetchTime,
           Date().timeIntervalSince(lastPrefetch) < olderPrefetchCooldown {
            return
        }

        isPrefetchingOlderMessages = true
        lastOlderPrefetchTime = Date()

        let repoId = isChannelMode() ? channelId : selectedId

        Task { [weak self] in
            guard let self = self else { return }

            do {
                let cached = try await self.messageRepository.getMessagesBefore(
                    conversationId: repoId,
                    beforeDate: oldestDisplayedDate,
                    limit: self.paginationBatchSize
                )

                // Cache already warm for next prepend.
                if cached.count >= self.paginationBatchSize {
                    await MainActor.run {
                        self.isPrefetchingOlderMessages = false
                    }
                    return
                }

                let safeBeforeDate = oldestDisplayedDate.addingTimeInterval(0.001)
                let response: ConversationMessagesResponse
                if self.isChannelMode() {
                    response = try await self.messageService.loadChannelMessagesBeforeAsync(
                        channelId: self.channelId,
                        beforeDate: safeBeforeDate,
                        page: 1,
                        limit: self.paginationBatchSize
                    )
                } else {
                    response = try await self.messageService.loadMessagesBeforeAsync(
                        conversationId: self.selectedId,
                        beforeDate: safeBeforeDate,
                        page: 1,
                        limit: self.paginationBatchSize
                    )
                }

                let older = response.data.data.messages.filter { $0.isDeleted != true }
                if !older.isEmpty {
                    try? await self.messageRepository.saveMessages(older, conversationId: self.isChannelMode() ? self.channelId : self.selectedId)
                    AppLogger.debug("[Prefetch] Warmed cache with older count=\(older.count)")
                }

                await MainActor.run {
                    self.isPrefetchingOlderMessages = false
                }
            } catch {
                await MainActor.run {
                    self.isPrefetchingOlderMessages = false
                }
                AppLogger.debug("[Prefetch] Failed to warm older cache: \(error)")
            }
        }
    }

    @MainActor
    func applyServerPinnedMessages(_ pinnedMessages: [ConversationMessage]?) {

        guard let pinnedMessages else { return }
        // Product is one-pin-at-a-time — keep only the first server pin
        let canonicalPinned = pinnedMessages.first
        let newPinnedIds: Set<String> = {
            guard let id = canonicalPinned?.id, !id.isEmpty else { return [] }
            return [id]
        }()

        // --- 1. in-memory isPinned flags ---
        var toUpdate: [ConversationMessage] = []

        for msg in messages {
            let shouldBePinned = newPinnedIds.contains(msg.id)
            let currentlyPinned = msg.isPinned == true
            if currentlyPinned != shouldBePinned {
                var updated = msg
                updated.isPinned = shouldBePinned
                toUpdate.append(updated)
            }
        }

        if !toUpdate.isEmpty {
            stateManager.batchUpdateMessages(toUpdate)
            groupedMessages = stateManager.getGroupedMessagesSnapshot()
            AppLogger.debug("[PinnedSync] Reconciled isPinned on \(toUpdate.count) in-memory messages")
        }

        // --- 2. Update banner (always assign so unpin → nil hides the bar)
        let newBanner = canonicalPinned
        currentPinnedMessage = newBanner

        if let newBanner = newBanner {
            prefetchPinnedMessageIntoMemory(newBanner)
        }

        if !toUpdate.isEmpty {
            handleMessageListUpdate(stateManager.getGroupedMessagesSnapshot().flatMap(\.messages))
        }

        // --- 3. Persist to CoreData in background ---
        let convId = selectedId
        guard !convId.isEmpty else { return }

        ChatDataPreloader.shared.storePinState(for: convId, message: newBanner)

        let repo = messageRepository
        let exceptId = canonicalPinned?.id
        Task.detached(priority: .utility) {
            try? await repo.clearOtherPinnedMessages(in: convId, except: exceptId)
            for id in newPinnedIds where !id.isEmpty {
                try? await repo.updateMessagePinStatus(id: id, isPinned: true)
            }
            for msg in toUpdate where !newPinnedIds.contains(msg.id) {
                try? await repo.updateMessagePinStatus(id: msg.id, isPinned: false)
            }
        }
    }

    @MainActor
    func checkAndLoadPinnedMessage() {
        guard !selectedId.isEmpty else { return }

        if let pinned = groupedMessages.flatMap({ $0.messages }).last(where: { $0.isPinned == true }) {
            if currentPinnedMessage?.id != pinned.id {
                currentPinnedMessage = pinned
            }
            return
        }

        // No in-memory pinned messages. If banner still points at a message we already
        // cleared locally, hide it (don't wait for CoreData / API).
        if let current = currentPinnedMessage {
            let livePinned = stateManager.messageById(current.id)?.isPinned == true
            let pendingUnpin = pendingPinUpdates[current.id] == false
            if !livePinned || pendingUnpin {
                currentPinnedMessage = nil
                ChatDataPreloader.shared.storePinState(for: selectedId, message: nil)
            }
        }

        guard !isPinStateRestoredFromCache else { return }

        Task { [weak self] in
            guard let self else { return }
            let pinned = try? await self.messageRepository.getPinnedMessage(for: self.selectedId)
            await MainActor.run {
                // Don't revive a banner we just unpinned
                if let pinned, self.pendingPinUpdates[pinned.id] == false {
                    return
                }
                if self.currentPinnedMessage == nil {
                    self.currentPinnedMessage = pinned
                }
                if let pinned = pinned {
                    self.prefetchPinnedMessageIntoMemory(pinned)
                }
            }
        }
    }

    @MainActor
    func handlePinnedMessageBannerTap(_ message: ConversationMessage) {
        let targetId = message.id
        guard !targetId.isEmpty else { return }

        let isInMemory = stateManager.messageById(targetId) != nil
            || messages.contains(where: { $0.id == targetId })

        if isInMemory {
            // Force scroll — near-bottom gate would block when pinned is the latest message
            setSelectedMessageId(targetId, force: true)
        } else {
            jumpToMessageWindow(message)
        }
    }

    @MainActor
    private func jumpToMessageWindow(_ message: ConversationMessage) {
        guard !isJumpingToPinnedMessage else { return } // debounce double-taps
        guard !selectedId.isEmpty else { return }
        guard let anchor = parseDate(message.createdAt) else {
            AppLogger.debug("[PinnedJump] Cannot parse createdAt for message=\(message.id)")
            return
        }

        isJumpingToPinnedMessage = true
        AppLogger.debug("[PinnedJump] Loading window around pinnedMessage=\(message.id) anchor=\(debugTimestamp(anchor))")

        let convId = selectedId
        let targetId = message.id

        Task { [weak self] in
            guard let self else { return }

            let fullSnapshot: [ConversationMessage]
            do {
                fullSnapshot = try await self.messageRepository.getMessagesSnapshot(
                    for: convId,
                    limit: self.initialDisplayCount + self.silentPreloadCount,
                    offset: 0
                ).filter { $0.isDeleted != true }
            } catch {
                fullSnapshot = []
            }

            if fullSnapshot.contains(where: { $0.id == targetId }), !fullSnapshot.isEmpty {
                AppLogger.debug("[PinnedJump] Full snapshot hit count=\(fullSnapshot.count) — replacing window")
                await MainActor.run {
                    self.replaceMessageWindow(with: fullSnapshot, scrollTo: targetId)
                    self.isJumpingToPinnedMessage = false
                }
                return
            }

            let cachedWindow: [ConversationMessage]
            do {
                cachedWindow = try await self.messageRepository.getMessagesBefore(
                    conversationId: convId,
                    beforeDate: anchor.addingTimeInterval(1),
                    limit: self.paginationBatchSize
                ).filter { $0.isDeleted != true }
            } catch {
                cachedWindow = []
            }

            let hasPinnedInCache = cachedWindow.contains(where: { $0.id == targetId })

            if hasPinnedInCache, !cachedWindow.isEmpty {
                // Also pull cached messages AFTER the anchor so the user has downward
                // context and doesn't hit the live-tail trigger immediately.
                let afterCtx = (try? await self.messageRepository.getMessagesAfter(
                    conversationId: convId,
                    afterDate: anchor,
                    limit: self.paginationBatchSize / 2
                ))?.filter { $0.isDeleted != true } ?? []
                var bidirectional = cachedWindow + afterCtx
                var seenBi = Set<String>()
                bidirectional = bidirectional.filter { seenBi.insert($0.id).inserted }
                bidirectional.sort { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
                AppLogger.debug("[PinnedJump] Before-window cache hit count=\(cachedWindow.count) afterCtx=\(afterCtx.count) — replacing window")
                await MainActor.run {
                    self.replaceMessageWindow(with: bidirectional, scrollTo: targetId)
                    self.isJumpingToPinnedMessage = false
                }
                return
            }

            AppLogger.debug("[PinnedJump] Cache miss — fetching from API anchor=\(self.debugTimestamp(anchor))")
            do {
                let response = try await self.messageService.loadMessagesBeforeAsync(
                    conversationId: convId,
                    beforeDate: anchor.addingTimeInterval(1),
                    page: 1,
                    limit: self.paginationBatchSize
                )
                let fetched = response.data.data.messages.filter { $0.isDeleted != true }
                AppLogger.debug("[PinnedJump] API returned count=\(fetched.count)")

                if !fetched.isEmpty {
                    Task.detached(priority: .utility) {
                        try? await MessageRepository().saveMessages(fetched, conversationId: convId)
                    }
                }

                let apiAfterCtx = (try? await self.messageRepository.getMessagesAfter(
                    conversationId: convId,
                    afterDate: anchor,
                    limit: self.paginationBatchSize / 2
                ))?.filter { $0.isDeleted != true } ?? []
                var apiWindow = (fetched.isEmpty ? cachedWindow : fetched) + apiAfterCtx
                var seenApi = Set<String>()
                apiWindow = apiWindow.filter { seenApi.insert($0.id).inserted }
                apiWindow.sort { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
                await MainActor.run {
                    self.replaceMessageWindow(with: apiWindow, scrollTo: targetId)
                    self.isJumpingToPinnedMessage = false
                }
            } catch {
                AppLogger.debug("[PinnedJump] API failed: \(error) — falling back to cache")
                await MainActor.run {
                    if !cachedWindow.isEmpty {
                        self.replaceMessageWindow(with: cachedWindow, scrollTo: targetId)
                    }
                    self.isJumpingToPinnedMessage = false
                }
            }
        }
    }

    @MainActor
    func prefetchPinnedMessageIntoMemory(_ pinned: ConversationMessage) {
        let targetId = pinned.id
        guard !targetId.isEmpty, !selectedId.isEmpty else { return }

        guard stateManager.messageById(targetId) == nil else { return }

        guard !isJumpingToPinnedMessage else { return }

        guard let anchor = parseDate(pinned.createdAt) else { return }

        let convId = selectedId
        AppLogger.debug("[PinnedPrefetch] Pinned not in memory — silently fetching id=\(targetId) anchor=\(debugTimestamp(anchor))")

        Task { [weak self] in
            guard let self else { return }

            let cachedBatch: [ConversationMessage]
            do {
                cachedBatch = try await self.messageRepository.getMessagesBefore(
                    conversationId: convId,
                    beforeDate: anchor.addingTimeInterval(1),
                    limit: self.paginationBatchSize
                ).filter { $0.isDeleted != true }
            } catch {
                cachedBatch = []
            }

            if cachedBatch.contains(where: { $0.id == targetId }), !cachedBatch.isEmpty {
                AppLogger.debug("[PinnedPrefetch] CoreData hit count=\(cachedBatch.count) — merging into window")

                self.stateManager.addMessages(cachedBatch)
                return
            }

            AppLogger.debug("[PinnedPrefetch] CoreData miss — fetching from API anchor=\(self.debugTimestamp(anchor))")
            guard !self.isJumpingToPinnedMessage else { return }

            do {
                let response = try await self.messageService.loadMessagesBeforeAsync(
                    conversationId: convId,
                    beforeDate: anchor.addingTimeInterval(1),
                    page: 1,
                    limit: self.paginationBatchSize
                )
                let fetched = response.data.data.messages.filter { $0.isDeleted != true }
                AppLogger.debug("[PinnedPrefetch] API returned count=\(fetched.count)")

                guard !fetched.isEmpty else { return }

                Task.detached(priority: .utility) {
                    try? await MessageRepository().saveMessages(fetched, conversationId: convId)
                }

                self.stateManager.addMessages(fetched)
            } catch {
                AppLogger.debug("[PinnedPrefetch] API failed: \(error)")
            }
        }
    }

    @MainActor
    private func replaceMessageWindow(with window: [ConversationMessage], scrollTo targetId: String) {
        guard !window.isEmpty else { return }

        displayInitialMessages(window, scrollToLatest: false)
        // displayInitialMessages resets isInHistoricalWindow to false; override that here
        // so that the scroll-down button and bottom-reach both trigger returnToLatestMessages().
        isInHistoricalWindow = true
        prefetchLiveWindowIfNeeded()
        setSelectedMessageId(targetId, force: true)
        AppLogger.debug("[PinnedJump] Window replaced count=\(window.count) scrollingTo=\(targetId) — historical window active")
    }

    func loadMoreMessages() {
        guard hasMorePages,
              !isLoadingMessages,
              !isLoadingOlderMessages,
              !isLoadingHistory,
              !messages.isEmpty else { return }

        if let lastTime = lastLoadMoreTime,
           Date().timeIntervalSince(lastTime) < loadMoreCooldown {
            return
        }

        isLoadingOlderMessages = true
        lastLoadMoreTime = Date()
        AppLogger.debug("[Pagination] loadMore triggered currentPage=\(currentPage) hasMorePages=\(hasMorePages) displayedCount=\(messages.count)")
        loadOlderMessagesFromCacheOrAPI()
    }

    private func loadOlderMessagesFromCacheOrAPI() {
        guard let oldestDisplayedDate = messages.first.flatMap({ parseDate($0.createdAt) }) else {
            AppLogger.debug("[Pagination] no oldest displayed date, loading page 1 from API")
            isLoadingHistory = true
            isLoadingOlderMessages = true
            loadMessagesFromAPI(page: 1)
            return
        }

        let repoId = isChannelMode() ? channelId : selectedId
        AppLogger.debug("[Pagination] cache-first lookup before=\(debugTimestamp(oldestDisplayedDate)) limit=\(paginationBatchSize)")

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let olderCachedMessages = try await self.messageRepository.getMessagesBefore(
                    conversationId: repoId,
                    beforeDate: oldestDisplayedDate,
                    limit: self.paginationBatchSize
                )
                await MainActor.run {
                    let existingIds = Set(self.messages.map { $0.id })
                    let uniqueOlderMessages = olderCachedMessages.filter { msg in
                        return !existingIds.contains(msg.id)
                    }

                    if !uniqueOlderMessages.isEmpty {
                        AppLogger.debug("[Pagination] cache hit older count=\(olderCachedMessages.count) unique=\(uniqueOlderMessages.count)")
                        self.stateManager.prependMessages(uniqueOlderMessages)
                        self.invalidateSenderCache()
                        self.currentPage += 1

                        self.isLoadingOlderMessages = false
                        self.prefetchNextPageIntoCache()
                    } else {
                        AppLogger.debug("[Pagination] cache miss, falling back to API before=\(oldestDisplayedDate)")
                        self.isLoadingHistory = true
                        self.loadOlderMessagesFromAPI(beforeDate: oldestDisplayedDate)
                    }
                }
            } catch {
                AppLogger.debug("[Pagination] cache lookup failed, falling back to API: \(error)")
                await MainActor.run {
                    self.isLoadingHistory = true
                    self.isLoadingOlderMessages = true
                    self.loadOlderMessagesFromAPI(beforeDate: oldestDisplayedDate)
                }
            }
        }
    }
}

// MARK: - API Loading (Fallback for No-Cache)

extension ChatDetailViewModel {

    private func loadMessagesFromAPI(page: Int, showLoadingState: Bool = true) {
        guard !isLoadingMessages, !ChatMockSeeder.isMockMode else { return }

        isLoadingMessages = true
        if showLoadingState {
            stateManager.setLoadingState(true)
        }
        isLoadingOlderMessages = page > 1

        if selectedId.isEmpty && !isChannel {
            ensureConversationReady { [weak self] success in
                guard let self = self else { return }
                self.isLoadingMessages = false
                if showLoadingState {
                    self.stateManager.setLoadingState(false)
                }
                self.isLoadingOlderMessages = false
                if success {
                    self.loadMessagesFromAPI(page: 1, showLoadingState: showLoadingState)
                } else {
                    self.handleError(.messageLoadFailed, context: "loadMessages.ensureConversationReady")
                }
            }
            return
        }

        let publisher: AnyPublisher<ConversationMessagesResponse, Error>
        if isChannelMode() {
            AppLogger.debug("[ChatFlow] API load channel channelId=\(channelId) page=\(page) limit=\(pageSize)")
            publisher = messageService.loadChannelMessages(channelId: channelId, page: page, limit: pageSize)
        } else {
            AppLogger.debug("[ChatFlow] API load conversation conversation=\(selectedId) page=\(page) limit=\(pageSize)")
            publisher = messageService.loadMessages(conversationId: selectedId, page: page, limit: pageSize)
        }

        publisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] _ in
                    guard let self = self else { return }
                    self.isLoadingMessages = false
                    if showLoadingState {
                        self.stateManager.setLoadingState(false)
                    }
                    self.isLoadingOlderMessages = false
                },
                receiveValue: { [weak self] response in
                    self?.handleMessagesResponse(response, page: page)
                }
            )
            .store(in: &cancellables)
    }

    private func loadOlderMessagesFromAPI(beforeDate: Date? = nil) {
        if ChatMockSeeder.isMockMode {
            isLoadingOlderMessages = false
            isLoadingHistory = false
            return
        }
        let anchorKey = beforeDate ?? Date.distantPast
        if let inFlight = inFlightOlderBeforeDate, abs(inFlight.timeIntervalSince(anchorKey)) < 1.0 {
            AppLogger.debug("[Pagination] deduplicated in-flight request anchor=\(debugTimestamp(beforeDate))")
            isLoadingOlderMessages = false
            isLoadingHistory = false
            return
        }
        inFlightOlderBeforeDate = anchorKey

        let publisher: AnyPublisher<ConversationMessagesResponse, Error>

        if isChannelMode() {
            if let beforeDate = beforeDate {
                let safeBeforeDate = beforeDate.addingTimeInterval(0.001)
                AppLogger.debug("[Pagination] loading older channel messages with before=\(debugTimestamp(safeBeforeDate)) limit=\(paginationBatchSize)")
                publisher = messageService.loadChannelMessagesBefore(
                    channelId: channelId,
                    beforeDate: safeBeforeDate,
                    page: 1,
                    limit: paginationBatchSize
                )
            } else {
                let nextPage = currentPage + 1
                AppLogger.debug("[Pagination] loading older channel messages page=\(nextPage) limit=\(paginationBatchSize)")
                publisher = messageService.loadChannelMessages(
                    channelId: channelId,
                    page: nextPage,
                    limit: paginationBatchSize
                )
            }
        } else if let beforeDate = beforeDate {
            let safeBeforeDate = beforeDate.addingTimeInterval(0.001)
            AppLogger.debug("[Pagination] loading older from API with before=\(debugTimestamp(safeBeforeDate)) limit=\(paginationBatchSize)")
            publisher = messageService.loadMessagesBefore(
                conversationId: selectedId,
                beforeDate: safeBeforeDate,
                page: 1,
                limit: paginationBatchSize
            )
        } else {
            let nextPage = currentPage + 1
            AppLogger.debug("[Pagination] loading older from API page=\(nextPage) limit=\(paginationBatchSize)")
            publisher = messageService.loadMessages(
                conversationId: selectedId,
                page: nextPage,
                limit: paginationBatchSize
            )
        }

        publisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    self.isLoadingMessages = false
                    self.isLoadingOlderMessages = false
                    self.isLoadingHistory = false
                    self.inFlightOlderBeforeDate = nil
                    if case .failure(let error) = completion {
                        AppLogger.debug("[Pagination] API error: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.handleOlderMessagesResponse(response, beforeDate: beforeDate)
                }
            )
            .store(in: &cancellables)
    }
}

// MARK: - API Response Handlers

extension ChatDetailViewModel {

    private func handleMessagesResponse(_ response: ConversationMessagesResponse, page: Int) {
        let responseData = response.data.data
        let allMessages = responseData.messages
        let newMessages = allMessages.filter { $0.isDeleted != true }
        AppLogger.debug("[ChatFlow] API response page=\(page) total=\(allMessages.count) nonDeleted=\(newMessages.count)")

        if let blocked = responseData.conversation?.settings?.isBlocked {
            applyBlockUIState(isBlocked: blocked)
        } else if isDirectChat {
            // Profile/list block may have landed before messages API reflects settings.isBlocked.
            let peerId = selectedUserChatID.isEmpty
                ? (user?.userId ?? user?.id ?? "")
                : selectedUserChatID
            if !peerId.isEmpty, BlockedUsersManager.shared.isBlocked(id: peerId) {
                applyBlockUIState(isBlocked: true)
            }
        }

        // NEW detail: `myRole` present ⇒ member; keep inbox-open true otherwise
        if isGroupChat,
           let role = responseData.conversation?.myRole?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !role.isEmpty {
            isGroupParticipant = true
        }

        // Seed group sender name/avatar map from conversation.members (decoded as participants)
        if isGroupChat, let participants = responseData.conversation?.participants, !participants.isEmpty {
            let mapped = participants.compactMap { p -> GroupParticipant? in
                guard let userId = p.userId ?? p.user?.userId ?? p.user?.id, p.isActive != false else { return nil }
                let details = p.user?.userDetails?.first
                let userName = GroupParticipantDisplay.cleanName(
                    details?.userName ?? p.user?.username
                ) ?? ""
                let fullName = GroupParticipantDisplay.cleanName(
                    details?.fullName ?? p.user?.fullName
                ) ?? userName
                let pic = details?.profilePictureDetails?.filePath
                    ?? details?.profilePicture
                    ?? p.user?.profilePicture
                    ?? p.user?.profileImage
                return GroupParticipant(
                    id: p.id ?? userId,
                    userId: userId,
                    role: p.role ?? "member",
                    userName: userName,
                    fullName: fullName,
                    profilePicture: pic,
                    isVerified: p.resolvedIsVerified
                )
            }
            if !mapped.isEmpty {
                groupParticipants = mapped
                if participantsCount == nil || (participantsCount ?? 0) < mapped.count {
                    participantsCount = mapped.count
                }
            }
        }

        // Seed direct-chat presence from messages payload when available
        if isDirectChat, let online = responseData.conversation?.onlineStatus {
            let profile = responseData.userProfileData
                ?? responseData.conversation?.userProfileData
            let viewerIsContact = (profile?.isFollowing == true)
                || (profile?.isOwnerFollowingVisitor == true)
                || otherUserProfileData?.isFollowing == true
                || otherUserProfileData?.isOwnerFollowingVisitor == true
            applyOnlineStatusFromAPI(online, viewerIsContact: viewerIsContact)
        }

        // Ensure peer id for presence:get when navigation omitted userChatId
        if isDirectChat,
           selectedUserChatID.isEmpty,
           let participants = responseData.conversation?.participants {
            let me = getCurrentUserId()
            if let peerId = participants
                .compactMap({ $0.userId ?? $0.user?.userId ?? $0.user?.id })
                .first(where: { !$0.isEmpty && $0 != me }) {
                selectedUserChatID = peerId
                socketService.setOtherUserId(peerId)
                socketService.emitSubscribePresence(userIds: [peerId])
            }
        }

        // Apply group/channel avatar from API response conversation data
        if let avatar = responseData.conversation?.avatar, !avatar.isEmpty {
            conversationAvatarURL = avatar
        }

        AppLogger.debug("[ChatProfile] API response userProfileData=\(responseData.userProfileData)")
        if !isChannel {
            let profileData = responseData.userProfileData
                ?? responseData.conversation?.userProfileData
            if let profileData {
                applyUserProfileToHeader(profileData)
                AppLogger.debug("[ChatProfile] API response assigned userProfileData=\(profileData)")
            }
        }

        if let shareLink = responseData.shareLink {
            channelShareLink = ChannelShareLinkBuilder.resolve(shareLink: shareLink, inviteSlug: nil) ?? shareLink
        }
        hydrateChannelShareLinkFromCacheIfNeeded()
        if let details = responseData.channelDetails {
            if let name = details.channelName, !name.isEmpty {
                channelName = name
                groupTitle = name
            }
            channelDescription = details.description
            let me = getCurrentUserId()
            let role = responseData.conversation?.myRole?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let isAdminFromRole = role == "admin" || role == "owner"
            let isAdminFromOwner = !(details.ownerId ?? "").isEmpty
                && details.ownerId?.caseInsensitiveCompare(me) == .orderedSame
            let resolvedAdmin = details.isAdmin == true || isAdminFromRole || isAdminFromOwner
            if resolvedAdmin {
                isChannelAdmin = true
            } else if details.isAdmin == false {
                // Explicit follower — only demote when API clearly says non-admin
                // and no owner/admin role signals are present.
                isChannelAdmin = false
            }
            // If isAdmin is nil and role/owner unknown, keep seeded navigation value (e.g. just created).
            // hasFollowed inside channelDetails OR isFollowing at the top level
            if let followed = details.hasFollowed ?? responseData.isFollowing {
                isChannelFollowed = followed
            }
            if let count = details.resolvedFollowersCount {
                channelFollowersCount = count
            }
            // Resolve channel icon: channelDetails.icon > participants[0].channel.icon
            if let icon = details.icon ?? responseData.resolvedChannelIcon, !icon.isEmpty {
                conversationAvatarURL = icon
            }
            hasResolvedChannelRole = true
            persistChannelDetails()
        } else if isChannel {
            // Even without channelDetails, extract icon from participants if available
            if let icon = responseData.resolvedChannelIcon, !icon.isEmpty {
                conversationAvatarURL = icon
            }
            let role = responseData.conversation?.myRole?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if role == "admin" || role == "owner" {
                isChannelAdmin = true
            }
            hasResolvedChannelRole = true
        }

        if let pagination = responseData.pagination, let serverPage = pagination.page, let serverTotal = pagination.totalPages {
            hasMorePages = serverPage < serverTotal
            AppLogger.debug("[ChatFlow] pagination serverPage=\(serverPage) totalPages=\(serverTotal) hasMorePages=\(hasMorePages)")
        } else if let cursor = responseData.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines), !cursor.isEmpty {
            // NEW FE MessagesPage: `{ rows, nextCursor, limit }`
            hasMorePages = true
            AppLogger.debug("[ChatFlow] pagination nextCursor present hasMorePages=true")
        } else if responseData.limit != nil {
            // FE page with null/empty nextCursor → no older pages
            hasMorePages = false
            AppLogger.debug("[ChatFlow] pagination nextCursor empty hasMorePages=false")
        } else {
            hasMorePages = allMessages.count >= pageSize
        }
        currentPage = page

        let mergedSourceMessages = normalizeMessagesForDisplay(
            newMessages,
            allowSystemPinInference: page == 1
        )

        if page == 1 && isInHistoricalWindow {
            AppLogger.debug("[HistoricalWindow] skipped page=1 UI replace while historical; caching-only count=\(mergedSourceMessages.count)")
        } else {
            messageSyncCoordinator.refreshWithNetworkPage(
                mergedSourceMessages,
                page: page,
                temporaryMessages: Array(tempMessageMapping.values)
            )

            if page == 1 && !isInHistoricalWindow {
                let groups = stateManager.getGroupedMessagesSnapshot()
                if groupedMessages != groups {
                    groupedMessages = groups
                    let flatMessages = groups.flatMap { $0.messages }
                    handleMessageListUpdate(flatMessages)
                }
            }
        }

        if page == 1 {
            if let pinned = responseData.pinnedMessages, !pinned.isEmpty {
                applyServerPinnedMessages(pinned)
            } else {
                // NEW FE: pin flag is on message rows; also refresh dedicated pinned-message endpoint
                let fromRows = responseData.messages.filter { $0.isPinned == true }
                if !fromRows.isEmpty {
                    applyServerPinnedMessages(fromRows)
                } else {
                    refreshPinnedMessageFromAPI()
                }
            }
            backgroundTasks["_initialPrefetch"]?.cancel()
            let prefetchTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.prefetchNextPageIntoCache() }
            }
            backgroundTasks["_initialPrefetch"] = prefetchTask
        }

        // Save to CoreData in background — does not block display.
        let convId = selectedId
        let msgsToSave = newMessages
        Task.detached(priority: .utility) {
            try? await MessageRepository().saveMessages(msgsToSave, conversationId: convId)
            AppLogger.debug("[ChatFlow] background CoreData save complete count=\(msgsToSave.count)")
        }

        // Defer media downloads to background so they don't stall the main render Task.
        let mediaMessages = newMessages
        Task.detached(priority: .background) {
            for msg in mediaMessages {
                MediaStorageManager.shared.autoDownloadIfNeeded(message: msg)
            }
        }

        stateManager.setLoadingState(false)
        hasPreloadedCachedMessages = true

        let wasLoadingOlder = isLoadingOlderMessages
        isLoadingMessages = false
        isLoadingHistory = false

        if wasLoadingOlder || page > 1 {
            DispatchQueue.main.async { self.isLoadingOlderMessages = false }
        } else {
            isLoadingOlderMessages = false
        }
    }

    private func handleOlderMessagesResponse(_ response: ConversationMessagesResponse, beforeDate: Date?) {
        let rawOlderMessages = response.data.data.messages
        let olderMessages = rawOlderMessages.filter { $0.isDeleted != true }
        AppLogger.debug("[Pagination] API older response raw=\(rawOlderMessages.count) nonDeleted=\(olderMessages.count) beforeAnchor=\(debugTimestamp(beforeDate))")

        if rawOlderMessages.isEmpty {
            hasMorePages = false
        } else {
            let pagination = response.data.data.pagination
            if let serverPage = pagination?.page, let serverTotal = pagination?.totalPages {
                hasMorePages = serverPage < serverTotal
                AppLogger.debug("[Pagination] older pagination serverPage=\(serverPage) totalPages=\(serverTotal) hasMorePages=\(hasMorePages)")
            } else {
                hasMorePages = !rawOlderMessages.isEmpty
            }

            stateManager.prependMessages(olderMessages)
            invalidateSenderCache()
            currentPage += 1
            if hasMorePages {
                prefetchNextPageIntoCache()
            }

            let convId = selectedId
            let msgsToSave = olderMessages
            Task.detached(priority: .utility) {
                try? await MessageRepository().saveMessages(msgsToSave, conversationId: convId)
                AppLogger.debug("[Pagination] background CoreData save older count=\(msgsToSave.count)")
            }
        }

        isLoadingMessages = false
        isLoadingOlderMessages = false
        isLoadingHistory = false
        inFlightOlderBeforeDate = nil
        stateManager.setLoadingState(false)
    }
}

// MARK: - Conversation Read State

extension ChatDetailViewModel {

    func markConversationAsRead() {
        guard !ChatMockSeeder.isMockMode else { return }
        if isChannel {
            markChannelAsRead()
            return
        }
        guard !selectedId.isEmpty else { return }

        hasEmittedMarkSeen = true
        socketService.emitJoinConversation(selectedId)

        // Console requires messageId on chat:message:seen for sender chat:message:status fanout
        let latestPeerMessageId = latestIncomingPeerMessageId()
        if let latestPeerMessageId {
            socketService.emitMarkMessagesSeen(
                conversationId: selectedId,
                messageId: latestPeerMessageId
            )
        } else {
            AppLogger.debug("[MarkRead] No peer messageId yet — REST read only for \(selectedId)")
        }

        // FE also POSTs chat/conversations/{id}/read
        if let sessionManager = Container.sharedContainer.resolve(SessionManager.self) {
            _ = sessionManager.markConversationReadREST(
                conversationId: selectedId,
                messageId: latestPeerMessageId
            )
                .subscribe(onSuccess: { _ in
                    AppLogger.debug("[MarkRead] REST read OK for \(self.selectedId)")
                }, onFailure: { error in
                    AppLogger.debug("[MarkRead] REST read failed: \(error.localizedDescription)")
                })
        }

        clearLocalUnreadAfterRead()
    }

    /// FE ConversationThreadPage.onNew: when already in the thread and a peer message
    /// arrives, emit console `chat:message:seen` + REST `/read` with that `messageId`
    /// so the sender receives `chat:message:status { status: "seen" }`.
    func markReceivedMessageAsSeen(messageId: String?) {
        if isChannel {
            markChannelAsRead(messageId: messageId)
            return
        }
        guard !selectedId.isEmpty else { return }

        hasEmittedMarkSeen = true
        let mid = (messageId?.isEmpty == false) ? messageId : latestIncomingPeerMessageId()
        guard let mid, !mid.isEmpty else {
            AppLogger.debug("[MarkRead] Skipped in-thread seen — missing messageId for \(selectedId)")
            return
        }

        // Delivered (both) + seen (c2s) — sender ticks via chat:message:status / delivered push
        socketService.emitMessageDelivered(conversationId: selectedId, messageId: mid)
        socketService.emitMarkMessagesSeen(conversationId: selectedId, messageId: mid)

        if let sessionManager = Container.sharedContainer.resolve(SessionManager.self) {
            _ = sessionManager.markConversationDelivered(conversationId: selectedId, messageId: mid)
                .subscribe(onSuccess: { _ in
                    AppLogger.debug("[Delivered] in-thread REST OK for \(self.selectedId) msg=\(mid)")
                }, onFailure: { error in
                    AppLogger.debug("[Delivered] in-thread REST failed: \(error.localizedDescription)")
                })
            _ = sessionManager.markConversationReadREST(conversationId: selectedId, messageId: mid)
                .subscribe(onSuccess: { _ in
                    AppLogger.debug("[MarkRead] in-thread REST read OK for \(self.selectedId) msg=\(mid)")
                }, onFailure: { error in
                    AppLogger.debug("[MarkRead] in-thread REST read failed: \(error.localizedDescription)")
                })
        }

        clearLocalUnreadAfterRead()
    }

    /// Newest inbound peer message id (for mark-seen / mark-delivered payloads).
    private func latestIncomingPeerMessageId() -> String? {
        let myId = getCurrentUserId()
        return stateManager.getGroupedMessagesSnapshot()
            .flatMap(\.messages)
            .reversed()
            .first(where: { msg in
                if msg.isSystemMessage { return false }
                let sender = msg.senderId ?? msg.sender?.id ?? ""
                guard !sender.isEmpty, sender != myId else { return false }
                return !msg.id.isEmpty
            })?.id
    }

    func markChannelAsRead(messageId: String? = nil) {
        guard isChannel, !channelId.isEmpty else { return }

        hasEmittedMarkSeen = true
        socketService.emitMarkChannelMessagesSeen(channelId: channelId, messageId: messageId)
        NotificationCenter.default.post(
            name: .channelUnreadCountUpdated,
            object: nil,
            userInfo: ["channelId": channelId, "unreadCount": 0]
        )
    }

    private func clearLocalUnreadAfterRead() {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.conversationRepository?.updateUnreadCount(conversationId: self.selectedId, unreadCount: 0)
                try await self.conversationRepository?.markAsRead(conversationId: self.selectedId)
                NotificationCenter.default.post(
                    name: NSNotification.Name("ChatUnreadCountUpdated"),
                    object: nil,
                    userInfo: ["conversationId": self.selectedId]
                )
                await Self.recalculateBadgeFromUnreadCounts()
            } catch {
                // Non-critical
            }
        }
    }

    /// Calculates the app badge from the sum of all conversation unread counts.
    private static func recalculateBadgeFromUnreadCounts() async {
        guard let repo = Container.sharedContainer.resolve(ConversationRepositoryProtocol.self) else { return }
        do {
            let conversations = try await repo.getAllConversations()
            let totalUnread = conversations.reduce(0) { $0 + ($1.unreadCount ?? 0) }
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = totalUnread
            }
        } catch {
            // Non-critical — the next notification will correct the badge.
        }
    }

    private func applyOnlineStatusFromAPI(_ online: OnlineStatus, viewerIsContact: Bool = true) {
        // Prefer open-chat null rules: online / last seen, or blank when privacy is nobody.
        userStatus = online.openChatSubtitle(username: peerUsernameForPresenceFallback())

        // Keep socket presence updates aligned with the same privacy rules.
        socketService.setPresencePrivacy(
            lastSeenVisibility: online.lastSeenVisibility ?? "everyone",
            onlineVisibility: online.onlineVisibility ?? "everyone",
            viewerIsContact: viewerIsContact
        )
    }

    /// Apply last-seen / online privacy from GET users/{id} (chat profile prefetch).
    func applyPresenceFromUserDetails(_ user: OtherUserResponse) {
        guard isDirectChat else { return }
        let viewerIsContact = (user.isFollowing == true) || (user.isOwnerFollowingVisitor == true)
        let hasVisibility = user.lastSeenVisibility != nil || user.onlineVisibility != nil
        let hasPresence = user.isOnline != nil || !(user.lastSeenAt ?? "").isEmpty
        guard hasVisibility || hasPresence else {
            socketService.updateViewerIsContact(viewerIsContact)
            return
        }

        let subtitle = PresencePrivacy.openChatSubtitle(
            isOnline: user.isOnline,
            lastSeenAt: user.lastSeenAt,
            status: nil,
            username: peerUsernameForPresenceFallback()
        )
        userStatus = subtitle
        socketService.setPresencePrivacy(
            lastSeenVisibility: user.lastSeenVisibility ?? "everyone",
            onlineVisibility: user.onlineVisibility ?? "everyone",
            viewerIsContact: viewerIsContact
        )
    }
}

// MARK: - Helpers

extension ChatDetailViewModel {

    private func emitMarkConversationMessagesSeen() {
        if isChannel, !channelId.isEmpty {
            guard !hasEmittedMarkSeen else { return }
            markChannelAsRead(messageId: messages.last?.id)
            return
        }
        guard !selectedId.isEmpty else { return }
        guard !hasEmittedMarkSeen else { return }
        hasEmittedMarkSeen = true
        socketService.emitMarkMessagesSeen(
            conversationId: selectedId,
            messageId: latestIncomingPeerMessageId()
        )
    }

    func restorePendingMessages() {
        let collected = collectPendingMessages()
        guard !collected.isEmpty else { return }

        let existingIds = Set(messages.map { $0.id })
        let missing = collected.filter { msg in
            return !existingIds.contains(msg.id)
        }
        guard !missing.isEmpty else { return }
        stateManager.addMessages(missing)

        for msg in missing {
            if msg.status != "failed" {
                let type = (msg.messageType ?? msg.type ?? "text").lowercased()
                if !["image", "video"].contains(type) {
                    scheduleFailureTimeout(for: msg.id)
                }
            }
        }
    }

    private func isChannelMode() -> Bool {
        return isChannel && !channelId.isEmpty
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    private func debugTimestamp(_ date: Date?) -> String {
        guard let date else { return "nil" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
