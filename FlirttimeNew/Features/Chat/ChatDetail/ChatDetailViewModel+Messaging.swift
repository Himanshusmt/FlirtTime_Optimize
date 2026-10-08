//
//  ChatDetailViewModel+Messaging.swift
//  FlirttimeNew
//
//  Created by Awais on 30/09/25.
//

import Foundation
import Combine
import RxSwift
import Swinject

extension ChatDetailViewModel {

    func sendMessage(text: String, mentions: [String] = [], socketMentions: [String] = [], isContact: Bool = false, contactMeta: [String: String]? = nil) {
        guard !text.isEmpty else { return }
        guard !isBlocked, !shouldShowBlockView else {
            handleError(.userBlockedError, context: "sendMessage.blocked")
            return
        }

        userStoppedTyping()

        if selectedId.isEmpty && !isChannel {
            ensureConversationReady { [weak self] success in
                guard let self = self else { return }
                if success {
                    self.sendMessage(text: text, mentions: mentions, socketMentions: socketMentions, isContact: isContact, contactMeta: contactMeta)
                } else {
                    self.handleError(.messageUploadFailed, context: "sendMessage.ensureConversationReady")
                }
            }
            return
        }

        let tempId = UUID().uuidString
        var tempMessage = createTemporaryTextMessage(tempId: tempId, content: text, replyTo: replyingToMessage)

        if !mentions.isEmpty {
            var meta = tempMessage.metadata ?? [:]
            meta["mentions"] = AnyCodable(mentions)
            tempMessage.metadata = meta
        }

        if isContact {
            var meta = tempMessage.metadata ?? [:]
            meta["isContact"] = AnyCodable(true)
            if let cm = contactMeta {
                meta["contactName"] = AnyCodable(cm["contactName"] ?? "")
                meta["contactPhone"] = AnyCodable(cm["contactPhone"] ?? "")
            }
            tempMessage.metadata = meta
        }

        stateManager.addMessages([tempMessage])
        tempMessageMapping[tempId] = tempMessage
        PendingMessageStore.shared.save(tempId: tempId, message: tempMessage, conversationId: selectedId)

        // Bypass throttle — push optimistic message to UI immediately
        let snapshot = stateManager.getGroupedMessagesSnapshot()
        if snapshot != groupedMessages {
            groupedMessages = snapshot
            handleMessageListUpdate(snapshot.flatMap { $0.messages })
        }

        shouldAutoScroll = true

        let replyToId = replyingToMessage?.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedReplyToId = (replyToId?.isEmpty == false) ? replyToId : nil

        AppLogger.debug("""
            [MESSAGE SEND] ▶ REST POST chat/messages conversationId=\(selectedId)
              tempId        = \(tempId)
              body          = "\(text)"
              replyToId     = \(resolvedReplyToId ?? "nil")
              optimistic mentions (bubble) = \(mentions)
              socket mentions (payload)    = \(socketMentions)
            """)

        if ChatMockSeeder.isMockMode {
            let sentMessage = ChatMockSeeder.sentCopy(of: tempMessage)
            replaceTemporaryMessage(tempId: tempId, with: sentMessage)
            updateConversationLastMessage(sentMessage)
            replyingToMessage = nil
            return
        }

        let started = messageService.sendViaREST(
            conversationId: selectedId,
            type: "text",
            body: text,
            mediaIds: nil,
            location: nil,
            poll: nil,
            clientMessageId: tempId,
            replyToId: resolvedReplyToId
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let serverMessage):
                self.replaceTemporaryMessage(tempId: tempId, with: serverMessage)
            case .failure:
                self.markMessageAsFailed(tempId: tempId)
            }
        }

        AppLogger.debug("[MESSAGE SEND] sendViaREST started=\(started) tempId=\(tempId) replyToId=\(resolvedReplyToId ?? "nil")")

        if !started {
            markMessageAsFailed(tempId: tempId)
        }

        replyingToMessage = nil
        scheduleFailureTimeout(for: tempId)
    }

    func sendPoll(pollData: PollCreationData) {
        guard !isBlocked, !shouldShowBlockView else {
            handleError(.userBlockedError, context: "sendPoll.blocked")
            return
        }
        if selectedId.isEmpty && !isChannel {
            ensureConversationReady { [weak self] success in
                guard let self = self, success else {
                    self?.handleError(.messageUploadFailed, context: "sendPoll")
                    return
                }
                self.sendPoll(pollData: pollData)
            }
            return
        }

        let tempId = UUID().uuidString

        let pollOptions = pollData.validOptions.map { text -> [String: Any] in
            return [
                "text": text,
                "option_id": UUID().uuidString,
                "vote_count": 0,
                "votes": [] as [[String: Any]]
            ]
        }

        let pollDict: [String: Any] = [
            "question": pollData.question,
            "options": pollOptions,
            "settings": [
                "multiple_answers": pollData.allowMultipleAnswers,
                "anonymous": pollData.isAnonymous
            ] as [String: Any],
            "totalVotes": 0,
            "createdBy": getCurrentUserId(),
            "myOptionIds": [] as [String],
            "isClosed": false
        ]

        var messageDict: [String: Any] = [
            "id": tempId,
            "conversationId": selectedId,
            "content": pollData.question,
            "messageType": "poll",
            "senderId": getCurrentUserId(),
            "createdAt": isoFormatter.string(from: Date()),
            "updatedAt": isoFormatter.string(from: Date()),
            "isEdited": false,
            "isDeleted": false,
            "status": "sending",
            "poll": pollDict
        ]

        if let r = replyingToMessage {
            let senderId = r.sender?.id ?? r.senderId ?? ""
            let resolved = resolvedDisplayName(for: senderId)
            let senderFullName = [r.sender?.fullName, resolved]
                .first(where: { !($0 ?? "").isEmpty }) ?? ""
            let senderUserName = [r.sender?.userName, resolved]
                .first(where: { !($0 ?? "").isEmpty }) ?? ""
            messageDict["replyToId"] = [
                "id": r.id,
                "content": r.content ?? "",
                "type": r.messageType ?? r.type ?? "text",
                "sender": [
                    "id": senderId,
                    "userName": senderUserName,
                    "fullName": senderFullName
                ]
            ] as [String: Any]
        }

        if let tempMessage = ConversationMessage.fromDictionary(messageDict) {
            stateManager.addMessages([tempMessage])
            tempMessageMapping[tempId] = tempMessage
            PendingMessageStore.shared.save(tempId: tempId, message: tempMessage, conversationId: selectedId)
            shouldAutoScroll = true
            scheduleFailureTimeout(for: tempId)
        }

        let pollPayload: [String: Any] = [
            "question": pollData.question,
            "options": pollData.validOptions,
            "allowMultiple": pollData.allowMultipleAnswers
        ]
        let replyToId = replyingToMessage?.id

        AppLogger.debug("Sending poll via REST tempId=\(tempId)")

        let started = messageService.sendViaREST(
            conversationId: selectedId,
            type: "poll",
            body: pollData.question,
            mediaIds: nil,
            location: nil,
            poll: pollPayload,
            clientMessageId: tempId,
            replyToId: replyToId
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let serverMessage):
                self.replaceTemporaryMessage(tempId: tempId, with: serverMessage)
            case .failure:
                self.markMessageAsFailed(tempId: tempId)
            }
        }

        if !started {
            markMessageAsFailed(tempId: tempId)
        }

        replyingToMessage = nil
    }

    func voteOnPoll(messageId: String, conversationId: String, optionId: String) {
        AppLogger.debug("Poll voting is not supported in FlirtTime chat")
    }

    func pollVoteAckReceived(messageId: String) -> Bool {
        let count = inFlightPollVotes[messageId, default: 0]
        if count == 0 {
            // No in-flight vote — this is a stale or duplicate ack, ignore it
            return false
        } else if count == 1 {
            inFlightPollVotes.removeValue(forKey: messageId)
            return true
        } else {
            inFlightPollVotes[messageId] = count - 1
            return false
        }
    }

    var inFlightPollVotesActive: Bool {
        return !inFlightPollVotes.isEmpty
    }

    private func applyPollVoteSummary(messageId: String, summary: PollData) {
        guard let currentMessage = stateManager.messageById(messageId) else { return }
        var updated = currentMessage
        if let existing = currentMessage.poll {
            updated.poll = existing.applyingSummary(summary)
        } else {
            updated.poll = summary
        }
        if let poll = updated.poll {
            updated.poll = enrichPollVoterProfiles(poll)
        }
        stateManager.updateMessage(updated)
        messageSyncCoordinator.persist(messages: [updated])
        syncPollSelectionFromMyOptions(messageId: messageId, poll: updated.poll)
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    private func revertPollVote(messageId: String, previous: PollData) {
        guard var currentMessage = stateManager.messageById(messageId) else { return }
        currentMessage.poll = previous
        stateManager.updateMessage(currentMessage)
        syncPollSelectionFromMyOptions(messageId: messageId, poll: previous)
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    private func syncPollSelectionFromMyOptions(messageId: String, poll: PollData?) {
        guard let poll else {
            setSelectedPollOptionId(for: messageId, optionId: nil)
            return
        }
        let ids = poll.resolvedMyOptionIds(currentUserId: getCurrentUserId())
        setSelectedPollOptionId(for: messageId, optionId: ids.first)
    }

    /// Optimistic UI update from target `optionIds` (FE `optimisticVote`).
    private func applyOptimisticPollVote(messageId: String, optionIds: [String], previous: PollData) {
        let currentUserId = getCurrentUserId()
        let prevIds = Set(previous.resolvedMyOptionIds(currentUserId: currentUserId))
        let nextIds = Set(optionIds)

        let updatedOptions: [PollOption] = previous.options.map { option in
            let was = prevIds.contains(option.optionId)
            let now = nextIds.contains(option.optionId)
            var votes = option.votes ?? []
            var count = max(option.votes?.count ?? 0, option.voteCount)

            if !was && now {
                count += 1
                if !currentUserId.isEmpty,
                   !votes.contains(where: { $0.userId.caseInsensitiveCompare(currentUserId) == .orderedSame }) {
                    votes.append(PollVoter(
                        userId: currentUserId,
                        userName: userListViewModel.sessionManager?.user?.userName,
                        fullName: userListViewModel.sessionManager?.user?.fullName,
                        profilePicture: userListViewModel.sessionManager?.user?.profilePicture,
                        votedAt: isoFormatter.string(from: Date())
                    ))
                }
            } else if was && !now {
                count = max(0, count - 1)
                votes.removeAll(where: {
                    $0.userId.caseInsensitiveCompare(currentUserId) == .orderedSame
                })
            }

            return PollOption(
                text: option.text,
                voteCount: count,
                optionId: option.optionId,
                votes: votes.isEmpty ? nil : votes,
                percent: nil
            )
        }

        let totalVotes = updatedOptions.reduce(0) { $0 + $1.voteCount }
        var poll = PollData(
            id: previous.id,
            settings: previous.settings,
            question: previous.question,
            options: updatedOptions,
            totalVotes: totalVotes,
            myOptionIds: optionIds,
            isClosed: previous.isClosed,
            version: previous.version,
            closesAt: previous.closesAt,
            createdBy: previous.createdBy
        )
        poll = enrichPollVoterProfiles(poll)

        guard var currentMessage = stateManager.messageById(messageId) else {
            setSelectedPollOptionId(for: messageId, optionId: optionIds.first)
            return
        }
        currentMessage.poll = poll
        stateManager.updateMessage(currentMessage)
        setSelectedPollOptionId(for: messageId, optionId: optionIds.first)
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    // Legacy single-option optimistic helper removed — use applyOptimisticPollVote(optionIds:)

    // MARK: - Edit / Delete

    /// FE edit — PATCH `/api/v1/chat/messages/{id}` with `{ body }` (optional `type`)
    func editMessage(messageId: String, newContent: String) {
        guard !newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLogger.debug("Cannot edit message with empty content")
            editingMessage = nil
            return
        }

        guard isValidServerMessageId(messageId) else {
            AppLogger.debug("[Edit] Skipped REST — invalid messageId: \(messageId)")
            editingMessage = nil
            return
        }

        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousSnapshot = stateManager.messageById(messageId)

        // Optimistic UI
        applyEditedContentLocally(messageId: messageId, content: trimmed)
        editingMessage = nil

        guard let session = userListViewModel.sessionManager
                ?? sessionManager
                ?? Container.sharedContainer.resolve(SessionManager.self) else {
            AppLogger.debug("[Edit] SessionManager unavailable")
            return
        }

        let msgType = previousSnapshot?.messageType ?? previousSnapshot?.type
        AppLogger.debug("[Edit] ▶ PATCH chat/messages/\(messageId) body=\(trimmed.prefix(40))")

        session.editChatMessage(messageId: messageId, body: trimmed, type: msgType)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] updated in
                    self?.handleEditChatMessageREST(updated, fallbackContent: trimmed)
                },
                onFailure: { [weak self] error in
                    AppLogger.debug("[Edit] ❌ \(error.localizedDescription)")
                    if let previous = previousSnapshot {
                        self?.stateManager.updateMessage(previous)
                        let groups = self?.stateManager.getGroupedMessagesSnapshot() ?? []
                        self?.groupedMessages = groups
                        self?.handleMessageListUpdate(groups.flatMap(\.messages))
                    }
                    self?.showToastMessage(error.localizedDescription)
                }
            )
            .disposed(by: disposeBag)
    }

    func applyEditedContentLocally(messageId: String, content: String) {
        guard var message = stateManager.messageById(messageId) else { return }
        message.content = content
        message.isEdited = true
        message.updatedAt = isoFormatter.string(from: Date())
        message.translation = nil
        showingTranslations.remove(messageId)
        var meta = plainMetadata(from: message.metadata)
        meta["_originalContent"] = content
        message.metadata = meta.mapValues { AnyCodable($0) }
        stateManager.updateMessage(message)
        let groups = stateManager.getGroupedMessagesSnapshot()
        groupedMessages = groups
        handleMessageListUpdate(groups.flatMap(\.messages))
    }

    func handleEditChatMessageREST(_ updated: ConversationMessage, fallbackContent: String) {
        var message = updated
        if (message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message.content = fallbackContent
        }
        message.isEdited = true
        message.translation = nil
        var meta = plainMetadata(from: message.metadata)
        meta["_originalContent"] = message.content ?? fallbackContent
        message.metadata = meta.mapValues { AnyCodable($0) }

        if stateManager.messageById(message.id) != nil {
            // Prefer merging into existing so media/reactions aren't dropped by sparse PATCH payloads
            if var existing = stateManager.messageById(message.id) {
                existing.content = message.content
                existing.isEdited = true
                existing.updatedAt = message.updatedAt ?? existing.updatedAt
                existing.translation = nil
                var existingMeta = plainMetadata(from: existing.metadata)
                existingMeta["_originalContent"] = existing.content ?? fallbackContent
                existing.metadata = existingMeta.mapValues { AnyCodable($0) }
                stateManager.updateMessage(existing)
                messageSyncCoordinator.persist(messages: [existing])
            }
        } else {
            stateManager.updateMessage(message)
            messageSyncCoordinator.persist(messages: [message])
        }

        let groups = stateManager.getGroupedMessagesSnapshot()
        groupedMessages = groups
        handleMessageListUpdate(groups.flatMap(\.messages))
        AppLogger.debug("[Edit] ✅ id=\(message.id)")
    }

    func deleteMessage(messageId: String) {
        deleteMessageForMe(messageId: messageId)
    }

    func editMessage(newText: String) {
        guard let editingMessage = editingMessage,
              !editingMessage.id.isEmpty else { return }
        let messageId = editingMessage.id
        editMessage(messageId: messageId, newContent: newText)
    }

    /// FE — POST `/chat/messages/delete` `{ messageIds, scope: "me" }`
    /// Channels — POST `/chat/channels/messages/delete` `{ messageIds, scope: "me" }`
    func deleteMessageForMe(messageId: String) {
        dismissDeleteSheet()

        let serverId = resolveServerMessageId(messageId)
        let uiIds = Array(Set([messageId, serverId].compactMap { $0 }).filter { !$0.isEmpty })
        for id in uiIds {
            silentlyUnpinIfPinned(messageId: id)
            locallyDeletedMessageIds.insert(id)
        }

        let pendingKey = [messageId, serverId].compactMap { $0 }.first(where: { tempMessageMapping[$0] != nil })
        if let pendingKey {
            tempMessageMapping.removeValue(forKey: pendingKey)
            PendingMessageStore.shared.remove(tempId: pendingKey)
            BackgroundUploadService.shared.cancel(tempId: pendingKey)
            backgroundTasks[pendingKey]?.cancel()
            backgroundTasks.removeValue(forKey: pendingKey)
            AppLogger.debug("Deleted pending message: \(pendingKey)")
        }

        for id in uiIds {
            removeMessageFromUI(messageId: id)
            messageSyncCoordinator.hardDeleteMessage(id: id)
        }
        refreshConversationLastMessageAfterDelete(deletedMessageId: serverId ?? messageId)

        guard pendingKey == nil, let apiId = serverId else {
            if pendingKey == nil {
                AppLogger.debug("[deleteMessageForMe] Skipped REST — unresolved messageId: \(messageId)")
            }
            return
        }

        AppLogger.debug("[Delete] ▶ POST chat/messages/delete messageIds=1 scope=me id=\(apiId)")
        messageService.deleteMessages(messageIds: [apiId], scope: "me")
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        AppLogger.debug("[Delete] scope=me failed: \(error.localizedDescription) — socket fallback")
                        self?.emitDeleteMessagesSocket(messageIds: [apiId], forEveryone: false)
                    }
                },
                receiveValue: { _ in
                    AppLogger.debug("[Delete] ✅ scope=me id=\(apiId)")
                }
            )
            .store(in: &cancellables)
    }

    /// FE — POST `/chat/messages/delete` `{ messageIds, scope: "everyone" }`
    func deleteMessageForEveryone(messageId: String) {
        dismissDeleteSheet()

        let serverId = resolveServerMessageId(messageId)
        let uiIds = Array(Set([messageId, serverId].compactMap { $0 }).filter { !$0.isEmpty })
        for id in uiIds {
            silentlyUnpinIfPinned(messageId: id)
        }

        let pendingKey = [messageId, serverId].compactMap { $0 }.first(where: { tempMessageMapping[$0] != nil })
        if let pendingKey {
            tempMessageMapping.removeValue(forKey: pendingKey)
            PendingMessageStore.shared.remove(tempId: pendingKey)
            BackgroundUploadService.shared.cancel(tempId: pendingKey)
            backgroundTasks[pendingKey]?.cancel()
            backgroundTasks.removeValue(forKey: pendingKey)
            for id in uiIds {
                removeMessageFromUI(messageId: id)
                messageSyncCoordinator.deleteMessage(id: id)
            }
            refreshConversationLastMessageAfterDelete(deletedMessageId: serverId ?? messageId)
            AppLogger.debug("Deleted pending message for everyone: \(pendingKey)")
            return
        }

        let interimContent = ChatStrings.chat_messageDeleted.localizedString()
        let lookupId = serverId ?? messageId
        if let existing = stateManager.messageById(lookupId)
            ?? messages.first(where: { $0.id == messageId || $0.stableId == messageId || $0.id == lookupId }) {
            var toDelete = existing
            toDelete.isDeleted = true
            toDelete.status = "deleted"
            toDelete.content = interimContent
            handleMessageDeleted(toDelete)
        } else {
            var fakeDeleted = ConversationMessage(
                id: lookupId,
                conversationId: selectedId,
                isDeleted: true,
                senderId: getCurrentUserId()
            )
            fakeDeleted.status = "deleted"
            fakeDeleted.content = interimContent
            handleMessageDeleted(fakeDeleted)
        }

        for id in uiIds {
            messageSyncCoordinator.deleteMessage(id: id)
        }

        guard let apiId = serverId else {
            AppLogger.debug("[deleteMessageForEveryone] Skipped REST — unresolved messageId: \(messageId)")
            return
        }

        AppLogger.debug("[Delete] ▶ POST chat/messages/delete messageIds=1 scope=everyone id=\(apiId)")
        messageService.deleteMessages(messageIds: [apiId], scope: "everyone")
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        AppLogger.debug("[Delete] scope=everyone failed: \(error.localizedDescription) — socket fallback")
                        self?.emitDeleteMessagesSocket(messageIds: [apiId], forEveryone: true)
                    }
                },
                receiveValue: { _ in
                    AppLogger.debug("[Delete] ✅ scope=everyone id=\(apiId)")
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Delete Helpers

    private func dismissDeleteSheet() {
        showDeleteMessageSheet = false
        selectedMessageForDelete = nil
    }

    func removeMessageFromUI(messageId: String) {
        pendingRemovalCount += 1
        stateManager.removeMessage(id: messageId)
        if highlightedMessageId == messageId { highlightedMessageId = nil }
        if editingMessage?.id == messageId { editingMessage = nil }
    }
    
    func markMessageAsDeletedInUI(messageId: String) {
        guard var msg = stateManager.messageById(messageId) else { return }
        msg.isDeleted = true
        msg.status = "deleted"
        stateManager.updateMessage(msg)
        if highlightedMessageId == messageId { highlightedMessageId = nil }
        if editingMessage?.id == messageId { editingMessage = nil }
        AppLogger.debug("[markMessageAsDeletedInUI] marked \(messageId) as deleted")
    }

    func refreshConversationLastMessageAfterDelete(deletedMessageId: String) {
        let conversationId = selectedId
        guard !conversationId.isEmpty else { return }

        let remaining = messages

        if let newLast = remaining.last {
            updateConversationLastMessage(newLast)
        } else {
            Task { [weak self] in
                try? await self?.conversationRepository?.clearLastMessage(conversationId: conversationId)
            }
        }
    }

    func refreshConversationLastMessageAfterBatchDelete(deletedMessageIds: [String]) {
        let conversationId = selectedId
        guard !conversationId.isEmpty else { return }

        let remaining = messages

        if let newLast = remaining.last {
            updateConversationLastMessage(newLast)
        } else {
            Task { [weak self] in
                try? await self?.conversationRepository?.clearLastMessage(conversationId: conversationId)
            }
        }
    }

    // MARK: - Translation Helpers

    /// FE translate — POST `/api/v1/chat/messages/{id}/translate` `{ targetLanguage }`
    func translateMessage(messageId: String, targetLanguage: String? = nil) {
        guard !messageId.isEmpty, isValidServerMessageId(messageId) else {
            AppLogger.debug("[Translate] Skipped REST — invalid messageId: \(messageId)")
            return
        }

        let resolvedTarget = LiveTranslationLanguages.code(
            from: targetLanguage ?? getSelectedLanguage(),
            fallback: "en"
        )

        guard let session = userListViewModel.sessionManager
                ?? sessionManager
                ?? Container.sharedContainer.resolve(SessionManager.self) else {
            AppLogger.debug("[Translate] SessionManager unavailable")
            return
        }

        AppLogger.debug("[Translate] ▶ POST chat/messages/\(messageId)/translate targetLanguage=\(resolvedTarget)")

        session.translateChatMessage(messageId: messageId, targetLanguage: resolvedTarget)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] data in
                    guard let self else { return }
                    let resolvedId = data.resolvedMessageId ?? messageId
                    let existing = self.stateManager.messageById(resolvedId)
                        ?? self.stateManager.messageById(messageId)
                    let original = existing?.originalContentForDisplay
                    guard let translatedText = data.resolvedTranslatedText(preferringOver: original) else {
                        AppLogger.debug("[Translate] ❌ Response missing translated text")
                        self.showToastMessage("Translation failed")
                        return
                    }
                    self.applyMessageTranslation(
                        messageId: existing?.id ?? messageId,
                        translatedText: translatedText,
                        detectLanguage: data.message?.detectLanguage,
                        targetLanguage: resolvedTarget
                    )
                },
                onFailure: { [weak self] error in
                    AppLogger.debug("[Translate] ❌ \(error.localizedDescription)")
                    self?.showToastMessage(error.localizedDescription)
                }
            )
            .disposed(by: disposeBag)
    }

    func isShowingTranslation(for messageId: String) -> Bool {
        showingTranslations.contains(messageId)
    }

    func toggleTranslation(for messageId: String) {
        if showingTranslations.contains(messageId) {
            showingTranslations.remove(messageId)
        } else {
            showingTranslations.insert(messageId)
        }
    }

    // MARK: - Pin/Unpin Message

    func silentlyUnpinIfPinned(messageId: String) {
        if currentPinnedMessage?.id == messageId {
            currentPinnedMessage = nil
        }
        if var msg = stateManager.messageById(messageId), msg.isPinned == true {
            msg.isPinned = false
            stateManager.updateMessage(msg)
        }
    }

    /// FE `pinChatMessage` — PATCH `/chat/conversations/{id}/messages/{messageId}/pin` `{ pinned, pinDuration? }`
    /// Also emits console `chat:message:pin` so room peers get `chat:message:pin:updated`.
    func pinMessage(messageId: String, isPinned: Bool, pinDuration: String?) {
        guard !messageId.isEmpty, !selectedId.isEmpty else { return }
        guard isValidServerMessageId(messageId) else {
            AppLogger.debug("[Pin] Skipped REST — invalid messageId: \(messageId)")
            return
        }

        // Optimistic UI (match FE: only one pinned message at a time)
        applyPinStateLocally(messageId: messageId, isPinned: isPinned)

        // Realtime fanout — console c2s uses `pinned` (+ optional pinDuration)
        socketService.pinMessage(
            messageId: messageId,
            conversationId: selectedId,
            isPinned: isPinned,
            pinDuration: isPinned ? pinDuration : nil
        )

        guard let session = userListViewModel.sessionManager
                ?? sessionManager
                ?? Container.sharedContainer.resolve(SessionManager.self) else {
            AppLogger.debug("[Pin] SessionManager unavailable")
            return
        }

        AppLogger.debug(
            "[Pin] ▶ PATCH conversations/\(selectedId)/messages/\(messageId)/pin pinned=\(isPinned) duration=\(pinDuration ?? "nil")"
        )

        session.pinChatMessage(
            conversationId: selectedId,
            messageId: messageId,
            pinned: isPinned,
            pinDuration: isPinned ? pinDuration : nil
        )
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] updated in
                    self?.handlePinChatMessageREST(updated, requestedPinned: isPinned)
                },
                onFailure: { [weak self] error in
                    AppLogger.debug("[Pin] ❌ \(error.localizedDescription)")
                    // Revert optimistic flip
                    self?.applyPinStateLocally(messageId: messageId, isPinned: !isPinned)
                    self?.showToastMessage(error.localizedDescription)
                }
            )
            .disposed(by: disposeBag)
    }

    private func applyPinStateLocally(messageId: String, isPinned: Bool) {
        var clearedIds: [String] = []
        if isPinned {
            for msg in stateManager.getGroupedMessagesSnapshot().flatMap(\.messages)
            where msg.isPinned == true && msg.id != messageId {
                var cleared = msg
                cleared.isPinned = false
                stateManager.updateMessage(cleared)
                clearedIds.append(cleared.id)
            }
        }

        if var msg = stateManager.messageById(messageId) {
            msg.isPinned = isPinned
            stateManager.updateMessage(msg)
        }

        let groups = stateManager.getGroupedMessagesSnapshot()
        groupedMessages = groups
        handleMessageListUpdate(groups.flatMap(\.messages))

        pendingPinUpdates[messageId] = isPinned
        for id in clearedIds { pendingPinUpdates[id] = false }

        if isPinned {
            currentPinnedMessage = stateManager.messageById(messageId)
        } else {
            // One-pin model: unpin clears the banner (don't revive a stale second pin)
            currentPinnedMessage = nil
        }

        ChatDataPreloader.shared.storePinState(for: selectedId, message: currentPinnedMessage)
        let convId = selectedId
        Task {
            if isPinned {
                try? await self.messageRepository.clearOtherPinnedMessages(
                    in: convId,
                    except: messageId
                )
            }
            try? await self.messageRepository.updateMessagePinStatus(id: messageId, isPinned: isPinned)
            for id in clearedIds {
                try? await self.messageRepository.updateMessagePinStatus(id: id, isPinned: false)
            }
        }
    }

    private func handlePinChatMessageREST(_ updated: ConversationMessage, requestedPinned: Bool) {
        // Prefer the client's requested state — some APIs omit/return stale `isPinned` on PATCH
        let pinned = requestedPinned
        var message = updated
        message.isPinned = pinned

        // Clear other pins, then apply server message
        var clearedIds: [String] = []
        if pinned {
            for msg in stateManager.getGroupedMessagesSnapshot().flatMap(\.messages)
            where msg.isPinned == true && msg.id != message.id {
                var cleared = msg
                cleared.isPinned = false
                stateManager.updateMessage(cleared)
                clearedIds.append(cleared.id)
            }
        }

        if stateManager.messageById(message.id) != nil {
            stateManager.updateMessage(message)
        } else if !pinned {
            // Ensure pin flag is cleared even if REST payload shape differs
            if var live = stateManager.getGroupedMessagesSnapshot()
                .flatMap(\.messages)
                .first(where: { $0.id == message.id || $0.stableId == message.id }) {
                live.isPinned = false
                stateManager.updateMessage(live)
            }
        }

        let groups = stateManager.getGroupedMessagesSnapshot()
        groupedMessages = groups
        handleMessageListUpdate(groups.flatMap(\.messages))

        if pinned {
            currentPinnedMessage = stateManager.messageById(message.id) ?? message
        } else {
            currentPinnedMessage = nil
        }

        pendingPinUpdates[message.id] = pinned
        for id in clearedIds { pendingPinUpdates[id] = false }
        ChatDataPreloader.shared.storePinState(for: selectedId, message: currentPinnedMessage)
        let messageId = message.id
        let convId = selectedId
        Task {
            if pinned {
                try? await self.messageRepository.clearOtherPinnedMessages(
                    in: convId,
                    except: messageId
                )
            }
            try? await self.messageRepository.updateMessagePinStatus(id: messageId, isPinned: pinned)
            for id in clearedIds {
                try? await self.messageRepository.updateMessagePinStatus(id: id, isPinned: false)
            }
            await MainActor.run {
                self.pendingPinUpdates.removeValue(forKey: messageId)
                for id in clearedIds { self.pendingPinUpdates.removeValue(forKey: id) }
                guard self.selectedId == convId else { return }
                if !pinned {
                    self.refreshPinnedMessageFromAPI()
                }
            }
        }

        AppLogger.debug("[Pin] ✅ id=\(message.id) pinned=\(pinned)")
        showToastMessage(
            pinned
                ? ChatStrings.chat_pinned.localizedString()
                : ChatStrings.chat_unpin.localizedString()
        )
    }

    /// FE `fetchPinnedMessage` — refresh banner from GET pinned-message
    func refreshPinnedMessageFromAPI() {
        guard !selectedId.isEmpty, !isChannel else { return }
        guard let session = userListViewModel.sessionManager
                ?? sessionManager
                ?? Container.sharedContainer.resolve(SessionManager.self) else { return }

        session.fetchPinnedMessage(conversationId: selectedId)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] pinned in
                    guard let self else { return }
                    if let pinned {
                        self.applyServerPinnedMessages([pinned])
                    } else {
                        // Clear pin flags + banner when server has none
                        self.applyServerPinnedMessages([])
                    }
                },
                onFailure: { error in
                    AppLogger.debug("[Pin] fetchPinnedMessage failed: \(error.localizedDescription)")
                }
            )
            .disposed(by: disposeBag)
    }

    // MARK: - Reactions

    /// FE — POST `/api/v1/chat/messages/{id}/react` `{ emoji }`
    /// Optimistic local toggle, then REST. Realtime fanout via `chat:message:reacted` / ack sockets.
    func reactToMessage(messageId: String, emoji: String) {
        guard !selectedId.isEmpty else {
            AppLogger.debug("reactToMessage: conversationId empty")
            return
        }
        guard !messageId.isEmpty, !emoji.isEmpty, isValidServerMessageId(messageId) else { return }

        applyOptimisticReaction(messageId: messageId, emoji: emoji)

        guard let session = userListViewModel.sessionManager
                ?? sessionManager
                ?? Container.sharedContainer.resolve(SessionManager.self) else {
            AppLogger.debug("[React] SessionManager unavailable")
            return
        }

        AppLogger.debug("[React] ▶ POST chat/messages/\(messageId)/react emoji=\(emoji)")
        session.reactChatMessage(messageId: messageId, emoji: emoji)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] updated in
                    guard let self else { return }
                    self.applyServerReactionUpdate(messageId: messageId, serverMessage: updated)
                    AppLogger.debug("[React] ✅ Applied server reactions for \(messageId)")
                },
                onFailure: { [weak self] error in
                    AppLogger.debug("[React] ❌ \(error.localizedDescription)")
                    // Keep optimistic state; socket ack / messageReacted may still reconcile.
                    self?.showToastMessage(error.localizedDescription)
                }
            )
            .disposed(by: disposeBag)
    }

    private func applyOptimisticReaction(messageId: String, emoji: String) {
        guard var msg = stateManager.messageById(messageId) else { return }
        var reactionGroups = msg.reactions ?? []
        let currentUserId = getCurrentUserId()

        if let existingGroupIndex = reactionGroups.firstIndex(where: { group in
            group.emoji == emoji && group.users.contains(where: { $0.userId == currentUserId })
        }) {
            reactionGroups[existingGroupIndex].users.removeAll { $0.userId == currentUserId }
            reactionGroups.removeAll { $0.users.isEmpty }
            msg.reactions = reactionGroups
            stateManager.updateMessage(msg)
            messageSyncCoordinator.persist(messages: [msg])
            return
        }

        for i in reactionGroups.indices {
            reactionGroups[i].users.removeAll { $0.userId == currentUserId }
        }
        reactionGroups.removeAll { $0.users.isEmpty }

        if let targetIndex = reactionGroups.firstIndex(where: { $0.emoji == emoji }) {
            reactionGroups[targetIndex].users.append(ReactionUser(userId: currentUserId))
        } else {
            reactionGroups.append(MessageReaction(emoji: emoji, users: [ReactionUser(userId: currentUserId)]))
        }

        msg.reactions = reactionGroups
        stateManager.updateMessage(msg)
        messageSyncCoordinator.persist(messages: [msg])
    }

    /// Merge server reaction payload onto the local message (REST or `chat:message:reacted`).
    /// Never inserts a new row — reaction fanouts are often partial and would create empty cells.
    func applyServerReactionUpdate(messageId: String, serverMessage: ConversationMessage) {
        let id = serverMessage.id.isEmpty ? messageId : serverMessage.id
        guard !id.isEmpty else { return }

        if serverMessage.conversationId.isEmpty == false,
           serverMessage.conversationId != selectedId,
           stateManager.messageById(id) == nil {
            return
        }

        guard var existing = stateManager.messageById(id) else {
            AppLogger.debug("[Reacted] No local message for \(id.prefix(8)) — skip insert")
            return
        }

        if serverMessage.reactions != nil || serverMessage.reactionsWrapper != nil {
            existing.reactions = serverMessage.reactions
        } else if let emoji = serverMessage.metadata?["_reactionDeltaEmoji"]?.value as? String,
                  let userId = serverMessage.metadata?["_reactionDeltaUserId"]?.value as? String,
                  !emoji.isEmpty, !userId.isEmpty {
            existing.reactions = ConversationMessage.applyingReactionDelta(
                existing.reactions ?? [],
                emoji: emoji,
                userId: userId
            )
        } else {
            AppLogger.debug("[Reacted] No reactions/delta for \(id.prefix(8)) — skip")
            return
        }

        if let updatedAt = serverMessage.updatedAt, !updatedAt.isEmpty {
            existing.updatedAt = updatedAt
        }

        stateManager.updateMessage(existing)
        messageSyncCoordinator.persist(messages: [existing])
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func isLastMessage(_ message: ConversationMessage) -> Bool {
        return messages.last?.id == message.id
    }
    
    func createTemporaryTextMessage(tempId: String, content: String, replyTo: ConversationMessage?) -> ConversationMessage {
        var messageDict: [String: Any] = [
            "id": tempId,
            "conversationId": selectedId,
            "content": content,
            "messageType": "text",
            "senderId": getCurrentUserId(),
            "createdAt": isoFormatter.string(from: Date()),
            "updatedAt": isoFormatter.string(from: Date()),
            "isEdited": false,
            "isDeleted": false,
            "status": "sending"
        ]
        if let r = replyTo {
            let senderId = r.sender?.id ?? r.senderId ?? ""
            let resolved = resolvedDisplayName(for: senderId)
            let senderFullName = [r.sender?.fullName, resolved]
                .first(where: { !($0 ?? "").isEmpty }) ?? ""
            let senderUserName = [r.sender?.userName, resolved]
                .first(where: { !($0 ?? "").isEmpty }) ?? ""
            messageDict["replyToId"] = [
                "id": r.id,
                "content": r.content ?? "",
                "type": r.messageType ?? r.type ?? "text",
                "sender": [
                    "id": senderId,
                    "userName": senderUserName,
                    "fullName": senderFullName
                ] as [String: Any],
                "thumbnail": r.thumbnail ?? r.media?.first?.thumbnail ?? r.media?.first?.url ?? ""
            ] as [String: Any]
        }

        return ConversationMessage.fromDictionary(messageDict)
            ?? ConversationMessage(id: tempId, type: "text", content: content,
                                   createdAt: isoFormatter.string(from: Date()),
                                   senderId: getCurrentUserId())
    }

    // MARK: - Forward Message

    /// FE `forwardChatMessages` — POST `/api/v1/chat/messages/forward`
    /// Payload: `{ messageIds, targetConversationIds }` (picker returns conversation ids).
    func forwardMessage(messageIds: [String], receiverIds: [String]) {
        AppLogger.debug("Forwarding is not supported in FlirtTime chat")
    }
}

extension FileManager {
    func fileSize(atPath path: String) -> String {
        guard let attributes = try? attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int64 else {
            return "0 bytes"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
