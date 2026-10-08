//
//  MessageRepository.swift
//  FlirttimeNew
//
//  Created by Awais on 19/09/25.
//

import CoreData
import Foundation

// MARK: - Sync Metadata Model
struct ConversationSyncMetadata {
    let conversationId: String
    let newestMessageDate: Date?
    let oldestMessageDate: Date?
    let messageCount: Int
    let lastSyncAt: Date?

    var hasCachedMessages: Bool { messageCount > 0 }
    var canSyncNewer: Bool { newestMessageDate != nil }
    var canSyncOlder: Bool { oldestMessageDate != nil }
}

// MARK: - Backward Compatibility
/// Typealias for backward compatibility with existing code
typealias MessageRepositoryProtocol = MessageRepositoryAsync

// MARK: - Async/Await Protocol (Modern, Clean)
protocol MessageRepositoryAsync {
    func getMessages(for conversationId: String, limit: Int, offset: Int) async throws -> [ConversationMessage]
    func getMessagesSnapshot(for conversationId: String, limit: Int, offset: Int) async throws -> [ConversationMessage]
    func getMessage(id: String) async throws -> ConversationMessage?
    func saveMessages(_ messages: [ConversationMessage], conversationId: String?) async throws
    func saveMessage(_ message: ConversationMessage) async throws
    func updateMessage(_ message: ConversationMessage) async throws
    func deleteMessage(id: String) async throws
    func hardDeleteMessage(id: String) async throws
    func updateMessageStatus(id: String, status: String) async throws
    func getMessagesBefore(conversationId: String, beforeDate: Date, limit: Int) async throws -> [ConversationMessage]
    func getMessagesAfter(conversationId: String, afterDate: Date, limit: Int) async throws -> [ConversationMessage]
    func markMessageAsRead(id: String) async throws
    func searchMessages(conversationId: String, searchText: String, limit: Int) async throws -> [ConversationMessage]
    func getAllMediaMessages(for conversationId: String) async throws -> [ConversationMessage]
    func deleteAllMessages() async throws

    // Pin status update
    func updateMessagePinStatus(id: String, isPinned: Bool) async throws
    /// Clears all pinned flags in a conversation except the given message (one-pin model).
    func clearOtherPinnedMessages(in conversationId: String, except messageId: String?) async throws

    // Pinned message lookup
    func getPinnedMessage(for conversationId: String) async throws -> ConversationMessage?

    // Rendered height cache (synchronous — fast indexed lookups)
    func getRenderedHeights(for conversationId: String) -> [String: CGFloat]
    func updateRenderedHeights(_ heights: [String: CGFloat])

    // Sync metadata (synchronous - fast lookups)
    func getMessageCount(for conversationId: String) -> Int
    func getNewestMessageDate(for conversationId: String) -> Date?
    func getOldestMessageDate(for conversationId: String) -> Date?
    func getConversationSyncMetadata(for conversationId: String) -> ConversationSyncMetadata?
    func debugPrintAllConversationIds()

    // Synchronous snapshot from viewContext — zero async latency for instant UI display
    func getMessagesSnapshotSync(for conversationId: String, limit: Int, offset: Int) -> [ConversationMessage]
}

// MARK: - Message Repository Implementation
class MessageRepository: MessageRepositoryAsync {

    private let coreDataManager: CoreDataManager

    private func applyPerformanceOptions<T>(_ request: NSFetchRequest<T>, batchSize: Int = 50) {
        request.fetchBatchSize = batchSize
        request.returnsObjectsAsFaults = true
    }

    init(coreDataManager: CoreDataManager = .shared) {
        self.coreDataManager = coreDataManager
        cleanupOrphanedMessages()
    }

    private func cleanupOrphanedMessages() {
        let context = coreDataManager.writeContext
        context.perform {
            let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
            request.predicate = NSPredicate(format: "conversationId == nil OR conversationId == %@", "")
            do {
                let orphans = try context.fetch(request)
                if !orphans.isEmpty {
                    AppLogger.debug("MessageRepository: Cleaning up \(orphans.count) orphaned CDMessage objects with nil conversationId")
                    for orphan in orphans {
                        context.delete(orphan)
                    }
                    try context.save()
                    AppLogger.debug("MessageRepository: Successfully cleaned up orphaned messages")
                }
            } catch {
                AppLogger.debug("MessageRepository: Failed to clean up orphaned messages: \(error)")
                context.rollback()
            }
        }
    }

    // MARK: - Async Methods

    func getMessages(for conversationId: String, limit: Int = 50, offset: Int = 0) async throws -> [ConversationMessage] {
        try await withCheckedThrowingContinuation { continuation in
            let context = coreDataManager.readContext
            context.perform { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "MessageRepository", code: -1))
                    return
                }

                let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                self.applyPerformanceOptions(request)
                request.predicate = NSPredicate(format: "conversationId == %@", conversationId)
                request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                request.fetchLimit = limit
                request.fetchOffset = offset

                do {
                    let cdMessages = try context.fetch(request)
                    let messages = cdMessages.compactMap { self.convertToConversationMessage($0) }
                    continuation.resume(returning: messages.reversed())
                } catch {
                    AppLogger.debug("MessageRepository getMessages error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getMessagesSnapshot(for conversationId: String, limit: Int = 50, offset: Int = 0) async throws -> [ConversationMessage] {
        try await withCheckedThrowingContinuation { continuation in
            let context = coreDataManager.readContext
            context.perform { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "MessageRepository", code: -1))
                    return
                }

                let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                self.applyPerformanceOptions(request)
                request.predicate = NSPredicate(format: "conversationId == %@", conversationId)
                request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                request.fetchLimit = limit
                request.fetchOffset = offset

                do {
                    let cdMessages = try context.fetch(request)
                    let messages = cdMessages.compactMap { self.convertToConversationMessageSnapshot($0) }
                    continuation.resume(returning: messages.reversed())
                } catch {
                    AppLogger.debug("MessageRepository getMessagesSnapshot error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getAllMediaMessages(for conversationId: String) async throws -> [ConversationMessage] {
        try await withCheckedThrowingContinuation { continuation in
            let context = coreDataManager.readContext
            context.perform { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "MessageRepository", code: -1))
                    return
                }

                let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                self.applyPerformanceOptions(request)
                request.predicate = NSPredicate(
                    format: "conversationId == %@ AND (messageIsDeleted == NO OR messageIsDeleted == nil) AND messageType IN %@",
                    conversationId,
                    ["image", "video", "photo"]
                )
                request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

                do {
                    let cdMessages = try context.fetch(request)
                    let messages = cdMessages.compactMap { self.convertToConversationMessageSnapshot($0) }
                        .filter { $0.isViewOnce != true }
                    continuation.resume(returning: messages)
                } catch {
                    AppLogger.debug("MessageRepository getAllMediaMessages error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getMessage(id: String) async throws -> ConversationMessage? {
        try await withCheckedThrowingContinuation { continuation in
            let context = coreDataManager.readContext
            context.perform { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "MessageRepository", code: -1))
                    return
                }

                let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                self.applyPerformanceOptions(request)
                request.predicate = NSPredicate(format: "id == %@", id)
                request.fetchLimit = 1

                do {
                    let message = try context.fetch(request).first.flatMap { self.convertToConversationMessage($0) }
                    continuation.resume(returning: message)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func saveMessages(_ messages: [ConversationMessage], conversationId: String? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.perform { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "MessageRepository", code: -1))
                    return
                }

                do {
                    AppLogger.debug("[ChatRepo] saveMessages count=\(messages.count) explicitConversationId=\(conversationId ?? "nil")")
                    let pinnedIds = messages.compactMap { ($0.isPinned == true) ? $0.id : nil }
                    let pinEventIds = messages.compactMap { ($0.isPinSystemEvent == true) ? $0.id : nil }
                    if !pinnedIds.isEmpty || !pinEventIds.isEmpty {
                        AppLogger.debug("[ChatRepo] saveMessages pinSummary pinnedCount=\(pinnedIds.count) pinnedIds=\(pinnedIds) pinEventCount=\(pinEventIds.count) pinEventIds=\(pinEventIds)")
                    }
                    var affectedConversationIds = Set<String>()

                    let validIds = messages.compactMap { ($0.id.isEmpty) ? nil : $0.id }
                    var existingById: [String: CDMessage] = [:]
                    if !validIds.isEmpty {
                        let batchRequest: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                        self.applyPerformanceOptions(batchRequest)
                        batchRequest.predicate = NSPredicate(format: "id IN %@", validIds)
                        let existingEntities = try context.fetch(batchRequest)
                        for entity in existingEntities {
                            if let entityId = entity.id {
                                existingById[entityId] = entity
                            }
                        }
                    }

                    for message in messages {
                        // Determine the effective conversationId
                        let effectiveConvId: String = ((message.conversationId != "") ? message.conversationId : conversationId ?? "") ?? ""
                        guard !effectiveConvId.isEmpty, message.id != "" else {
                            AppLogger.debug("MessageRepository: Skipping message with nil conversationId or id: \(message.id)")
                            continue
                        }

                        if !effectiveConvId.isEmpty {
                            affectedConversationIds.insert(effectiveConvId)
                        }

                        let cdMessage: CDMessage
                        let isExistingMessage: Bool
                        if let existing = existingById[message.id ?? ""] {
                            cdMessage = existing
                            isExistingMessage = true
                        } else {
                            cdMessage = CDMessage(context: context)
                            isExistingMessage = false
                        }

                        self.updateCDMessage(
                            cdMessage,
                            from: message,
                            fallbackConversationId: conversationId,
                            preserveExistingPinState: isExistingMessage
                        )
                    }

                    for conversationId in affectedConversationIds {
                        self.updateConversationSyncMetadata(conversationId: conversationId, in: context)
                    }

                    if !affectedConversationIds.isEmpty {
                        AppLogger.debug("[ChatRepo] updated sync metadata for conversations=\(Array(affectedConversationIds).sorted())")
                    }

                    try context.save()
                    // viewContext is kept fresh automatically via automaticallyMergesChangesFromParent=true.
                    // No manual refreshAllObjects() needed — that was O(n) main-thread work on every save.
                    continuation.resume()
                } catch {
                    AppLogger.debug("MessageRepository saveMessages error: \(error)")
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func saveMessage(_ message: ConversationMessage) async throws {
        try await saveMessages([message])
    }

    func updateMessage(_ message: ConversationMessage) async throws {
        try await saveMessage(message)
    }

    func deleteMessage(id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.perform {
                do {
                    let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                    self.applyPerformanceOptions(request)
                    request.predicate = NSPredicate(format: "id == %@", id)

                    let messages = try context.fetch(request)
                    for message in messages {
                        message.messageIsDeleted = true
                        message.status = "deleted"
                    }

                    try context.save()
                    continuation.resume()
                } catch {
                    AppLogger.debug("MessageRepository deleteMessage error: \(error)")
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Persist delete-for-everyone so peers who are outside the open chat still see it
    /// after reopening (CD + later sync). Mirrors FE socket `{ messageId, scope: everyone }`.
    func markMessagesDeletedForEveryone(
        ids: [String],
        conversationId: String?,
        deletedContent: String?
    ) async throws {
        let messageIds = ids.filter { !$0.isEmpty }
        guard !messageIds.isEmpty else { return }

        let tombstoneContent = (deletedContent?.isEmpty == false)
            ? deletedContent!
            : ChatStrings.chat_messageDeleted.localizedString()
        let convId = conversationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.perform {
                do {
                    let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                    self.applyPerformanceOptions(request)
                    request.predicate = NSPredicate(format: "id IN %@", messageIds)

                    let existing = try context.fetch(request)
                    var existingById: [String: CDMessage] = [:]
                    for entity in existing {
                        if let entityId = entity.id {
                            existingById[entityId] = entity
                        }
                    }

                    for messageId in messageIds {
                        let cdMessage: CDMessage
                        if let found = existingById[messageId] {
                            cdMessage = found
                        } else if !convId.isEmpty {
                            // Message not cached yet — store a tombstone so reopen/sync
                            // cannot resurrect the original body from a stale preload.
                            cdMessage = CDMessage(context: context)
                            cdMessage.id = messageId
                            cdMessage.conversationId = convId
                            cdMessage.createdAt = Date()
                            cdMessage.messageType = "text"
                        } else {
                            AppLogger.debug("MessageRepository: skip delete tombstone — no CD row and no conversationId for \(messageId)")
                            continue
                        }

                        cdMessage.messageIsDeleted = true
                        cdMessage.status = "deleted"
                        cdMessage.content = tombstoneContent
                        cdMessage.messageIsPinned = false

                        var meta: [String: Any] = [:]
                        if let raw = cdMessage.metadata,
                           let data = raw.data(using: .utf8),
                           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            meta = parsed
                        }
                        meta["isDeletedEveryone"] = true
                        if let metaData = try? JSONSerialization.data(withJSONObject: meta),
                           let metaString = String(data: metaData, encoding: .utf8) {
                            cdMessage.metadata = metaString
                        }
                    }

                    try context.save()
                    continuation.resume()
                } catch {
                    AppLogger.debug("MessageRepository markMessagesDeletedForEveryone error: \(error)")
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func hardDeleteMessage(id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.perform {
                do {
                    let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                    self.applyPerformanceOptions(request)
                    request.predicate = NSPredicate(format: "id == %@", id)

                    let messages = try context.fetch(request)
                    for message in messages {
                        context.delete(message)
                    }

                    try context.save()
                    continuation.resume()
                } catch {
                    AppLogger.debug("MessageRepository hardDeleteMessage error: \(error)")
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func updateMessageStatus(id: String, status: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.perform {
                do {
                    let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                    self.applyPerformanceOptions(request)
                    request.predicate = NSPredicate(format: "id == %@", id)

                    if let message = try context.fetch(request).first {
                        message.status = status
                        message.updatedAt = Date()
                        try context.save()
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "MessageNotFound", code: -1))
                    }
                } catch {
                    AppLogger.debug("MessageRepository updateMessageStatus error: \(error)")
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getMessagesBefore(conversationId: String, beforeDate: Date, limit: Int = 50) async throws -> [ConversationMessage] {
        try await withCheckedThrowingContinuation { continuation in
            let context = coreDataManager.readContext
            context.perform { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "MessageRepository", code: -1))
                    return
                }

                let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                self.applyPerformanceOptions(request)
                request.predicate = NSPredicate(format: "conversationId == %@ AND createdAt < %@", conversationId, beforeDate as NSDate)
                request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                request.fetchLimit = limit

                do {
                    let cdMessages = try context.fetch(request)
                    let messages = cdMessages.compactMap { self.convertToConversationMessage($0) }
                    let beforeStr = MessageMapper.iso8601Formatter.string(from: beforeDate)
                    let firstId = messages.first?.id ?? "nil"
                    let lastId = messages.last?.id ?? "nil"
                    AppLogger.debug("[ChatRepo] getMessagesBefore conversation=\(conversationId) before=\(beforeStr) returned=\(messages.count) first=\(firstId) last=\(lastId) limit=\(limit)")
                    continuation.resume(returning: messages.reversed())
                } catch {
                    AppLogger.debug("MessageRepository getMessagesBefore error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getMessagesAfter(conversationId: String, afterDate: Date, limit: Int = 50) async throws -> [ConversationMessage] {
        try await withCheckedThrowingContinuation { continuation in
            let context = coreDataManager.readContext
            context.perform { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "MessageRepository", code: -1))
                    return
                }

                let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                self.applyPerformanceOptions(request)
                request.predicate = NSPredicate(format: "conversationId == %@ AND createdAt > %@", conversationId, afterDate as NSDate)
                request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                request.fetchLimit = limit

                do {
                    let cdMessages = try context.fetch(request)
                    let messages = cdMessages.compactMap { self.convertToConversationMessage($0) }
                    continuation.resume(returning: messages)
                } catch {
                    AppLogger.debug("MessageRepository getMessagesAfter error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func markMessageAsRead(id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.perform {
                do {
                    let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                    self.applyPerformanceOptions(request)
                    request.predicate = NSPredicate(format: "id == %@", id)

                    if let message = try context.fetch(request).first {
                        message.updatedAt = Date()
                        try context.save()
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "MessageNotFound", code: -1))
                    }
                } catch {
                    AppLogger.debug("MessageRepository markMessageAsRead error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Pin Status Update
    func updateMessagePinStatus(id: String, isPinned: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.perform {
                do {
                    let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                    self.applyPerformanceOptions(request)
                    request.predicate = NSPredicate(format: "id == %@", id)

                    if let message = try context.fetch(request).first {
                        message.messageIsPinned = isPinned
                        message.updatedAt = Date()
                        try context.save()
                        AppLogger.debug("MessageRepository: Updated pin status for message \(id), isPinned: \(isPinned)")
                        continuation.resume()
                    } else {
                        // Message not found in cache yet - this is okay, it will be synced later
                        AppLogger.debug("MessageRepository: Message \(id) not found in cache for pin update")
                        continuation.resume()
                    }
                } catch {
                    AppLogger.debug("MessageRepository updateMessagePinStatus error: \(error)")
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func clearOtherPinnedMessages(in conversationId: String, except messageId: String?) async throws {
        guard !conversationId.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.perform {
                do {
                    let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                    self.applyPerformanceOptions(request)
                    if let messageId, !messageId.isEmpty {
                        request.predicate = NSPredicate(
                            format: "conversationId == %@ AND messageIsPinned == YES AND id != %@",
                            conversationId,
                            messageId
                        )
                    } else {
                        request.predicate = NSPredicate(
                            format: "conversationId == %@ AND messageIsPinned == YES",
                            conversationId
                        )
                    }
                    let pinned = try context.fetch(request)
                    guard !pinned.isEmpty else {
                        continuation.resume()
                        return
                    }
                    for message in pinned {
                        message.messageIsPinned = false
                        message.updatedAt = Date()
                    }
                    try context.save()
                    AppLogger.debug(
                        "MessageRepository: Cleared \(pinned.count) other pins in \(conversationId)"
                    )
                    continuation.resume()
                } catch {
                    AppLogger.debug("MessageRepository clearOtherPinnedMessages error: \(error)")
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Pinned Message Lookup
    func getPinnedMessage(for conversationId: String) async throws -> ConversationMessage? {
        try await withCheckedThrowingContinuation { continuation in
            let context = coreDataManager.readContext
            context.perform { [weak self] in
                guard let self else { continuation.resume(returning: nil); return }

                let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                self.applyPerformanceOptions(request)
                request.predicate = NSPredicate(
                    format: "conversationId == %@ AND messageIsPinned == YES AND (messageIsDeleted == NO OR messageIsDeleted == nil)",
                    conversationId
                )
                // Most recently created pinned message
                request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                request.fetchLimit = 1

                do {
                    let msg = try context.fetch(request).first.flatMap { self.convertToConversationMessage($0) }
                    AppLogger.debug("[MessageRepository] getPinnedMessage conversationId=\(conversationId) found=\(msg?.id ?? "nil")")
                    continuation.resume(returning: msg)
                } catch {
                    AppLogger.debug("[MessageRepository] getPinnedMessage error: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func searchMessages(conversationId: String, searchText: String, limit: Int = 50) async throws -> [ConversationMessage] {
        try await withCheckedThrowingContinuation { continuation in
            let context = coreDataManager.readContext
            context.perform { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "MessageRepository", code: -1))
                    return
                }

                let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                self.applyPerformanceOptions(request)
                request.predicate = NSPredicate(format: "conversationId == %@ AND content CONTAINS[cd] %@ AND (messageIsDeleted == NO OR messageIsDeleted == nil)", conversationId, searchText)
                request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                request.fetchLimit = limit

                do {
                    let cdMessages = try context.fetch(request)
                    let messages = cdMessages.compactMap { self.convertToConversationMessage($0) }
                    continuation.resume(returning: messages)
                } catch {
                    AppLogger.debug("MessageRepository searchMessages error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deleteAllMessages() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.perform {
                do {
                    let fetchRequest: NSFetchRequest<NSFetchRequestResult> = CDMessage.fetchRequest()
                    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                    deleteRequest.resultType = .resultTypeCount

                    let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                    let deletedCount = result?.result as? Int ?? 0

                    try context.save()

                    DispatchQueue.main.async {
                        self.coreDataManager.viewContext.reset()
                        AppLogger.debug("Deleted \(deletedCount) messages from database")
                    }
                    continuation.resume()
                } catch {
                    AppLogger.debug("Failed to delete all messages: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Synchronous Metadata Methods
    //
    // All four date/count queries are batched into a SINGLE context.perform block
    // so only one semaphore.wait() is needed instead of four serial stalls.
    // Total main-thread block time: ~30-80 ms (was ~150-380 ms).

    func getMessageCount(for conversationId: String) -> Int {
        return getConversationSyncMetadata(for: conversationId)?.messageCount ?? 0
    }

    func getNewestMessageDate(for conversationId: String) -> Date? {
        return getConversationSyncMetadata(for: conversationId)?.newestMessageDate
    }

    func getOldestMessageDate(for conversationId: String) -> Date? {
        return getConversationSyncMetadata(for: conversationId)?.oldestMessageDate
    }

    func getConversationSyncMetadata(for conversationId: String) -> ConversationSyncMetadata? {
        let context = coreDataManager.readContext
        var result: ConversationSyncMetadata?
        let semaphore = DispatchSemaphore(value: 0)

        context.perform {
            // ── 1. Newest & oldest dates — single sorted fetch, take head/tail ──
            let msgPredicate = NSPredicate(
                format: "conversationId == %@ AND (messageIsDeleted == NO OR messageIsDeleted == nil)",
                conversationId
            )

            let newestReq: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
            newestReq.predicate = msgPredicate
            newestReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            newestReq.fetchLimit = 1
            newestReq.propertiesToFetch = ["createdAt"]
            newestReq.returnsObjectsAsFaults = true

            let oldestReq: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
            oldestReq.predicate = msgPredicate
            oldestReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            oldestReq.fetchLimit = 1
            oldestReq.propertiesToFetch = ["createdAt"]
            oldestReq.returnsObjectsAsFaults = true

            let countReq: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
            countReq.predicate = msgPredicate

            let convReq: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
            convReq.predicate = NSPredicate(format: "id == %@", conversationId)
            convReq.fetchLimit = 1
            convReq.propertiesToFetch = ["lastSyncedAt"]
            convReq.returnsObjectsAsFaults = true

            do {
                let newestDate  = try context.fetch(newestReq).first?.createdAt
                let oldestDate  = try context.fetch(oldestReq).first?.createdAt
                let count       = try context.count(for: countReq)
                let lastSyncAt  = try context.fetch(convReq).first?.lastSyncedAt

                result = ConversationSyncMetadata(
                    conversationId:    conversationId,
                    newestMessageDate: newestDate,
                    oldestMessageDate: oldestDate,
                    messageCount:      count,
                    lastSyncAt:        lastSyncAt
                )
            } catch {
                AppLogger.debug("[MessageRepository] getConversationSyncMetadata error: \(error)")
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    // MARK: - Async Metadata (preferred — call from Task contexts to avoid blocking)

    func getConversationSyncMetadataAsync(for conversationId: String) async -> ConversationSyncMetadata? {
        await withCheckedContinuation { continuation in
            let context = coreDataManager.readContext
            context.perform {
                let msgPredicate = NSPredicate(
                    format: "conversationId == %@ AND (messageIsDeleted == NO OR messageIsDeleted == nil)",
                    conversationId
                )

                let newestReq: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                newestReq.predicate = msgPredicate
                newestReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                newestReq.fetchLimit = 1
                newestReq.returnsObjectsAsFaults = true

                let oldestReq: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                oldestReq.predicate = msgPredicate
                oldestReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                oldestReq.fetchLimit = 1
                oldestReq.returnsObjectsAsFaults = true

                let countReq: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                countReq.predicate = msgPredicate

                let convReq: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                convReq.predicate = NSPredicate(format: "id == %@", conversationId)
                convReq.fetchLimit = 1
                convReq.returnsObjectsAsFaults = true

                do {
                    let newestDate = try context.fetch(newestReq).first?.createdAt
                    let oldestDate = try context.fetch(oldestReq).first?.createdAt
                    let count      = try context.count(for: countReq)
                    let lastSyncAt = try context.fetch(convReq).first?.lastSyncedAt

                    continuation.resume(returning: ConversationSyncMetadata(
                        conversationId:    conversationId,
                        newestMessageDate: newestDate,
                        oldestMessageDate: oldestDate,
                        messageCount:      count,
                        lastSyncAt:        lastSyncAt
                    ))
                } catch {
                    AppLogger.debug("[MessageRepository] getConversationSyncMetadataAsync error: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func debugPrintAllConversationIds() {
        let context = coreDataManager.readContext
        context.perform {
            let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
            self.applyPerformanceOptions(request)

            do {
                let allMessages = try context.fetch(request)
                let uniqueIds = Set(allMessages.compactMap { $0.conversationId })
                AppLogger.debug("🔍 CoreData contains \(allMessages.count) total messages for \(uniqueIds.count) conversations:")
                for id in uniqueIds.sorted() {
                    let count = allMessages.filter { $0.conversationId == id }.count
                    AppLogger.debug("  - '\(id)': \(count) messages")
                }

                let nilCount = allMessages.filter { $0.conversationId == nil }.count
                if nilCount > 0 {
                    AppLogger.debug("  - (nil): \(nilCount) messages")
                }
            } catch {
                AppLogger.debug("Error fetching conversation IDs: \(error)")
            }
        }
    }

    // MARK: - Synchronous Snapshot (viewContext — main thread, zero async latency)

    /// Reads directly from the main-thread `viewContext` without any queue hop.
    /// Use this for instant initial display. `viewContext` is kept fresh
    /// automatically via `automaticallyMergesChangesFromParent = true` after every save.
    func getMessagesSnapshotSync(for conversationId: String, limit: Int, offset: Int = 0) -> [ConversationMessage] {
        let context = coreDataManager.viewContext
        let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
        // Prefetch all columns so no per-object fault fires on the main thread
        request.returnsObjectsAsFaults = false
        request.fetchBatchSize = limit > 0 ? limit : 50
        request.predicate = NSPredicate(
            format: "conversationId == %@",
            conversationId
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        if limit > 0 { request.fetchLimit = limit }
        if offset > 0 { request.fetchOffset = offset }

        do {
            let cdMessages = try context.fetch(request)
            return cdMessages.compactMap { convertToConversationMessageSnapshot($0) }.reversed()
        } catch {
            AppLogger.debug("MessageRepository getMessagesSnapshotSync error: \(error)")
            return []
        }
    }

    // MARK: - Rendered Height Cache

    func getRenderedHeights(for conversationId: String) -> [String: CGFloat] {
        var result: [String: CGFloat] = [:]
        let context = coreDataManager.readContext
        let semaphore = DispatchSemaphore(value: 0)
        context.perform {
            let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
            request.predicate = NSPredicate(
                format: "conversationId == %@ AND renderedHeight > 0",
                conversationId
            )
            request.propertiesToFetch = ["id", "renderedHeight"]
            request.returnsObjectsAsFaults = false
            if let messages = try? context.fetch(request) {
                for msg in messages {
                    if let id = msg.id, msg.renderedHeight > 0 {
                        result[id] = CGFloat(msg.renderedHeight)
                    }
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    func updateRenderedHeights(_ heights: [String: CGFloat]) {
        guard !heights.isEmpty else { return }
        let context = coreDataManager.writeContext
        let messageIds = Array(heights.keys)
        context.perform {
            let request: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", messageIds)
            request.returnsObjectsAsFaults = false
            guard let messages = try? context.fetch(request) else { return }
            var dirty = false
            for msg in messages {
                guard let id = msg.id, let newHeight = heights[id] else { continue }
                let newH = Float(newHeight)
                if abs(msg.renderedHeight - newH) > 0.5 {
                    msg.renderedHeight = newH
                    dirty = true
                }
            }
            if dirty { try? context.save() }
        }
    }

    // MARK: - Data Conversion (delegates to MessageMapper)

    func convertToConversationMessage(_ cdMessage: CDMessage, useSenderUserRelationship: Bool = true) -> ConversationMessage? {
        MessageMapper.toDomain(cdMessage, useSenderUserRelationship: useSenderUserRelationship)
    }

    private func convertToConversationMessageSnapshot(_ cdMessage: CDMessage) -> ConversationMessage? {
        MessageMapper.toDomainSnapshot(cdMessage)
    }

    private func updateCDMessage(
        _ cdMessage: CDMessage,
        from message: ConversationMessage,
        fallbackConversationId: String? = nil,
        preserveExistingPinState: Bool = false
    ) {
        MessageMapper.update(cdMessage, from: message, fallbackConversationId: fallbackConversationId, preserveExistingPinState: preserveExistingPinState)
    }

    private func updateConversationSyncMetadata(conversationId: String, in context: NSManagedObjectContext) {
        guard !conversationId.isEmpty else { return }

        let convReq: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
        convReq.predicate = NSPredicate(format: "id == %@", conversationId)
        convReq.fetchLimit = 1

        let conversation: CDConversation
        if let existing = try? context.fetch(convReq).first {
            conversation = existing
        } else {
            let created = CDConversation(context: context)
            created.id = conversationId
            conversation = created
        }

        let newestReq: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
        applyPerformanceOptions(newestReq, batchSize: 1)
        newestReq.predicate = NSPredicate(format: "conversationId == %@ AND (messageIsDeleted == NO OR messageIsDeleted == nil)", conversationId)
        newestReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        newestReq.fetchLimit = 1

        let oldestReq: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
        applyPerformanceOptions(oldestReq, batchSize: 1)
        oldestReq.predicate = NSPredicate(format: "conversationId == %@ AND (messageIsDeleted == NO OR messageIsDeleted == nil)", conversationId)
        oldestReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        oldestReq.fetchLimit = 1

        let newestDate: Date?
        if let newest = try? context.fetch(newestReq).first {
            newestDate = newest.createdAt
            conversation.newestCachedMessageDate = newestDate
        } else {
            newestDate = nil
            conversation.newestCachedMessageDate = nil
        }

        if let oldest = try? context.fetch(oldestReq).first {
            conversation.oldestCachedMessageDate = oldest.createdAt
        } else {
            conversation.oldestCachedMessageDate = nil
        }

        conversation.lastSyncedAt = newestDate ?? conversation.lastSyncedAt ?? Date()

        let newestValue = conversation.newestCachedMessageDate.map { MessageMapper.iso8601Formatter.string(from: $0) } ?? "nil"
        let oldestValue = conversation.oldestCachedMessageDate.map { MessageMapper.iso8601Formatter.string(from: $0) } ?? "nil"
        let lastSyncValue = conversation.lastSyncedAt.map { MessageMapper.iso8601Formatter.string(from: $0) } ?? "nil"
        AppLogger.debug("[ChatRepo] metadata conversation=\(conversationId) newest=\(newestValue) oldest=\(oldestValue) lastSync=\(lastSyncValue)")
    }

}
