//
//  ConversationRepository.swift
//  FlirttimeNew
//
//  Created by Awais on 19/09/25.
//

import CoreData
import Foundation
import Swinject

// MARK: - Backward Compatibility
typealias ConversationRepositoryProtocol = ConversationRepositoryAsync

// MARK: - Async/Await Protocol
protocol ConversationRepositoryAsync {
    func getAllConversations() async throws -> [ChatMessageRow]
    func getAllConversationsIncludingArchived() async throws -> [ChatMessageRow]
    func getConversation(id: String) async throws -> ChatMessageRow?
    func getConversationWithParticipants(id: String) async throws -> ChatMessageRow?
    func saveConversations(_ conversations: [ChatMessageRow]) async throws
    func saveConversation(_ conversation: ChatMessageRow) async throws
    func updateConversationSettings(id: String, settings: ConversationSettings) async throws
    func updateConversationTitle(id: String, newTitle: String) async throws
    func updateConversationAvatar(id: String, newAvatar: String) async throws
    func updateLastMessage(conversationId: String, message: ConversationMessage) async throws
    func updateLastMessageStatusIfLatest(conversationId: String, messageId: String, status: String) async
    func markLastMessageAsDeleted(conversationId: String, messageId: String) async
    func updateUnreadCount(conversationId: String, unreadCount: Int) async throws
    func deleteConversation(id: String) async throws
    func deleteConversations(notIn ids: Set<String>) async throws
    func markAsRead(conversationId: String) async throws
    func markAsUnread(conversationId: String) async throws
    func clearAllData() async throws
    func addParticipant(conversationId: String, participant: GroupParticipant) async throws
    func removeParticipant(conversationId: String, userId: String) async throws
    func updateParticipantRole(conversationId: String, userId: String, newRole: String) async throws
    func clearLastMessage(conversationId: String) async throws

    func getConversationListSync() -> [ChatMessageRow]

    func findConversationIdByParticipant(userId: String) -> String?
}

class ConversationRepository: ConversationRepositoryAsync {

    private let coreDataManager: CoreDataManager

    private let sessionManager: SessionManager?

    init(coreDataManager: CoreDataManager = .shared) {
        self.coreDataManager = coreDataManager
        self.sessionManager = Container.sharedContainer.resolve(SessionManager.self)
        migrateGroupAvatarStoreIfNeeded()
    }

    private static let avatarMigrationKey = "groupAvatarMigratedToCoreData"

    private func migrateGroupAvatarStoreIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.avatarMigrationKey) else { return }

        let store = ChatUserDefaultsStore.shared.groupAvatarStore
        guard !store.isEmpty else {
            defaults.set(true, forKey: Self.avatarMigrationKey)
            return
        }

        let context = coreDataManager.writeContext
        context.performAndWait {
            for (id, avatarURL) in store {
                let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id)
                request.fetchLimit = 1
                if let conversation = try? context.fetch(request).first {
                    conversation.avatar = avatarURL
                }
            }
            try? context.save()
        }

        ChatUserDefaultsStore.shared.groupAvatarStore = [:]
        defaults.set(true, forKey: Self.avatarMigrationKey)
        AppLogger.debug("[ConversationRepository] Migrated \(store.count) group avatars from UserDefaults to CDConversation.avatar")
    }

    // MARK: - Cleanup

    func cleanupDuplicateConversations() {
        let context = coreDataManager.backgroundContext
        context.perform {
            do {
                let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                let all = try context.fetch(request)
                let grouped = Dictionary(grouping: all, by: { $0.id ?? "" })
                var removed = 0
                for (id, items) in grouped {
                    guard !id.isEmpty, items.count > 1 else { continue }
                    guard let primary = items.max(by: { a, b in
                        let ad = a.updatedAt ?? a.lastMessageAt ?? Date.distantPast
                        let bd = b.updatedAt ?? b.lastMessageAt ?? Date.distantPast
                        return ad < bd
                    }) else { continue }
                    for obj in items where obj != primary {
                        context.delete(obj)
                        removed += 1
                    }
                }
                if removed > 0 {
                    try context.save()
                }
                if removed > 0 {
                    AppLogger.debug("ConversationRepository: Removed duplicate conversations: \(removed)")
                }
            } catch {
                AppLogger.debug("ConversationRepository cleanupDuplicateConversations error: \(error)")
            }
        }
    }

    // MARK: - Sync Methods (Instant UI)

    func getConversationListSync() -> [ChatMessageRow] {
        let startTime = Date()
        let context = coreDataManager.viewContext

        var result: [ChatMessageRow] = []

        context.performAndWait {
            let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: "settings.settingsIsPinned", ascending: false),
                NSSortDescriptor(key: "lastMessageTimestamp", ascending: false),
                NSSortDescriptor(key: "updatedAt", ascending: false)
            ]
            request.relationshipKeyPathsForPrefetching = ["settings", "participants"]
            request.fetchBatchSize = 50
            request.returnsObjectsAsFaults = false

            do {
                let conversations = try context.fetch(request)
                result = conversations.compactMap { self.convertToChatMessageRowSnapshot($0) }
            } catch {
                AppLogger.debug("ConversationRepository getConversationListSync error: \(error)")
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        AppLogger.debug("ConversationRepository: Sync load \(result.count) chats in \(String(format: "%.3f", duration))s")

        return result
    }

    func findConversationIdByParticipant(userId: String) -> String? {
        let context = coreDataManager.viewContext
        var conversationId: String?
        context.performAndWait {
            let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
            request.relationshipKeyPathsForPrefetching = ["participants"]
            request.returnsObjectsAsFaults = false
            request.predicate = NSPredicate(format: "type == %@", "direct")
            do {
                let conversations = try context.fetch(request)
                for conv in conversations {
                    guard let participants = conv.participants as? Set<CDParticipant> else { continue }
                    // 1:1 direct chat: exactly 2 participants, one of which is the target user
                    let isOneOnOne = participants.count == 2
                    let hasTargetUser = participants.contains { $0.userId == userId }
                    if isOneOnOne, hasTargetUser {
                        conversationId = conv.id
                        return
                    }
                }
            } catch {
                AppLogger.debug("ConversationRepository findConversationIdByParticipant error: \(error)")
            }
        }
        return conversationId
    }

    // MARK: - Async Methods

    /// Fetch all conversations (non-archived) using async/await
    func getAllConversations() async throws -> [ChatMessageRow] {
        try await withCheckedThrowingContinuation { continuation in
            let context = coreDataManager.readContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.sortDescriptors = [
                        NSSortDescriptor(key: "settings.settingsIsPinned", ascending: false),
                        NSSortDescriptor(key: "lastMessageTimestamp", ascending: false),
                        NSSortDescriptor(key: "lastMessageAt", ascending: false),
                        NSSortDescriptor(key: "updatedAt", ascending: false),
                        NSSortDescriptor(key: "title", ascending: true)
                    ]
                    request.predicate = NSPredicate(format: "conversationIsArchived == false")
                    request.returnsObjectsAsFaults = false

                    let results = try context.fetch(request)
                    let chats = results.compactMap { self.convertToChatMessageRow($0) }
                    continuation.resume(returning: chats)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetch all conversations including archived using async/await
    func getAllConversationsIncludingArchived() async throws -> [ChatMessageRow] {
        try await withCheckedThrowingContinuation { continuation in
            let context = coreDataManager.readContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.sortDescriptors = [
                        NSSortDescriptor(key: "settings.settingsIsPinned", ascending: false),
                        NSSortDescriptor(key: "lastMessageTimestamp", ascending: false),
                        NSSortDescriptor(key: "lastMessageAt", ascending: false),
                        NSSortDescriptor(key: "updatedAt", ascending: false)
                    ]
                    request.returnsObjectsAsFaults = false

                    let results = try context.fetch(request)
                    let chats = results.compactMap { self.convertToChatMessageRow($0) }
                    continuation.resume(returning: chats)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getAllConversationsSync() -> [ChatMessageRow] {
        let context = coreDataManager.viewContext
        var result: [ChatMessageRow] = []
        context.performAndWait {
            let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: "settings.settingsIsPinned", ascending: false),
                NSSortDescriptor(key: "lastMessageTimestamp", ascending: false),
                NSSortDescriptor(key: "lastMessageAt", ascending: false),
                NSSortDescriptor(key: "updatedAt", ascending: false)
            ]
            request.returnsObjectsAsFaults = false
            if let results = try? context.fetch(request) {
                result = results.compactMap { self.convertToChatMessageRow($0) }
            }
        }
        return result
    }

    /// Fetch a single conversation by ID using async/await
    func getConversation(id: String) async throws -> ChatMessageRow? {
        try await withCheckedThrowingContinuation { continuation in
            let context = coreDataManager.readContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", id)
                    request.relationshipKeyPathsForPrefetching = ["participants", "settings"]
                    request.fetchLimit = 1
                    request.returnsObjectsAsFaults = false

                    if let result = try context.fetch(request).first {
                        let chat = self.convertToChatMessageRow(result)
                        continuation.resume(returning: chat)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetch conversation with full participant data using async/await
    func getConversationWithParticipants(id: String) async throws -> ChatMessageRow? {
        try await withCheckedThrowingContinuation { continuation in
            // Use viewContext since it's refreshed after saves
            let context = coreDataManager.viewContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", id)
                    request.relationshipKeyPathsForPrefetching = ["participants", "settings"]
                    request.fetchLimit = 1
                    request.returnsObjectsAsFaults = false

                    if let result = try context.fetch(request).first {
                        // Debug: Check participants directly via relationship
                        let participantsCount = result.participants?.count ?? 0
                        AppLogger.debug("ConversationRepository: getConversationWithParticipants - conversation \(id) has \(participantsCount) participants via relationship")

                        // Also try fetching participants directly to verify they exist in the store
                        let participantRequest: NSFetchRequest<CDParticipant> = CDParticipant.fetchRequest()
                        participantRequest.predicate = NSPredicate(format: "conversationId == %@", id)
                        let directParticipants = try context.fetch(participantRequest)
                        AppLogger.debug("ConversationRepository: Direct query found \(directParticipants.count) participants for conversation \(id)")

                        let chat = self.convertToChatMessageRow(result)
                        continuation.resume(returning: chat)
                    } else {
                        AppLogger.debug("ConversationRepository: No conversation found with id \(id)")
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Save conversations using async/await
    func saveConversations(_ conversations: [ChatMessageRow]) async throws {
        // Collect IDs to refresh later
        let conversationIds = conversations.compactMap { $0.id }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    for chatRow in conversations {
                        guard let id = chatRow.id, !id.isEmpty else { continue }
                        let entity = self.getOrCreateConversationEntity(id: id, in: context)
                        self.updateConversationEntity(entity, from: chatRow, context: context)
                    }
                    try context.save()
                    continuation.resume()
                } catch {
                    AppLogger.debug("ConversationRepository: saveConversations error, rolling back: \(error)")
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }

        // After save completes, refresh these specific objects in viewContext
        await MainActor.run {
            let viewContext = coreDataManager.viewContext
            for id in conversationIds {
                let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id)
                request.fetchLimit = 1
                if let conversation = try? viewContext.fetch(request).first {
                    viewContext.refresh(conversation, mergeChanges: false)
                }
            }
            viewContext.processPendingChanges()
        }
    }

    /// Save a single conversation using async/await
    func saveConversation(_ conversation: ChatMessageRow) async throws {
        try await saveConversations([conversation])
    }

    /// Update conversation settings using async/await
    func updateConversationSettings(id: String, settings: ConversationSettings) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", id)

                    if let conversation = try context.fetch(request).first {
                        let settingsEntity = conversation.settings ?? self.createSettingsEntity(for: conversation, in: context)
                        self.applySettings(settings, to: settingsEntity)
                        // Touch parent so ChatList FRC re-publishes (settings-only edits
                        // on the relationship often don't trigger FRC otherwise).
                        conversation.updatedAt = Date()
                        try context.save()
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "ConversationNotFound", code: -1))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Update conversation title using async/await
    func updateConversationTitle(id: String, newTitle: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", id)

                    if let conversation = try context.fetch(request).first {
                        conversation.title = newTitle
                        conversation.updatedAt = Date()
                        try context.save()
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "ConversationNotFound", code: -1))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func updateConversationAvatar(id: String, newAvatar: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", id)

                    if let conversation = try context.fetch(request).first {
                        conversation.avatar = newAvatar
                        conversation.updatedAt = Date()
                        try context.save()
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "ConversationNotFound", code: -1))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Update last message using async/await
    func updateLastMessage(conversationId: String, message: ConversationMessage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", conversationId)

                    if let conversation = try context.fetch(request).first {
                        conversation.lastMessageContent = message.content
                        conversation.lastMessageSender = message.sender?.id ?? message.senderId
                        conversation.lastMessageType = message.messageType ?? message.type
                        // System events have no delivery receipts — never store tick status
                        conversation.lastMessageStatus = message.isSystemMessage ? nil : message.status

                        if !message.createdAt.isEmpty,
                           let date = ConversationMapper.isoFormatter.date(from: message.createdAt) ?? ConversationMapper.isoFormatterFallback.date(from: message.createdAt) {
                            conversation.lastMessageTimestamp = date
                            conversation.lastMessageAt = date
                        }

                        conversation.updatedAt = Date()
                        try context.save()
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "ConversationNotFound", code: -1))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func updateLastMessageStatusIfLatest(conversationId: String, messageId: String, status: String) async {
        let context = coreDataManager.writeContext
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            context.perform {
                let convRequest: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                convRequest.predicate = NSPredicate(format: "id == %@", conversationId)
                convRequest.fetchLimit = 1
                guard let conversation = try? context.fetch(convRequest).first else {
                    continuation.resume()
                    return
                }

                let msgRequest: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                msgRequest.predicate = NSPredicate(format: "conversationId == %@", conversationId)
                msgRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                msgRequest.fetchLimit = 1
                guard let latest = try? context.fetch(msgRequest).first,
                      latest.id == messageId else {
                    continuation.resume()
                    return
                }

                // System events ("created the group", etc.) never show delivery ticks
                let latestType = (latest.messageType ?? conversation.lastMessageType ?? "").lowercased()
                if latestType == "system" {
                    conversation.lastMessageStatus = nil
                    try? context.save()
                    continuation.resume()
                    return
                }

                conversation.lastMessageStatus = status
                try? context.save()
                continuation.resume()
            }
        }
    }

    func markLastMessageAsDeleted(conversationId: String, messageId: String) async {
        let context = coreDataManager.writeContext
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            context.perform {
                let convRequest: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                convRequest.predicate = NSPredicate(format: "id == %@", conversationId)
                convRequest.fetchLimit = 1
                guard let conversation = try? context.fetch(convRequest).first else {
                    continuation.resume()
                    return
                }

                let msgRequest: NSFetchRequest<CDMessage> = CDMessage.fetchRequest()
                msgRequest.predicate = NSPredicate(format: "conversationId == %@", conversationId)
                msgRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                msgRequest.fetchLimit = 1
                guard let latest = try? context.fetch(msgRequest).first,
                      latest.id == messageId else {
                    continuation.resume()
                    return
                }

                conversation.lastMessageContent = ChatStrings.chat_messageDeleted.localizedString()
                conversation.lastMessageStatus = "deleted"
                try? context.save()
                continuation.resume()
            }
        }
    }

    /// Clear lastMessage fields for a conversation (used after deleting the last message)
    func clearLastMessage(conversationId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", conversationId)

                    if let conversation = try context.fetch(request).first {
                        conversation.lastMessageContent = nil
                        conversation.lastMessageSender = nil
                        conversation.lastMessageType = nil
                        conversation.lastMessageStatus = nil
                        conversation.lastMessageTimestamp = nil
                        conversation.lastMessageAt = nil
                        conversation.updatedAt = Date()
                        try context.save()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Update unread count using async/await
    func updateUnreadCount(conversationId: String, unreadCount: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", conversationId)

                    if let conversation = try context.fetch(request).first {
                        conversation.unreadCount = Int32(max(0, unreadCount))
                        try context.save()
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "ConversationNotFound", code: -1))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deleteConversation(id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.perform {
                do {
                    let viewCtx = self.coreDataManager.viewContext

                    // 1. Delete all CDMessage rows for this conversation by string ID.
                    let msgFetch: NSFetchRequest<NSFetchRequestResult> = CDMessage.fetchRequest()
                    msgFetch.predicate = NSPredicate(format: "conversationId == %@", id)
                    let msgDelete = NSBatchDeleteRequest(fetchRequest: msgFetch)
                    msgDelete.resultType = .resultTypeObjectIDs
                    if let result = try context.execute(msgDelete) as? NSBatchDeleteResult,
                       let ids = result.result as? [NSManagedObjectID], !ids.isEmpty {
                        NSManagedObjectContext.mergeChanges(
                            fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                            into: [viewCtx, context]
                        )
                    }

                    // 2. Delete CDParticipant rows.
                    let partFetch: NSFetchRequest<NSFetchRequestResult> = CDParticipant.fetchRequest()
                    partFetch.predicate = NSPredicate(format: "conversationId == %@", id)
                    let partDelete = NSBatchDeleteRequest(fetchRequest: partFetch)
                    partDelete.resultType = .resultTypeObjectIDs
                    if let result = try context.execute(partDelete) as? NSBatchDeleteResult,
                       let ids = result.result as? [NSManagedObjectID], !ids.isEmpty {
                        NSManagedObjectContext.mergeChanges(
                            fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                            into: [viewCtx, context]
                        )
                    }

                    // 3. Delete CDConversation (cascade rule will clean up CDConversationSettings).
                    let convFetch: NSFetchRequest<NSFetchRequestResult> = CDConversation.fetchRequest()
                    convFetch.predicate = NSPredicate(format: "id == %@", id)
                    let convDelete = NSBatchDeleteRequest(fetchRequest: convFetch)
                    convDelete.resultType = .resultTypeObjectIDs
                    if let result = try context.execute(convDelete) as? NSBatchDeleteResult,
                       let ids = result.result as? [NSManagedObjectID], !ids.isEmpty {
                        NSManagedObjectContext.mergeChanges(
                            fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                            into: [viewCtx, context]
                        )
                    }

                    // Flush any pending in-memory changes and refresh the view context.
                    if context.hasChanges { try context.save() }

                    AppLogger.debug("ConversationRepository: Deleted conversation \(id) with all messages and participants")
                    continuation.resume()
                } catch {
                    AppLogger.debug("ConversationRepository deleteConversation error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deleteConversations(notIn ids: Set<String>) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    let all = try context.fetch(request)
                    var deleted = 0
                    for conversation in all {
                        guard let id = conversation.id, !ids.contains(id) else { continue }
                        // Keep archived chats — they come from a separate
                        // GET conversations?archived=true fetch and must not be
                        // wiped by the main inbox prune.
                        if conversation.settings?.settingsIsArchived == true
                            || conversation.conversationIsArchived {
                            continue
                        }
                        context.delete(conversation)
                        deleted += 1
                    }
                    if deleted > 0 {
                        try context.save()
                        AppLogger.debug("ChatDataService: Removed \(deleted) stale conversation(s) from database")
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Mark conversation as read using async/await
    func markAsRead(conversationId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", conversationId)

                    if let conversation = try context.fetch(request).first {
                        conversation.unreadCount = 0
                        conversation.updatedAt = Date()
                        try context.save()
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "ConversationNotFound", code: -1))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Mark conversation as unread using async/await
    func markAsUnread(conversationId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", conversationId)

                    if let conversation = try context.fetch(request).first {
                        conversation.unreadCount = max(1, conversation.unreadCount)
                        try context.save()
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "ConversationNotFound", code: -1))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Clear all data using async/await
    func clearAllData() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let conversationRequest: NSFetchRequest<NSFetchRequestResult> = CDConversation.fetchRequest()
                    let conversationDelete = NSBatchDeleteRequest(fetchRequest: conversationRequest)
                    try context.execute(conversationDelete)

                    let messageRequest: NSFetchRequest<NSFetchRequestResult> = CDMessage.fetchRequest()
                    let messageDelete = NSBatchDeleteRequest(fetchRequest: messageRequest)
                    try context.execute(messageDelete)

                    try context.save()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Add participant using async/await
    func addParticipant(conversationId: String, participant: GroupParticipant) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", conversationId)

                    guard let conversation = try context.fetch(request).first else {
                        continuation.resume(throwing: NSError(domain: "ConversationNotFound", code: -1))
                        return
                    }

                    // Check if participant already exists
                    let existingRequest: NSFetchRequest<CDParticipant> = CDParticipant.fetchRequest()
                    existingRequest.predicate = NSPredicate(format: "conversationId == %@ AND userId == %@", conversationId, participant.userId)

                    if try context.fetch(existingRequest).first == nil {
                        let entity = CDParticipant(context: context)
                        entity.id = participant.id
                        entity.conversationId = conversationId
                        entity.userId = participant.userId
                        entity.role = participant.role
                        entity.userName = participant.userName
                        entity.fullName = participant.fullName
                        entity.profilePicture = participant.profilePicture
                        entity.isActive = true
                        entity.verified = participant.isVerified
                        entity.joinedAt = Date()
                        entity.conversation = conversation

                        // Increment participantsCount
                        conversation.participantsCount += 1

                        try context.save()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Remove participant using async/await
    func removeParticipant(conversationId: String, userId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDParticipant> = CDParticipant.fetchRequest()
                    request.predicate = NSPredicate(format: "conversationId == %@ AND userId == %@", conversationId, userId)

                    if let participant = try context.fetch(request).first {
                        context.delete(participant)
                    }

                    // Decrement participantsCount on the conversation
                    let convRequest: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
                    convRequest.predicate = NSPredicate(format: "id == %@", conversationId)
                    if let conversation = try context.fetch(convRequest).first, conversation.participantsCount > 0 {
                        conversation.participantsCount -= 1
                    }

                    try context.save()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Update participant role using async/await
    func updateParticipantRole(conversationId: String, userId: String, newRole: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = coreDataManager.writeContext
            context.performAndWait {
                do {
                    let request: NSFetchRequest<CDParticipant> = CDParticipant.fetchRequest()
                    request.predicate = NSPredicate(format: "conversationId == %@ AND userId == %@", conversationId, userId)

                    if let participant = try context.fetch(request).first {
                        participant.role = newRole
                        try context.save()
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "ParticipantNotFound", code: -1))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func getOrCreateConversationEntity(id: String, in context: NSManagedObjectContext) -> CDConversation {
        let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let entity = CDConversation(context: context)
        entity.id = id
        return entity
    }

    private func createSettingsEntity(for conversation: CDConversation, in context: NSManagedObjectContext) -> CDConversationSettings {
        let settings = CDConversationSettings(context: context)
        settings.conversationId = conversation.id
        // With proper inverse relationships, this automatically sets conversation.settings = settings
        settings.conversation = conversation
        return settings
    }

    // MARK: - Mapping Delegates

    private func convertToChatMessageRow(_ cdConversation: CDConversation) -> ChatMessageRow? {
        ConversationMapper.toDomain(cdConversation, sessionManager: sessionManager)
    }

    private func convertToChatMessageRowSnapshot(_ cdConversation: CDConversation) -> ChatMessageRow {
        ConversationMapper.toDomainSnapshot(cdConversation, sessionManager: sessionManager)
    }

    private func convertToChatMessageRowWithParticipants(_ cdConversation: CDConversation) -> ChatMessageRow? {
        ConversationMapper.toDomain(cdConversation, sessionManager: sessionManager)
    }

    private func updateConversationEntity(_ conversation: CDConversation, from chatRow: ChatMessageRow, context: NSManagedObjectContext) {
        ConversationMapper.update(conversation, from: chatRow, context: context, sessionManager: sessionManager)
    }

    private func applySettings(_ settings: ConversationSettings, to cdSettings: CDConversationSettings) {
        ConversationMapper.applySettings(settings, to: cdSettings)
    }
}

