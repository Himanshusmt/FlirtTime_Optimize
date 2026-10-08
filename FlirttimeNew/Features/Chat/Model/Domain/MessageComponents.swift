//
//  MessageComponents.swift
//  FlirttimeNew
//

import Foundation

// MARK: - Message Types
enum ChatMessageType: String, Codable {
    case text = "text"
    case image = "image"
    case video = "video"
    case audio = "audio"
    case post = "post"
    case reel = "reel"
    case story = "story"
    case poll = "poll"
    case location = "location"
}

// MARK: - NEW FE sharedPost payload on chat messages
/// `GET …/messages` rows with `type: "post"` include this object (not nested `post`).
struct SharedChatPost: Codable, Equatable {
    let postId: String?
    /// `"post"` | `"vibe"` | `"reel"` (server `contentType`)
    let contentType: String?
    let caption: String?
    let thumbnailUrl: String?
    let mediaUrl: String?
    /// `"image"` | `"video"`
    let mediaType: String?
    let author: SharedChatPostAuthor?

    var resolvedContentType: String {
        (contentType ?? "post").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isVibe: Bool { resolvedContentType == "vibe" }
    var isReel: Bool { resolvedContentType == "reel" }
}

struct SharedChatPostAuthor: Codable, Equatable {
    let id: String?
    let username: String?
    let fullName: String?
    let profilePicture: String?
    let isVerified: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, fullName, profilePicture, isVerified
        case userName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        username = try c.decodeIfPresent(String.self, forKey: .username)
            ?? c.decodeIfPresent(String.self, forKey: .userName)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        profilePicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
        isVerified = try c.decodeIfPresent(Bool.self, forKey: .isVerified)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(profilePicture, forKey: .profilePicture)
        try c.encodeIfPresent(isVerified, forKey: .isVerified)
    }
}

// MARK: - Message Sender
struct ConversationMessageSender: Codable {
    let id: String?
    let profilePicture: String?
    let userDetails: UserDetailsWrapper?

    let userName: String?
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case id, userId, profilePicture, userDetails, userName, username, fullName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .userId)
        profilePicture = try container.decodeIfPresent(String.self, forKey: .profilePicture)

        // Handle userDetails which can be a wrapper object or array
        if let wrapper = try? container.decode(UserDetailsWrapper.self, forKey: .userDetails) {
            userDetails = wrapper
            // Extract userName and fullName from wrapper's dataValues
            userName = wrapper.dataValues?.userName
            fullName = wrapper.dataValues?.fullName
        } else {
            userDetails = nil
            userName = try container.decodeIfPresent(String.self, forKey: .userName)
                ?? container.decodeIfPresent(String.self, forKey: .username)
            fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        }
    }

    init(id: String?, userName: String? = nil, fullName: String? = nil, profilePicture: String? = nil, userDetails: UserDetailsWrapper? = nil) {
        self.id = id
        self.userName = userName
        self.fullName = fullName
        self.profilePicture = profilePicture
        self.userDetails = userDetails
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(profilePicture, forKey: .profilePicture)
        try container.encodeIfPresent(userDetails, forKey: .userDetails)
        try container.encodeIfPresent(userName, forKey: .userName)
        try container.encodeIfPresent(fullName, forKey: .fullName)
    }
}

// MARK: - User Details Wrapper (for Sequelize dataValues structure)
struct UserDetailsWrapper: Codable {
    let dataValues: UserDetailsDataValues?
    let previousDataValues: UserDetailsDataValues?
    let uniqno: Int?
    let changed: [String: AnyCodable]?
    let options: UserDetailsOptions?
    let isNewRecord: Bool?
}

struct UserDetailsDataValues: Codable {
    let userName: String?
    let fullName: String?
    let profilePicture: String?
}

struct UserDetailsOptions: Codable {
    let isNewRecord: Bool?
    let schema: String?
    let schemaDelimiter: String?
    let includeValidated: Bool?
    let raw: Bool?
    let attributes: [String]?
}

// MARK: - Message Status
struct MessageStatus: Codable {
    let id: String?
    let messageId: String
    let conversationId: String?
    let userId: String
    let status: String
    let statusUpdatedAt: String?
    let isDeletedForUser: Bool?
    let updatedAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case messageId
        case conversationId
        case userId
        case status
        case statusUpdatedAt
        case isDeletedForUser
        case updatedAt
        case createdAt
    }
}

struct ConversationMedia: Codable {
    let id: String?
    let url: String?
    let type: String?
    let fileName: String?
    let fileSize: Int?
    let duration: Double?
    let thumbnail: String?
    let streamId: String?
    let isStreamAvailable: Bool?
    let raw: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id, url, type, fileName, fileSize, duration, thumbnail, streamId, isStreamAvailable
    }

    private enum FEKeys: String, CodingKey {
        case kind, thumbnailUrl, filename, publicUrl, mediaUrl, filePath
    }

    // Support String, keyed object (NEW FE medias), and loose dictionary
    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           keyed.contains(.url) || keyed.contains(.id) || keyed.contains(.type) || keyed.contains(.thumbnail) {
            let fe = try? decoder.container(keyedBy: FEKeys.self)
            id = try keyed.decodeIfPresent(String.self, forKey: .id)
            url = try keyed.decodeIfPresent(String.self, forKey: .url)
                ?? (try fe?.decodeIfPresent(String.self, forKey: .publicUrl))
                ?? (try fe?.decodeIfPresent(String.self, forKey: .mediaUrl))
                ?? (try fe?.decodeIfPresent(String.self, forKey: .filePath))
            type = try keyed.decodeIfPresent(String.self, forKey: .type)
                ?? (try fe?.decodeIfPresent(String.self, forKey: .kind))
            fileName = try keyed.decodeIfPresent(String.self, forKey: .fileName)
                ?? (try fe?.decodeIfPresent(String.self, forKey: .filename))
            if let size = try? keyed.decodeIfPresent(Int.self, forKey: .fileSize) {
                fileSize = size
            } else if let sizeStr = try? keyed.decodeIfPresent(String.self, forKey: .fileSize) {
                fileSize = Int(sizeStr)
            } else {
                fileSize = nil
            }
            if let d = try? keyed.decodeIfPresent(Double.self, forKey: .duration) {
                duration = d
            } else if let dStr = try? keyed.decodeIfPresent(String.self, forKey: .duration) {
                duration = Double(dStr)
            } else {
                duration = nil
            }
            thumbnail = try keyed.decodeIfPresent(String.self, forKey: .thumbnail)
                ?? (try fe?.decodeIfPresent(String.self, forKey: .thumbnailUrl))
            streamId = try keyed.decodeIfPresent(String.self, forKey: .streamId)
            isStreamAvailable = try keyed.decodeIfPresent(Bool.self, forKey: .isStreamAvailable)
            raw = nil
            return
        }

        // FE object that only has `kind` / `thumbnailUrl` (no OLD keys) — still keyed
        if let fe = try? decoder.container(keyedBy: FEKeys.self),
           fe.contains(.kind) || fe.contains(.thumbnailUrl) || fe.contains(.publicUrl) || fe.contains(.mediaUrl) {
            let keyed = try? decoder.container(keyedBy: CodingKeys.self)
            id = try keyed?.decodeIfPresent(String.self, forKey: .id)
            url = try keyed?.decodeIfPresent(String.self, forKey: .url)
                ?? fe.decodeIfPresent(String.self, forKey: .publicUrl)
                ?? fe.decodeIfPresent(String.self, forKey: .mediaUrl)
                ?? fe.decodeIfPresent(String.self, forKey: .filePath)
            type = try keyed?.decodeIfPresent(String.self, forKey: .type)
                ?? fe.decodeIfPresent(String.self, forKey: .kind)
            fileName = try keyed?.decodeIfPresent(String.self, forKey: .fileName)
                ?? fe.decodeIfPresent(String.self, forKey: .filename)
            fileSize = try keyed?.decodeIfPresent(Int.self, forKey: .fileSize)
            duration = try keyed?.decodeIfPresent(Double.self, forKey: .duration)
            thumbnail = try keyed?.decodeIfPresent(String.self, forKey: .thumbnail)
                ?? fe.decodeIfPresent(String.self, forKey: .thumbnailUrl)
            streamId = try keyed?.decodeIfPresent(String.self, forKey: .streamId)
            isStreamAvailable = try keyed?.decodeIfPresent(Bool.self, forKey: .isStreamAvailable)
            raw = nil
            return
        }

        let container = try decoder.singleValueContainer()
        if let urlString = try? container.decode(String.self) {
            self.url = urlString
            self.id = nil
            self.type = nil
            self.fileName = nil
            self.fileSize = nil
            self.duration = nil
            self.thumbnail = nil
            self.streamId = nil
            self.isStreamAvailable = nil
            self.raw = nil
        } else if let dictContainer = try? container.decode([String: AnyCodable].self) {
            self.id = dictContainer["id"]?.value as? String
            self.url = (dictContainer["url"]?.value as? String)
                ?? (dictContainer["publicUrl"]?.value as? String)
                ?? (dictContainer["mediaUrl"]?.value as? String)
                ?? (dictContainer["filePath"]?.value as? String)
            self.type = (dictContainer["type"]?.value as? String)
                ?? (dictContainer["kind"]?.value as? String)
            self.fileName = dictContainer["fileName"]?.value as? String
                ?? dictContainer["filename"]?.value as? String
            if let fileSizeStr = dictContainer["fileSize"]?.value as? String {
                self.fileSize = Int(fileSizeStr)
            } else {
                self.fileSize = dictContainer["fileSize"]?.value as? Int
            }
            if let durationNum = dictContainer["duration"]?.value as? Double {
                self.duration = durationNum
            } else if let durationStr = dictContainer["duration"]?.value as? String, let d = Double(durationStr) {
                self.duration = d
            } else {
                self.duration = nil
            }
            self.thumbnail = (dictContainer["thumbnail"]?.value as? String)
                ?? (dictContainer["thumbnailUrl"]?.value as? String)
            self.streamId = dictContainer["streamId"]?.value as? String
            self.isStreamAvailable = dictContainer["isStreamAvailable"]?.value as? Bool
            self.raw = dictContainer
        } else {
            self.id = nil
            self.url = nil
            self.type = nil
            self.fileName = nil
            self.fileSize = nil
            self.duration = nil
            self.thumbnail = nil
            self.streamId = nil
            self.isStreamAvailable = nil
            self.raw = nil
        }
    }

    init(id: String? = nil, url: String? = nil, type: String? = nil, fileName: String? = nil,
         fileSize: Int? = nil, duration: Double? = nil, thumbnail: String? = nil,
         streamId: String? = nil, isStreamAvailable: Bool? = nil, raw: [String: AnyCodable]? = nil) {
        self.id = id
        self.url = url
        self.type = type
        self.fileName = fileName
        self.fileSize = fileSize
        self.duration = duration
        self.thumbnail = thumbnail
        self.streamId = streamId
        self.isStreamAvailable = isStreamAvailable
        self.raw = raw
    }

    static func normalizeList(_ items: [ConversationMedia]) -> [ConversationMedia] {
        items.map { normalize($0) }
    }

    static func normalize(_ item: ConversationMedia) -> ConversationMedia {
        let trimmedURL = item.url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedURL: String? = {
            if let trimmedURL, !trimmedURL.isEmpty { return trimmedURL }
            for key in ["publicUrl", "mediaUrl", "filePath", "url"] {
                if let value = item.raw?[key]?.value as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            return nil
        }()

        var resolvedType = (item.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if resolvedType == "photo" { resolvedType = "image" }
        if resolvedType.isEmpty, let kind = item.raw?["kind"]?.value as? String {
            let normalizedKind = kind.lowercased()
            resolvedType = normalizedKind == "photo" ? "image" : normalizedKind
        }
        if resolvedType.isEmpty, let url = resolvedURL?.lowercased() {
            if url.hasSuffix(".mp4") || url.hasSuffix(".mov") || url.hasSuffix(".m4v") {
                resolvedType = "video"
            } else if url.hasSuffix(".jpg") || url.hasSuffix(".jpeg") || url.hasSuffix(".png") || url.hasSuffix(".webp") {
                resolvedType = "image"
            }
        }

        let resolvedThumb: String? = {
            if let thumb = item.thumbnail?.trimmingCharacters(in: .whitespacesAndNewlines), !thumb.isEmpty {
                return thumb
            }
            if let thumb = item.raw?["thumbnailUrl"]?.value as? String {
                let trimmed = thumb.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            return nil
        }()

        return ConversationMedia(
            id: item.id,
            url: resolvedURL,
            type: resolvedType.isEmpty ? item.type : resolvedType,
            fileName: item.fileName,
            fileSize: item.fileSize,
            duration: item.duration,
            thumbnail: resolvedThumb ?? item.thumbnail,
            streamId: item.streamId,
            isStreamAvailable: item.isStreamAvailable,
            raw: item.raw
        )
    }
}

// MARK: - Server Location (simple)
struct ServerLocationSimple: Codable {
    var lat: Double?
    var lng: Double?
    var address: String?

    enum CodingKeys: String, CodingKey {
        case lat, lng, address
    }

    init(lat: Double? = nil, lng: Double? = nil, address: String? = nil) {
        self.lat = lat
        self.lng = lng
        self.address = address
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let latVal = try? container.decodeIfPresent(Double.self, forKey: .lat) {
            lat = latVal
        } else if let latStr = try? container.decodeIfPresent(String.self, forKey: .lat), let d = Double(latStr) {
            lat = d
        }

        if let lngVal = try? container.decodeIfPresent(Double.self, forKey: .lng) {
            lng = lngVal
        } else if let lngStr = try? container.decodeIfPresent(String.self, forKey: .lng), let d = Double(lngStr) {
            lng = d
        }

        address = try container.decodeIfPresent(String.self, forKey: .address)
    }
}

// MARK: - Message Reaction
struct MessageReaction: Codable, Identifiable, Hashable {
    let emoji: String
    var users: [ReactionUser]
    /// NEW FE `{ emoji, count, reactedByMe }` — used when `users` is absent.
    private let storedCount: Int?
    let reactedByMe: Bool?

    var count: Int {
        if !users.isEmpty { return users.count }
        return storedCount ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case emoji, users, userIds, count, reactedByMe
    }

    // Identifiable conformance (emoji treated as unique key per message scope)
    var id: String { emoji }

    func hash(into hasher: inout Hasher) {
        hasher.combine(emoji)
    }

    static func == (lhs: MessageReaction, rhs: MessageReaction) -> Bool {
        lhs.emoji == rhs.emoji
    }

    init(emoji: String, users: [ReactionUser], storedCount: Int? = nil, reactedByMe: Bool? = nil) {
        self.emoji = emoji
        self.users = users
        self.storedCount = storedCount
        self.reactedByMe = reactedByMe
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        emoji = try container.decode(String.self, forKey: .emoji)
        storedCount = try container.decodeIfPresent(Int.self, forKey: .count)
        reactedByMe = try container.decodeIfPresent(Bool.self, forKey: .reactedByMe)

        if let decodedUsers = try? container.decode([ReactionUser].self, forKey: .users) {
            users = decodedUsers
        } else if let userIdStrings = try? container.decode([String].self, forKey: .users) {
            users = userIdStrings.map { ReactionUser(userId: $0) }
        } else if let userIds = try? container.decode([String].self, forKey: .userIds) {
            users = userIds.map { ReactionUser(userId: $0) }
        } else {
            users = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(users, forKey: .users)
        try container.encodeIfPresent(storedCount, forKey: .count)
        try container.encodeIfPresent(reactedByMe, forKey: .reactedByMe)
    }
}

struct ReactionUser: Codable {
    let userId: String
    let userName: String?
    let fullName: String?
    let profilePicture: String?

    enum CodingKeys: String, CodingKey {
        case userIdSnake = "user_id"
        case userIdCamel = "userId"
        case userNameSnake = "user_name"
        case userNameCamel = "userName"
        case fullNameSnake = "full_name"
        case fullNameCamel = "fullName"
        case profilePictureSnake = "profile_picture"
        case profilePictureCamel = "profilePicture"
    }

    init(from decoder: Decoder) throws {
        // Bare user id string: "user-123"
        if let single = try? decoder.singleValueContainer(),
           let bareId = try? single.decode(String.self),
           !bareId.isEmpty {
            userId = bareId
            userName = nil
            fullName = nil
            profilePicture = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)

        // userId (accept both snake_case and camelCase)
        if let id = try container.decodeIfPresent(String.self, forKey: .userIdSnake) ?? container.decodeIfPresent(String.self, forKey: .userIdCamel) {
            userId = id
        } else {
            throw DecodingError.keyNotFound(CodingKeys.userIdSnake, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing user id in reaction user"))
        }

        // Optional fields (accept both cases)
        userName = try container.decodeIfPresent(String.self, forKey: .userNameSnake) ?? container.decodeIfPresent(String.self, forKey: .userNameCamel)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullNameSnake) ?? container.decodeIfPresent(String.self, forKey: .fullNameCamel)
        profilePicture = try container.decodeIfPresent(String.self, forKey: .profilePictureSnake) ?? container.decodeIfPresent(String.self, forKey: .profilePictureCamel)
    }

    // Memberwise convenience initializer for manual construction (optimistic updates)
    init(userId: String, userName: String? = nil, fullName: String? = nil, profilePicture: String? = nil) {
        self.userId = userId
        self.userName = userName
        self.fullName = fullName
        self.profilePicture = profilePicture
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userIdSnake)
        try container.encodeIfPresent(userName, forKey: .userNameSnake)
        try container.encodeIfPresent(fullName, forKey: .fullNameSnake)
        try container.encodeIfPresent(profilePicture, forKey: .profilePictureSnake)
    }
}

// MARK: - Message Reactions Wrapper
struct MessageReactionsWrapper: Codable {
    let count: Int?
    let data: [MessageReaction]
}

struct AnyCodable: Codable {
    let value: Any
    init<T>(_ value: T?) { self.value = value.map { $0 as Any } ?? NSNull() }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if value is NSNull || value is Void {
            try container.encodeNil()
        } else if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else if let dictVal = value as? [String: AnyCodable] {
            try container.encode(dictVal)
        } else if let arrayVal = value as? [AnyCodable] {
            try container.encode(arrayVal)
        } else {
            try container.encodeNil()
        }
    }

    var jsonCompatibleValue: Any {
        if let dict = value as? [String: AnyCodable] {
            var result: [String: Any] = [:]
            for (k, v) in dict { result[k] = v.jsonCompatibleValue }
            return result
        } else if let array = value as? [AnyCodable] {
            return array.map { $0.jsonCompatibleValue }
        } else {
            return value
        }
    }
}
