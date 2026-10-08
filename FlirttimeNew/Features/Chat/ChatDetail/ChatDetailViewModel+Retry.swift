//
//  ChatDetailViewModel+Retry.swift
//  FlirttimeNew
//

import Foundation
import Combine
import RxSwift
import Swinject

extension ChatDetailViewModel {

    func resetTimeoutsAfterReconnect() {
        guard !selectedId.isEmpty else { return }
        isAudioUploading = false
        BackgroundUploadService.shared.cancelStuckTasks()
        for (tempId, message) in tempMessageMapping {
            guard message.status != "failed" else { continue }
            guard !activeMediaUploads.contains(tempId) else { continue }
            backgroundTasks[tempId]?.cancel()
            backgroundTasks.removeValue(forKey: tempId)
            messageRetryAttempts.removeValue(forKey: tempId)
            scheduleFailureTimeout(for: tempId)
            AppLogger.debug("[Reconnect] Reset timeout for tempId=\(tempId)")
        }
    }

    func retryPendingMessagesAfterReconnect() {
        guard !selectedId.isEmpty else { return }
        let now = Date()
        let minimumAge: TimeInterval = 5
        for (tempId, message) in tempMessageMapping {
            let type = (message.messageType ?? message.type ?? "text").lowercased()
            guard type == "text", let content = message.content, !content.isEmpty else { continue }
            guard message.status != "failed" else { continue }
            guard let sentDate = isoFormatter.date(from: message.createdAt),
                  now.timeIntervalSince(sentDate) >= minimumAge else { continue }
            AppLogger.debug("[Pending] Retrying tempId=\(tempId) after socket reconnect")
            retryTextSocketEmit(tempId: tempId, content: content, message: message)
        }

        let mediaTypes: Set<String> = ["image", "video"]
        for (tempId, message) in tempMessageMapping {
            let type = (message.messageType ?? message.type ?? "text").lowercased()
            guard mediaTypes.contains(type) else { continue }
            guard message.status != "failed" else { continue }
            guard !activeMediaUploads.contains(tempId) else { continue }
            guard !BackgroundUploadService.shared.isActive(tempId: tempId) else { continue }
            AppLogger.debug("[Pending] Retrying media tempId=\(tempId) type=\(type) via BackgroundUploadService")
            BackgroundUploadService.shared.retry(tempId: tempId)
        }

        for (tempId, message) in tempMessageMapping {
            let type = (message.messageType ?? message.type ?? "text").lowercased()
            guard message.status != "failed" else { continue }
            guard let sentDate = isoFormatter.date(from: message.createdAt),
                  now.timeIntervalSince(sentDate) >= minimumAge else { continue }
            switch type {
            case "audio":
                guard !isAudioUploading else { continue }
                AppLogger.debug("[Pending] Retrying audio tempId=\(tempId) after socket reconnect")
                audioManager.retryAudioSend(tempId: tempId, message: message)
                scheduleFailureTimeout(for: tempId)
            case "location":
                AppLogger.debug("[Pending] Retrying location tempId=\(tempId) after socket reconnect")
                retryLocationMessage(tempId: tempId, message: message)
            case "poll":
                AppLogger.debug("[Pending] Retrying poll tempId=\(tempId) after socket reconnect")
                retryPollMessage(tempId: tempId, message: message)
            default:
                continue
            }
        }
    }

    func retryFailedMessagesOnReconnect() {
        guard !selectedId.isEmpty else { return }
        guard ChatSocketManager.shared.isSocketConnected() else { return }
        let failedEntries = tempMessageMapping.filter { $0.value.status == "failed" }
        guard !failedEntries.isEmpty else { return }
        lastFailedMessageId = nil
        for (tempId, message) in failedEntries {
            var retryMsg = message
            retryMsg.status = "sending"
            tempMessageMapping[tempId] = retryMsg
            stateManager.updateMessage(retryMsg)
            PendingMessageStore.shared.save(tempId: tempId, message: retryMsg, conversationId: isChannel ? channelId : selectedId)
            let type = (retryMsg.messageType ?? retryMsg.type ?? "text").lowercased()
            switch type {
            case "text":
                retryTextMessage(tempId: tempId)
            case "image", "video":
                if !activeMediaUploads.contains(tempId),
                   !BackgroundUploadService.shared.isActive(tempId: tempId) {
                    BackgroundUploadService.shared.retry(tempId: tempId)
                }
            case "audio":
                audioManager.retryAudioSend(tempId: tempId, message: retryMsg)
            case "location":
                retryLocationMessage(tempId: tempId, message: retryMsg)
            case "poll":
                retryPollMessage(tempId: tempId, message: retryMsg)
            default:
                break
            }
        }
    }

    func markMessageAsFailed(tempId: String) {
        messageRetryAttempts.removeValue(forKey: tempId)
        activeMediaUploads.remove(tempId)
        mediaUploadTempIds.remove(tempId)
        lastFailedMessageId = tempId
        backgroundTasks[tempId]?.cancel()
        backgroundTasks.removeValue(forKey: tempId)
        if var failedMessage = tempMessageMapping[tempId] {
            failedMessage.status = "failed"
            tempMessageMapping[tempId] = failedMessage
            stateManager.updateMessage(failedMessage)
            // Keep in PendingMessageStore so the failed bubble survives navigation.
            // The user can tap it to retry; it's removed only on successful ack.
            let conversationKey = isChannel ? channelId : selectedId
            PendingMessageStore.shared.save(tempId: tempId, message: failedMessage, conversationId: conversationKey)
        }
        handleError(.messageUploadFailed, context: "tempMessage")
    }

    func scheduleFailureTimeout(for tempId: String) {
        backgroundTasks[tempId]?.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.handleMessageSendTimeout(tempId: tempId)
            }
        }
        backgroundTasks[tempId] = task
    }

    func handleMessageSendTimeout(tempId: String) {
        guard let msg = tempMessageMapping[tempId], msg.status != "failed" else { return }
        let type = (msg.messageType ?? msg.type ?? "text").lowercased()
        if (["image", "video"].contains(type) && BackgroundUploadService.shared.isActive(tempId: tempId))
            || (type == "audio" && isAudioUploading) {
            scheduleFailureTimeout(for: tempId)
            return
        }
        let attempt = messageRetryAttempts[tempId, default: 0]
        if attempt < 3 {
            messageRetryAttempts[tempId] = attempt + 1
            AppLogger.debug("[SilentRetry] Attempt \(attempt + 1)/3 for tempId=\(tempId)")
            silentlyRetryPendingMessage(tempId: tempId, message: msg)
            backgroundTasks[tempId]?.cancel()
            let task = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.handleMessageSendTimeout(tempId: tempId)
                }
            }
            backgroundTasks[tempId] = task
        } else {
            messageRetryAttempts.removeValue(forKey: tempId)
            markMessageAsFailed(tempId: tempId)
        }
    }

    func silentlyRetryPendingMessage(tempId: String, message: ConversationMessage) {
        let type = (message.messageType ?? message.type ?? "text").lowercased()
        if type == "text" {
            guard ChatSocketManager.shared.isSocketConnected(), let content = message.content else {
                AppLogger.debug("[SilentRetry] Socket offline — will retry on reconnect, tempId=\(tempId)")
                return
            }
            retryTextSocketEmit(tempId: tempId, content: content, message: message)
            AppLogger.debug("[SilentRetry] Re-emitted text via socket tempId=\(tempId)")
        } else if ["image", "video"].contains(type) {
            guard !activeMediaUploads.contains(tempId), !BackgroundUploadService.shared.isActive(tempId: tempId) else {
                AppLogger.debug("[SilentRetry] Upload already in-flight, skipping — tempId=\(tempId)")
                return
            }
            BackgroundUploadService.shared.retry(tempId: tempId)
        } else if type == "audio" {
            guard !activeMediaUploads.contains(tempId), !isAudioUploading else { return }
            audioManager.retryAudioSend(tempId: tempId, message: message)
        } else if type == "location" {
            retryLocationMessage(tempId: tempId, message: message)
        } else if type == "poll" {
            retryPollMessage(tempId: tempId, message: message)
        }
    }

    // MARK: - Tap-to-retry entry point

    func retryFailedMessage(tempId: String) {
        guard var message = tempMessageMapping[tempId] else { return }
        message.status = "sending"
        tempMessageMapping[tempId] = message
        stateManager.updateMessage(message)
        lastFailedMessageId = nil
        PendingMessageStore.shared.save(tempId: tempId, message: message, conversationId: isChannel ? channelId : selectedId)
        let type = (message.messageType ?? message.type ?? "text").lowercased()
        switch type {
        case "text":
            retryTextMessage(tempId: tempId)
        case "image", "video":
            BackgroundUploadService.shared.retry(tempId: tempId)
        case "audio":
            audioManager.retryAudioSend(tempId: tempId, message: message)
        case "location":
            retryLocationMessage(tempId: tempId, message: message)
        case "poll":
            retryPollMessage(tempId: tempId, message: message)
        default:
            break
        }
    }

    func retryTextMessage(tempId: String) {
        guard let failedMessage = tempMessageMapping[tempId] else { return }

        lastFailedMessageId = nil

        if let content = failedMessage.content {
            retryTextSocketEmit(tempId: tempId, content: content, message: failedMessage)
        } else {
            lastFailedMessageId = nil
        }
    }

    func replaceTemporaryMessage(tempId: String, with serverMessage: ConversationMessage) {
        let msgType1 = serverMessage.messageType
        let msgType2 = serverMessage.type

        var updatedServerMessage = serverMessage

        // Cancel silent-retry timeout — message is confirmed
        backgroundTasks[tempId]?.cancel()
        backgroundTasks.removeValue(forKey: tempId)

        // Preserve clientTempId so ConversationMessage.stableId remains the same
        // after replacement — prevents full snapshot rebuild / scroll jump.
        // Clear isTemporary so selection/delete resolve to server `message.id`.
        var meta = updatedServerMessage.metadata ?? [:]
        if meta["clientTempId"] == nil {
            meta["clientTempId"] = AnyCodable(tempId)
        }
        meta.removeValue(forKey: "isTemporary")
        updatedServerMessage.metadata = meta

        // Ack payloads often omit delivery fields — leave the clock icon otherwise
        let statusLower = (updatedServerMessage.status ?? "").lowercased()
        if statusLower.isEmpty || statusLower == "sending" || statusLower == "pending" {
            updatedServerMessage.status = "sent"
        }
        if (updatedServerMessage.sentAt ?? "").isEmpty {
            updatedServerMessage.sentAt = updatedServerMessage.createdAt
        }

        // Re-apply delivered/seen that may have arrived before temp→server id swap.
        // Receipts often land on the optimistic temp row / temp-id cache first.
        var bestCached = MessageDeliveryStatus.unknown
        if let tempMsg = tempMessageMapping[tempId] {
            let tempLive = MessageDeliveryStatus.from(
                status: tempMsg.status,
                sentAt: tempMsg.sentAt,
                deliveredAt: tempMsg.deliveredAt,
                seenAt: tempMsg.seenAt
            )
            bestCached = max(bestCached, tempLive)
            let tempCached = MessageStatusManager.shared.status(for: tempId)
            bestCached = max(bestCached, tempCached)
            if let pending = pendingStatusUpdates[tempId] {
                bestCached = max(bestCached, pending)
            }
        }
        let serverIdForCache = updatedServerMessage.id
        if !serverIdForCache.isEmpty {
            bestCached = max(bestCached, MessageStatusManager.shared.status(for: serverIdForCache))
            if let pending = pendingStatusUpdates[serverIdForCache] {
                bestCached = max(bestCached, pending)
            }
        }
        if bestCached != .unknown {
            let current = MessageDeliveryStatus.from(
                status: updatedServerMessage.status,
                sentAt: updatedServerMessage.sentAt,
                deliveredAt: updatedServerMessage.deliveredAt,
                seenAt: updatedServerMessage.seenAt
            )
            if bestCached > current {
                updatedServerMessage = updatedServerMessage.withStatus(bestCached)
            }
            if !serverIdForCache.isEmpty {
                registerPendingDeliveryStatus(bestCached, for: [serverIdForCache, tempId])
            }
        }

        // Preserve contact metadata if server response doesn't include it
        if let tempMsg = tempMessageMapping[tempId],
           tempMsg.metadata?["isContact"]?.value as? Bool == true {
            if updatedServerMessage.metadata?["isContact"] == nil {
                updatedServerMessage.metadata?["isContact"] = tempMsg.metadata?["isContact"]
                updatedServerMessage.metadata?["contactName"] = tempMsg.metadata?["contactName"]
                updatedServerMessage.metadata?["contactPhone"] = tempMsg.metadata?["contactPhone"]
            }
        }

        // Preserve mention userIds so @mentions stay bold after REST ack omits metadata
        if let tempMentions = tempMessageMapping[tempId]?.metadata?["mentions"],
           updatedServerMessage.metadata?["mentions"] == nil {
            var merged = updatedServerMessage.metadata ?? [:]
            merged["mentions"] = tempMentions
            updatedServerMessage.metadata = merged
        }

        // Preserve audio duration / waveform seed — REST ack usually omits these
        if let tempMsg = tempMessageMapping[tempId] {
            let tempType = (tempMsg.messageType ?? tempMsg.type ?? "").lowercased()
            let serverType = (updatedServerMessage.messageType ?? updatedServerMessage.type ?? "").lowercased()
            if tempType == "audio" || serverType == "audio" {
                var merged = updatedServerMessage.metadata ?? [:]
                let keysToPreserve = ["audio_duration", "audioDuration", "waveSeed", "filename", "filesize"]
                for key in keysToPreserve {
                    if merged[key] == nil, let value = tempMsg.metadata?[key] {
                        merged[key] = value
                    }
                }
                // If server sent a zero/empty duration, prefer the optimistic value
                if let tempDuration = audioDurationSeconds(from: tempMsg),
                   tempDuration > 0.05 {
                    let serverDuration = audioDurationSeconds(from: updatedServerMessage) ?? 0
                    if serverDuration <= 0.05 {
                        merged["audio_duration"] = AnyCodable(tempDuration)
                        merged["audioDuration"] = AnyCodable(tempDuration)
                    }
                }
                updatedServerMessage.metadata = merged
                let serverId = updatedServerMessage.id
                if !serverId.isEmpty, serverId != tempId {
                    _ = MediaStorageManager.shared.copyMedia(from: tempId, to: serverId, type: .audio)
                }
            }
        }

        // Preserve optimistic createdAt so ack doesn't reorder the bubble (top↔bottom jump).
        if let tempMsg = tempMessageMapping[tempId],
           !tempMsg.createdAt.isEmpty,
           updatedServerMessage.createdAt != tempMsg.createdAt,
           let encoded = try? JSONEncoder().encode(updatedServerMessage),
           var dict = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
            dict["createdAt"] = tempMsg.createdAt
            if (dict["conversationId"] as? String)?.isEmpty != false,
               !tempMsg.conversationId.isEmpty {
                dict["conversationId"] = tempMsg.conversationId
            }
            if dict["channelId"] == nil, let channelId = tempMsg.channelId {
                dict["channelId"] = channelId
            }
            if let preserved = ConversationMessage.fromDictionary(dict) {
                updatedServerMessage = preserved
            }
        }

        // REST may omit body mapping edge-cases — keep optimistic text so the bubble isn't empty
        if (updatedServerMessage.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let tempContent = tempMessageMapping[tempId]?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !tempContent.isEmpty {
            let tempType = (tempMessageMapping[tempId]?.messageType
                ?? tempMessageMapping[tempId]?.type ?? "").lowercased()
            if tempType.isEmpty || tempType == "text" || tempType == "poll" || tempType == "location" {
                updatedServerMessage.content = tempMessageMapping[tempId]?.content
            }
        }

        var fileWasCopied = false

        let serverId = serverMessage.id
        if !serverId.isEmpty {
            let messageType = (serverMessage.messageType ?? serverMessage.type ?? "").lowercased()
            AppLogger.debug("   Final messageType (lowercased): \(messageType)")

            if messageType == "image" {
                let moveResult = MediaStorageManager.shared.moveMedia(from: tempId, to: serverId, type: .image)
                switch moveResult {
                case .success(let localURL):
                    AppLogger.debug("Moved image: \(tempId) -> \(serverId)")
                    updatedServerMessage.content = localURL.absoluteString
                    fileWasCopied = true
                case .failure:
                    if let cachedData = mediaCacheData[tempId] {
                        let result = MediaStorageManager.shared.saveMedia(data: cachedData, messageId: serverId, type: .image)
                        if case .success(let localURL) = result {
                            updatedServerMessage.content = localURL.absoluteString
                            fileWasCopied = true
                        }
                    }
                }
            } else if messageType == "video" {
                let moveResult = MediaStorageManager.shared.moveMedia(from: tempId, to: serverId, type: .video)
                switch moveResult {
                case .success(let localURL):
                    AppLogger.debug("Moved video: \(tempId) -> \(serverId)")
                    updatedServerMessage.content = localURL.absoluteString
                    fileWasCopied = true
                    MediaStorageManager.shared.moveVideoThumbnail(from: tempId, to: serverId)
                case .failure:
                    if let cachedData = mediaCacheData[tempId] {
                        let result = MediaStorageManager.shared.saveMedia(data: cachedData, messageId: serverId, type: .video)
                        if case .success(let localURL) = result {
                            updatedServerMessage.content = localURL.absoluteString
                            fileWasCopied = true
                        }
                    }
                }
            } else if messageType == "audio" {
                let moveResult = MediaStorageManager.shared.moveMedia(from: tempId, to: serverId, type: .audio)
                switch moveResult {
                case .success(let localURL):
                    AppLogger.debug("Moved audio: \(tempId) -> \(serverId)")
                    updatedServerMessage.content = localURL.absoluteString
                    fileWasCopied = true
                    MediaStorageManager.shared.markDownloaded(messageId: serverId)
                case .failure:
                    if let cachedData = mediaCacheData[tempId] {
                        let result = MediaStorageManager.shared.saveMedia(data: cachedData, messageId: serverId, type: .audio)
                        if case .success(let localURL) = result {
                            updatedServerMessage.content = localURL.absoluteString
                            fileWasCopied = true
                            MediaStorageManager.shared.markDownloaded(messageId: serverId)
                        }
                    }
                }
            }
        }

        tempMessageMapping.removeValue(forKey: tempId)
        messageRetryAttempts.removeValue(forKey: tempId)
        activeMediaUploads.remove(tempId)
        // Clear upload UI flag — socket may replace before BG upload finishes;
        // without this, bindings keep the progress spinner after the sent tick.
        mediaUploadTempIds.remove(tempId)
        PendingMessageStore.shared.remove(tempId: tempId)

        let serverId2 = updatedServerMessage.id
        if !serverId2.isEmpty {
            transferCachedMedia(from: tempId, to: serverId2)
            InMemoryMediaCache.shared.transfer(from: tempId, to: serverId2)
            InMemoryMediaCache.shared.transfer(from: tempId + "_thumb", to: serverId2 + "_thumb")
        }

        stateManager.replaceMessage(tempId: tempId, with: updatedServerMessage)
        messageSyncCoordinator.persist(messages: [updatedServerMessage])

        AppLogger.debug("Replaced temp message \(tempId) with server message \(updatedServerMessage.id) - local file: \(fileWasCopied)")
    }

    func tryMatchAndReplaceTemporaryMessage(with serverMessage: ConversationMessage) -> Bool {
        let serverSenderId = serverMessage.senderId ?? serverMessage.sender?.id
        let serverConversationId = serverMessage.conversationId
        let serverMessageType = (serverMessage.messageType ?? serverMessage.type ?? "").lowercased()

        // Prefer exact clientMsgId / clientTempId match (NEW + OLD)
        if let clientTempId = serverMessage.metadata?["clientTempId"]?.value as? String,
           !clientTempId.isEmpty,
           tempMessageMapping[clientTempId] != nil {
            AppLogger.debug("Matched by clientTempId/clientMsgId: \(clientTempId) -> serverId: \(serverMessage.id)")
            replaceTemporaryMessage(tempId: clientTempId, with: serverMessage)
            if lastFailedMessageId == clientTempId || currentError == .messageUploadFailed {
                lastFailedMessageId = nil
                currentError = nil
                canRetryLastError = false
            }
            return true
        }

        if ["image", "video", "audio"].contains(serverMessageType) {
            AppLogger.debug("   Media type detected, checking metadata...")
            AppLogger.debug("   metadata: \(serverMessage.metadata ?? [:])")

            if let metadata = serverMessage.metadata,
               let clientTempId = metadata["clientTempId"]?.value as? String {
                AppLogger.debug("   Found clientTempId in metadata: \(clientTempId)")

                if let tempMessage = tempMessageMapping[clientTempId] {
                    AppLogger.debug("Matched media message by clientTempId: \(clientTempId) -> serverId: \(serverMessage.id)")
                    replaceTemporaryMessage(tempId: clientTempId, with: serverMessage)

                    if lastFailedMessageId == clientTempId || currentError == .messageUploadFailed {
                        lastFailedMessageId = nil
                        currentError = nil
                        canRetryLastError = false
                    }
                    return true
                } else {
                    AppLogger.debug("   clientTempId found but NOT in tempMessageMapping!")
                    AppLogger.debug("   Available tempIds: \(Array(tempMessageMapping.keys))")
                }
            } else {
                AppLogger.debug("   No clientTempId in metadata or metadata is nil")
            }

            AppLogger.debug("clientTempId not found in metadata, trying timestamp matching...")
            let serverCreatedAt = serverMessage.createdAt
            if let serverDate = self.isoFormatter.date(from: serverCreatedAt) {
                for (tempId, tempMessage) in tempMessageMapping {
                    let tempMessageType = (tempMessage.messageType ?? tempMessage.type ?? "").lowercased()
                    guard tempMessageType == serverMessageType,
                          (tempMessage.senderId ?? tempMessage.sender?.id) == serverSenderId,
                          (tempMessage.conversationId) == serverConversationId else {
                        continue
                    }

                    let tempCreatedAt = tempMessage.createdAt
                    if let tempDate = self.isoFormatter.date(from: tempCreatedAt) {
                        let timeDiff = abs(serverDate.timeIntervalSince(tempDate))
                        if timeDiff < 30.0 {
                            AppLogger.debug("Matched by timestamp proximity: \(timeDiff)s (type: \(serverMessageType))")
                            replaceTemporaryMessage(tempId: tempId, with: serverMessage)

                            if lastFailedMessageId == tempId || currentError == .messageUploadFailed {
                                lastFailedMessageId = nil
                                currentError = nil
                                canRetryLastError = false
                            }
                            return true
                        }
                    }
                }
            }

        }

        let serverContent = serverMessage.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        for (tempId, tempMessage) in tempMessageMapping {
            let tempContent = tempMessage.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tempSenderId = tempMessage.senderId ?? tempMessage.sender?.id
            let tempConversationId = tempMessage.conversationId
            let sameThread: Bool = {
                if !serverConversationId.isEmpty, serverConversationId == tempConversationId {
                    return true
                }
                let serverChannel = serverMessage.channelId ?? ""
                let tempChannel = tempMessage.channelId ?? ""
                if !serverChannel.isEmpty, serverChannel == tempChannel {
                    return true
                }
                // Channel optimistic rows often have empty conversationId on both sides
                return isChannel
                    && serverConversationId.isEmpty
                    && tempConversationId.isEmpty
            }()

            guard serverContent == tempContent,
                  serverSenderId == tempSenderId,
                  sameThread else { continue }

            replaceTemporaryMessage(tempId: tempId, with: serverMessage)

            if lastFailedMessageId == tempId || currentError == .messageUploadFailed {
                lastFailedMessageId = nil
                currentError = nil
                canRetryLastError = false
            }
            return true
        }
        return false
    }

    private func retryTextSocketEmit(tempId: String, content: String, message: ConversationMessage) {
        let started = messageService.sendViaREST(
            conversationId: selectedId,
            type: "text",
            body: content,
            mediaIds: nil,
            location: nil,
            poll: nil,
            clientMessageId: tempId,
            replyToId: message.replyToId?.id
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
        scheduleFailureTimeout(for: tempId)
    }

    private func retryLocationMessage(tempId: String, message: ConversationMessage) {
        let contentText = message.content ?? "Location"
        var locationPayload: [String: Any]?
        if let latStr = message.metadata?["latitude"]?.value as? String, let lat = Double(latStr),
           let lngStr = message.metadata?["longitude"]?.value as? String, let lng = Double(lngStr) {
            locationPayload = [
                "lat": lat,
                "lng": lng,
                "address": message.metadata?["address"]?.value as? String ?? ""
            ]
        }
        let started = messageService.sendViaREST(
            conversationId: selectedId,
            type: "location",
            body: contentText,
            mediaIds: nil,
            location: locationPayload,
            poll: nil,
            clientMessageId: tempId,
            replyToId: message.replyToId?.id
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
        scheduleFailureTimeout(for: tempId)
    }

    private func retryPollMessage(tempId: String, message: ConversationMessage) {
        guard let poll = message.poll else { return }
        let pollPayload: [String: Any] = [
            "question": poll.question,
            "options": poll.options.map { $0.text },
            "allowMultiple": poll.settings?.multipleAnswers ?? false
        ]
        let started = messageService.sendViaREST(
            conversationId: selectedId,
            type: "poll",
            body: poll.question,
            mediaIds: nil,
            location: nil,
            poll: pollPayload,
            clientMessageId: tempId,
            replyToId: message.replyToId?.id
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
        scheduleFailureTimeout(for: tempId)
    }
}
