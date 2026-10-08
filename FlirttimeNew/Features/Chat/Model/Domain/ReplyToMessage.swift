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
        id = try c.decodeIfPresent(String.self, forKey: .id)
        // NEW `body` | OLD `content`
        content = try c.decodeIfPresent(String.self, forKey: .content)
            ?? c.decodeIfPresent(String.self, forKey: .body)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        poll = try c.decodeIfPresent(PollData.self, forKey: .poll)
        location = try c.decodeIfPresent(ServerLocationSimple.self, forKey: .location)
        media = try c.decodeIfPresent([ConversationMedia].self, forKey: .media)
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail)

        if let decodedSender = try c.decodeIfPresent(ReplyToSender.self, forKey: .sender) {
            sender = decodedSender
        } else {
            // NEW API: only `senderId` on reply preview
            let senderId = try c.decodeIfPresent(String.self, forKey: .senderId)
            sender = ReplyToSender(id: senderId)
        }
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
}

struct ReplyToSender: Codable {
    let id: String?
    let userName: String?
    let fullName: String?
    let profilePicture: String?

    enum CodingKeys: String, CodingKey {
        case id, userName, username, fullName, profilePicture
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
        id = try c.decodeIfPresent(String.self, forKey: .id)
        userName = try c.decodeIfPresent(String.self, forKey: .userName)
            ?? c.decodeIfPresent(String.self, forKey: .username)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        profilePicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
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
