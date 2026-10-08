//
//  ConversationAPIModels.swift
//  FlirttimeNew
//

import Foundation

/// NEW API — GET chat/conversations/{id}
/// FE unwraps `{ success, data }` then reads `data.conversation` (with `members`).
/// Raw body may be `{ success, data: { conversation } }` or bare `{ conversation }`.
struct ConversationDetailAPIResponse: Codable {
    let success: Bool?
    let message: String?
    let conversation: ChatMessageRow?
    let data: ConversationDetailDataNode?

    var resolvedConversation: ChatMessageRow? {
        conversation ?? data?.conversation ?? data?.asConversationRow
    }

    enum CodingKeys: String, CodingKey {
        case success, message, conversation, data
    }
}

/// `data` may be `{ conversation: {...} }` or the conversation object itself.
struct ConversationDetailDataNode: Codable {
    let conversation: ChatMessageRow?
    /// When `data` is the conversation object directly (no nested `conversation` key).
    let asConversationRow: ChatMessageRow?

    init(from decoder: Decoder) throws {
        // Try nested `{ conversation: Row }` first
        if let keyed = try? decoder.container(keyedBy: NestedKeys.self),
           keyed.contains(.conversation) {
            conversation = try keyed.decodeIfPresent(ChatMessageRow.self, forKey: .conversation)
            asConversationRow = nil
            return
        }
        // Else decode the whole node as the conversation row
        conversation = nil
        asConversationRow = try ChatMessageRow(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        if let conversation {
            var c = encoder.container(keyedBy: NestedKeys.self)
            try c.encode(conversation, forKey: .conversation)
        } else if let asConversationRow {
            try asConversationRow.encode(to: encoder)
        }
    }

    private enum NestedKeys: String, CodingKey {
        case conversation
    }
}

/// Unwrapped `data` payload after `loadChatRequest` (matches FE `apiFetch` result).
/// Accepts either `{ conversation: {...} }` or the conversation object itself.
struct ConversationDetailPayload: Codable {
    let conversation: ChatMessageRow

    enum CodingKeys: String, CodingKey {
        case conversation
    }

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           keyed.contains(.conversation),
           let nested = try keyed.decodeIfPresent(ChatMessageRow.self, forKey: .conversation) {
            conversation = nested
            return
        }
        conversation = try ChatMessageRow(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(conversation, forKey: .conversation)
    }
}

/// FE `fetchConversationMembers` — `{ members: ConversationMember[] }`
struct ConversationMembersPayload: Codable {
    let members: [Participant]?
}

/// Full envelope for members endpoint when not unwrapped
struct ConversationMembersEnvelope: Codable {
    let success: Bool?
    let data: ConversationMembersPayload?
    let members: [Participant]?

    var resolvedMembers: [Participant] {
        members ?? data?.members ?? []
    }
}

struct ConversationMessagesResponse: Codable {
    let success: Bool?
    let data: ConversationMessagesWrapper
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success, data, message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success)
        message = try c.decodeIfPresent(String.self, forKey: .message)

        if let wrapper = try? c.decode(ConversationMessagesWrapper.self, forKey: .data) {
            data = wrapper
        } else if let page = try? ConversationMessagesData(from: decoder) {
            // Bare page at root (no success/data envelope)
            data = ConversationMessagesWrapper(data: page)
        } else {
            data = ConversationMessagesWrapper(data: .empty)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(success, forKey: .success)
        try c.encodeIfPresent(message, forKey: .message)
        try c.encode(data, forKey: .data)
    }
}

struct ConversationMessagesWrapper: Codable {
    let status: Bool?
    let message: String?
    let data: ConversationMessagesData

    enum CodingKeys: String, CodingKey {
        case status, message, data
        case rows, messages, nextCursor, limit, count
        case pinnedMessages, shareLink, channelDetails, pagination, conversation
        case isFollowing, participants, followersCount
        case userProfileData = "user_profile_data"
    }

    init(data: ConversationMessagesData, status: Bool? = nil, message: String? = nil) {
        self.status = status
        self.message = message
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(Bool.self, forKey: .status)
        message = try c.decodeIfPresent(String.self, forKey: .message)

        // OLD: `{ status, data: { messages } }`
        if let nested = try? c.decode(ConversationMessagesData.self, forKey: .data) {
            data = nested
            return
        }

        // NEW FE MessagesPage: `{ rows, nextCursor, limit }` (and aliases)
        data = try ConversationMessagesData(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(message, forKey: .message)
        try c.encode(data, forKey: .data)
    }
}

struct ConversationPagination: Codable {
    let page: Int?
    let totalPages: Int?
    let pageSize: Int?
    let total: Int?
}

struct ConversationInfo: Codable {
    let id: String?
    let title: String?
    let type: String?
    let avatar: String?
    let participants: [ConversationParticipant]?
    let settings: ConversationSettings?
    let userProfileData: ChatUserProfileData?
    let onlineStatus: OnlineStatus?
    /// NEW detail API — `admin` | `member`; null means left / not a member
    let myRole: String?

    enum CodingKeys: String, CodingKey {
        case id, title, type, avatar, avatarPath, participants, members, settings, onlineStatus, myRole
        case userProfileData = "userProfileData"
        case online, lastSeen, lastSeenAt, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
            ?? c.decodeIfPresent(String.self, forKey: .avatarPath)
        var decodedParticipants = try c.decodeIfPresent([ConversationParticipant].self, forKey: .participants)
        if decodedParticipants == nil || decodedParticipants?.isEmpty == true {
            decodedParticipants = try c.decodeIfPresent([ConversationParticipant].self, forKey: .members)
        }
        participants = decodedParticipants
        settings = try c.decodeIfPresent(ConversationSettings.self, forKey: .settings)
        userProfileData = try c.decodeIfPresent(ChatUserProfileData.self, forKey: .userProfileData)
        var decodedOnline = try c.decodeIfPresent(OnlineStatus.self, forKey: .onlineStatus)
        if decodedOnline == nil,
           c.contains(.online) || c.contains(.lastSeen) || c.contains(.lastSeenAt) {
            decodedOnline = OnlineStatus(
                isOnline: try c.decodeIfPresent(Bool.self, forKey: .online),
                lastSeen: try c.decodeIfPresent(String.self, forKey: .lastSeen)
                    ?? c.decodeIfPresent(String.self, forKey: .lastSeenAt),
                status: try c.decodeIfPresent(String.self, forKey: .status)
            )
        }
        onlineStatus = decodedOnline
        myRole = try c.decodeIfPresent(String.self, forKey: .myRole)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(avatar, forKey: .avatar)
        try c.encodeIfPresent(participants, forKey: .participants)
        try c.encodeIfPresent(settings, forKey: .settings)
        try c.encodeIfPresent(userProfileData, forKey: .userProfileData)
        try c.encodeIfPresent(onlineStatus, forKey: .onlineStatus)
        try c.encodeIfPresent(myRole, forKey: .myRole)
    }
}

struct OnlineStatus: Codable {
    let isOnline: Bool?
    let lastSeen: String?
    let lastSeenVisibility: String?
    let onlineVisibility: String?
    /// Privacy-masked status from NEW API (`online` | `offline` | null). Null ⇒ hide presence.
    let status: String?

    enum CodingKeys: String, CodingKey {
        case isOnline, lastSeen, lastSeenVisibility, onlineVisibility, status
        case online, lastSeenAt
    }

    init(
        isOnline: Bool? = nil,
        lastSeen: String? = nil,
        lastSeenVisibility: String? = nil,
        onlineVisibility: String? = nil,
        status: String? = nil
    ) {
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.lastSeenVisibility = lastSeenVisibility
        self.onlineVisibility = onlineVisibility
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isOnline = try c.decodeIfPresent(Bool.self, forKey: .isOnline)
            ?? c.decodeIfPresent(Bool.self, forKey: .online)
        lastSeen = try c.decodeIfPresent(String.self, forKey: .lastSeen)
            ?? c.decodeIfPresent(String.self, forKey: .lastSeenAt)
        lastSeenVisibility = try c.decodeIfPresent(String.self, forKey: .lastSeenVisibility)
        onlineVisibility = try c.decodeIfPresent(String.self, forKey: .onlineVisibility)
        // Explicit null in JSON → decode as Optional.none; missing key also none
        status = try c.decodeIfPresent(String.self, forKey: .status)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(isOnline, forKey: .isOnline)
        try c.encodeIfPresent(lastSeen, forKey: .lastSeen)
        try c.encodeIfPresent(lastSeenVisibility, forKey: .lastSeenVisibility)
        try c.encodeIfPresent(onlineVisibility, forKey: .onlineVisibility)
        try c.encodeIfPresent(status, forKey: .status)
    }

    /// Chat-header subtitle respecting peer privacy. Empty string ⇒ hide.
    func presenceSubtitle(viewerIsContact: Bool = true) -> String {
        PresencePrivacy.subtitle(
            isOnline: isOnline,
            lastSeenAt: lastSeen,
            status: status,
            lastSeenVisibility: lastSeenVisibility,
            onlineVisibility: onlineVisibility,
            viewerIsContact: viewerIsContact
        )
    }

    /// Open-chat subtitle from GET conversations/{id}:
    /// online data → "online"; else lastSeen → last seen; else blank (name stays centered).
    func openChatSubtitle(username: String?) -> String {
        PresencePrivacy.openChatSubtitle(
            isOnline: isOnline,
            lastSeenAt: lastSeen,
            status: status,
            username: username
        )
    }
}

// MARK: - Presence privacy (last seen / online)

/// Resolves chat-header presence text from peer privacy settings
/// (`everyone` | `my_contacts` | `nobody` | `same_as_last_seen`, plus aliases).
enum PresencePrivacy {

    enum Visibility: Equatable {
        case everyone
        case myContacts
        case myContactsExcept
        case nobody
        case sameAsLastSeen
    }

    static func normalize(_ raw: String?) -> Visibility {
        let key = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch key {
        case "everyone", "every", "all":
            return .everyone
        case "my_contacts", "my_contact", "contacts", "mycontacts":
            return .myContacts
        case "my_contacts_except", "my_contact_except", "contacts_except":
            return .myContactsExcept
        case "nobody", "no_body", "none", "noone", "no_one":
            return .nobody
        case "same_as_last_seen", "samelastseen", "same_as_lastseen":
            return .sameAsLastSeen
        default:
            return .everyone
        }
    }

    static func allows(_ visibility: Visibility, viewerIsContact: Bool) -> Bool {
        switch visibility {
        case .everyone:
            return true
        case .nobody:
            return false
        case .myContacts, .myContactsExcept:
            return viewerIsContact
        case .sameAsLastSeen:
            return true
        }
    }

    /// Empty string means the UI should hide online / last-seen.
    static func subtitle(
        isOnline: Bool?,
        lastSeenAt: String?,
        status: String? = nil,
        lastSeenVisibility: String?,
        onlineVisibility: String?,
        viewerIsContact: Bool = true
    ) -> String {
        // NEW API: explicit null/empty status ⇒ fully hidden
        if let status {
            let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.lowercased() == "null" {
                return ""
            }
        }

        let lastSeenVis = normalize(lastSeenVisibility)
        var onlineVis = normalize(onlineVisibility)
        if onlineVis == .sameAsLastSeen {
            onlineVis = lastSeenVis
        }

        let canSeeOnline = allows(onlineVis, viewerIsContact: viewerIsContact)
        let canSeeLastSeen = allows(lastSeenVis, viewerIsContact: viewerIsContact)

        let statusValue = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let online = isOnline == true || statusValue == "online"

        if online {
            return canSeeOnline ? ChatStrings.chat_online.localizedString() : ""
        }

        // Offline: last-seen only when allowed
        if canSeeLastSeen, let lastSeenAt, !lastSeenAt.isEmpty,
           let date = parseFlexibleDate(lastSeenAt) {
            return "\(ChatStrings.chat_lastSeen.localizedString()) \(date.timeAgoDisplay())"
        }

        // lastSeen = nobody, online = everyone → can show "offline" without a timestamp
        if canSeeOnline && !canSeeLastSeen {
            return ChatStrings.chat_offline.localizedString()
        }

        return ""
    }

    /// GET conversations/{id} open-chat rules (null-based):
    /// - online has data → "online"
    /// - online null + lastSeen has data → last seen
    /// - both null / nobody → blank (header name is vertically centered)
    static func openChatSubtitle(
        isOnline: Bool?,
        lastSeenAt: String?,
        status: String? = nil,
        username: String?
    ) -> String {
        _ = username
        let statusValue = status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Field is populated only while the peer is online (or status == "online").
        let onlineHasData = isOnline == true || statusValue == "online"

        let lastSeenTrimmed = lastSeenAt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lastSeenHasData = !lastSeenTrimmed.isEmpty

        if onlineHasData {
            return ChatStrings.chat_online.localizedString()
        }

        if lastSeenHasData, let date = parseFlexibleDate(lastSeenTrimmed) {
            return "\(ChatStrings.chat_lastSeen.localizedString()) \(date.timeAgoDisplay())"
        }

        // Privacy-hidden (nobody) or missing presence — keep subtitle empty.
        return ""
    }

    private static func parseFlexibleDate(_ string: String) -> Date? {
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFull.date(from: string) { return d }

        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        if let d = isoBasic.date(from: string) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(abbreviation: "UTC")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd HH:mm:ss"] {
            df.dateFormat = fmt
            if let d = df.date(from: string) { return d }
        }
        return nil
    }
}

struct ConversationMessagesData: Codable {
    let count: Int?
    let messages: [ConversationMessage]
    let pinnedMessages: [ConversationMessage]?
    let shareLink: String?
    let channelDetails: ChannelDetails?
    let isFollowing: Bool?
    let followersCount: Int?
    let userProfileData: ChatUserProfileData?
    let pagination: ConversationPagination?
    let conversation: ConversationInfo?
    let participants: [ChannelParticipant]?
    /// NEW FE MessagesPage cursor for loading older messages
    let nextCursor: String?
    let limit: Int?

    static let empty = ConversationMessagesData(
        count: 0,
        messages: [],
        pinnedMessages: nil,
        shareLink: nil,
        channelDetails: nil,
        isFollowing: nil,
        followersCount: nil,
        userProfileData: nil,
        pagination: nil,
        conversation: nil,
        participants: nil,
        nextCursor: nil,
        limit: nil
    )

    enum CodingKeys: String, CodingKey {
        case count, messages, rows, pinnedMessages, shareLink, channelDetails, pagination, conversation
        case isFollowing, participants, followersCount, nextCursor, limit
        case userProfileData = "user_profile_data"
    }

    init(
        count: Int?,
        messages: [ConversationMessage],
        pinnedMessages: [ConversationMessage]?,
        shareLink: String?,
        channelDetails: ChannelDetails?,
        isFollowing: Bool?,
        followersCount: Int?,
        userProfileData: ChatUserProfileData?,
        pagination: ConversationPagination?,
        conversation: ConversationInfo?,
        participants: [ChannelParticipant]?,
        nextCursor: String?,
        limit: Int?
    ) {
        self.count = count
        self.messages = messages
        self.pinnedMessages = pinnedMessages
        self.shareLink = shareLink
        self.channelDetails = channelDetails
        self.isFollowing = isFollowing
        self.followersCount = followersCount
        self.userProfileData = userProfileData
        self.pagination = pagination
        self.conversation = conversation
        self.participants = participants
        self.nextCursor = nextCursor
        self.limit = limit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decodeIfPresent(Int.self, forKey: .count)
        shareLink = try c.decodeIfPresent(String.self, forKey: .shareLink)
        channelDetails = try c.decodeIfPresent(ChannelDetails.self, forKey: .channelDetails)
        isFollowing = try c.decodeIfPresent(Bool.self, forKey: .isFollowing)
        followersCount = try c.decodeIfPresent(Int.self, forKey: .followersCount)
        userProfileData = try c.decodeIfPresent(ChatUserProfileData.self, forKey: .userProfileData)
        pagination = try c.decodeIfPresent(ConversationPagination.self, forKey: .pagination)
        conversation = try c.decodeIfPresent(ConversationInfo.self, forKey: .conversation)
        participants = try c.decodeIfPresent([ChannelParticipant].self, forKey: .participants)
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
        limit = try c.decodeIfPresent(Int.self, forKey: .limit)

        // NEW `rows` | OLD `messages` — decode lossily so one bad item cannot blank the chat
        let fromMessages = Self.decodeMessagesLossy(from: c, forKey: .messages)
        let fromRows = Self.decodeMessagesLossy(from: c, forKey: .rows)
        if !fromMessages.isEmpty {
            messages = fromMessages
        } else {
            messages = fromRows
        }
        pinnedMessages = Self.decodeMessagesLossyOptional(from: c, forKey: .pinnedMessages)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(count, forKey: .count)
        try c.encode(messages, forKey: .messages)
        try c.encodeIfPresent(pinnedMessages, forKey: .pinnedMessages)
        try c.encodeIfPresent(shareLink, forKey: .shareLink)
        try c.encodeIfPresent(channelDetails, forKey: .channelDetails)
        try c.encodeIfPresent(isFollowing, forKey: .isFollowing)
        try c.encodeIfPresent(followersCount, forKey: .followersCount)
        try c.encodeIfPresent(userProfileData, forKey: .userProfileData)
        try c.encodeIfPresent(pagination, forKey: .pagination)
        try c.encodeIfPresent(conversation, forKey: .conversation)
        try c.encodeIfPresent(participants, forKey: .participants)
        try c.encodeIfPresent(nextCursor, forKey: .nextCursor)
        try c.encodeIfPresent(limit, forKey: .limit)
    }

    var resolvedChannelIcon: String? {
        participants?.first?.channel?.icon
    }

    private static func decodeMessagesLossy(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [ConversationMessage] {
        guard container.contains(key),
              var unkeyed = try? container.nestedUnkeyedContainer(forKey: key) else {
            return []
        }
        var result: [ConversationMessage] = []
        var skipped = 0
        while !unkeyed.isAtEnd {
            if let msg = try? unkeyed.decode(ConversationMessage.self) {
                result.append(msg)
            } else {
                _ = try? unkeyed.decode(AnyCodable.self)
                skipped += 1
            }
        }
        if skipped > 0 {
            AppLogger.debug("[MessagesDecode] skipped \(skipped) undecodable message(s) for key=\(key.stringValue)")
        }
        return result
    }

    private static func decodeMessagesLossyOptional(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [ConversationMessage]? {
        guard container.contains(key) else { return nil }
        return decodeMessagesLossy(from: container, forKey: key)
    }
}

/// NEW API — POST chat/messages response `data` (FE: `{ message: ChatMessage }`)
struct SendChatMessageAPIData: Codable {
    let message: ConversationMessage?

    enum CodingKeys: String, CodingKey {
        case message
    }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let msg = try c.decodeIfPresent(ConversationMessage.self, forKey: .message) {
            message = msg
            return
        }
        // Some backends return the message object directly as `data`
        message = try? ConversationMessage(from: decoder)
    }
}

/// NEW API — POST chat/channels/messages/delete response `data`
struct DeleteChannelMessageAPIData: Codable {
    let channelId: String?
    let messageId: String?
    let messageIds: [String]?
    let scope: String?
}

/// Resolves chat translation payloads that may be a string, lang→text map, or mixed metadata.
enum ChatTranslationText {
    private static var knownLanguageCodes: Set<String> {
        var codes = Set(["en", "ru", "uk", "pl", "ja", "tr", "es", "de", "ko", "pt", "it", "fr", "ar", "hi"])
        codes.formUnion(["en", "zh", "zh-hans", "zh-hant", "zh-cn", "zh-tw", "pt-br", "pt-pt", "nb", "nn"])
        return codes
    }

    /// True when value looks like a language/locale code (`en`, `ru`, `en-US`) rather than message text.
    static func isLanguageCode(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 12, !trimmed.contains(" ") else { return false }
        let normalized = trimmed.lowercased().replacingOccurrences(of: "_", with: "-")
        if knownLanguageCodes.contains(normalized) { return true }
        let base = normalized.split(separator: "-").first.map(String.init) ?? normalized
        return knownLanguageCodes.contains(base)
    }

    /// Returns trimmed translation text, or nil when empty / language-code-only.
    static func sanitized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if isLanguageCode(trimmed) { return nil }
        return trimmed
    }

    /// Pick real translated text from a map like `{ "en": "Hello" }` or `{ "text": "Hello", "language": "en" }`.
    static func fromMap(_ map: [String: String], preferredLanguage: String) -> String? {
        let preferred = preferredLanguage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let preferredBase = preferred.split(separator: "-").first.map(String.init) ?? preferred

        let preferredKeys = [preferred, preferredBase, "en"]
        for key in preferredKeys {
            if let value = sanitized(map[key]) { return value }
            if let pair = map.first(where: { $0.key.lowercased().replacingOccurrences(of: "_", with: "-") == key }),
               let value = sanitized(pair.value) {
                return value
            }
        }

        let textKeys = [
            "text", "translatedText", "translatedBody", "translated_text",
            "translated_body", "body", "content", "value", "result", "message"
        ]
        for key in textKeys {
            if let value = sanitized(map[key]) { return value }
            if let pair = map.first(where: { $0.key.lowercased() == key.lowercased() }),
               let value = sanitized(pair.value) {
                return value
            }
        }

        var bestFromLangKey: String?
        for (key, value) in map {
            guard isLanguageCode(key), let sanitizedValue = sanitized(value) else { continue }
            if bestFromLangKey == nil || sanitizedValue.count > (bestFromLangKey?.count ?? 0) {
                bestFromLangKey = sanitizedValue
            }
        }
        if let bestFromLangKey { return bestFromLangKey }

        return map.values.compactMap(sanitized).max(by: { $0.count < $1.count })
    }

    static func fromAnyMap(_ map: [String: AnyCodable], preferredLanguage: String) -> String? {
        let stringMap = map.reduce(into: [String: String]()) { result, item in
            if let value = item.value.value as? String {
                result[item.key] = value
            }
        }
        return fromMap(stringMap, preferredLanguage: preferredLanguage)
    }
}

/// NEW API — POST chat/messages/{id}/translate response `data`
/// Accepts several shapes: full message, or flat translation fields.
struct TranslateChatMessageAPIData: Codable {
    let message: ConversationMessage?
    let translation: String?
    let translatedText: String?
    let translatedBody: String?
    let body: String?
    let text: String?
    let id: String?
    let messageId: String?

    enum CodingKeys: String, CodingKey {
        case message
        case translation
        case translations
        case translatedText
        case translatedBody
        case body
        case text
        case content
        case id
        case messageId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if c.contains(.message) {
            message = try c.decodeIfPresent(ConversationMessage.self, forKey: .message)
        } else if c.contains(.id) || c.contains(.body) || c.contains(.content) {
            // Bare message object as `data`
            message = try? ConversationMessage(from: decoder)
        } else {
            // Translation-only payload — do not synthesize a ConversationMessage
            // (its decoder would invent a random `id`).
            message = nil
        }

        let preferred = getSelectedLanguage().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let s = try? c.decodeIfPresent(String.self, forKey: .translation) {
            translation = ChatTranslationText.sanitized(s)
        } else if let map = try? c.decodeIfPresent([String: String].self, forKey: .translation) {
            translation = ChatTranslationText.fromMap(map, preferredLanguage: preferred)
        } else if let map = try? c.decodeIfPresent([String: AnyCodable].self, forKey: .translation) {
            translation = ChatTranslationText.fromAnyMap(map, preferredLanguage: preferred)
        } else if let map = try? c.decodeIfPresent([String: String].self, forKey: .translations) {
            translation = ChatTranslationText.fromMap(map, preferredLanguage: preferred)
        } else if let map = try? c.decodeIfPresent([String: AnyCodable].self, forKey: .translations) {
            translation = ChatTranslationText.fromAnyMap(map, preferredLanguage: preferred)
        } else {
            translation = nil
        }

        translatedText = ChatTranslationText.sanitized(try c.decodeIfPresent(String.self, forKey: .translatedText))
        translatedBody = ChatTranslationText.sanitized(try c.decodeIfPresent(String.self, forKey: .translatedBody))
        body = try c.decodeIfPresent(String.self, forKey: .body)
            ?? c.decodeIfPresent(String.self, forKey: .content)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        messageId = try c.decodeIfPresent(String.self, forKey: .messageId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(message, forKey: .message)
        try c.encodeIfPresent(translation, forKey: .translation)
        try c.encodeIfPresent(translatedText, forKey: .translatedText)
        try c.encodeIfPresent(translatedBody, forKey: .translatedBody)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(messageId, forKey: .messageId)
    }

    /// Prefer explicit translation fields. Fall back to body/content only when it differs from the original.
    func resolvedTranslatedText(preferringOver originalContent: String? = nil) -> String? {
        let original = originalContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let preferred: [String?] = [
            translatedText,
            translatedBody,
            translation,
            ChatTranslationText.sanitized(message?.translation)
        ]
        for value in preferred {
            if let text = ChatTranslationText.sanitized(value) {
                return text
            }
        }

        let fallbacks: [String?] = [text, body, message?.content]
        for value in fallbacks {
            guard let trimmed = ChatTranslationText.sanitized(value) else { continue }
            if trimmed != original { return trimmed }
        }
        return nil
    }

    var resolvedMessageId: String? {
        let candidates = [messageId, id, message?.id].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        return candidates.first(where: { !$0.isEmpty })
    }
}

/// NEW API — POST chat/messages/forward response `data` (FE: `{ messages: ChatMessage[] }`)
struct ForwardChatMessagesAPIData: Codable {
    let messages: [ConversationMessage]?

    enum CodingKeys: String, CodingKey {
        case messages
    }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let list = try c.decodeIfPresent([ConversationMessage].self, forKey: .messages) {
            messages = list
            return
        }
        // Some backends return the array directly as `data`
        messages = try? [ConversationMessage](from: decoder)
    }
}

/// NEW API — GET chat/conversations/{id}/pinned-message (FE: `{ message: ChatMessage | null }`)
struct PinnedMessageAPIData: Codable {
    let message: ConversationMessage?

    enum CodingKeys: String, CodingKey {
        case message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Explicit null is valid — means no pinned message
        if c.contains(.message), (try? c.decodeNil(forKey: .message)) == true {
            message = nil
            return
        }
        message = try c.decodeIfPresent(ConversationMessage.self, forKey: .message)
            ?? (try? ConversationMessage(from: decoder))
    }
}

struct ChatDeliveredSyncAPIData: Codable {
    let updated: Int?
}

struct ChatConversationReadAPIData: Codable {
    let conversationId: String?
    let unreadCount: Int?
}

/// NEW API — PATCH chat/conversations/{id}/settings response `data`
/// Accepts flat settings, nested `settings`, or wrapped `conversation.settings`.
struct UpdateConversationSettingsAPIData: Codable {
    let settings: ConversationSettings?

    init(settings: ConversationSettings?) {
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey {
        case settings
        case conversation
        case isMuted
        case isPinned
        case isArchived
        case isBlocked
        case isLocked
        case labelText
        case labelColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let nested = try c.decodeIfPresent(ConversationSettings.self, forKey: .settings) {
            settings = nested
            return
        }

        if let conversation = try? c.nestedContainer(keyedBy: CodingKeys.self, forKey: .conversation),
           let nested = try conversation.decodeIfPresent(ConversationSettings.self, forKey: .settings) {
            settings = nested
            return
        }

        // Flat settings object as `data`
        let muted = try c.decodeIfPresent(Bool.self, forKey: .isMuted)
        let pinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned)
        let archived = try c.decodeIfPresent(Bool.self, forKey: .isArchived)
        let blocked = try c.decodeIfPresent(Bool.self, forKey: .isBlocked)
        let locked = try c.decodeIfPresent(Bool.self, forKey: .isLocked)
        let labelText = try c.decodeIfPresent(String.self, forKey: .labelText)
        let labelColor = try c.decodeIfPresent(String.self, forKey: .labelColor)

        if muted != nil || pinned != nil || archived != nil || blocked != nil || locked != nil
            || labelText != nil || labelColor != nil {
            settings = ConversationSettings(
                isMuted: muted,
                isPinned: pinned,
                isArchived: archived,
                isLocked: locked,
                isBlocked: blocked,
                labelText: labelText,
                labelColor: labelColor
            )
        } else {
            settings = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(settings, forKey: .settings)
    }
}
