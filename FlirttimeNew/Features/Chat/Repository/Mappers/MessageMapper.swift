//
//  MessageMapper.swift
//  FlirttimeNew
//

import Foundation
import CoreData

enum MessageMapper {

    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Data Conversion

    static func toDomain(_ cdMessage: CDMessage, useSenderUserRelationship: Bool = true) -> ConversationMessage? {
        let id = cdMessage.id ?? UUID().uuidString
        let conversationId = cdMessage.conversationId ?? ""
        let content = cdMessage.content
        let messageType = cdMessage.messageType
        let senderId = cdMessage.senderId
        let isEdited = cdMessage.messageIsEdited
        let isDeleted = cdMessage.messageIsDeleted
        let status = cdMessage.status

        var replyToMessage: ReplyToMessage?
        if let json = cdMessage.replyToJSON {
            replyToMessage = decodeJSON(json)
        } else if let replyId = cdMessage.replyToId {
            replyToMessage = ReplyToMessage(
                id: replyId,
                content: "",
                type: messageType,
                sender: ReplyToSender(
                    id: nil,
                    userName: nil,
                    fullName: nil,
                    profilePicture: nil
                )
            )
        }

        let statuses: [MessageStatus]? = decodeJSON(cdMessage.statusesJSON)

        var createdAtStr: String?
        if let date = cdMessage.createdAt {
            createdAtStr = Self.iso8601Formatter.string(from: date)
        }

        var updatedAtStr: String?
        if let date = cdMessage.updatedAt {
            updatedAtStr = Self.iso8601Formatter.string(from: date)
        }

        var media: [ConversationMedia]?
        if let mediaURLs = cdMessage.mediaURLs {
            if mediaURLs.hasPrefix("["), let data = mediaURLs.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([ConversationMedia].self, from: data) {
                media = decoded
            } else {
                let fbType = cdMessage.messageType
                media = mediaURLs.components(separatedBy: ",").filter { !$0.isEmpty }.map { urlStr in
                    return ConversationMedia(url: urlStr, type: fbType, raw: nil)
                }
            }
        }

        let sharedPost: SharedChatPost? = {
            guard let decoded: SharedChatPost = decodeJSON(cdMessage.postData),
                  let postId = decoded.postId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !postId.isEmpty else {
                return nil
            }
            return decoded
        }()
        let post: Post? = sharedPost == nil ? decodeJSON(cdMessage.postData) : nil
        let reel: ReelResponse? = decodeJSON(cdMessage.reelData)
        let story: ChatStory? = decodeJSON(cdMessage.storyData)
        let poll: PollData? = decodeJSON(cdMessage.pollData)

        let serverLocation: ServerLocationSimple? = decodeJSON(cdMessage.locationData)

        let rawMetadata: [String: AnyCodable]? = decodeJSON(cdMessage.metadata)
        let detectLanguage = metadataStringValue(for: "_detectLanguage", in: rawMetadata)
        let translation = ChatTranslationText.sanitized(metadataStringValue(for: "_translation", in: rawMetadata))
        let sentAtStr = metadataStringValue(for: "_sentAt", in: rawMetadata)
        let deliveredAtStr = metadataStringValue(for: "_deliveredAt", in: rawMetadata)
        let seenAtStr = metadataStringValue(for: "_seenAt", in: rawMetadata)
        let metadata = sanitizedMetadata(rawMetadata)

        let reactions: [MessageReaction]? = decodeJSON(cdMessage.reactionsJSON)

        let senderUser = useSenderUserRelationship ? cdMessage.senderUser : nil
        let resolvedFullName = senderUser?.fullName ?? cdMessage.senderFullName
        let resolvedUserName = senderUser?.userName ?? cdMessage.senderUserName
        let resolvedAvatar = senderUser?.profilePicture ?? cdMessage.senderAvatar

        let myStatus: MessageStatus? = decodeJSON(cdMessage.myStatus)

        return ConversationMessage(
            id: id,
            conversationId: conversationId,
            channelId: cdMessage.channelId,
            sender: senderId != nil ? ConversationMessageSender(
                id: senderId,
                userName: resolvedUserName,
                fullName: resolvedFullName,
                profilePicture: resolvedAvatar
            ) : nil,
            type: messageType,
            messageType: messageType,
            content: content,
            media: media,
            thumbnail: cdMessage.thumbnail,
            replyToId: replyToMessage,
            isEdited: isEdited,
            statuses: statuses,
            myStatus: myStatus,
            status: status,
            metadata: metadata,
            serverLocation: serverLocation,
            createdAt: createdAtStr ?? "",
            updatedAt: updatedAtStr,
            reactions: reactions,
            seenAt: seenAtStr,
            deliveredAt: deliveredAtStr,
            sentAt: sentAtStr,
            isDeleted: isDeleted,
            isStreamAvailable: cdMessage.isStreamAvailable,
            streamId: cdMessage.streamId,
            translation: translation,
            detectLanguage: detectLanguage,
            senderId: senderId,
            post: post,
            sharedPost: sharedPost,
            reel: reel,
            story: story,
            poll: poll,
            isPinned: cdMessage.messageIsPinned,
            isViewOnce: cdMessage.isViewOnce,
            isViewed: cdMessage.isViewed
        )
    }

    static func toDomainSnapshot(_ cdMessage: CDMessage) -> ConversationMessage? {
        return toDomain(cdMessage, useSenderUserRelationship: false)
    }

    static func update(
        _ cdMessage: CDMessage,
        from message: ConversationMessage,
        fallbackConversationId: String? = nil,
        preserveExistingPinState: Bool = false
    ) {
        let convId: String = ((message.conversationId != "") ?  message.conversationId : (fallbackConversationId ?? "")) ?? ""
        AppLogger.debug("💾 MessageRepository saving message: id=\(message.id), conversationId='\(convId)')")

        let prevPin = cdMessage.messageIsPinned

        cdMessage.id = message.id
        cdMessage.conversationId = convId
        cdMessage.messageType = message.messageType ?? message.type
        cdMessage.senderId = message.sender?.id ?? message.senderId
        cdMessage.senderFullName = message.sender?.fullName ?? message.sender?.userDetails?.dataValues?.fullName
        cdMessage.senderUserName = message.sender?.userName ?? message.sender?.userDetails?.dataValues?.userName
        cdMessage.senderAvatar = message.sender?.profilePicture ?? message.sender?.userDetails?.dataValues?.profilePicture

        if let senderId = cdMessage.senderId, !senderId.isEmpty,
           let context = cdMessage.managedObjectContext {
            let fullName = cdMessage.senderFullName
            let userName = cdMessage.senderUserName
            let avatar = cdMessage.senderAvatar
            if fullName != nil || userName != nil || avatar != nil {
                let user = upsertCDUser(userId: senderId, fullName: fullName, userName: userName, profilePicture: avatar, in: context)
                cdMessage.senderUser = user
            }
        }
        cdMessage.messageIsEdited = message.isEdited ?? false

        // Never resurrect a locally deleted-for-everyone message from a stale API/preload payload.
        // Socket delete may arrive while the chat is closed; later sync must not undo it.
        let incomingDeleted = message.isDeleted == true
        let locallyDeleted = cdMessage.messageIsDeleted
        if locallyDeleted && !incomingDeleted {
            AppLogger.debug("[ChatRepo] preserving local deleted state id=\(message.id)")
        } else {
            cdMessage.messageIsDeleted = incomingDeleted
            cdMessage.content = message.content
        }
        if preserveExistingPinState {
            if let incomingPinned = message.isPinned {
                if shouldApplyIncomingPinState(existingMessage: cdMessage, incomingMessage: message) {
                    cdMessage.messageIsPinned = incomingPinned
                } else {
                    let updatedAtValue = message.updatedAt ?? "nil"
                    AppLogger.debug("[ChatRepo] pinStateSkippedAsStale id=\(message.id) existing=\(cdMessage.messageIsPinned) incoming=\(incomingPinned) updatedAt=\(updatedAtValue)")
                }
            }
        } else {
            cdMessage.messageIsPinned = message.isPinned ?? false
        }

        let newPin = cdMessage.messageIsPinned
        if prevPin != newPin {
            AppLogger.debug("[ChatRepo] pinStateChanged id=\(message.id) prev=\(prevPin) new=\(newPin) preserveExisting=\(preserveExistingPinState) incoming=\(String(describing: message.isPinned))")
        }
        cdMessage.channelId = message.channelId
        cdMessage.thumbnail = message.thumbnail
        cdMessage.isStreamAvailable = message.isStreamAvailable ?? false
        cdMessage.streamId = message.streamId
        cdMessage.isViewOnce = message.isViewOnce ?? false
        cdMessage.isViewed = message.isViewed ?? false
        if let myStatus = message.myStatus {
            if let data = try? JSONEncoder().encode(myStatus),
               let jsonString = String(data: data, encoding: .utf8) {
                cdMessage.myStatus = jsonString
            }
        } else {
            cdMessage.myStatus = nil
        }
        cdMessage.replyToId = message.replyToId?.id
        if let replyTo = message.replyToId,
           let jsonData = try? JSONEncoder().encode(replyTo),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            cdMessage.replyToJSON = jsonString
        } else {
            cdMessage.replyToJSON = nil
        }

        let incomingStatus = MessageDeliveryStatus.from(message.status)
        if locallyDeleted && !incomingDeleted {
            // Keep deleted status
            if (cdMessage.status ?? "").lowercased() != "deleted" {
                cdMessage.status = "deleted"
            }
        } else if incomingStatus != .unknown {
            let existingStatus = MessageDeliveryStatus.from(cdMessage.status)
            if incomingStatus >= existingStatus {
                cdMessage.status = message.status
            }
        } else {
            cdMessage.status = message.status
        }

        if let statuses = message.statuses {
            let statusDicts = statuses.map { status -> [String: Any] in
                return [
                    "id": status.id as Any,
                    "messageId": status.messageId,
                    "userId": status.userId,
                    "status": status.status,
                    "statusUpdatedAt": status.statusUpdatedAt as Any
                ]
            }
            if let jsonData = try? JSONSerialization.data(withJSONObject: statusDicts, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                cdMessage.statusesJSON = jsonString
            }
        }

        if message.createdAt != "" {
            cdMessage.createdAt = parseDate(from: message.createdAt ?? "")
        }
        if let updatedAt = message.updatedAt {
            cdMessage.updatedAt = parseDate(from: updatedAt)
        }

        if let media = message.media {
            if let mediaData = try? JSONEncoder().encode(media),
               let mediaJSON = String(data: mediaData, encoding: .utf8) {
                cdMessage.mediaURLs = mediaJSON
            } else {
                let mediaURLs = media.compactMap { $0.url }.joined(separator: ",")
                cdMessage.mediaURLs = mediaURLs.isEmpty ? nil : mediaURLs
            }
        }

        // Post / reel / story / NEW FE sharedPost — Codable via JSONEncoder.
        if let sharedPost = message.sharedPost {
            cdMessage.postData = encodeCodableToJSONString(sharedPost)
        } else if let post = message.post {
            cdMessage.postData = encodeCodableToJSONString(post)
        }
        if let reel = message.reel {
            cdMessage.reelData = encodeCodableToJSONString(reel)
        }
        if let story = message.story {
            cdMessage.storyData = encodeCodableToJSONString(story)
        }
        if let poll = message.poll {
            if let pollData = try? JSONEncoder().encode(poll),
               let pollString = String(data: pollData, encoding: .utf8) {
                cdMessage.pollData = pollString
            }
        }
        if let location = message.serverLocation {
            let locationDict: [String: Any?] = [
                "lat": location.lat,
                "lng": location.lng,
                "address": location.address
            ]
            if let locationJSONData = try? JSONSerialization.data(withJSONObject: locationDict, options: []),
               let locationJSONString = String(data: locationJSONData, encoding: .utf8) {
                cdMessage.locationData = locationJSONString
            }
        }
        let hasIncomingTimestamps =
            !(message.sentAt?.isEmpty ?? true)
            || !(message.deliveredAt?.isEmpty ?? true)
            || !(message.seenAt?.isEmpty ?? true)

        let shouldPersistTranslationContext =
            !(message.detectLanguage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(message.translation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || message.metadata != nil
            || hasIncomingTimestamps

        if shouldPersistTranslationContext || (locallyDeleted && !incomingDeleted) {
            var combinedMetadata = convertJSONStringToDict(cdMessage.metadata ?? "") ?? [:]

            if let metadata = message.metadata {
                let incomingMetadataAny = unwrapAnyCodable(metadata)
                if let incomingMetadata = incomingMetadataAny as? [String: Any] {
                    for (key, value) in incomingMetadata {
                        combinedMetadata[key] = value
                    }
                }
            }

            if locallyDeleted || incomingDeleted {
                combinedMetadata["isDeletedEveryone"] = true
            }

            if let detectLanguage = message.detectLanguage?.trimmingCharacters(in: .whitespacesAndNewlines), !detectLanguage.isEmpty {
                combinedMetadata["_detectLanguage"] = detectLanguage
            }

            if let translation = ChatTranslationText.sanitized(message.translation) {
                combinedMetadata["_translation"] = translation

                let existingOriginal = (combinedMetadata["_originalContent"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let incomingContent = message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
                let existingContent = cdMessage.content?.trimmingCharacters(in: .whitespacesAndNewlines)

                if (existingOriginal?.isEmpty ?? true),
                   let incomingContent,
                   !incomingContent.isEmpty,
                   incomingContent == translation,
                   let existingContent,
                   !existingContent.isEmpty,
                   existingContent != translation {
                    combinedMetadata["_originalContent"] = existingContent
                }
            }

            if (combinedMetadata["_sentAt"] as? String)?.isEmpty ?? true,
               let sent = message.sentAt, !sent.isEmpty {
                combinedMetadata["_sentAt"] = sent
            }
            // Always upgrade delivery timestamps when the incoming message carries them
            // (previously only wrote when empty — late "delivered" saves could leave
            // FRC without `_seenAt` after an in-memory seen tick).
            if let delivered = message.deliveredAt, !delivered.isEmpty {
                combinedMetadata["_deliveredAt"] = delivered
            }
            if let seen = message.seenAt, !seen.isEmpty {
                combinedMetadata["_seenAt"] = seen
            }

            cdMessage.metadata = convertDictToJSONString(combinedMetadata)
        }

        if let reactions = message.reactions {
            if reactions.isEmpty {
                cdMessage.reactionsJSON = nil
            } else if let data = try? JSONEncoder().encode(reactions),
               let jsonString = String(data: data, encoding: .utf8) {
                cdMessage.reactionsJSON = jsonString
            }
        } else if message.reactionsWrapper == nil {
        }
    }

    // MARK: - Private Helpers

    private static func decodeJSON<T: Decodable>(_ jsonString: String?) -> T? {
        guard let data = jsonString?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func parseDate(from string: String) -> Date? {
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: string) { return date }

        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601Formatter.date(from: string) { return date }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        if let date = dateFormatter.date(from: string) { return date }

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let date = dateFormatter.date(from: string) { return date }

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        if let date = dateFormatter.date(from: string) { return date }

        AppLogger.debug("parseDate: Failed to parse '\(string)'")
        return nil
    }

    private static func shouldApplyIncomingPinState(existingMessage: CDMessage, incomingMessage: ConversationMessage) -> Bool {
        let existingStamp = existingMessage.updatedAt ?? existingMessage.createdAt
        let incomingUpdated = incomingMessage.updatedAt ?? ""
        let incomingCreated = incomingMessage.createdAt ?? ""
        let incomingStamp = parseDate(from: incomingUpdated) ?? parseDate(from: incomingCreated)

        guard let incomingStamp else { return true }
        guard let existingStamp else { return true }

        return incomingStamp >= existingStamp
    }

    private static func convertJSONStringToDict(_ jsonString: String) -> [String: Any]? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func metadataStringValue(for key: String, in metadata: [String: AnyCodable]?) -> String? {
        guard let value = metadata?[key]?.value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sanitizedMetadata(_ metadata: [String: AnyCodable]?) -> [String: AnyCodable]? {
        guard var metadata = metadata else { return nil }
        metadata.removeValue(forKey: "_detectLanguage")
        metadata.removeValue(forKey: "_translation")
        metadata.removeValue(forKey: "_sentAt")
        metadata.removeValue(forKey: "_deliveredAt")
        metadata.removeValue(forKey: "_seenAt")
        return metadata.isEmpty ? nil : metadata
    }

    private static func convertDictToJSONString(_ dict: Any) -> String? {
        let serializableDict = unwrapAnyCodable(dict)
        guard JSONSerialization.isValidJSONObject(serializableDict),
              let data = try? JSONSerialization.data(withJSONObject: serializableDict),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }

    private static func encodeCodableToJSONString<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }

    private static func unwrapAnyCodable(_ value: Any) -> Any {
        if let anyCodable = value as? AnyCodable {
            return unwrapAnyCodable(anyCodable.value)
        }
        if let dict = value as? [String: AnyCodable] {
            return dict.mapValues { unwrapAnyCodable($0) }
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { unwrapAnyCodable($0) }
        }
        if let array = value as? [AnyCodable] {
            return array.map { unwrapAnyCodable($0) }
        }
        if let array = value as? [Any] {
            return array.map { unwrapAnyCodable($0) }
        }
        if value is String || value is Int || value is Double || value is Bool || value is NSNull {
            return value
        }
        return NSNull()
    }

    // MARK: - CDUser Upsert

    @discardableResult
    private static func upsertCDUser(
        userId: String,
        fullName: String?,
        userName: String?,
        profilePicture: String?,
        in context: NSManagedObjectContext
    ) -> CDUser {
        let request = CDUser.fetchRequest() as NSFetchRequest<CDUser>
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.fetchLimit = 1

        let user = (try? context.fetch(request).first) ?? CDUser(context: context)
        user.userId = userId
        if let fullName { user.fullName = fullName }
        if let userName { user.userName = userName }
        if let profilePicture { user.profilePicture = profilePicture }
        user.updatedAt = Date()
        return user
    }
}
