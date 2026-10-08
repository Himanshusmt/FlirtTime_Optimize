//
//  ChatDetailViewModel+Selection.swift
//  FlirttimeNew
//

import SwiftUI

extension ChatDetailViewModel {

    // MARK: - ID Resolution

    /// Resolve selection / UI ids (`stableId` / `clientTempId`) to server `message.id`
    /// from the send response (`data.message.id`). Never return clientTempId as a server id.
    private func resolveSelectedIds(_ rawIds: [String]) -> (serverIds: [String], pendingIds: [String]) {
        var serverIds: [String] = []
        var pendingIds: [String] = []
        var seenServer = Set<String>()
        var seenPending = Set<String>()

        for rawId in rawIds {
            let trimmed = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let pendingKey = pendingSelectionKey(for: trimmed) {
                if seenPending.insert(pendingKey).inserted {
                    pendingIds.append(pendingKey)
                }
                continue
            }

            if let serverId = resolveServerMessageId(trimmed), seenServer.insert(serverId).inserted {
                serverIds.append(serverId)
            } else {
                AppLogger.debug("[Selection] Could not resolve server message id for selectionId=\(trimmed.prefix(8))")
            }
        }
        return (serverIds, pendingIds)
    }

    /// Still-sending optimistic message keyed by `clientTempId` / temp mapping.
    private func pendingSelectionKey(for id: String) -> String? {
        if tempMessageMapping[id] != nil { return id }
        guard let msg = findMessage(forSelectionId: id) else { return nil }
        let clientTemp = (msg.metadata?["clientTempId"]?.value as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !clientTemp.isEmpty, tempMessageMapping[clientTemp] != nil {
            return clientTemp
        }
        let status = (msg.status ?? "").lowercased()
        let stillSending = msg.isOptimisticTemporary
            || status == "sending"
            || status == "pending"
            || (!clientTemp.isEmpty && msg.id == clientTemp)
        return stillSending ? (clientTemp.isEmpty ? msg.stableId : clientTemp) : nil
    }

    /// Look up message by server id, stableId, or clientTempId.
    private func findMessage(forSelectionId id: String) -> ConversationMessage? {
        if let msg = stateManager.messageById(id) { return msg }
        let liveMessages = stateManager.getGroupedMessagesSnapshot().flatMap(\.messages)
        if let msg = liveMessages.first(where: { $0.id == id || $0.stableId == id }) {
            return msg
        }
        if let msg = liveMessages.first(where: {
            ($0.metadata?["clientTempId"]?.value as? String) == id
        }) {
            return msg
        }
        return messages.first(where: {
            $0.id == id
                || $0.stableId == id
                || ($0.metadata?["clientTempId"]?.value as? String) == id
        })
    }

    /// Maps a selection id to the API `message.id` (UUID from create response).
    func resolveServerMessageId(_ id: String) -> String? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let msg = findMessage(forSelectionId: trimmed) {
            let serverId = msg.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let clientTemp = (msg.metadata?["clientTempId"]?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Prefer `data.message.id` — never clientTempId / optimistic id.
            // Selection UI keys off stableId (== clientTempId after send), so we must map it.
            if !serverId.isEmpty,
               isValidServerMessageId(serverId),
               serverId != clientTemp,
               !serverId.hasPrefix("temp") {
                return serverId
            }
            return nil
        }

        // No local row — do NOT treat a bare UUID as a server id (selection keys are
        // clientTempId UUIDs). Allow legacy Mongo ObjectIds only.
        if isValidMongoObjectId(trimmed), tempMessageMapping[trimmed] == nil {
            return trimmed
        }
        return nil
    }

    /// OLD Mongo ObjectId (24 hex) or NEW API UUID message ids.
    func isValidMongoObjectId(_ id: String) -> Bool {
        id.count == 24 && id.allSatisfy { $0.isHexDigit }
    }

    func isValidServerMessageId(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if isValidMongoObjectId(trimmed) { return true }
        return UUID(uuidString: trimmed) != nil
    }

    // MARK: - Forward

    func handleForwardMessagesREST(_ messages: [ConversationMessage]) {
        var addedToCurrentChat = false
        for message in messages {
            let belongsHere = isChannel
                ? (message.conversationId == channelId || message.channelId == channelId)
                : (message.conversationId == selectedId)

            AppLogger.debug("[Forward] REST message id=\(message.id.prefix(8)) conversationId=\(message.conversationId.prefix(8)) belongsHere=\(belongsHere)")

            if belongsHere {
                stateManager.addMessages([message])
                messageSyncCoordinator.persist(messages: [message])
                addedToCurrentChat = true
            }
        }

        if addedToCurrentChat {
            shouldAutoScroll = true
            let snapshot = stateManager.getGroupedMessagesSnapshot()
            if snapshot != groupedMessages {
                groupedMessages = snapshot
                handleMessageListUpdate(snapshot.flatMap { $0.messages })
            }
        }

        showToastMessage(ChatStrings.chat_successMessageForwarded.localizedString())
    }

    func handleForwardMessageAck(_ response: [String: Any]) {
        guard let status = response["status"] as? Bool, status == true else {
            let errorMsg = response["message"] as? String ?? ChatStrings.chat_errorForwardFailed.localizedString()
            showToastMessage(errorMsg)
            return
        }

        if let forwardedItems = response["data"] as? [[String: Any]] {
            var addedToCurrentChat = false
            for item in forwardedItems {
                let msgData = (item["data"] as? [String: Any]) ?? item

                guard let message = ConversationMessage.fromDictionary(msgData) else {
                    AppLogger.debug("[Forward] fromDictionary failed for messageId: \(item["messageId"] ?? item["id"] ?? "unknown") — keys: \(msgData.keys)")
                    continue
                }

                let belongsHere = isChannel
                    ? (message.conversationId == channelId || message.channelId == channelId)
                    : (message.conversationId == selectedId)

                AppLogger.debug("[Forward] parsed message id=\(message.id.prefix(8)) conversationId=\(message.conversationId.prefix(8)) selectedId=\(selectedId.prefix(8)) belongsHere=\(belongsHere)")

                if belongsHere {
                    stateManager.addMessages([message])
                    messageSyncCoordinator.persist(messages: [message])
                    addedToCurrentChat = true
                }
            }

            if addedToCurrentChat {
                shouldAutoScroll = true
                let snapshot = stateManager.getGroupedMessagesSnapshot()
                if snapshot != groupedMessages {
                    groupedMessages = snapshot
                    handleMessageListUpdate(snapshot.flatMap { $0.messages })
                }
            }
        }

        showToastMessage(ChatStrings.chat_successMessageForwarded.localizedString())
    }

    func forwardSelectedMessages(to userIds: [String], filteredIds: [String]? = nil) {
        let rawIds = filteredIds ?? Array(selection.selectedMessageIds)
        let (serverIds, _) = resolveSelectedIds(rawIds)

        clearSelection()
        exitSelectionMode()

        guard !serverIds.isEmpty else {
            showToastMessage(ChatStrings.chat_errorNotDelivered.localizedString())
            return
        }
        AppLogger.debug("[Forward] resolved serverIds=\(serverIds) from selection count=\(rawIds.count)")
        forwardMessage(messageIds: serverIds, receiverIds: userIds)
    }

    // MARK: - Delete

    /// Multi-select delete — POST `chat/messages/delete` `{ messageIds, scope: me|everyone }`.
    /// Optimistic UI first; socket used only as fallback if REST fails.
    func deleteSelectedMessages(forEveryone: Bool) {
        let rawIds = Array(selection.selectedMessageIds)
        let (serverIds, pendingIds) = resolveSelectedIds(rawIds)

        clearSelection()
        exitSelectionMode()

        for tempId in pendingIds {
            backgroundTasks[tempId]?.cancel()
            backgroundTasks.removeValue(forKey: tempId)
            tempMessageMapping.removeValue(forKey: tempId)
            PendingMessageStore.shared.remove(tempId: tempId)
            BackgroundUploadService.shared.cancel(tempId: tempId)
        }

        for id in pendingIds {
            silentlyUnpinIfPinned(messageId: id)
            locallyDeletedMessageIds.insert(id)
            removeMessageFromUI(messageId: id)
            messageSyncCoordinator.hardDeleteMessage(id: id)
        }

        let deletedContent = ChatStrings.chat_messageDeleted.localizedString()
        for id in serverIds {
            silentlyUnpinIfPinned(messageId: id)
            if forEveryone, let existing = stateManager.messageById(id) {
                var tombstone = existing
                tombstone.isDeleted = true
                tombstone.status = "deleted"
                tombstone.content = deletedContent
                handleMessageDeleted(tombstone)
                messageSyncCoordinator.deleteMessage(id: id)
            } else {
                locallyDeletedMessageIds.insert(id)
                removeMessageFromUI(messageId: id)
                messageSyncCoordinator.hardDeleteMessage(id: id)
            }
        }

        refreshConversationLastMessageAfterBatchDelete(deletedMessageIds: serverIds + pendingIds)

        let scope = forEveryone ? "everyone" : "me"
        if !serverIds.isEmpty {
            AppLogger.debug(
                "[Delete] ▶ POST chat/messages/delete count=\(serverIds.count) scope=\(scope) ids=\(serverIds) (multi-select)"
            )
            messageService.deleteMessages(messageIds: serverIds, scope: scope)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak self] completion in
                        if case .failure(let error) = completion {
                            AppLogger.debug(
                                "[Delete] multi-select scope=\(scope) failed: \(error.localizedDescription) — socket fallback"
                            )
                            self?.emitDeleteMessagesSocket(messageIds: serverIds, forEveryone: forEveryone)
                        }
                    },
                    receiveValue: { _ in
                        AppLogger.debug("[Delete] ✅ multi-select scope=\(scope) count=\(serverIds.count)")
                    }
                )
                .store(in: &cancellables)
        }

        let totalCount = serverIds.count + pendingIds.count
        showToastMessage(totalCount > 1 ? ChatStrings.chat_messagesDeleted.localizedString() : ChatStrings.chat_messageDeleted.localizedString())
    }

    /// Socket fallback — FE `chat:message:delete` with `{ messageIds, scope }` (web parity).
    func emitDeleteMessagesSocket(messageIds: [String], forEveryone: Bool) {
        guard !messageIds.isEmpty else { return }
        let scope = forEveryone ? "everyone" : "me"
        var payload: [String: Any] = [
            "messageIds": messageIds,
            "scope": scope,
            "forEveryone": forEveryone
        ]
        if !selectedId.isEmpty {
            payload["conversationId"] = selectedId
        }
        ChatSocketManager.shared.emitMessage(
            SocketEvent.deleteConversationMessage.rawValue,
            withData: [payload]
        )
        AppLogger.debug(
            "[Delete] ▶ socket fallback \(SocketEvent.deleteConversationMessage.rawValue) messageIds=\(messageIds.count) scope=\(scope)"
        )
    }

    // MARK: - Selection State

    func toggleSelectionMode() {
        selection.isSelectionMode.toggle()
        if !selection.isSelectionMode {
            selection.selectedMessageIds.removeAll()
        }
    }

    func enterSelectionMode(with messageId: String) {
        cancelReply()
        cancelEdit()
        selection.isSelectionMode = true
        selection.selectedMessageIds.insert(messageId)
    }

    func toggleMessageSelection(_ messageId: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 1.8)) {
            if selection.selectedMessageIds.contains(messageId) {
                selection.selectedMessageIds.remove(messageId)
            } else {
                selection.selectedMessageIds.insert(messageId)
            }
        }
    }

    func isSelected(_ messageId: String) -> Bool {
        selection.selectedMessageIds.contains(messageId)
    }

    func selectAllMessages() {
        let allIds = Set(messages.map(\.stableId).filter { !$0.isEmpty })
        withAnimation(.spring(response: 0.25, dampingFraction: 1.8)) {
            selection.selectedMessageIds = allIds
        }
    }

    func clearSelection() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            selection.selectedMessageIds.removeAll()
        }
    }

    func exitSelectionMode() {
        selection.isSelectionMode = false
        selection.selectedMessageIds.removeAll()
    }

    func canDeleteForEveryoneSelected() -> Bool {
        guard !selection.selectedMessageIds.isEmpty else { return false }
        if isChannel && isChannelAdmin { return true }
        let currentUserId = getCurrentUserId()
        guard !currentUserId.isEmpty else { return false }
        return selection.selectedMessageIds.allSatisfy { selectedId in
            let msg = message(byId: selectedId)
                ?? messages.first(where: { $0.id == selectedId || $0.stableId == selectedId })
            guard let message = msg else { return false }
            let senderId = message.sender?.id ?? message.senderId ?? ""
            return senderId == currentUserId
        }
    }
}
