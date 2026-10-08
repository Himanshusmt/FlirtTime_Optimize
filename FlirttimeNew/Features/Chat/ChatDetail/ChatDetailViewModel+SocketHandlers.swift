//
//  ChatDetailViewModel+SocketHandlers.swift
//  FlirttimeNew
//

import Foundation

extension ChatDetailViewModel {

    // MARK: - New Socket Message

    func handleNewSocketMessage(_ message: ConversationMessage) {
        let msgId = message.id
        let clientTempId = (message.metadata?["clientTempId"]?.value as? String) ?? "none"
        AppLogger.debug("[MsgFlow] get-latest → id=\(msgId) clientTempId=\(clientTempId) type=\(message.messageType ?? message.type ?? "??")")

        guard (message.conversationId) == selectedId else {
            AppLogger.debug("[MsgFlow] get-latest: skipped – wrong conversationId")
            return
        }

        handleSystemMessageSideEffects(message)

        let isFromSelf = (message.sender?.id ?? message.senderId) == getCurrentUserId()

        if message.isPinSystemEvent {
            if !message.id.isEmpty, recentPinSystemMessageIds.contains(message.id) {
                AppLogger.debug("[MsgFlow] get-latest: skipping duplicate pin system message \(message.id.prefix(8))")
                return
            }
            if !message.id.isEmpty {
                recentPinSystemMessageIds.insert(message.id)
                if recentPinSystemMessageIds.count > 50 {
                    recentPinSystemMessageIds = Set(recentPinSystemMessageIds.suffix(30))
                }
            }
            handlePinSystemMessage(message)
        }

        if !isFromSelf {
            registerOffBottomNewMessage(message)
        }

        let msgType = (message.messageType ?? message.type ?? "").lowercased()
        if msgType == "location", let loc = message.locationData {
            MapSnapshotCache.shared.prewarmNow(lat: loc.latitude, lng: loc.longitude)
        }

        if !message.id.isEmpty,
           let existing = stateManager.messageById(message.id) {
            let messageId = message.id
            AppLogger.debug("[MsgFlow] get-latest: FOUND existing \(messageId.prefix(8)) → updateMessage (in-place, no position change)")
            var merged = message
            if (merged.reactions == nil || merged.reactions?.isEmpty == true), let existingReactions = existing.reactions, !existingReactions.isEmpty {
                merged.reactions = existingReactions
            }

            if merged.replyToId == nil, let existingReply = existing.replyToId {
                merged.replyToId = existingReply
            }

            if merged.isEdited != true, existing.isEdited == true {
                merged.isEdited = true
                merged.content = existing.content
                merged.translation = existing.translation
                var meta = plainMetadata(from: merged.metadata)
                let existingMeta = plainMetadata(from: existing.metadata)
                if let original = existingMeta["_originalContent"] as? String {
                    meta["_originalContent"] = original
                }
                if let translationLang = existingMeta["_translationLanguage"] as? String {
                    meta["_translationLanguage"] = translationLang
                }
                merged.metadata = meta.mapValues { AnyCodable($0) }
            }

            let existingDelivery = existing.deliveryStatus
            let mergedDelivery = merged.deliveryStatus
            if existingDelivery > mergedDelivery {
                merged.status = existing.status
                merged.sentAt = existing.sentAt
                merged.deliveredAt = existing.deliveredAt
                merged.seenAt = existing.seenAt
                merged.statuses = existing.statuses
            }

            stateManager.updateMessage(merged)
            messageSyncCoordinator.persist(messages: [merged])
            updateConversationLastMessage(merged)
            if !isFromSelf { markReceivedMessageAsSeen(messageId: message.id) }
            return
        }
        AppLogger.debug("[MsgFlow] get-latest: \(msgId.prefix(8)) not in messageById → trying tempMatch")
        if tryMatchAndReplaceTemporaryMessage(with: message) {
            AppLogger.debug("[MsgFlow] get-latest: matched+replaced temp via clientTempId=\(clientTempId)")
            updateConversationLastMessage(message)
            return
        }
        AppLogger.debug("[MsgFlow] get-latest: ⚠️ NO MATCH – addMessages (new insert, may reorder!) id=\(msgId.prefix(8))")

        if msgType == "location" && !isFromSelf, let loc = message.locationData {
            if typingIndicator.isTyping { clearTypingIndicator() }
            Task { [weak self] in
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        _ = await MapSnapshotCache.shared.generate(lat: loc.latitude, lng: loc.longitude)
                    }
                    group.addTask {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    }
                    await group.next()
                    group.cancelAll()
                }
                guard let self else { return }
                self.stateManager.addMessages([message])
                self.messageSyncCoordinator.persist(messages: [message])
                self.updateConversationLastMessage(message)
                self.markReceivedMessageAsSeen(messageId: message.id)
            }
            return
        }

        if !isFromSelf && typingIndicator.isTyping {
            clearTypingIndicator()
            let messageId = message.id
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard let self else { return }
                self.stateManager.addMessages([message])
                self.messageSyncCoordinator.persist(messages: [message])
                self.updateConversationLastMessage(message)
                self.markReceivedMessageAsSeen(messageId: messageId)
            }
        } else {
            stateManager.addMessages([message])
            messageSyncCoordinator.persist(messages: [message])
            updateConversationLastMessage(message)
            if !isFromSelf { markReceivedMessageAsSeen(messageId: message.id) }
        }
    }

    // MARK: - Message Acknowledgment

    func handleMessageAcknowledgment(_ acknowledgedMessage: ConversationMessage) {
        // Guard: reaction fanouts must never go through insert/replace ack path
        if acknowledgedMessage.isReactionOnlyPayload {
            applyServerReactionUpdate(messageId: acknowledgedMessage.id, serverMessage: acknowledgedMessage)
            return
        }

        let msgId = acknowledgedMessage.id
        let clientTempId = (acknowledgedMessage.metadata?["clientTempId"]?.value as? String) ?? "none"
        AppLogger.debug("[MsgFlow] msg-ack → id=\(msgId.prefix(8)) clientTempId=\(clientTempId) type=\(acknowledgedMessage.messageType ?? acknowledgedMessage.type ?? "??")")

        guard (acknowledgedMessage.conversationId) == selectedId else {
            AppLogger.debug("[MsgFlow] msg-ack: skipped – wrong conversationId")
            return
        }

        if tryMatchAndReplaceTemporaryMessage(with: acknowledgedMessage) {
            AppLogger.debug("[MsgFlow] msg-ack: ✅ replaced temp → serverId=\(msgId.prefix(8)) clientTempId=\(clientTempId)")

            if acknowledgedMessage.poll != nil,
               let optimisticOptionId = getSelectedPollOptionId(for: msgId),
               !optimisticOptionId.isEmpty,
               let serverMessage = stateManager.messageById(msgId),
               var serverPoll = serverMessage.poll {
                let currentUserId = getCurrentUserId()
                let userAlreadyVotedOnServer = serverPoll.options.contains { opt in
                    opt.votes?.contains(where: { $0.userId.caseInsensitiveCompare(currentUserId) == .orderedSame }) ?? false
                }
                if !userAlreadyVotedOnServer {
                    // Re-apply the optimistic vote on top of the server-confirmed message
                    let updatedOptions = serverPoll.options.map { option in
                        var votes = option.votes ?? []
                        if option.optionId == optimisticOptionId {
                            let alreadyThere = votes.contains(where: { $0.userId.caseInsensitiveCompare(currentUserId) == .orderedSame })
                            if !alreadyThere {
                                votes.append(PollVoter(
                                    userId: currentUserId,
                                    userName: userListViewModel.sessionManager?.user?.userName,
                                    fullName: userListViewModel.sessionManager?.user?.fullName,
                                    profilePicture: userListViewModel.sessionManager?.user?.profilePicture,
                                    votedAt: isoFormatter.string(from: Date())
                                ))
                            }
                        }
                        return PollOption(
                            text: option.text,
                            voteCount: votes.count,
                            optionId: option.optionId,
                            votes: votes.isEmpty ? nil : votes
                        )
                    }
                    let totalVotes = updatedOptions.reduce(0) { $0 + max($1.votes?.count ?? 0, $1.voteCount) }
                    serverPoll = PollData(
                        id: serverPoll.id,
                        settings: serverPoll.settings,
                        question: serverPoll.question,
                        options: updatedOptions,
                        totalVotes: totalVotes,
                        myOptionIds: [optimisticOptionId],
                        isClosed: serverPoll.isClosed,
                        version: serverPoll.version,
                        closesAt: serverPoll.closesAt,
                        createdBy: serverPoll.createdBy
                    )
                    var updatedMessage = serverMessage
                    updatedMessage.poll = serverPoll
                    stateManager.updateMessage(updatedMessage)
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                    }
                    AppLogger.debug("[MsgFlow] msg-ack: preserved optimistic vote for option \(optimisticOptionId) on poll \(msgId.prefix(8))")
                }
            }

            updateConversationLastMessage(acknowledgedMessage)
            return
        }

        if !acknowledgedMessage.id.isEmpty,
           let existing = stateManager.messageById(acknowledgedMessage.id) {
            let messageId = acknowledgedMessage.id
            AppLogger.debug("[MsgFlow] msg-ack: FOUND existing \(messageId.prefix(8)) → updateMessage (no temp match found)")

            var merged = acknowledgedMessage

            // Prefer server reactions when present (react REST / socket fanout).
            if acknowledgedMessage.reactions != nil || acknowledgedMessage.reactionsWrapper != nil {
                merged.reactions = acknowledgedMessage.reactions
            } else if merged.reactions == nil, existing.reactions != nil {
                merged.reactions = existing.reactions
            }

            // Never wipe a real bubble with a sparse ack/fanout (empty content/media).
            let incomingContent = (acknowledgedMessage.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let existingContent = (existing.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let incomingLooksSparse = incomingContent.isEmpty
                && (acknowledgedMessage.media?.isEmpty != false)
                && acknowledgedMessage.poll == nil
            if incomingLooksSparse, !existingContent.isEmpty || existing.media?.isEmpty == false || existing.poll != nil {
                var rebuilt = existing
                if acknowledgedMessage.reactions != nil || acknowledgedMessage.reactionsWrapper != nil {
                    rebuilt.reactions = acknowledgedMessage.reactions
                }
                if let updatedAt = acknowledgedMessage.updatedAt, !updatedAt.isEmpty {
                    rebuilt.updatedAt = updatedAt
                }
                if let status = acknowledgedMessage.status, !status.isEmpty {
                    rebuilt.status = status
                }
                merged = rebuilt
            }

            if merged.replyToId == nil, let existingReply = existing.replyToId {
                merged.replyToId = existingReply
            }

            if merged.isEdited != true, existing.isEdited == true {
                merged.isEdited = true
                merged.content = existing.content
                merged.translation = existing.translation
                var meta = plainMetadata(from: merged.metadata)
                let existingMeta = plainMetadata(from: existing.metadata)
                if let original = existingMeta["_originalContent"] as? String {
                    meta["_originalContent"] = original
                }
                if let translationLang = existingMeta["_translationLanguage"] as? String {
                    meta["_translationLanguage"] = translationLang
                }
                merged.metadata = meta.mapValues { AnyCodable($0) }
            }

            let existingDelivery = existing.deliveryStatus
            let mergedDelivery = merged.deliveryStatus
            if existingDelivery > mergedDelivery {
                merged.status = existing.status
                merged.sentAt = existing.sentAt
                merged.deliveredAt = existing.deliveredAt
                merged.seenAt = existing.seenAt
                merged.statuses = existing.statuses
            }

            if var poll = merged.poll {
                poll = enrichPollVoterProfiles(poll)
                merged.poll = poll
            }

            let isPollAck = acknowledgedMessage.poll != nil

            if isPollAck {
                let isInFlight = pollVoteAckReceived(messageId: messageId) // decrement in-flight counter

                if isInFlight {
                    if let optimisticMsg = stateManager.messageById(messageId) {
                        messageSyncCoordinator.persist(messages: [optimisticMsg])
                    } else {
                        messageSyncCoordinator.persist(messages: [merged])
                    }
                } else if inFlightPollVotes[messageId, default: 0] == 0 {
                    stateManager.updateMessage(merged)
                    messageSyncCoordinator.persist(messages: [merged])
                    syncPollSelectionFromAck(merged, currentUserId: getCurrentUserId())
                } else {
                    if let optimisticMsg = stateManager.messageById(messageId) {
                        messageSyncCoordinator.persist(messages: [optimisticMsg])
                    } else {
                        messageSyncCoordinator.persist(messages: [merged])
                    }
                }
                return
            }

            stateManager.updateMessage(merged)
            messageSyncCoordinator.persist(messages: [merged])
            return
        }

        AppLogger.debug("[MsgFlow] msg-ack: ⚠️ NO MATCH – addMessages (unexpected new insert!) id=\(msgId.prefix(8)) clientTempId=\(clientTempId)")
        // Never insert sparse reaction fanouts as brand-new empty bubbles
        if acknowledgedMessage.isReactionOnlyPayload
            || ((acknowledgedMessage.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (acknowledgedMessage.media?.isEmpty != false)
                && acknowledgedMessage.poll == nil
                && (acknowledgedMessage.reactions != nil || acknowledgedMessage.reactionsWrapper != nil)) {
            AppLogger.debug("[MsgFlow] msg-ack: blocked empty/reaction insert for \(msgId.prefix(8))")
            return
        }
        var insertMessage = acknowledgedMessage
        if let poll = insertMessage.poll {
            insertMessage.poll = enrichPollVoterProfiles(poll)
        }
        stateManager.addMessages([insertMessage])
        if let poll = acknowledgedMessage.poll {
            let messageId = acknowledgedMessage.id
            let currentUserId = self.getCurrentUserId()
            if let votedOption = poll.options.first(where: { opt in
                opt.votes?.contains(where: { voter in
                    voter.userId.lowercased() == currentUserId.lowercased()
                }) == true
            }) {
                self.setSelectedPollOptionId(for: messageId, optionId: votedOption.optionId)
            } else {
                self.setSelectedPollOptionId(for: messageId, optionId: nil)
            }
        }
        messageSyncCoordinator.persist(messages: [insertMessage])
        updateConversationLastMessage(acknowledgedMessage)
    }

    private func syncPollSelectionFromAck(_ message: ConversationMessage, currentUserId: String) {
        let messageId = message.id
        guard let poll = message.poll else { return }
        let ids = poll.resolvedMyOptionIds(currentUserId: currentUserId)
        if let first = ids.first {
            // Only update if we don't already have a selection (avoid overwriting optimistic state)
            if getSelectedPollOptionId(for: messageId) == nil {
                setSelectedPollOptionId(for: messageId, optionId: first)
            }
        }
    }

    func enrichPollVoterProfiles(_ poll: PollData) -> PollData {
        let currentUserId = getCurrentUserId()
        let session = userListViewModel.sessionManager?.user

        let enrichedOptions = poll.options.map { option in
            guard let votes = option.votes, !votes.isEmpty else { return option }
            let enrichedVotes = votes.map { voter -> PollVoter in
                // Already has a picture — nothing to do
                if voter.profilePicture != nil { return voter }
                // Current logged-in user
                if voter.userId.lowercased() == currentUserId.lowercased() {
                    return PollVoter(
                        userId: voter.userId,
                        userName: voter.userName ?? session?.userName,
                        fullName: voter.fullName ?? session?.fullName,
                        profilePicture: session?.profilePicture,
                        votedAt: voter.votedAt
                    )
                }
                // Known group participant
                if let participant = groupParticipants.first(where: {
                    $0.userId.lowercased() == voter.userId.lowercased()
                }) {
                    return PollVoter(
                        userId: voter.userId,
                        userName: voter.userName ?? participant.userName,
                        fullName: voter.fullName ?? participant.fullName,
                        profilePicture: participant.profilePicture,
                        votedAt: voter.votedAt
                    )
                }
                return voter
            }
            return PollOption(
                text: option.text,
                voteCount: option.voteCount,
                optionId: option.optionId,
                votes: enrichedVotes,
                percent: option.percent
            )
        }
        return PollData(
            id: poll.id,
            settings: poll.settings,
            question: poll.question,
            options: enrichedOptions,
            totalVotes: poll.totalVotes,
            myOptionIds: poll.myOptionIds,
            isClosed: poll.isClosed,
            version: poll.version,
            closesAt: poll.closesAt,
            createdBy: poll.createdBy
        )
    }

    // MARK: - Message Edited / Deleted / Translation

    func handleMessageEdited(_ editedMessage: ConversationMessage) {
        let belongsHere = isChannel
            ? (editedMessage.conversationId == channelId || editedMessage.channelId == channelId)
            : (editedMessage.conversationId == selectedId)
        guard belongsHere else { return }

        let messageId = editedMessage.id
        guard !messageId.isEmpty else { return }

        if let existing = stateManager.messageById(messageId) {
            var merged = editedMessage

            if (merged.reactions == nil || merged.reactions?.isEmpty == true),
               let existingReactions = existing.reactions, !existingReactions.isEmpty {
                merged.reactions = existingReactions
            }

            if merged.replyToId == nil, let existingReply = existing.replyToId {
                merged.replyToId = existingReply
            }

            let existingDelivery = existing.deliveryStatus
            let mergedDelivery = merged.deliveryStatus
            if existingDelivery > mergedDelivery {
                merged.status = existing.status
                merged.sentAt = existing.sentAt
                merged.deliveredAt = existing.deliveredAt
                merged.seenAt = existing.seenAt
                merged.statuses = existing.statuses
            }

            if merged.isEdited != true, existing.isEdited == true {
                merged.isEdited = true
            }

            if let existingEdited = existing.content, !existingEdited.isEmpty,
               let mergedContent = merged.content, !mergedContent.isEmpty,
               existingEdited != mergedContent {
                // Server has a different content — could be a concurrent edit or stale ack
                // Prefer the server version as source of truth
            }

            if let incomingPoll = editedMessage.poll {
                if let existingPoll = existing.poll {
                    merged.poll = enrichPollVoterProfiles(existingPoll.applyingSummary(incomingPoll))
                } else {
                    merged.poll = enrichPollVoterProfiles(incomingPoll)
                }
                syncPollSelectionFromAck(merged, currentUserId: getCurrentUserId())
            } else if let existingPoll = existing.poll {
                // Sparse edit payloads should not wipe poll data
                merged.poll = existingPoll
            }

            var meta = plainMetadata(from: merged.metadata)
            meta["_originalContent"] = merged.content ?? ""
            meta.removeValue(forKey: "translation")
            merged.metadata = meta.mapValues { AnyCodable($0) }
            merged.translation = nil

            stateManager.updateMessage(merged)
            messageSyncCoordinator.persist(messages: [merged])
        } else {
            stateManager.updateMessage(editedMessage)
            messageSyncCoordinator.persist(messages: [editedMessage])
        }
        AppLogger.debug("Message edited successfully: \(messageId)")
    }

    func handleMessageDeleted(_ deletedMessage: ConversationMessage) {
        guard !deletedMessage.id.isEmpty else { return }
        let messageId = deletedMessage.id

        let sourceMessage: ConversationMessage?
        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
            sourceMessage = messages[idx]
        } else if let fromState = stateManager.messageById(messageId) {
            sourceMessage = fromState  // ← ADD THIS FALLBACK
        } else {
            AppLogger.debug("[handleMessageDeleted] \(messageId) not found, skipping")
            return  // ← DON'T create ghost cells for unknown IDs
        }

        guard var updatedMessage = sourceMessage else { return }

        if updatedMessage.isDeleted == true {
            if let newContent = deletedMessage.content, !newContent.isEmpty,
               newContent != updatedMessage.content {
                updatedMessage.content = newContent
                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[idx] = updatedMessage
                }
                stateManager.updateMessage(updatedMessage)
                groupedMessages = applyPendingDeletions(to: stateManager.getGroupedMessagesSnapshot())
            }
            return
        }

        updatedMessage.isDeleted = true
        updatedMessage.status   = "deleted"
        if let newContent = deletedMessage.content, !newContent.isEmpty {
            updatedMessage.content = newContent
        } else {
            updatedMessage.content = ChatStrings.chat_messageDeleted.localizedString()
        }

        var meta = plainMetadata(from: updatedMessage.metadata)
        meta["isDeletedEveryone"] = true
        updatedMessage.metadata = meta.mapValues { AnyCodable($0) }

        // Register as pending so FRC cannot revert it
        pendingDeletions[messageId] = updatedMessage

        // Update the flat message array in-place (no insert)
        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
            messages[idx] = updatedMessage
        }

        // Push into state manager and rebuild grouped messages
        stateManager.updateMessage(updatedMessage)
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        groupedMessages = applyPendingDeletions(to: stateManager.getGroupedMessagesSnapshot())

        Task { [weak self] in
            guard let self else { return }
            messageSyncCoordinator.persist(messages: [updatedMessage])
            DispatchQueue.main.async {
                self.pendingDeletions.removeValue(forKey: messageId)
            }
        }

        refreshConversationLastMessageAfterDelete(deletedMessageId: messageId)
    }

    func handleMessageTranslation(_ translatedMessage: ConversationMessage) {
        let messageId = translatedMessage.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageId.isEmpty else {
            AppLogger.debug("Translation received without message id")
            return
        }

        // Prefer applying by local message id. Only drop when conversationId is present,
        // mismatches selected chat, and the message is not in this chat's state.
        let conversationId = translatedMessage.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !conversationId.isEmpty,
           conversationId != selectedId,
           stateManager.messageById(messageId) == nil {
            return
        }

        let original = stateManager.messageById(messageId)?.originalContentForDisplay
        let translatedText = translatedMessage.translation?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? {
                let content = translatedMessage.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let originalTrimmed = original?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (!content.isEmpty && content != originalTrimmed) ? content : nil
            }()

        guard let translatedText, !translatedText.isEmpty else {
            AppLogger.debug("Translation ack received without translated text")
            return
        }

        applyMessageTranslation(
            messageId: messageId,
            translatedText: translatedText,
            detectLanguage: translatedMessage.detectLanguage
        )
    }

    /// Persist translation on the local message and show it in the bubble.
    func applyMessageTranslation(
        messageId: String,
        translatedText: String,
        detectLanguage: String? = nil,
        targetLanguage: String? = nil
    ) {
        guard !messageId.isEmpty,
              let existingMessage = stateManager.messageById(messageId) else {
            AppLogger.debug("Translation received for message not found in local messages: \(messageId)")
            return
        }

        let trimmedTranslation = ChatTranslationText.sanitized(translatedText)
        guard let trimmedTranslation else {
            AppLogger.debug("Translation apply skipped — empty or language-code-only text: \(translatedText)")
            return
        }

        var messageDict = existingMessage.toDictionary()
        var metadataDict = plainMetadata(from: existingMessage.metadata)

        let existingOriginal = (metadataDict["_originalContent"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentContent = existingMessage.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (existingOriginal?.isEmpty ?? true),
           let currentContent,
           !currentContent.isEmpty,
           currentContent != trimmedTranslation {
            metadataDict["_originalContent"] = currentContent
        }

        let currentLang = LiveTranslationLanguages.code(
            from: targetLanguage ?? getSelectedLanguage(),
            fallback: "en"
        )
        metadataDict["_translationLanguage"] = currentLang

        if !metadataDict.isEmpty {
            messageDict["metadata"] = metadataDict
        }

        messageDict["translation"] = trimmedTranslation

        let incomingDetect = detectLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let incomingDetect, !incomingDetect.isEmpty {
            messageDict["detectLanguage"] = incomingDetect
        } else if messageDict["detectLanguage"] == nil,
                  let existingDetect = existingMessage.detectLanguage?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !existingDetect.isEmpty {
            messageDict["detectLanguage"] = existingDetect
        }

        guard let newMessage = ConversationMessage.fromDictionary(messageDict) else {
            AppLogger.debug("Translation apply failed — could not rebuild message \(messageId)")
            return
        }

        // Update message first so groupedMessages already carries `translation`
        // before `showingTranslations` triggers a cell reconfigure.
        stateManager.updateMessage(newMessage)
        messageSyncCoordinator.persist(messages: [newMessage])

        if !newMessage.id.isEmpty {
            showingTranslations.insert(newMessage.id)
        }

        AppLogger.debug("Message translation updated successfully: \(newMessage.id)")
    }

    // MARK: - System Message Side Effects

    func handleSystemMessageSideEffects(_ message: ConversationMessage) {
        guard let metadata = message.metadata else { return }

        let isSystem = metadata["isSystem"]?.value as? Bool ?? false
        guard isSystem else { return }

        let action = metadata["action"]?.value as? String ?? ""
        let convId = message.conversationId
        guard convId == selectedId else { return }

        switch action {
        case "left", "removed":
            guard let memberId = metadata["participantId"]?.value as? String, !memberId.isEmpty else { return }
            AppLogger.debug("[SystemMsg] Member \(action): \(memberId) in \(convId)")
            if memberId == getCurrentUserId() {
                isGroupParticipant = false
                onConversationDeleted?()
            } else {
                groupParticipants.removeAll { $0.userId == memberId }
                if let count = participantsCount, count > 0 {
                    participantsCount = count - 1
                }
                Task.detached(priority: .utility) {
                    try? await ConversationRepository().removeParticipant(conversationId: convId, userId: memberId)
                }
            }

        case "added":
            AppLogger.debug("[SystemMsg] Member added in \(convId)")
            if let count = participantsCount {
                participantsCount = count + 1
            }
            refreshHeaderData()

        case "admin_promoted":
            guard let targetId = metadata["targetUserId"]?.value as? String else { return }
            AppLogger.debug("[SystemMsg] Admin promoted: \(targetId) in \(convId)")
            updateParticipantRole(targetId, newRole: "admin")

        case "admin_demoted":
            guard let targetId = metadata["targetUserId"]?.value as? String else { return }
            AppLogger.debug("[SystemMsg] Admin demoted: \(targetId) in \(convId)")
            updateParticipantRole(targetId, newRole: "member")

        case "title_change":
            guard let newTitle = metadata["newTitle"]?.value as? String, !newTitle.isEmpty else { return }
            AppLogger.debug("[SystemMsg] Title changed to: \(newTitle) in \(convId)")
            groupTitle = newTitle

        case "icon_change":
            let newIcon = metadata["newIcon"]?.value as? String
            AppLogger.debug("[SystemMsg] Group icon changed in \(convId) newIcon=\(newIcon ?? "nil")")
            if let newIcon, !newIcon.isEmpty {
                conversationAvatarURL = newIcon
            }
            refreshHeaderData()

        default:
            break
        }
    }

    private func updateParticipantRole(_ userId: String, newRole: String) {
        guard let index = groupParticipants.firstIndex(where: { $0.userId == userId }) else { return }
        let current = groupParticipants[index]
        groupParticipants[index] = GroupParticipant(
            id: current.id,
            userId: current.userId,
            role: newRole,
            userName: current.userName,
            fullName: current.fullName,
            profilePicture: current.profilePicture,
            isVerified: current.isVerified
        )
    }

    func handlePinSystemMessage(_ message: ConversationMessage) {
        switch message.systemAction {
        case "pinned":
            guard let targetId = message.pinnedTargetMessageId else { return }
            let update = PinMessageUpdate(messageId: targetId, conversationId: selectedId, isPinned: true, unpinnedMessageIds: [])
            handlePinMessageUpdate(update)
        case "unpinned":
            if let targetId = message.pinnedTargetMessageId {
                let update = PinMessageUpdate(messageId: targetId, conversationId: selectedId, isPinned: false, unpinnedMessageIds: [])
                handlePinMessageUpdate(update)
            } else {
                refreshCurrentPinnedMessage()
            }
        default:
            break
        }
    }

    // MARK: - Conversation Last Message Update

    func updateConversationLastMessage(_ message: ConversationMessage) {
        if !message.conversationId.isEmpty {
            NotificationCenter.default.post(
                name: NSNotification.Name("ChatLastMessageUpdated"),
                object: nil,
                userInfo: ["conversationId": message.conversationId, "message": message]
            )
        }

        lastMessageUpdatePending = message

        lastMessageUpdateTimer?.invalidate()
        lastMessageUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self, let msg = self.lastMessageUpdatePending else { return }
            self.lastMessageUpdatePending = nil
            guard !msg.conversationId.isEmpty else { return }
            let conversationId = msg.conversationId

            Task { [weak self] in
                do {
                    try await self?.conversationRepository?.updateLastMessage(conversationId: conversationId, message: msg)
                } catch {
                    AppLogger.debug("ChatDetailViewModel: Failed to update last message: \(error)")
                }
            }
        }
    }

    // MARK: - Merge Helpers

    func mergeMessagePreservingContext(
        incoming: ConversationMessage,
        existing: ConversationMessage,
        preserveReactionsWhenMissingFieldOnly: Bool
    ) -> ConversationMessage {
        var merged = incoming

        if preserveReactionsWhenMissingFieldOnly {
            let incomingHadNoReactionsField = merged.reactions == nil && merged.reactionsWrapper == nil
            if incomingHadNoReactionsField,
               let existingReactions = existing.reactions,
               !existingReactions.isEmpty {
                merged.reactions = existingReactions
            }
        } else if (merged.reactions == nil || merged.reactions?.isEmpty == true),
                  let existingReactions = existing.reactions,
                  !existingReactions.isEmpty {
            merged.reactions = existingReactions
        }

        var mergedDict = merged.toDictionary()

        if (merged.detectLanguage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
           let existingLanguage = existing.detectLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existingLanguage.isEmpty {
            mergedDict["detectLanguage"] = existingLanguage
        }

        if (merged.translation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
           let existingTranslation = existing.translation?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existingTranslation.isEmpty {
            mergedDict["translation"] = existingTranslation
        }

        var mergedMetadata = plainMetadata(from: merged.metadata)
        let existingMetadata = plainMetadata(from: existing.metadata)
        if mergedMetadata["_originalContent"] == nil,
           let existingOriginal = existingMetadata["_originalContent"] as? String,
           !existingOriginal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mergedMetadata["_originalContent"] = existingOriginal
        }

        if let storedOriginal = mergedMetadata["_originalContent"] as? String {
            let trimmedOriginal = storedOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTranslation = (mergedDict["translation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedContent = (mergedDict["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmedOriginal.isEmpty,
               let trimmedTranslation,
               !trimmedTranslation.isEmpty,
               trimmedContent == trimmedTranslation {
                mergedDict["content"] = trimmedOriginal
            }
        } else {
            let trimmedTranslation = (mergedDict["translation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedContent = (mergedDict["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let existingContent = existing.content?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let trimmedTranslation,
               !trimmedTranslation.isEmpty,
               trimmedContent == trimmedTranslation,
               let existingContent,
               !existingContent.isEmpty,
               existingContent != trimmedTranslation {
                mergedDict["content"] = existingContent
                mergedMetadata["_originalContent"] = existingContent
            }
        }

        if !mergedMetadata.isEmpty {
            mergedDict["metadata"] = mergedMetadata
        }

        return ConversationMessage.fromDictionary(mergedDict) ?? merged
    }

    func plainMetadata(from metadata: [String: AnyCodable]?) -> [String: Any] {
        guard let metadata else { return [:] }
        var plain: [String: Any] = [:]
        for (key, value) in metadata {
            plain[key] = value.jsonCompatibleValue
        }
        return plain
    }
}
