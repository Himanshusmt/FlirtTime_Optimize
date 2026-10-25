//
//  ChatDetailViewModel+Location.swift
//  FlirttimeNew
//

import Foundation

extension ChatDetailViewModel {

    func sendLocation(locationRequest: SendLocationRequest) {
        guard !isBlocked, !shouldShowBlockView else {
            handleError(.userBlockedError, context: "sendLocation.blocked")
            return
        }
        if isDuplicateInFlightLocation(locationRequest) {
            AppLogger.debug("[sendLocation] ignored duplicate in-flight send")
            return
        }
        if selectedId.isEmpty {
            ensureConversationReady { [weak self] success in
                guard let self else { return }
                if success {
                    self.sendLocation(locationRequest: locationRequest)
                } else {
                    self.handleError(.messageUploadFailed, context: "sendLocation.ensureConversationReady")
                }
            }
            return
        }

        let tempId = UUID().uuidString
        let replyToId = replyingToMessage?.id

        let lat = locationRequest.latitude
        let lng = locationRequest.longitude
        let address = locationRequest.address ?? ""

        MapSnapshotCache.shared.prewarmNow(lat: lat, lng: lng)

        var metadata: [String: String] = [
            "latitude": String(lat),
            "longitude": String(lng),
            "locationType": locationRequest.type.rawValue
        ]
        if let replyToId { metadata["reply_to_id"] = replyToId }
        if !address.isEmpty {
            metadata["address"] = address
            metadata["name"] = address
        }

        let locationPayload: [String: Any] = [
            "lat": lat,
            "lng": lng,
            "latitude": lat,
            "longitude": lng,
            "name": address,
            "address": address
        ]
        let contentText = locationRequest.comment.flatMap { $0.isEmpty ? nil : $0 }
            ?? ChatStrings.chat_locationContent.localizedString()
        let now = isoFormatter.string(from: Date())
        let messageDict: [String: Any] = [
            "id": tempId,
            "conversationId": selectedId,
            "content": contentText,
            "messageType": "location",
            "senderId": getCurrentUserId(),
            "createdAt": now,
            "updatedAt": now,
            "isEdited": false,
            "isDeleted": false,
            "status": "sending",
            "metadata": metadata,
            "location": locationPayload
        ]

        guard let tempMessage = ConversationMessage.fromDictionary(messageDict) else { return }
        stateManager.addMessages([tempMessage])
        tempMessageMapping[tempId] = tempMessage
        PendingMessageStore.shared.save(tempId: tempId, message: tempMessage, conversationId: selectedId)

        let snapshot = stateManager.getGroupedMessagesSnapshot()
        if snapshot != groupedMessages {
            groupedMessages = snapshot
            handleMessageListUpdate(snapshot.flatMap { $0.messages })
        }
        shouldAutoScroll = true

        if ChatMockSeeder.isMockMode {
            let sentMessage = ChatMockSeeder.sentCopy(of: tempMessage)
            replaceTemporaryMessage(tempId: tempId, with: sentMessage)
            updateConversationLastMessage(sentMessage)
            replyingToMessage = nil
            return
        }

        scheduleFailureTimeout(for: tempId)

        let started = messageService.sendLocationViaSocket(
            conversationId: selectedId,
            body: contentText,
            location: locationPayload,
            clientMessageId: tempId,
            replyToId: replyToId
        )
        AppLogger.debug("[sendLocation] socket chat:send_message started=\(started) tempId=\(tempId)")

        if !started {
            markMessageAsFailed(tempId: tempId)
        }
        replyingToMessage = nil
    }

    /// Same coordinates already sitting in a "sending" bubble — a second tap / callback.
    private func isDuplicateInFlightLocation(_ request: SendLocationRequest) -> Bool {
        tempMessageMapping.values.contains { message in
            let type = (message.messageType ?? message.type ?? "").lowercased()
            guard type == "location" else { return false }
            let status = (message.status ?? "").lowercased()
            guard status == "sending" || status == "pending" else { return false }
            let lat = ConversationMessage.coordinateValue(
                message.metadata?["latitude"]?.value ?? message.metadata?["lat"]?.value
            )
            let lng = ConversationMessage.coordinateValue(
                message.metadata?["longitude"]?.value ?? message.metadata?["lng"]?.value
            )
            guard let lat, let lng else { return false }
            return abs(lat - request.latitude) < 0.0001 && abs(lng - request.longitude) < 0.0001
        }
    }
}
