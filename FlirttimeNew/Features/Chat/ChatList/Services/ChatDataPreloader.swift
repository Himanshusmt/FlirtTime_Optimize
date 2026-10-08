//
//  ChatDataPreloader.swift
//  FlirttimeNew
//

import Foundation
import Combine
import CoreData
import UIKit

@MainActor
final class ChatDataPreloader: ObservableObject {

    static let shared = ChatDataPreloader()

    @Published private(set) var isPreloaded = false

    private var hasPreloaded = false
    private var hasPreloadedMessages = false

    private let preloadConversationCount = 15
    private let preloadMessageCount = ChatConstants.Pagination.initialDisplayCount + ChatConstants.Pagination.silentPreloadCount

    /// First batch of chats for instant display (only 20 items)
    private(set) var firstBatch: [ChatMessageRow] = []

    private(set) var preloadedMessages: [String: [ConversationMessage]] = [:]

    private(set) var preloadedConversationIds: Set<String> = []
    
    private var inFlightPreloads: Set<String> = []

    private var pinnedMessageCache: [String: ConversationMessage?] = [:]

    private init() {}

    // MARK: - Pin state cache

    func storePinState(for conversationId: String, message: ConversationMessage?) {
        guard !conversationId.isEmpty else { return }
        pinnedMessageCache[conversationId] = message
    }

    func cachedPinState(for conversationId: String) -> ConversationMessage?? {
        guard !conversationId.isEmpty else { return nil }
        return pinnedMessageCache[conversationId]
    }

    func warmUpCoreDataCache() {
        guard !hasPreloaded else {
            return
        }

        let startTime = Date()

        // Use background context to avoid blocking main thread
        let context = CoreDataManager.shared.backgroundContext

        context.performAndWait {
            let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: "settings.settingsIsPinned", ascending: false),
                NSSortDescriptor(key: "lastMessageTimestamp", ascending: false),
                NSSortDescriptor(key: "updatedAt", ascending: false)
            ]
            request.fetchLimit = 20
            request.fetchBatchSize = 20
            request.relationshipKeyPathsForPrefetching = ["settings"]
            request.returnsObjectsAsFaults = true

            do {
                let results = try request.execute()
                AppLogger.debug("ChatDataPreloader: Warmed up cache with \(results.count) conversations")
            } catch {
                AppLogger.debug("ChatDataPreloader: Warm-up error: \(error)")
            }
        }

        let loadTime = Date().timeIntervalSince(startTime)
        AppLogger.debug("ChatDataPreloader: Cache warm-up in \(String(format: "%.3f", loadTime))s")

        hasPreloaded = true
        isPreloaded = true
    }

    func preloadRecentConversationMessages() {
        guard !hasPreloadedMessages else { return }
        hasPreloadedMessages = true

        let startTime = Date()
        let messageRepo = MessageRepository()

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            let conversationCount = await self.preloadConversationCount
            let context = CoreDataManager.shared.backgroundContext
            var conversationIds: [String] = []

            context.performAndWait {
                let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                request.sortDescriptors = [
                    NSSortDescriptor(key: "settings.settingsIsPinned", ascending: false),
                    NSSortDescriptor(key: "lastMessageTimestamp", ascending: false)
                ]
                request.fetchLimit = conversationCount
                request.propertiesToFetch = ["id"]
                request.returnsObjectsAsFaults = true

                do {
                    let results = try context.fetch(request)
                    conversationIds = results.compactMap { $0.id }
                } catch {
                    AppLogger.debug("ChatDataPreloader: Failed to fetch conversation IDs: \(error)")
                }
            }

            guard !conversationIds.isEmpty else { return }

            var preloaded: [String: [ConversationMessage]] = [:]
            var preloadedIds: Set<String> = []
            let limit = await self.preloadMessageCount

            await withTaskGroup(of: (String, [ConversationMessage]).self) { group in
                for conversationId in conversationIds {
                    group.addTask {
                        guard let messages = try? await messageRepo.getMessagesSnapshot(
                            for: conversationId,
                            limit: limit,
                            offset: 0
                        ), !messages.isEmpty else {
                            return (conversationId, [])
                        }

                        // Media warm-up: runs concurrently across conversations
                        for msg in messages {
                            let messageId = msg.id
                            guard !messageId.isEmpty else { continue }
                            let type = msg.messageType ?? ""
                            if type == "image" || type == "photo" {
                                if InMemoryMediaCache.shared.getCachedImage(for: messageId) == nil {
                                    if let url = MediaStorageManager.shared.getMediaURL(messageId: messageId, type: .image),
                                       let image = UIImage(contentsOfFile: url.path) {
                                        _ = InMemoryMediaCache.shared.cacheImage(image, for: messageId)
                                    } else {
                                        MediaStorageManager.shared.autoDownloadIfNeeded(message: msg)
                                    }
                                }
                            } else if type == "video" {
                                if InMemoryMediaCache.shared.getCachedImage(for: messageId) == nil {
                                    if let thumbnail = MediaStorageManager.shared.getVideoThumbnail(messageId: messageId) {
                                        _ = InMemoryMediaCache.shared.cacheImage(thumbnail, for: messageId)
                                    } else {
                                        MediaStorageManager.shared.autoDownloadIfNeeded(message: msg)
                                    }
                                }
                            }
                        }

                        return (conversationId, messages)
                    }
                }

                for await (conversationId, messages) in group where !messages.isEmpty {
                    preloaded[conversationId] = messages
                    preloadedIds.insert(conversationId)
                }
            }

            let totalTime = Date().timeIntervalSince(startTime)

            await MainActor.run { [preloaded, preloadedIds] in
                self.preloadedMessages = preloaded
                self.preloadedConversationIds = preloadedIds
                let totalMessages = preloaded.values.reduce(0) { $0 + $1.count }
                AppLogger.debug("ChatDataPreloader: Preloaded \(totalMessages) messages for \(preloadedIds.count) conversations in \(String(format: "%.3f", totalTime))s")
            }
        }
    }

    /// Get preloaded messages for a specific conversation
    func getPreloadedMessages(for conversationId: String) -> [ConversationMessage]? {
        return preloadedMessages[conversationId]
    }

    /// Remove preloaded messages for a conversation after they've been consumed
    func consumePreloadedMessages(for conversationId: String) {
        preloadedMessages.removeValue(forKey: conversationId)
    }

    func setPreloadedMessages(for conversationId: String, messages: [ConversationMessage]) {
        guard !conversationId.isEmpty, !messages.isEmpty else { return }
        let capped = Array(messages.suffix(preloadMessageCount))
        preloadedMessages[conversationId] = capped
        preloadedConversationIds.insert(conversationId)
    }

    /// Apply FE `chat:message:deleted` (scope=everyone) to the in-memory preload cache
    /// so reopening a chat does not flash the original body from a stale preload.
    func markMessagesDeletedForEveryone(
        conversationId: String,
        messageIds: [String],
        deletedContent: String = ChatStrings.chat_messageDeleted.localizedString()
    ) {
        guard !conversationId.isEmpty else { return }
        let ids = Set(messageIds.filter { !$0.isEmpty })
        guard !ids.isEmpty else { return }

        if var cached = preloadedMessages[conversationId] {
            cached = cached.map { msg in
                guard ids.contains(msg.id) else { return msg }
                var updated = msg
                updated.isDeleted = true
                updated.status = "deleted"
                updated.content = deletedContent
                var meta = updated.metadata ?? [:]
                meta["isDeletedEveryone"] = AnyCodable(true)
                updated.metadata = meta
                return updated
            }
            preloadedMessages[conversationId] = cached
        }

        if let wrapped = pinnedMessageCache[conversationId],
           let pinned = wrapped,
           ids.contains(pinned.id) {
            pinnedMessageCache[conversationId] = nil as ConversationMessage?
        }
    }

    /// Update preloaded data when new chats arrive
    func updatePreloadedChats(_ newChats: [ChatMessageRow]) {
        // No-op for zero-memory approach on chat list
    }

    func refreshPreload(conversationId: String, newMessages: [ConversationMessage]) {
        guard !newMessages.isEmpty else { return }
        var current = preloadedMessages[conversationId] ?? []
        let existingIds = Set(current.map { $0.id })
        let fresh = newMessages.filter { !existingIds.contains($0.id) }
        current.append(contentsOf: fresh)
        if current.count > preloadMessageCount {
            current = Array(current.suffix(preloadMessageCount))
        }
        preloadedMessages[conversationId] = current
        preloadedConversationIds.insert(conversationId)

        for msg in fresh {
            let messageId = msg.id
            guard !messageId.isEmpty else { continue }
            let type = msg.messageType ?? ""
            if (type == "image" || type == "photo"),
               InMemoryMediaCache.shared.getCachedImage(for: messageId) == nil,
               let url = MediaStorageManager.shared.getMediaURL(messageId: messageId, type: .image),
               let image = UIImage(contentsOfFile: url.path) {
                _ = InMemoryMediaCache.shared.cacheImage(image, for: messageId)
            } else if type == "video",
                      InMemoryMediaCache.shared.getCachedImage(for: messageId) == nil,
                      let thumbnail = MediaStorageManager.shared.getVideoThumbnail(messageId: messageId) {
                _ = InMemoryMediaCache.shared.cacheImage(thumbnail, for: messageId)
            }
        }
    }

    func preloadFromNetworkIfEmpty(conversationIds: [String], sessionManager: SessionManager) {
        guard !conversationIds.isEmpty, !ChatMockSeeder.isMockMode else { return }

        var candidateIds: [String] = []
        for id in conversationIds.prefix(10) {
            if !inFlightPreloads.contains(id) {
                candidateIds.append(id)
            }
        }
        
        guard !candidateIds.isEmpty else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            let repo = MessageRepository()
            var idsToFetch: [String] = []
            
            for id in candidateIds {
                if repo.getMessageCount(for: id) == 0 {
                    idsToFetch.append(id)
                }
            }

            guard !idsToFetch.isEmpty else {
                AppLogger.debug("[ChatDataPreloader] CoreData warm for candidates — skipping network preload")
                return
            }
            
            await MainActor.run {
                for id in idsToFetch {
                    self.inFlightPreloads.insert(id)
                }
            }

            AppLogger.debug("[ChatDataPreloader] CoreData empty — starting network preload for \(idsToFetch.count) conversations")

            await withTaskGroup(of: (String, [ConversationMessage]).self) { group in
                for conversationId in idsToFetch {
                    group.addTask {
                        do {
                            let response = try await withCheckedThrowingContinuation { cont in
                                sessionManager.getConversationMessages(
                                    conversationId: conversationId,
                                    page: 1,
                                    limit: 20
                                )
                                .subscribe(
                                    onSuccess: { cont.resume(returning: $0) },
                                    onFailure: { cont.resume(throwing: $0) }
                                )
                            } as ConversationMessagesResponse
                            let msgs = response.data.data.messages.filter { $0.isDeleted != true }
                            if !msgs.isEmpty {
                                try? await repo.saveMessages(msgs, conversationId: conversationId)
                            }
                            return (conversationId, msgs)
                        } catch {
                            return (conversationId, [])
                        }
                    }
                }

                var fetched: [String: [ConversationMessage]] = [:]
                for await (convId, msgs) in group where !msgs.isEmpty {
                    fetched[convId] = msgs
                }

                await MainActor.run { [fetched] in
                    for id in idsToFetch {
                        self.inFlightPreloads.remove(id)
                    }
                    
                    guard !fetched.isEmpty else { return }
                    for (convId, msgs) in fetched {
                        self.setPreloadedMessages(for: convId, messages: msgs)
                    }
                    let total = fetched.values.reduce(0) { $0 + $1.count }
                    AppLogger.debug("[ChatDataPreloader] Network preload complete: \(total) messages for \(fetched.count) conversations")
                }
            }
        }
    }

    /// Clear all preloaded data (call on logout)
    func clearCache() {
        firstBatch = []
        preloadedMessages.removeAll()
        preloadedConversationIds.removeAll()
        inFlightPreloads.removeAll()
        hasPreloaded = false
        hasPreloadedMessages = false
        isPreloaded = false
        AppLogger.debug("ChatDataPreloader: Cleared all caches")
    }
}
