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
        if !address.isEmpty { metadata["address"] = address }

        let locationPayload: [String: Any] = ["lat": lat, "lng": lng, "address": address]
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

        let started = messageService.sendViaREST(
            conversationId: selectedId,
            type: "location",
            body: contentText,
            mediaIds: nil,
            location: locationPayload,
            poll: nil,
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
}
