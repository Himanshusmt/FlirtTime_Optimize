//
//  ReplyToMessage.swift
//  FlirttimeNew
//

import Foundation

// MARK: - Reply To Message
/// UI reply preview. Supports:
/// - NEW API `replyTo`: `{ id, body, senderId, type }` (+ string `replyToId`)
/// - OLD API nested object with `content` + `sender`
struct ReplyToMessage: Codable {
    let id: String?
    let content: String?
    let type: String?
    let poll: PollData?
    let location: ServerLocationSimple?
    let media: [ConversationMedia]?
    let thumbnail: String?
    let sender: ReplyToSender

    enum CodingKeys: String, CodingKey {
        case id, content, body, type, poll, location, media, thumbnail, sender, senderId
    }

    init(
        id: String? = nil,
        content: String? = nil,
        type: String? = nil,
        poll: PollData? = nil,
        location: ServerLocationSimple? = nil,
        media: [ConversationMedia]? = nil,
        thumbnail: String? = nil,
        sender: ReplyToSender = ReplyToSender()
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.poll = poll
        self.location = location
        self.media = media
        self.thumbnail = thumbnail
        self.sender = sender
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.decodeFlexibleString(c, forKey: .id)
        // NEW `body` | OLD `content`
        content = Self.decodeFlexibleString(c, forKey: .content)
            ?? Self.decodeFlexibleString(c, forKey: .body)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        poll = try c.decodeIfPresent(PollData.self, forKey: .poll)
        location = try c.decodeIfPresent(ServerLocationSimple.self, forKey: .location)
        media = try c.decodeIfPresent([ConversationMedia].self, forKey: .media)
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail)

        let topLevelSenderId = Self.decodeFlexibleString(c, forKey: .senderId)
        let decodedSender: ReplyToSender
        if let senderObject = try? c.decode(ReplyToSender.self, forKey: .sender) {
            decodedSender = senderObject
        } else if let senderString = Self.decodeFlexibleString(c, forKey: .sender) {
            decodedSender = ReplyToSender(id: senderString)
        } else {
            decodedSender = ReplyToSender(id: topLevelSenderId)
        }

        // NEW API often sends both `senderId` and a sparse `sender` object.
        // Keep names from `sender`, but never drop the top-level id.
        if (decodedSender.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let topLevelSenderId, !topLevelSenderId.isEmpty {
            sender = ReplyToSender(
                id: topLevelSenderId,
                userName: decodedSender.userName,
                fullName: decodedSender.fullName,
                profilePicture: decodedSender.profilePicture
            )
        } else {
            sender = decodedSender
        }
    }

    static func decodeFlexibleString(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let value = try? c.decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = try? c.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? c.decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(poll, forKey: .poll)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(media, forKey: .media)
        try c.encodeIfPresent(thumbnail, forKey: .thumbnail)
        try c.encode(sender, forKey: .sender)
        try c.encodeIfPresent(sender.id, forKey: .senderId)
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id ?? "",
            "content": content ?? "",
            "type": type ?? "",
            "sender": sender.toDictionary()
        ]

        if let thumbnail, !thumbnail.isEmpty {
            dict["thumbnail"] = thumbnail
        }

        return dict
    }

    var resolvedSenderId: String {
        (sender.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasUsableSenderName: Bool {
        if let name = GroupParticipantDisplay.cleanName(sender.fullName),
           !GroupParticipantDisplay.isPlaceholderName(name) {
            return true
        }
        if let name = GroupParticipantDisplay.cleanName(sender.userName),
           !GroupParticipantDisplay.isPlaceholderName(name) {
            return true
        }
        return false
    }

    func mergingMissingSender(from fallback: ReplyToMessage) -> ReplyToMessage {
        let mergedId = resolvedSenderId.isEmpty ? fallback.resolvedSenderId : resolvedSenderId
        let mergedUserName = hasUsableSenderName ? sender.userName : (fallback.sender.userName ?? sender.userName)
        let mergedFullName = hasUsableSenderName ? sender.fullName : (fallback.sender.fullName ?? sender.fullName)
        return ReplyToMessage(
            id: (id?.isEmpty == false) ? id : fallback.id,
            content: (content?.isEmpty == false) ? content : fallback.content,
            type: (type?.isEmpty == false) ? type : fallback.type,
            poll: poll ?? fallback.poll,
            location: location ?? fallback.location,
            media: (media?.isEmpty == false) ? media : fallback.media,
            thumbnail: (thumbnail?.isEmpty == false) ? thumbnail : fallback.thumbnail,
            sender: ReplyToSender(
                id: mergedId.isEmpty ? nil : mergedId,
                userName: mergedUserName,
                fullName: mergedFullName,
                profilePicture: sender.profilePicture ?? fallback.sender.profilePicture
            )
        )
    }

    func withSender(id: String?, userName: String?, fullName: String?, profilePicture: String? = nil) -> ReplyToMessage {
        ReplyToMessage(
            id: self.id,
            content: content,
            type: type,
            poll: poll,
            location: location,
            media: media,
            thumbnail: thumbnail,
            sender: ReplyToSender(
                id: id ?? sender.id,
                userName: userName ?? sender.userName,
                fullName: fullName ?? sender.fullName,
                profilePicture: profilePicture ?? sender.profilePicture
            )
        )
    }
}

struct ReplyToSender: Codable {
    let id: String?
    let userName: String?
    let fullName: String?
    let profilePicture: String?

    enum CodingKeys: String, CodingKey {
        case id, userId, userName, username, fullName, profilePicture
    }

    init(
        id: String? = nil,
        userName: String? = nil,
        fullName: String? = nil,
        profilePicture: String? = nil
    ) {
        self.id = id
        self.userName = userName
        self.fullName = fullName
        self.profilePicture = profilePicture
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.decodeFlexibleString(c, forKey: .id)
            ?? Self.decodeFlexibleString(c, forKey: .userId)
        userName = try c.decodeIfPresent(String.self, forKey: .userName)
            ?? c.decodeIfPresent(String.self, forKey: .username)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        profilePicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
    }

    fileprivate static func decodeFlexibleString(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let value = try? c.decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = try? c.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? c.decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(userName, forKey: .userName)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(profilePicture, forKey: .profilePicture)
    }

    func toDictionary() -> [String: Any] {
        return [
            "id": id ?? "",
            "userName": userName ?? "",
            "fullName": fullName ?? "",
            "profilePicture": profilePicture ?? ""
        ]
    }
}
