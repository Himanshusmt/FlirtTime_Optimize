//
//  ConversationMessage.swift
//  FlirttimeNew
//
//  Created by Awais on 05/08/25.
//

import Foundation

// MARK: - Individual Message
struct ConversationMessage: Codable {
    let id: String
    let conversationId: String
    let channelId: String?
    var sender: ConversationMessageSender?
    let type: String?
    let messageType: String?
    var content: String?
    let media: [ConversationMedia]?
    let thumbnail: String?
    var replyToId: ReplyToMessage?
    var isEdited: Bool?
    var statuses: [MessageStatus]?
    let myStatus: MessageStatus?
    var status: String?
    var metadata: [String: AnyCodable]?
    var serverLocation: ServerLocationSimple?
    let createdAt: String
    var updatedAt: String?
    var reactions: [MessageReaction]?
    let reactionsWrapper: MessageReactionsWrapper?

    var seenAt: String?
    var deliveredAt: String?
    var sentAt: String?
    var isDeleted: Bool?
    let isStreamAvailable: Bool?
    let streamId: String?

    // Translation fields
    var translation: String?
    let detectLanguage: String?

    // Pin message field
    var isPinned: Bool?

    // View Once media fields
    let isViewOnce: Bool?
    var isViewed: Bool?

    // Socket-specific fields
    var senderId: String?

    // Media content properties
    let post: Post?
    /// NEW FE: top-level `sharedPost` on `type: "post"` messages (post / vibe / reel share cards).
    let sharedPost: SharedChatPost?
    let reel: ReelResponse?
    let story: ChatStory?
    var poll: PollData?

    enum CodingKeys: String, CodingKey {
        case id, type, content, body, media, medias, thumbnail, statuses, myStatus, status, metadata, post, sharedPost, reel, story, poll, reactions, reactionsWrapper
        case messageType
        case conversationId
        case channelId
        case sender, senderId
        case replyToId
        case serverLocation = "location"
        case createdAt, updatedAt, isEdited, isDeleted, isStreamAvailable, streamId
        case seenAt, deliveredAt, sentAt
        case translation, detectLanguage
        case isPinned, isViewOnce, isViewed
        case replyTo
        case clientMessageId, clientMsgId
        case receiptStatus
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type)
        // NEW API: `body` → UI `content`
        content = try container.decodeIfPresent(String.self, forKey: .content)
            ?? container.decodeIfPresent(String.self, forKey: .body)
        // Soft-decode media/status/poll so one bad field cannot drop the whole page
        let decodedMedia = (try? container.decodeIfPresent([ConversationMedia].self, forKey: .media))
            ?? (try? container.decodeIfPresent([ConversationMedia].self, forKey: .medias))
        media = decodedMedia.map { ConversationMedia.normalizeList($0) }
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
            ?? media?.first?.thumbnail
        statuses = (try? container.decodeIfPresent([MessageStatus].self, forKey: .statuses)) ?? nil
        myStatus = (try? container.decodeIfPresent(MessageStatus.self, forKey: .myStatus)) ?? nil
        // NEW FE uses `receiptStatus`; older payloads use `status`
        status = try container.decodeIfPresent(String.self, forKey: .status)
            ?? container.decodeIfPresent(String.self, forKey: .receiptStatus)
        metadata = try container.decodeIfPresent([String: AnyCodable].self, forKey: .metadata)
        serverLocation = try? container.decodeIfPresent(ServerLocationSimple.self, forKey: .serverLocation)
        post = try? container.decodeIfPresent(Post.self, forKey: .post)
        sharedPost = try? container.decodeIfPresent(SharedChatPost.self, forKey: .sharedPost)
        reel = try? container.decodeIfPresent(ReelResponse.self, forKey: .reel)
        story = try? container.decodeIfPresent(ChatStory.self, forKey: .story)
        poll = try? container.decodeIfPresent(PollData.self, forKey: .poll)
        channelId = try container.decodeIfPresent(String.self, forKey: .channelId)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited)
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted)
        isStreamAvailable = try container.decodeIfPresent(Bool.self, forKey: .isStreamAvailable)
        streamId = try container.decodeIfPresent(String.self, forKey: .streamId)
        seenAt = try container.decodeIfPresent(String.self, forKey: .seenAt)
        deliveredAt = try container.decodeIfPresent(String.self, forKey: .deliveredAt)
        sentAt = try container.decodeIfPresent(String.self, forKey: .sentAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned)
        isViewOnce = try container.decodeIfPresent(Bool.self, forKey: .isViewOnce)
        isViewed = try container.decodeIfPresent(Bool.self, forKey: .isViewed)
        let decodedMessageType = try container.decodeIfPresent(String.self, forKey: .messageType)
        messageType = decodedMessageType ?? type
        senderId = try container.decodeIfPresent(String.self, forKey: .senderId)
        sender = try container.decodeIfPresent(ConversationMessageSender.self, forKey: .sender)

        // NEW API: `replyToId` is a UUID string + optional `replyTo` preview `{ id, body, senderId, type }`.
        // OLD API: `replyToId` / `replyTo` were nested ReplyToMessage objects.
        if let preview = try? container.decode(ReplyToMessage.self, forKey: .replyTo) {
            if (preview.id ?? "").isEmpty,
               let replyId = try? container.decode(String.self, forKey: .replyToId),
               !replyId.isEmpty {
                replyToId = ReplyToMessage(
                    id: replyId,
                    content: preview.content,
                    type: preview.type,
                    poll: preview.poll,
                    location: preview.location,
                    media: preview.media,
                    thumbnail: preview.thumbnail,
                    sender: preview.sender
                )
            } else {
                replyToId = preview
            }
        } else if let replyId = try? container.decode(String.self, forKey: .replyToId),
                  !replyId.isEmpty {
            replyToId = ReplyToMessage(id: replyId, sender: ReplyToSender())
        } else if let nested = try? container.decode(ReplyToMessage.self, forKey: .replyToId) {
            replyToId = nested
        } else {
            replyToId = nil
        }

        detectLanguage = try container.decodeIfPresent(String.self, forKey: .detectLanguage)

        // Decode reactions (supports both flat array and wrapper format)
        if container.contains(.reactions) {
            if let arr = try? container.decode([MessageReaction].self, forKey: .reactions) {
                reactions = arr
                reactionsWrapper = nil
            } else if let wrapper = try? container.decode(MessageReactionsWrapper.self, forKey: .reactions) {
                reactionsWrapper = wrapper
                reactions = wrapper.data
            } else {
                reactions = nil
                reactionsWrapper = nil
            }
        } else if container.contains(.reactionsWrapper) {
            reactionsWrapper = try container.decodeIfPresent(MessageReactionsWrapper.self, forKey: .reactionsWrapper)
            reactions = reactionsWrapper?.data
        } else {
            reactions = nil
            reactionsWrapper = nil
        }

        // Handle translation: either a String or a Map [String: String]
        // Never keep a bare language code (`en`/`ru`) as the displayed translation text.
        if let translationString = try? container.decode(String.self, forKey: .translation) {
            translation = ChatTranslationText.sanitized(translationString)
        } else if let translationMap = try? container.decode([String: String].self, forKey: .translation) {
            let preferredLanguage = getSelectedLanguage().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            translation = ChatTranslationText.fromMap(translationMap, preferredLanguage: preferredLanguage)
        } else {
            translation = nil
        }

        // NEW clientMessageId / clientMsgId → metadata.clientTempId (optimistic match)
        let clientId = (try? container.decodeIfPresent(String.self, forKey: .clientMessageId))
            ?? (try? container.decodeIfPresent(String.self, forKey: .clientMsgId))
        if let clientId, !clientId.isEmpty {
            var meta = metadata ?? [:]
            if meta["clientTempId"] == nil {
                meta["clientTempId"] = AnyCodable(clientId)
                metadata = meta
            }
        }

        // Media messages: seed content from first media URL when body is empty (UI fallbacks)
        if (content ?? "").isEmpty,
           let firstURL = media?.first?.url, !firstURL.isEmpty {
            let kind = (messageType ?? type ?? media?.first?.type ?? "").lowercased()
            if ["image", "video", "audio", "voice"].contains(kind) {
                content = firstURL
            }
        }
    }
    
    // Custom encoder
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encodeIfPresent(channelId, forKey: .channelId)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(media, forKey: .media)
        try container.encodeIfPresent(thumbnail, forKey: .thumbnail)
        try container.encodeIfPresent(statuses, forKey: .statuses)
        try container.encodeIfPresent(myStatus, forKey: .myStatus)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        try container.encodeIfPresent(post, forKey: .post)
        try container.encodeIfPresent(sharedPost, forKey: .sharedPost)
        try container.encodeIfPresent(reel, forKey: .reel)
        try container.encodeIfPresent(story, forKey: .story)
        try container.encodeIfPresent(poll, forKey: .poll)
        try container.encodeIfPresent(reactions, forKey: .reactions)
        try container.encodeIfPresent(sender, forKey: .sender)
        try container.encodeIfPresent(senderId, forKey: .senderId)
        try container.encodeIfPresent(messageType, forKey: .messageType)
        try container.encodeIfPresent(replyToId, forKey: .replyToId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(isEdited, forKey: .isEdited)
        try container.encodeIfPresent(isDeleted, forKey: .isDeleted)
        try container.encodeIfPresent(isStreamAvailable, forKey: .isStreamAvailable)
        try container.encodeIfPresent(streamId, forKey: .streamId)
        try container.encodeIfPresent(seenAt, forKey: .seenAt)
        try container.encodeIfPresent(deliveredAt, forKey: .deliveredAt)
        try container.encodeIfPresent(sentAt, forKey: .sentAt)
        try container.encodeIfPresent(translation, forKey: .translation)
        try container.encodeIfPresent(detectLanguage, forKey: .detectLanguage)
        try container.encodeIfPresent(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(isViewOnce, forKey: .isViewOnce)
        try container.encodeIfPresent(isViewed, forKey: .isViewed)
    }

    var fromSelf: Bool {
        return false
    }
    
    var canTranslate: Bool {
        guard let detectedLanguage = detectLanguage,
              !detectedLanguage.isEmpty,
              detectedLanguage != "en" else {
            return false
        }
        return true
    }
    
    var hasTranslation: Bool {
        return ChatTranslationText.sanitized(translation) != nil
    }
    
    func toMessageResponse(currentUserId: String) -> MessageResponse {
        var dictionary: [String: Any] = [
            "id": id,
            "message": content ?? "",
            "message_type": type ?? "",
            "createdAt": createdAt,
            "fromSelf": sender?.id == currentUserId
        ]
        
        // Add optional fields if they exist
        if let updatedAt = updatedAt {
            dictionary["updatedAt"] = updatedAt
        }
        if let isEdited = isEdited {
            dictionary["is_edited"] = isEdited
        }
        if let status = status {
            dictionary["status"] = status
        }
        if let metadata = metadata {
            // Convert [String:AnyCodable] -> [String:Any] for downstream consumers
            var plain: [String: Any] = [:]
            for (k, v) in metadata {
                plain[k] = v.value
            }
            dictionary["meta"] = plain
        }
        if let seenAt = seenAt {
            dictionary["seen_at"] = seenAt
        }
        if let deliveredAt = deliveredAt {
            dictionary["delevired_at"] = deliveredAt
        }
        if let sentAt = sentAt {
            dictionary["sent_at"] = sentAt
        }
        if let isDeleted = isDeleted {
            dictionary["is_deleted"] = isDeleted
        }
        if let isStreamAvailable = isStreamAvailable {
            dictionary["is_stream_available"] = isStreamAvailable
        }
        if let streamId = streamId {
            dictionary["streamId"] = streamId
        }
        
        return MessageResponse(dictionary: dictionary)
    }

    static func normalizeMediaDictionary(_ item: [String: Any]) -> [String: Any] {
        var m = item
        if m["type"] == nil, let kind = m["kind"] { m["type"] = kind }
        if let type = m["type"] as? String, type.lowercased() == "photo" {
            m["type"] = "image"
        }
        if m["thumbnail"] == nil, let thumb = m["thumbnailUrl"] { m["thumbnail"] = thumb }
        let urlEmpty = (m["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        if urlEmpty {
            for key in ["publicUrl", "mediaUrl", "filePath"] {
                if let value = m[key] as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    m["url"] = value
                    break
                }
            }
        }
        return m
    }
    
    static func fromDictionary(_ dictionary: [String: Any]) -> ConversationMessage? {
        var modifiedDictionary = dictionary

        // FE / socket delete (and some other) payloads use `messageId` without `id`.
        // Without this remap, Codable falls back to a random UUID and lookups miss.
        let existingId = (modifiedDictionary["id"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingId.isEmpty {
            if let messageId = modifiedDictionary["messageId"] as? String, !messageId.isEmpty {
                modifiedDictionary["id"] = messageId
            } else if let messageId = modifiedDictionary["message_id"] as? String, !messageId.isEmpty {
                modifiedDictionary["id"] = messageId
            }
        }

        // NEW socket/REST payloads use `body` instead of `content`
        if modifiedDictionary["content"] == nil,
           let body = modifiedDictionary["body"] as? String {
            modifiedDictionary["content"] = body
        }

        // NEW API: `medias` → `media` (+ kind/thumbnailUrl/publicUrl aliases)
        if modifiedDictionary["media"] == nil,
           let medias = modifiedDictionary["medias"] as? [[String: Any]] {
            modifiedDictionary["media"] = medias.map { Self.normalizeMediaDictionary($0) }
        } else if var mediaArr = modifiedDictionary["media"] as? [[String: Any]] {
            mediaArr = mediaArr.map { Self.normalizeMediaDictionary($0) }
            modifiedDictionary["media"] = mediaArr
        }

        // Seed content from media URL for image/video when body empty
        if (modifiedDictionary["content"] as? String)?.isEmpty != false {
            let mediaArr = modifiedDictionary["media"] as? [[String: Any]]
            if let url = mediaArr?.first?["url"] as? String, !url.isEmpty {
                let kind = (
                    (modifiedDictionary["messageType"] as? String)
                    ?? (modifiedDictionary["type"] as? String)
                    ?? (mediaArr?.first?["type"] as? String)
                    ?? ""
                ).lowercased()
                if ["image", "video", "audio", "voice"].contains(kind) {
                    modifiedDictionary["content"] = url
                }
            }
        }

        // NEW: top-level `clientMsgId` / `clientMessageId` → metadata.clientTempId (optimistic match key)
        let clientIdKeys = ["clientMsgId", "clientMessageId"]
        for key in clientIdKeys {
            if let clientMsgId = modifiedDictionary[key] as? String, !clientMsgId.isEmpty {
                var meta = modifiedDictionary["metadata"] as? [String: Any] ?? [:]
                if meta["clientTempId"] == nil {
                    meta["clientTempId"] = clientMsgId
                }
                modifiedDictionary["metadata"] = meta
                break
            }
        }

        // Align type / messageType when only one is present
        if modifiedDictionary["messageType"] == nil,
           let type = modifiedDictionary["type"] as? String {
            modifiedDictionary["messageType"] = type
        } else if modifiedDictionary["type"] == nil,
                  let messageType = modifiedDictionary["messageType"] as? String {
            modifiedDictionary["type"] = messageType
        }

        // Persist optimistic flags that are not Codable properties so they survive decode.
        var optimisticMeta = modifiedDictionary["metadata"] as? [String: Any]
            ?? modifiedDictionary["meta"] as? [String: Any]
            ?? [:]
        if let isTemp = modifiedDictionary["isTemporary"] as? Bool {
            optimisticMeta["isTemporary"] = isTemp
        }
        let messageId = (modifiedDictionary["id"] as? String) ?? ""
        if (optimisticMeta["isTemporary"] as? Bool) == true,
           optimisticMeta["clientTempId"] == nil,
           !messageId.isEmpty {
            optimisticMeta["clientTempId"] = messageId
        }
        if !optimisticMeta.isEmpty {
            modifiedDictionary["metadata"] = optimisticMeta
        }

        // Ack payloads often omit status/sentAt — treat as sent so UI leaves the clock icon.
        // Optimistic local bubbles use UUID ids (not a "temp" prefix) and must stay "sending"
        // until the server ack; otherwise the clock/spinner skip straight to a single tick.
        let statusStr = (modifiedDictionary["status"] as? String)?.lowercased() ?? ""
        if statusStr.isEmpty || statusStr == "sending" || statusStr == "pending" {
            let isOptimistic = messageId.hasPrefix("temp")
                || (optimisticMeta["isTemporary"] as? Bool) == true
            if modifiedDictionary["id"] != nil, !isOptimistic {
                modifiedDictionary["status"] = "sent"
                if (modifiedDictionary["sentAt"] as? String)?.isEmpty != false {
                    modifiedDictionary["sentAt"] = modifiedDictionary["createdAt"] as? String ?? modifiedDictionary["sentAt"]
                }
            }
        }

        // Extract senderId from sender.id / sender.userId if not present at top level
        if modifiedDictionary["senderId"] == nil,
           let sender = dictionary["sender"] as? [String: Any] {
            let senderId = (sender["id"] as? String)
                ?? (sender["userId"] as? String)
                ?? (sender["_id"] as? String)
            if let senderId, !senderId.isEmpty {
                modifiedDictionary["senderId"] = senderId
            }
        }

        // Remap "meta" → "metadata" (server sends "meta", model expects "metadata")
        if modifiedDictionary["metadata"] == nil, let meta = modifiedDictionary["meta"] {
            modifiedDictionary["metadata"] = meta
            modifiedDictionary.removeValue(forKey: "meta")
        }

        // For system messages: use server-provided content, or fall back to generated text
        if (modifiedDictionary["type"] as? String) == "system" {
            let existingContent = (modifiedDictionary["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existingContent.isEmpty,
               let metadata = modifiedDictionary["metadata"] as? [String: Any],
               let action = metadata["action"] as? String {
                modifiedDictionary["content"] = Self.systemMessageText(for: action)
            }
        }

        // Convert replyTo string to replyToId object format
        if let replyToIdStr = dictionary["replyTo"] as? String {
            let replyToDict: [String: Any] = [
                "id": replyToIdStr,
                "content": "",
                "type": dictionary["messageType"] as? String ?? "",
                "sender": ["id": "", "userName": "", "fullName": ""]
            ]
            modifiedDictionary["replyToId"] = replyToDict
        } else if let replyToObj = dictionary["replyTo"] as? [String: Any] {
            modifiedDictionary["replyToId"] = replyToObj
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: modifiedDictionary, options: [])
            let conversationMessage = try JSONDecoder().decode(ConversationMessage.self, from: jsonData)
            return conversationMessage
        } catch {
            AppLogger.debug("Error creating ConversationMessage from dictionary: \(error)")
            AppLogger.debug("Dictionary keys: \(modifiedDictionary.keys)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    AppLogger.debug("Missing key: \(key) at path: \(context.codingPath)")
                case .typeMismatch(let type, let context):
                    AppLogger.debug("Type mismatch: expected \(type) at path: \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    AppLogger.debug("Value not found: expected \(type) at path: \(context.codingPath)")
                case .dataCorrupted(let context):
                    AppLogger.debug("Data corrupted at path: \(context.codingPath)")
                @unknown default:
                    AppLogger.debug("Unknown decoding error")
                }
            }
            return nil
        }
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]

        dict["id"] = id
        dict["conversationId"] = conversationId
        dict["channelId"] = channelId

        if let sender = sender {
            var senderDict: [String: Any] = [:]
            if let id = sender.id { senderDict["id"] = id }
            if let pic = sender.profilePicture { senderDict["profilePicture"] = pic }
            if let name = sender.userName { senderDict["userName"] = name }
            if let full = sender.fullName { senderDict["fullName"] = full }
            dict["sender"] = senderDict
        }

        if let senderId = senderId {
            dict["senderId"] = senderId
        } else if let senderId = sender?.id {
            dict["senderId"] = senderId
        }

        dict["type"] = type
        dict["messageType"] = messageType
        dict["content"] = content
        dict["translation"] = translation
        dict["detectLanguage"] = detectLanguage

        if let media = media {
            dict["media"] = media.map { mediaItem in
                var mediaDict: [String: Any] = [:]
                mediaDict["id"] = mediaItem.id
                mediaDict["type"] = mediaItem.type
                mediaDict["url"] = mediaItem.url
                mediaDict["fileName"] = mediaItem.fileName
                mediaDict["fileSize"] = mediaItem.fileSize
                mediaDict["duration"] = mediaItem.duration
                mediaDict["thumbnail"] = mediaItem.thumbnail
                mediaDict["streamId"] = mediaItem.streamId
                mediaDict["isStreamAvailable"] = mediaItem.isStreamAvailable
                return mediaDict
            }
        }

        if let replyToId = replyToId {
            dict["replyToId"] = [
                "id": replyToId.id,
                "content": replyToId.content,
                "type": replyToId.type,
                "sender": replyToId.sender.toDictionary()
            ]
        }

        dict["isEdited"] = isEdited
        dict["isDeleted"] = isDeleted
        dict["status"] = status
        dict["createdAt"] = createdAt
        dict["updatedAt"] = updatedAt
        dict["thumbnail"] = thumbnail
        dict["isPinned"] = isPinned
        dict["isViewOnce"] = isViewOnce
        dict["isViewed"] = isViewed
        dict["isStreamAvailable"] = isStreamAvailable
        dict["streamId"] = streamId
        dict["seenAt"] = seenAt
        dict["deliveredAt"] = deliveredAt
        dict["sentAt"] = sentAt

        if let statuses = statuses {
            dict["statuses"] = statuses.map { status -> [String: Any] in
                var s: [String: Any] = [
                    "messageId": status.messageId,
                    "userId": status.userId,
                    "status": status.status
                ]
                if let id = status.id { s["id"] = id }
                if let statusUpdatedAt = status.statusUpdatedAt { s["statusUpdatedAt"] = statusUpdatedAt }
                if let isDeletedForUser = status.isDeletedForUser { s["isDeletedForUser"] = isDeletedForUser }
                if let updatedAt = status.updatedAt { s["updatedAt"] = updatedAt }
                if let createdAt = status.createdAt { s["createdAt"] = createdAt }
                if let conversationId = status.conversationId { s["conversationId"] = conversationId }
                return s
            }
        }

        if let metadata = metadata {
            var plain: [String: Any] = [:]
            for (k, v) in metadata { plain[k] = v.jsonCompatibleValue }
            dict["metadata"] = plain
        }

        if let reactions = reactions {
            dict["reactions"] = reactions.map { reaction in
                var reactionDict: [String: Any] = [:]
                reactionDict["emoji"] = reaction.emoji
                reactionDict["users"] = reaction.users.map { user -> [String: Any] in
                    var userDict: [String: Any] = ["userId": user.userId]
                    if let name = user.userName { userDict["userName"] = name }
                    if let full = user.fullName { userDict["fullName"] = full }
                    if let pic = user.profilePicture { userDict["profilePicture"] = pic }
                    return userDict
                }
                return reactionDict
            }
        }

        if let poll = poll,
           let pollData = try? JSONEncoder().encode(poll),
           let pollDict = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any] {
            dict["poll"] = pollDict
        }

        if let post = post,
           let data = try? JSONEncoder().encode(post),
           let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict["post"] = d
        }
        if let sharedPost = sharedPost,
           let data = try? JSONEncoder().encode(sharedPost),
           let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict["sharedPost"] = d
        }
        if let reel = reel,
           let data = try? JSONEncoder().encode(reel),
           let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict["reel"] = d
        }
        if let story = story,
           let data = try? JSONEncoder().encode(story),
           let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict["story"] = d
        }

        return dict
    }
}

// MARK: - Programmatic Init (CoreData reconstruction, optimistic updates)
extension ConversationMessage {
    init(
        id: String = UUID().uuidString,
        conversationId: String = "",
        channelId: String? = nil,
        sender: ConversationMessageSender? = nil,
        type: String? = nil,
        messageType: String? = nil,
        content: String? = nil,
        media: [ConversationMedia]? = nil,
        thumbnail: String? = nil,
        replyToId: ReplyToMessage? = nil,
        isEdited: Bool? = nil,
        statuses: [MessageStatus]? = nil,
        myStatus: MessageStatus? = nil,
        status: String? = nil,
        metadata: [String: AnyCodable]? = nil,
        serverLocation: ServerLocationSimple? = nil,
        createdAt: String = "",
        updatedAt: String? = nil,
        reactions: [MessageReaction]? = nil,
        reactionsWrapper: MessageReactionsWrapper? = nil,
        seenAt: String? = nil,
        deliveredAt: String? = nil,
        sentAt: String? = nil,
        isDeleted: Bool? = nil,
        isStreamAvailable: Bool? = nil,
        streamId: String? = nil,
        translation: String? = nil,
        detectLanguage: String? = nil,
        senderId: String? = nil,
        post: Post? = nil,
        sharedPost: SharedChatPost? = nil,
        reel: ReelResponse? = nil,
        story: ChatStory? = nil,
        poll: PollData? = nil,
        isPinned: Bool? = nil,
        isViewOnce: Bool? = nil,
        isViewed: Bool? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.channelId = channelId
        self.sender = sender
        self.type = type
        self.messageType = messageType
        self.content = content
        self.media = media
        self.thumbnail = thumbnail
        self.replyToId = replyToId
        self.isEdited = isEdited
        self.statuses = statuses
        self.myStatus = myStatus
        self.status = status
        self.metadata = metadata
        self.serverLocation = serverLocation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reactions = reactions
        self.reactionsWrapper = reactionsWrapper
        self.seenAt = seenAt
        self.deliveredAt = deliveredAt
        self.sentAt = sentAt
        self.isDeleted = isDeleted
        self.isStreamAvailable = isStreamAvailable
        self.streamId = streamId
        self.translation = translation
        self.detectLanguage = detectLanguage
        self.senderId = senderId
        self.post = post
        self.sharedPost = sharedPost
        self.reel = reel
        self.story = story
        self.poll = poll
        self.isPinned = isPinned
        self.isViewOnce = isViewOnce
        self.isViewed = isViewed
    }

    /// Generate display text for system messages based on metadata action.
    static func systemMessageText(for action: String) -> String {
        switch action {
        case "screenshot_taken":
            return "Screenshot captured"
        default:
            return action.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

extension ConversationMessage: Identifiable {}

extension ConversationMessage: Equatable {
    static func == (lhs: ConversationMessage, rhs: ConversationMessage) -> Bool {
        guard lhs.id == rhs.id else { return false }

        // Fast path: if all cheap fields match, skip heavy comparisons
        guard lhs.content == rhs.content
            && lhs.status == rhs.status
            && lhs.isEdited == rhs.isEdited
            && lhs.isDeleted == rhs.isDeleted
            && lhs.updatedAt == rhs.updatedAt
            && lhs.translation == rhs.translation
            && lhs.isPinned == rhs.isPinned else { return false }

        // Reactions: compare count, emojis, and user membership
        let lhsReactions = lhs.reactions
        let rhsReactions = rhs.reactions
        if lhsReactions?.count != rhsReactions?.count { return false }
        if let lhsR = lhsReactions, let rhsR = rhsReactions {
            for (l, r) in zip(lhsR, rhsR) {
                if l.emoji != r.emoji { return false }
                if l.users.count != r.users.count { return false }
            }
        }

        // Statuses: compare count first, then user-status pairs element-wise
        let lhsStatuses = lhs.statuses
        let rhsStatuses = rhs.statuses
        if lhsStatuses?.count != rhsStatuses?.count { return false }
        if let lhsS = lhsStatuses, let rhsS = rhsStatuses {
            for (l, r) in zip(lhsS, rhsS) where l.userId != r.userId || l.status != r.status { return false }
        }

        // myStatus
        if lhs.myStatus?.status != rhs.myStatus?.status { return false }

        // Poll: compare totalVotes, voteCount, and actual voter userIds per option
        if lhs.poll?.totalVotes != rhs.poll?.totalVotes { return false }
        if let lhsPoll = lhs.poll, let rhsPoll = rhs.poll {
            guard lhsPoll.options.count == rhsPoll.options.count else { return false }
            for (l, r) in zip(lhsPoll.options, rhsPoll.options) {
                if l.voteCount != r.voteCount { return false }
                let lVoterIds = Set(l.votes?.map { $0.userId } ?? [])
                let rVoterIds = Set(r.votes?.map { $0.userId } ?? [])
                if lVoterIds != rVoterIds { return false }
            }
        }

        return true
    }
}

// MARK: - Message Type Display

extension ConversationMessage {

    /// Single source of truth: maps a raw message-type string to a localized display name.
    /// Returns empty string for "text" (callers should show content instead).
    static func messageTypeDisplayName(_ rawType: String) -> String {
        switch rawType.lowercased() {
        case "text":             return ""
        case "image", "photo":   return ChatStrings.chat_photo.localizedString()
        case "video":            return ChatStrings.chat_video.localizedString()
        case "audio", "voice":   return ChatStrings.chat_audio.localizedString()
        case "poll":             return ChatStrings.chat_poll.localizedString()
        case "location":         return ChatStrings.chat_location.localizedString()
        case "contact":          return ChatStrings.chat_contact.localizedString()
        case "document":         return ChatStrings.chat_document.localizedString()
        case "sticker":          return ChatStrings.chat_sticker.localizedString()
        case "post":             return ChatStrings.chat_post.localizedString()
        case "reel":             return ChatStrings.chat_reel.localizedString()
        case "story":            return ChatStrings.chat_story.localizedString()
        case "video_call", "videocall":
            return "Video call"
        case "audio_call", "voice_call", "audiocall", "voicecall":
            return "Audio call"
        case "call":
            return ChatStrings.chat_call.localizedString()
        default:                 return ChatStrings.chat_message.localizedString()
        }
    }

    /// Inbox / reply preview for `call` messages → "Audio call" or "Video call".
    static func callPreviewText(content: String?, messageType: String?) -> String {
        callDisplayLabel(content: content, messageType: messageType)
    }

    /// Resolves "Audio call" vs "Video call" from type and/or body text.
    static func callDisplayLabel(content: String?, messageType: String?) -> String {
        let type = (messageType ?? "").lowercased()
        let body = (content ?? "").htmlToString.lowercased()
        if type.contains("video") || body.contains("video") {
            return "Video call"
        }
        if type.contains("audio") || type.contains("voice")
            || body.contains("audio") || body.contains("voice") {
            return "Audio call"
        }
        // Generic `call` with no hint — default to audio (most common)
        return "Audio call"
    }

    /// Returns content for text/unknown types, localized type name for everything else.
    func displayPreviewText() -> String {
        let type = (messageType ?? type ?? "").lowercased()
        if type == "call" || type.contains("call") {
            return Self.callPreviewText(content: content, messageType: type)
        }
        let name = Self.messageTypeDisplayName(type)
        if name.isEmpty {
            return content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        if name == ChatStrings.chat_message.localizedString() {
            return content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? name
        }
        return name
    }
}

// MARK: - Mutation Helpers

extension ConversationMessage {
    mutating func withMetadata(_ metadata: [String: AnyCodable]?) {
        self.metadata = metadata
    }

    mutating func withPinned(_ isPinned: Bool?) {
        self.isPinned = isPinned
    }

    mutating func withReactions(_ reactions: [MessageReaction]?) {
        self.reactions = reactions
    }

    /// Parse react REST/socket envelopes into a **reaction-only** message update.
    /// Never invents a random `id` — returns nil when message id cannot be resolved.
    /// Does not include empty `content`/`createdAt` so callers must merge onto an existing message.
    ///
    /// Supports Android / backend `chat:message:reacted` shapes:
    /// - `{ messageId, reactions }` / `{ id, reactions }`
    /// - `{ data: { messageId|id, reactions } }`
    /// - `{ message: { ... } }`
    /// - map-style reactions `{ "👍": ["userId"] }`
    /// - delta `{ messageId, emoji, userId }` (reactions left nil — caller applies delta)
    static func reactionUpdate(from envelope: [String: Any], fallbackMessageId: String? = nil) -> ConversationMessage? {
        let root: [String: Any] = {
            if let data = envelope["data"] as? [String: Any] {
                if let message = data["message"] as? [String: Any] { return message }
                return data
            }
            if let message = envelope["message"] as? [String: Any] { return message }
            return envelope
        }()

        let messageId = firstNonEmptyString(
            root["id"], root["messageId"], root["message_id"],
            envelope["messageId"], envelope["message_id"],
            fallbackMessageId
        )
        guard !messageId.isEmpty, !messageId.hasPrefix("temp") else { return nil }

        var dict: [String: Any] = ["id": messageId]
        let conversationId = firstNonEmptyString(
            root["conversationId"], root["conversation_id"],
            envelope["conversationId"], envelope["conversation_id"]
        )
        if !conversationId.isEmpty {
            dict["conversationId"] = conversationId
        }

        if let normalized = normalizeReactionsValue(root["reactions"] ?? envelope["reactions"]) {
            dict["reactions"] = normalized
        }

        let updatedAt = firstNonEmptyString(root["updatedAt"], root["updated_at"], envelope["updatedAt"])
        if !updatedAt.isEmpty {
            dict["updatedAt"] = updatedAt
        }

        return fromDictionary(dict)
    }

    /// Incremental fields when server fans out emoji + actor instead of full reactions list.
    static func reactionDelta(from envelope: [String: Any]) -> (messageId: String, conversationId: String?, emoji: String, userId: String)? {
        let root: [String: Any] = {
            if let data = envelope["data"] as? [String: Any] {
                if let message = data["message"] as? [String: Any] { return message }
                return data
            }
            if let message = envelope["message"] as? [String: Any] { return message }
            return envelope
        }()

        let messageId = firstNonEmptyString(
            root["id"], root["messageId"], root["message_id"],
            envelope["messageId"], envelope["message_id"]
        )
        let emoji = firstNonEmptyString(root["emoji"], envelope["emoji"])
        let userId = firstNonEmptyString(
            root["userId"], root["user_id"], root["reactorId"], root["reactor_id"],
            envelope["userId"], envelope["user_id"]
        )
        guard !messageId.isEmpty, !emoji.isEmpty, !userId.isEmpty else { return nil }

        let conversationId = firstNonEmptyString(
            root["conversationId"], root["conversation_id"],
            envelope["conversationId"], envelope["conversation_id"]
        )
        return (messageId, conversationId.isEmpty ? nil : conversationId, emoji, userId)
    }

    private static func firstNonEmptyString(_ values: Any?...) -> String {
        for value in values {
            if let s = value as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }

    /// Normalize reactions to `[[emoji, users[{userId}]]]` for `fromDictionary`.
    private static func normalizeReactionsValue(_ raw: Any?) -> [[String: Any]]? {
        guard let raw else { return nil }

        if let arr = raw as? [[String: Any]] {
            return arr.map { item -> [String: Any] in
                var out = item
                if out["users"] == nil {
                    if let userIds = item["userIds"] as? [String] {
                        out["users"] = userIds.map { ["userId": $0] }
                    } else if let userIds = item["user_ids"] as? [String] {
                        out["users"] = userIds.map { ["userId": $0] }
                    } else if let users = item["users"] as? [String] {
                        out["users"] = users.map { ["userId": $0] }
                    }
                } else if let users = item["users"] as? [String] {
                    out["users"] = users.map { ["userId": $0] }
                }
                return out
            }
        }

        // Map style: { "👍": ["u1","u2"] } or { "👍": [{ userId: "u1" }] }
        if let map = raw as? [String: Any] {
            var result: [[String: Any]] = []
            for (emoji, value) in map {
                var users: [[String: Any]] = []
                if let ids = value as? [String] {
                    users = ids.map { ["userId": $0] }
                } else if let objs = value as? [[String: Any]] {
                    users = objs.map { obj in
                        if obj["userId"] != nil || obj["user_id"] != nil { return obj }
                        return obj
                    }
                }
                result.append(["emoji": emoji, "users": users])
            }
            return result
        }

        return nil
    }

    /// Toggle `userId` on `emoji` (server react toggle semantics).
    static func applyingReactionDelta(
        _ reactions: [MessageReaction],
        emoji: String,
        userId: String
    ) -> [MessageReaction] {
        var groups = reactions
        if let idx = groups.firstIndex(where: { $0.emoji == emoji && $0.users.contains(where: { $0.userId == userId }) }) {
            groups[idx].users.removeAll { $0.userId == userId }
            groups.removeAll { $0.users.isEmpty }
            return groups
        }
        for i in groups.indices {
            groups[i].users.removeAll { $0.userId == userId }
        }
        groups.removeAll { $0.users.isEmpty }
        if let idx = groups.firstIndex(where: { $0.emoji == emoji }) {
            groups[idx].users.append(ReactionUser(userId: userId))
        } else {
            groups.append(MessageReaction(emoji: emoji, users: [ReactionUser(userId: userId)]))
        }
        return groups
    }

    /// True when this payload looks like a reaction fanout rather than a full message.
    var isReactionOnlyPayload: Bool {
        let hasReactionField = reactions != nil || reactionsWrapper != nil
        let contentEmpty = (content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        let noMedia = media?.isEmpty != false
        let noPoll = poll == nil
        let createdEmpty = createdAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasReactionField && contentEmpty && noMedia && noPoll && (createdEmpty || (type == nil && messageType == nil))
    }

    mutating func withEditedContent(_ content: String?, updatedAt: String?) {
        self.content = content
        self.isEdited = true
        self.updatedAt = updatedAt
    }

    mutating func withTranslation(_ translation: String?) {
        self.translation = translation
    }

    var isSystemMessage: Bool {
        if metadata?["isSystem"]?.value as? Bool == true { return true }
        if type?.lowercased() == "system" { return true }
        if messageType?.lowercased() == "system" { return true }
        return false
    }

    /// Parsed shared post / reel / story — prefers NEW FE `sharedPost`, then metadata fallbacks.
    var sharedContentInfo: SharedContentInfo? {
        if let sp = sharedPost {
            let caption = sp.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
            return SharedContentInfo(
                contentId:   sp.postId,
                authorId:    sp.author?.id,
                authorName:  sp.author?.fullName ?? sp.author?.username,
                authorImage: sp.author?.profilePicture,
                caption:     (caption?.isEmpty == false ? caption : nil)
                          ?? Self.captionFromSharedPreview(content),
                mediaType:   sp.mediaType ?? sp.contentType ?? "post",
                contentType: sp.resolvedContentType,
                thumbnail:   sp.thumbnailUrl ?? sp.mediaUrl ?? media?.first?.thumbnail ?? thumbnail
            )
        }

        guard let meta = metadata else { return nil }

        let sc = meta["sharedContent"]?.jsonCompatibleValue as? [String: Any]
        let flagged = meta["isSharedContent"]?.value as? Bool == true
            || meta["isSharedContent"]?.value as? String == "true"
        let topPostId = stringValue(meta["postId"])
            ?? stringValue(meta["reelId"])
            ?? stringValue(meta["originalMediaId"])
        let msgType = (messageType ?? type ?? "").lowercased()
        let isSharedType = ["post", "reel", "story"].contains(msgType)

        guard flagged || sc != nil || (isSharedType && topPostId != nil) else { return nil }

        func scString(_ key: String) -> String? {
            guard let sc else { return nil }
            if let s = sc[key] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            if let n = sc[key] as? NSNumber { return n.stringValue }
            return nil
        }

        let contentId = scString("postId")
            ?? scString("reelId")
            ?? scString("storyId")
            ?? scString("id")
            ?? topPostId

        let caption = scString("caption")
            ?? Self.captionFromSharedPreview(content)

        let resolvedContentType = scString("contentType")
            ?? stringValue(meta["contentType"])
            ?? msgType

        return SharedContentInfo(
            contentId:   contentId,
            authorId:    scString("authorId") ?? stringValue(meta["authorId"]),
            authorName:  scString("authorName") ?? stringValue(meta["authorName"]),
            authorImage: scString("authorImage") ?? stringValue(meta["authorImage"]),
            caption:     caption,
            mediaType:   scString("mediaType") ?? stringValue(meta["mediaType"]) ?? msgType,
            contentType: resolvedContentType,
            thumbnail:   scString("thumbnail")
                      ?? scString("thumbnailUrl")
                      ?? stringValue(meta["thumbnail"])
                      ?? media?.first?.thumbnail
                      ?? thumbnail
        )
    }

    /// Strips the paperclip preview prefix (`📎 caption`) used by shared-post lastMessage/body.
    static func captionFromSharedPreview(_ content: String?) -> String? {
        guard var text = content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("📎") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : text
    }

    private func stringValue(_ any: AnyCodable?) -> String? {
        guard let any else { return nil }
        if let s = any.value as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = any.value as? NSNumber { return n.stringValue }
        return nil
    }

    /// Best-effort content id for navigation from a shared-content bubble.
    var sharedContentId: String? {
        if let id = sharedPost?.postId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return id
        }
        if let id = post?.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty { return id }
        if let id = reel?.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty { return id }
        if let id = story?.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty { return id }
        if let id = sharedContentInfo?.contentId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return id
        }
        return nil
    }

    /// Server `sharedPost.contentType` — `"post"` | `"vibe"` | `"reel"`.
    var sharedContentType: String {
        if let sp = sharedPost {
            return sp.resolvedContentType
        }
        return (sharedContentInfo?.contentType ?? messageType ?? type ?? "post")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Shared vibe with caption only (no image/video). A generated preview
    /// thumbnail is ignored so the native text card is used.
    var isTextOnlySharedVibe: Bool {
        guard sharedContentType == "vibe" else { return false }

        func hasValue(_ value: String?) -> Bool {
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let mediaKind = (sharedPost?.mediaType ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if mediaKind == "image" || mediaKind == "video" || mediaKind == "photo" {
            return false
        }
        if hasValue(sharedPost?.mediaUrl) {
            return false
        }
        if sharedPost == nil {
            let scKind = (sharedContentInfo?.mediaType ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if scKind == "image" || scKind == "video" || scKind == "photo" {
                return false
            }
        }
        if let media, media.contains(where: { hasValue($0.url) || hasValue($0.thumbnail) }) {
            return false
        }
        if let files = post?.fileData, files.contains(where: { hasValue($0.filePath) || hasValue($0.thumbnail) }) {
            return false
        }
        return true
    }

    /// Plain caption for shared post / vibe cards (HTML stripped).
    var sharedCaptionPlainText: String {
        let raw = sharedPost?.caption
            ?? sharedContentInfo?.caption
            ?? post?.caption
            ?? Self.captionFromSharedPreview(content)
            ?? ""
        return raw.htmlToString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Author of the shared post / vibe / reel, when the payload includes one.
    var sharedAuthorUserId: String? {
        let candidates: [String?] = [
            sharedPost?.author?.id,
            sharedContentInfo?.authorId,
            post?.user?.userId,
            post?.user?.id,
            post?.userId
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var sharedAuthorUsername: String? {
        let candidates: [String?] = [
            sharedPost?.author?.username,
            post?.user?.userName
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    struct SharedContentInfo {
        let contentId:  String?
        let authorId:   String?
        let authorName: String?
        let authorImage: String?
        let caption:    String?
        let mediaType:  String?   // "image" | "video" | "post" | "reel" | "story"
        let contentType: String?  // "post" | "vibe" | "reel"
        let thumbnail:  String?
    }

    var systemAction: String? {
        (metadata?["action"]?.value as? String)?.lowercased()
    }

    var pinnedTargetMessageId: String? {
        metadata?["pinnedMessageId"]?.value as? String
    }

    var isPinSystemEvent: Bool {
        guard isSystemMessage, let action = systemAction else { return false }
        return action == "pinned" || action == "unpinned"
    }

    var originalContentForDisplay: String {
        if let metadata,
           let storedOriginal = metadata["_originalContent"]?.value as? String {
            let trimmed = storedOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return content ?? ""
    }

    /// Local optimistic bubble that has not been acknowledged by the server yet.
    var isOptimisticTemporary: Bool {
        if id.hasPrefix("temp") { return true }
        if let flag = metadata?["isTemporary"]?.value as? Bool, flag { return true }
        return false
    }

    var stableId: String {
        let isForwarded = metadata?["isForwarded"]?.value as? Bool == true
        if !isForwarded,
           let clientTempId = metadata?["clientTempId"]?.value as? String,
           !clientTempId.isEmpty {
            return clientTempId
        }
        if !id.isEmpty {
            return id
        }

        let sender = sender?.id ?? senderId ?? "unknown"
        let created = createdAt ?? "unknown-time"
        let body = (content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return "fallback:\(sender)|\(created)|\(body)"
    }
}
