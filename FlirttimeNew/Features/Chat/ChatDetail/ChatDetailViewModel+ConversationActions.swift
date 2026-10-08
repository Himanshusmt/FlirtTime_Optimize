//
//  ChatDetailViewModel+ConversationActions.swift
//  FlirttimeNew
//

import Foundation
import Combine
import RxSwift
import Swinject

extension ChatDetailViewModel {

    // MARK: - Block / Unblock

    func applyBlockUIState(isBlocked blocked: Bool) {
        isBlocked = blocked
        shouldShowBlockView = blocked
    }

    func unblockUser(userID: String) {
        guard !selectedId.isEmpty else { return }
        let cid = selectedId
        let peerId = userID.isEmpty
            ? (user?.userId ?? headerUserData?.userId ?? user?.id ?? selectedUserChatID)
            : userID

        // Optimistic UI — show input again immediately (FE does not wait for refresh).
        applyBlockUIState(isBlocked: false)
        NotificationCenter.default.post(
            name: .ChatBlockStatusChanged,
            object: nil,
            userInfo: ["conversationId": cid, "isBlocked": false]
        )
        if !peerId.isEmpty {
            BlockedUsersManager.shared.unblockUser(id: peerId)
        }

        // Primary FE path: DELETE users/{id}/block → fans out `user:unblocked`.
        if !peerId.isEmpty {
            let session = userListViewModel.sessionManager
                ?? sessionManager
                ?? Container.sharedContainer.resolve(SessionManager.self)
            _ = session?.unblockUser(id: peerId)
                .observe(on: MainScheduler.instance)
                .subscribe(
                    onSuccess: { [weak self] _ in
                        self?.showSuccess(ChatStrings.chat_userBlocked.localizedString())
                    },
                    onFailure: { error in
                        AppLogger.debug("ChatDetailViewModel: unblockUser API failed: \(error.localizedDescription)")
                    }
                )
                .disposed(by: disposeBag)
        }

        // Keep conversation settings in sync (flat payload — FE console shape).
        let payload: [String: Any] = ["conversationId": cid, "isBlocked": false]
        socketService.emitMessage(
            SocketEvent.updateConversationSettings.rawValue,
            withData: payload
        )
        AppLogger.debug("ChatDetailViewModel: Emitted update-conversation-settings isBlocked=false for \(cid)")
    }

    func blockUserInConversation() {
        guard !selectedId.isEmpty else { return }
        let cid = selectedId
        let blockedUserId = user?.userId ?? headerUserData?.userId ?? user?.id ?? selectedUserChatID

        applyBlockUIState(isBlocked: true)
        NotificationCenter.default.post(
            name: .ChatBlockStatusChanged,
            object: nil,
            userInfo: ["conversationId": cid, "isBlocked": true]
        )
        if !blockedUserId.isEmpty {
            BlockedUsersManager.shared.blockUser(id: blockedUserId)
            let session = userListViewModel.sessionManager
                ?? sessionManager
                ?? Container.sharedContainer.resolve(SessionManager.self)
            let myId = getCurrentUserId()
            _ = session?.blockUser(id: blockedUserId, userId: myId)
                .observe(on: MainScheduler.instance)
                .subscribe(
                    onSuccess: { [weak self] _ in
                        self?.showSuccess(ChatStrings.chat_userBlocked.localizedString())
                    },
                    onFailure: { error in
                        AppLogger.debug("ChatDetailViewModel: blockUser API failed: \(error.localizedDescription)")
                    }
                )
                .disposed(by: disposeBag)
        }

        let payload: [String: Any] = ["conversationId": cid, "isBlocked": true]
        socketService.emitMessage(
            SocketEvent.updateConversationSettings.rawValue,
            withData: payload
        )
        AppLogger.debug("ChatDetailViewModel: Emitted update-conversation-settings isBlocked=true for \(cid)")
    }

    // MARK: - Delete Chat

    func deleteChat(id: String) {
        guard !id.isEmpty else { return }
        let cid = id
        // Clean up linked data before deleting.
        ConversationDraftStore.shared.remove(conversationId: cid)
        PendingMessageStore.shared.removeAll(for: cid)
        ChatDataPreloader.shared.consumePreloadedMessages(for: cid)
        ChatDataPreloader.shared.storePinState(for: cid, message: nil)

        let session = userListViewModel.sessionManager
            ?? Container.sharedContainer.resolve(SessionManager.self)
        _ = session?.deleteChatConversation(id: cid, scope: "me")
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] in
                    Task { [weak self] in
                        guard let self else { return }
                        try? await self.conversationRepository?.deleteConversation(id: cid)
                        await MainActor.run {
                            self.onConversationDeleted?()
                        }
                    }
                },
                onFailure: { [weak self] _ in
                    // Fallback to socket if REST fails
                    ChatListSocketService.shared.emitDeleteConversation(conversationId: cid)
                    Task { [weak self] in
                        guard let self else { return }
                        try? await self.conversationRepository?.deleteConversation(id: cid)
                        await MainActor.run {
                            self.onConversationDeleted?()
                        }
                    }
                }
            )
            .disposed(by: disposeBag)
    }

    // MARK: - Fetch All Media Messages

    func fetchAllMediaMessages() async -> [ConversationMessage] {
        let conversationId = selectedId
        guard !conversationId.isEmpty else { return messages }
        do {
            let allMedia = try await messageRepository.getAllMediaMessages(for: conversationId)
            return allMedia.isEmpty ? messages : allMedia
        } catch {
            AppLogger.debug("fetchAllMediaMessages failed: \(error)")
            return messages
        }
    }

    // MARK: - Message Status Update (Real-time)

    func handleMessageStatusUpdate(messageId: String, status: MessageDeliveryStatus) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
            AppLogger.debug("ChatDetailViewModel: Status update for unknown message \(messageId)")
            return
        }

        let currentMessage = messages[index]
        let updatedMessage = currentMessage.withStatus(status)
        messages[index] = updatedMessage
        stateManager.replaceMessage(tempId: messageId, with: updatedMessage)
        AppLogger.debug("ChatDetailViewModel: Updated message \(messageId) status to \(status.rawValue)")
    }

    func handleConversationMessageStatusUpdate(_ payload: MessageStatusUpdatePayload) {
        guard payload.conversationId == selectedId else { return }

        let deliveryStatus = MessageDeliveryStatus.from(payload.status)
        guard deliveryStatus != .unknown else { return }

        var updatedMessages: [ConversationMessage] = []
        let myId = getCurrentUserId()

        // FE ConversationThreadPage.onSeen / onDelivered: advance all own outbound
        // messages in the thread (ignores specific messageId). That also covers the
        // race where seen arrives before the optimistic temp id is swapped to server id.
        let snapshot = stateManager.getGroupedMessagesSnapshot().flatMap(\.messages)
        let ownOutboundIds: [String] = snapshot.compactMap { msg in
            if msg.isSystemMessage { return nil }
            let sender = msg.senderId ?? msg.sender?.id ?? ""
            guard sender == myId else { return nil }
            let status = (msg.status ?? "").lowercased()
            guard status != "failed" else { return nil }
            return msg.id
        }

        let targetIds: [String]
        if deliveryStatus == .read || deliveryStatus == .delivered || payload.messageIds.isEmpty {
            var ids = Set(ownOutboundIds)
            // Explicit server ids from the socket payload (may arrive before/without senderId match)
            for mid in payload.messageIds where !mid.isEmpty {
                ids.insert(mid)
            }
            targetIds = Array(ids)
        } else {
            targetIds = payload.messageIds
        }

        var touchedIds = Set(payload.messageIds.filter { !$0.isEmpty })
        touchedIds.formUnion(targetIds)

        registerPendingDeliveryStatus(deliveryStatus, for: Array(touchedIds))

        for messageId in targetIds {
            guard let existing = stateManager.messageById(messageId) else {
                if deliveryStatus == .sent || deliveryStatus == .delivered || deliveryStatus == .read {
                    cancelTimeoutForUnmatchedTempMessage(serverMessageId: messageId)
                    // Seen/delivered may arrive for server id before temp swap — upgrade matching temps
                    for (tempId, tempMsg) in tempMessageMapping
                    where tempMsg.conversationId == selectedId {
                        let sender = tempMsg.senderId ?? tempMsg.sender?.id ?? ""
                        guard sender == myId else { continue }
                        let currentStatus = MessageDeliveryStatus.from(
                            status: tempMsg.status,
                            sentAt: tempMsg.sentAt,
                            deliveredAt: tempMsg.deliveredAt,
                            seenAt: tempMsg.seenAt
                        )
                        guard deliveryStatus > currentStatus else { continue }
                        var updated = tempMsg.withStatus(deliveryStatus)
                        stateManager.updateMessage(updated)
                        tempMessageMapping[tempId] = updated
                        updatedMessages.append(updated)
                        registerPendingDeliveryStatus(deliveryStatus, for: [tempId, messageId])
                    }
                }
                continue
            }

            // Only upgrade ticks on messages we sent
            let sender = existing.senderId ?? existing.sender?.id ?? ""
            guard sender == myId else { continue }

            let currentStatus = MessageDeliveryStatus.from(
                status: existing.status,
                sentAt: existing.sentAt,
                deliveredAt: existing.deliveredAt,
                seenAt: existing.seenAt
            )
            guard deliveryStatus > currentStatus else { continue }

            var updated = existing.withStatus(deliveryStatus)
            updated.statuses = Self.mergeStatusUpdates(
                existing: updated.statuses,
                deliveredTo: payload.deliveredTo,
                seenBy: payload.seenBy,
                currentUserId: myId,
                deliveryStatus: deliveryStatus,
                messageId: messageId,
                conversationId: payload.conversationId
            )
            updatedMessages.append(updated)
            messageSyncCoordinator.persist(messages: [updated])
            registerPendingDeliveryStatus(deliveryStatus, for: [messageId])
            if let serverId = tempMessageMapping[messageId]?.id, !serverId.isEmpty, serverId != messageId {
                registerPendingDeliveryStatus(deliveryStatus, for: [serverId])
            }
            for (tempId, tempMsg) in tempMessageMapping where tempMsg.id == messageId || tempId == messageId {
                registerPendingDeliveryStatus(deliveryStatus, for: [tempId, tempMsg.id])
            }
        }

        // Explicit server ids that are not yet in the list (still temp) — cancel send timeout
        for messageId in payload.messageIds where stateManager.messageById(messageId) == nil {
            if deliveryStatus == .sent || deliveryStatus == .delivered || deliveryStatus == .read {
                cancelTimeoutForUnmatchedTempMessage(serverMessageId: messageId)
            }
        }

        if !updatedMessages.isEmpty {
            stateManager.batchUpdateMessages(updatedMessages)
            // Keep UI list in sync immediately (FRC may lag / race)
            let groups = applyPendingStatusUpdates(to: stateManager.getGroupedMessagesSnapshot())
            groupedMessages = groups
            messages = groups.flatMap(\.messages)
        }

        let idsToClear = Array(touchedIds)
        Task { [weak self] in
            // Give CoreData persist a moment, then drop pending overrides
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                guard let self else { return }
                for id in idsToClear {
                    if self.pendingStatusUpdates[id] == deliveryStatus {
                        self.pendingStatusUpdates.removeValue(forKey: id)
                    }
                }
            }
        }

        AppLogger.debug("[StatusUpdate] Applied \(deliveryStatus.rawValue) to \(targetIds.count) messages in \(payload.conversationId)")
    }

    static func mergeStatusUpdates(
        existing: [MessageStatus]?,
        deliveredTo: [String],
        seenBy: String?,
        currentUserId: String,
        deliveryStatus: MessageDeliveryStatus,
        messageId: String,
        conversationId: String
    ) -> [MessageStatus] {
        let now = ISO8601DateFormatter().string(from: Date())
        var statuses = existing ?? []

        let deliveredStatusRaw = deliveryStatus >= .delivered ? "delivered" : deliveryStatus.rawValue

        var upgrades: [(userId: String, status: String)] =
            deliveredTo.filter { $0 != currentUserId }.map { ($0, deliveredStatusRaw) }
        if let seen = seenBy, seen != currentUserId, deliveryStatus >= .read {
            upgrades.append((seen, "seen"))
        }

        for (userId, newStatusRaw) in upgrades {
            let newPriority = MessageDeliveryStatus.from(newStatusRaw)
            if let idx = statuses.firstIndex(where: { $0.userId == userId }) {
                let existingPriority = MessageDeliveryStatus.from(statuses[idx].status)
                if newPriority > existingPriority {
                    statuses[idx] = MessageStatus(
                        id: statuses[idx].id,
                        messageId: statuses[idx].messageId,
                        conversationId: statuses[idx].conversationId,
                        userId: userId,
                        status: newStatusRaw,
                        statusUpdatedAt: now,
                        isDeletedForUser: statuses[idx].isDeletedForUser,
                        updatedAt: now,
                        createdAt: statuses[idx].createdAt
                    )
                }
            } else {
                statuses.append(MessageStatus(
                    id: nil,
                    messageId: messageId,
                    conversationId: conversationId,
                    userId: userId,
                    status: newStatusRaw,
                    statusUpdatedAt: now,
                    isDeletedForUser: nil,
                    updatedAt: now,
                    createdAt: now
                ))
            }
        }

        return statuses
    }

    func cancelTimeoutForUnmatchedTempMessage(serverMessageId: String) {
        guard !tempMessageMapping.isEmpty else { return }

        for (tempId, tempMsg) in tempMessageMapping {
            let isSameConversation = tempMsg.conversationId == selectedId
            let isStillSending = {
                let s = (tempMsg.status ?? "").lowercased()
                return s != "failed" && s != "delivered" && s != "seen" && s != "read"
            }()
            guard isSameConversation, isStillSending else { continue }

            if tempMsg.id == serverMessageId {
                backgroundTasks[tempId]?.cancel()
                backgroundTasks.removeValue(forKey: tempId)
                AppLogger.debug("[StatusUpdate] Cancelled failure timeout for tempId=\(tempId) (serverId=\(serverMessageId))")
                return
            }
        }

        let recentTemp = tempMessageMapping
            .filter { $0.value.conversationId == selectedId && $0.value.status == "sending" }
            .sorted { ($0.value.createdAt) > ($1.value.createdAt) }
            .first
        if let (tempId, _) = recentTemp {
            backgroundTasks[tempId]?.cancel()
            backgroundTasks.removeValue(forKey: tempId)
            AppLogger.debug("[StatusUpdate] Cancelled failure timeout for most recent tempId=\(tempId) (serverId=\(serverMessageId))")
        }
    }

    func handleMessageStatusMessageUpdate(_ message: ConversationMessage) {
        let messageId = message.id
        let conversationId = message.conversationId
        if !conversationId.isEmpty, conversationId != selectedId {
            return
        }

//        if let index = messages.firstIndex(where: { $0.id == messageId }) {
//            messages[index] = message
//            stateManager.replaceMessage(tempId: messageId, with: message)
//        }
        if let index = messages.firstIndex(where: {
            $0.id == message.id
        }) {

            messages[index].isDeleted = true
            if let content = message.content, !content.isEmpty {
                messages[index].content = content
            }
            messages[index].status = "deleted"
        }
        else if conversationId == selectedId {
            stateManager.addMessages([message])
        }
    }

    // MARK: - Conversation helpers

    func getCurrentUserId() -> String {
        return userListViewModel.sessionManager?.user?.userId ?? ""
    }

    func updateBottomVisibility(isAtBottom: Bool) {
        self.isAtBottom = isAtBottom
        if isAtBottom {
            offBottomNewMessageIds.removeAll()
        }
    }

    func registerOffBottomNewMessage(_ message: ConversationMessage) {
        guard !isAtBottom else { return }
        guard !message.id.isEmpty else { return }
        guard (message.sender?.id ?? message.senderId) != getCurrentUserId() else { return }
        offBottomNewMessageIds.insert(message.id)
    }

    func clearOffBottomNewMessageBadge() {
        offBottomNewMessageIds.removeAll()
    }

    func canDeleteForEveryone(message: ConversationMessage) -> Bool {
        if isChannel && isChannelAdmin { return true }
        let senderId = message.sender?.id ?? message.senderId ?? ""
        return !senderId.isEmpty && senderId == getCurrentUserId()
    }

    func setHeaderUserData(_ user: UserRes) {
        headerUserData = user
    }

    func setStoryData(_ storyData: OtherStoryResponseModel?, selfStoryData: StoryResponseModel?) {
        self.storyData = storyData
        self.selfUserStoryData = selfStoryData
    }

    func getReportReasons() {
//        userListViewModel.getReportReasons()
    }

    // MARK: - Message Info

    /// NEW API — GET `chat/messages/{messageId}/info`
    func fetchMessageInfo(
        messageId: String,
        completion: @escaping (Result<MessageInfoData, Error>) -> Void
    ) {
        guard !messageId.isEmpty else {
            completion(.failure(APIError.apiError("Invalid message id")))
            return
        }
        let session = userListViewModel.sessionManager
            ?? sessionManager
            ?? Container.sharedContainer.resolve(SessionManager.self)
        guard let session else {
            completion(.failure(APIError.apiError("Session unavailable")))
            return
        }

        session.messageInfo(messageId: messageId)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { response in
                    if let data = response.data {
                        completion(.success(data))
                    } else {
                        completion(.failure(APIError.apiError(response.message ?? "Message info unavailable")))
                    }
                },
                onFailure: { error in
                    AppLogger.debug("[MessageInfo] failed: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            )
            .disposed(by: disposeBag)
    }
}
