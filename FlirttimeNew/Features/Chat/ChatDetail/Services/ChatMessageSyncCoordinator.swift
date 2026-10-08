//
//  ChatMessageSyncCoordinator.swift
//  FlirttimeNew
//
//  Created by Awais on 30/09/25.
//

import Foundation

final class ChatMessageSyncCoordinator {

    private let messageRepository: MessageRepositoryAsync
    private let stateManager: ChatStateManagerProtocol

    init(messageRepository: MessageRepositoryAsync,
         stateManager: ChatStateManagerProtocol) {
        self.messageRepository = messageRepository
        self.stateManager = stateManager
    }

    func bootstrapState(conversationId: String,
                        pageSize: Int,
                        temporaryMessages: [ConversationMessage]) {
        DispatchQueue.main.async { [weak self] in
            self?.stateManager.setMessages(temporaryMessages)
        }
    }

    func appendCachedMessages(conversationId: String,
                              page: Int,
                              pageSize: Int) {
    }

    func refreshWithNetworkPage(_ newMessages: [ConversationMessage],
                                page: Int,
                                temporaryMessages: [ConversationMessage]) {
        guard !newMessages.isEmpty || !temporaryMessages.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if page == 1 {
                // Preserve in-flight / just-acked live tail so a late page-1 response
                // does not wipe an optimistic or newly sent bubble (causes top→bottom jump).
                let existing = self.stateManager.getGroupedMessagesSnapshot().flatMap(\.messages)
                let pageIds = Set(newMessages.map(\.id))
                let pageStableIds = Set(newMessages.map(\.stableId))
                let tempIds = Set(temporaryMessages.map(\.id))
                let newestPageCreatedAt = newMessages.map(\.createdAt).max() ?? ""

                let liveExtras = existing.filter { msg in
                    if pageIds.contains(msg.id) || pageStableIds.contains(msg.stableId) { return false }
                    if tempIds.contains(msg.id) { return false }
                    let status = (msg.status ?? "").lowercased()
                    if status == "sending" || status == "pending" || status == "failed" {
                        return true
                    }
                    if !newestPageCreatedAt.isEmpty, msg.createdAt > newestPageCreatedAt {
                        return true
                    }
                    return false
                }

                self.stateManager.setMessages(newMessages + temporaryMessages + liveExtras)
            } else {
                self.stateManager.addMessages(newMessages)
            }
        }
    }

    func persist(messages: [ConversationMessage], conversationId: String? = nil) {
        guard !messages.isEmpty else { return }
        let repo = messageRepository
        Task {
            do {
                try await repo.saveMessages(messages, conversationId: conversationId)
                AppLogger.debug("ChatMessageSyncCoordinator: Successfully persisted \(messages.count) messages to CoreData")
            } catch {
                AppLogger.debug("ChatMessageSyncCoordinator: Failed to persist messages - \(error.localizedDescription)")
            }
        }
    }

    func deleteMessage(id: String) {
        let repo = messageRepository
        Task {
            do {
                try await repo.deleteMessage(id: id)
                AppLogger.debug("ChatMessageSyncCoordinator: Successfully deleted message \(id) from CoreData")
            } catch {
                AppLogger.debug("ChatMessageSyncCoordinator: Failed to delete message \(id) - \(error.localizedDescription)")
            }
        }
    }

    func hardDeleteMessage(id: String) {
        let repo = messageRepository
        Task {
            do {
                try await repo.hardDeleteMessage(id: id)
                AppLogger.debug("ChatMessageSyncCoordinator: Successfully hard-deleted message \(id) from CoreData")
            } catch {
                AppLogger.debug("ChatMessageSyncCoordinator: Failed to hard-delete message \(id) - \(error.localizedDescription)")
            }
        }
    }
}
