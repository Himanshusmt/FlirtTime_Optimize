//
//  ChannelAPIModels.swift
//  FlirttimeNew
//

import Foundation

/// FE `InviteSlugCheck` — GET chat/channels/slug-available
struct ChannelSlugAvailability: Codable {
    let slug: String?
    let available: Bool?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case slug, available, reason
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        slug = try values.decodeIfPresent(String.self, forKey: .slug)
        available = try values.decodeIfPresent(Bool.self, forKey: .available)
        reason = try values.decodeIfPresent(String.self, forKey: .reason)
    }
}

struct ChannelFollowersList : Codable {
    let success : Bool?
    let serverTime : String?
    let data : ChannelData?
    let message : String?

    enum CodingKeys: String, CodingKey {

        case success = "success"
        case serverTime = "serverTime"
        case data = "data"
        case message = "message"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        success = try values.decodeIfPresent(Bool.self, forKey: .success)
        serverTime = try values.decodeIfPresent(String.self, forKey: .serverTime)
        data = try values.decodeIfPresent(ChannelData.self, forKey: .data)
        message = try values.decodeIfPresent(String.self, forKey: .message)
    }

}

struct Followers : Codable,Identifiable {
    let id : String?
    let channelId : String?
    let userId : String?
    let role : String?
    let joinedAt : String?
    let isActive : Bool?
    let user : ChannelUser?

    enum CodingKeys: String, CodingKey {

        case id = "id"
        case channelId = "channelId"
        case userId = "userId"
        case role = "role"
        case joinedAt = "joinedAt"
        case isActive = "isActive"
        case user = "user"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id)
        channelId = try values.decodeIfPresent(String.self, forKey: .channelId)
        userId = try values.decodeIfPresent(String.self, forKey: .userId)
        role = try values.decodeIfPresent(String.self, forKey: .role)
        joinedAt = try values.decodeIfPresent(String.self, forKey: .joinedAt)
        isActive = try values.decodeIfPresent(Bool.self, forKey: .isActive)
        user = try values.decodeIfPresent(ChannelUser.self, forKey: .user)
    }

    init(
        id: String?,
        channelId: String?,
        userId: String?,
        role: String?,
        joinedAt: String?,
        isActive: Bool?,
        user: ChannelUser?
    ) {
        self.id = id
        self.channelId = channelId
        self.userId = userId
        self.role = role
        self.joinedAt = joinedAt
        self.isActive = isActive
        self.user = user
    }

    init(fromMember member: ChannelMemberAPI, channelId: String) {
        self.init(
            id: member.id,
            channelId: channelId,
            userId: member.id,
            role: member.role,
            joinedAt: member.joinedAt,
            isActive: true,
            user: ChannelUser(
                id: member.id,
                userName: member.username ?? member.userName,
                fullName: member.fullName,
                profilePicture: member.profilePicture
            )
        )
    }
}

struct ChannelData : Codable {
    let channel : Channel?
    let followers : [Followers]?
    let pagination : ChannelPagination?

    enum CodingKeys: String, CodingKey {

        case channel = "channel"
        case followers = "followers"
        case pagination = "pagination"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        channel = try values.decodeIfPresent(Channel.self, forKey: .channel)
        followers = try values.decodeIfPresent([Followers].self, forKey: .followers)
        pagination = try values.decodeIfPresent(ChannelPagination.self, forKey: .pagination)
    }

    init(channel: Channel?, followers: [Followers]?, pagination: ChannelPagination?) {
        self.channel = channel
        self.followers = followers
        self.pagination = pagination
    }
}

struct Channel : Codable {
    let id : String?
    let name : String?
    let icon : String?
    let description : String?
    let ownerId : String?
    let followerCount : Int?
    let createdAt : String?
    let updatedAt : String?

    enum CodingKeys: String, CodingKey {

        case id = "id"
        case name = "name"
        case icon = "icon"
        case description = "description"
        case ownerId = "ownerId"
        case followerCount = "followerCount"
        case createdAt = "createdAt"
        case updatedAt = "updatedAt"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        icon = try values.decodeIfPresent(String.self, forKey: .icon)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        ownerId = try values.decodeIfPresent(String.self, forKey: .ownerId)
        followerCount = try values.decodeIfPresent(Int.self, forKey: .followerCount)
        createdAt = try values.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
    }

}


struct ChannelPagination : Codable {
    let total : Int?
    let page : Int?
    let limit : Int?
    let totalPages : Int?

    enum CodingKeys: String, CodingKey {

        case total = "total"
        case page = "page"
        case limit = "limit"
        case totalPages = "totalPages"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        total = try values.decodeIfPresent(Int.self, forKey: .total)
        page = try values.decodeIfPresent(Int.self, forKey: .page)
        limit = try values.decodeIfPresent(Int.self, forKey: .limit)
        totalPages = try values.decodeIfPresent(Int.self, forKey: .totalPages)
    }

}


struct ChannelUser : Codable {
    let id : String?
    let userName : String?
    let fullName : String?
    let profilePicture : String?
    let isOnline : Bool?
    let lastOnline : String?
    let bio : String?
    let verified : Bool?
    let isFollowing : Bool?
    let relationshipStatus : String?

    enum CodingKeys: String, CodingKey {

        case id = "id"
        case userName = "userName"
        case fullName = "fullName"
        case profilePicture = "profilePicture"
        case isOnline = "isOnline"
        case lastOnline = "lastOnline"
        case bio = "bio"
        case verified = "verified"
        case isFollowing = "isFollowing"
        case relationshipStatus = "relationshipStatus"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id)
        userName = try values.decodeIfPresent(String.self, forKey: .userName)
        fullName = try values.decodeIfPresent(String.self, forKey: .fullName)
        profilePicture = try values.decodeIfPresent(String.self, forKey: .profilePicture)
        isOnline = try values.decodeIfPresent(Bool.self, forKey: .isOnline)
        lastOnline = try values.decodeIfPresent(String.self, forKey: .lastOnline)
        bio = try values.decodeIfPresent(String.self, forKey: .bio)
        verified = try values.decodeIfPresent(Bool.self, forKey: .verified)
        isFollowing = try values.decodeIfPresent(Bool.self, forKey: .isFollowing)
        relationshipStatus = try values.decodeIfPresent(String.self, forKey: .relationshipStatus)
    }

    init(
        id: String? = nil,
        userName: String? = nil,
        fullName: String? = nil,
        profilePicture: String? = nil,
        isOnline: Bool? = nil,
        lastOnline: String? = nil,
        bio: String? = nil,
        verified: Bool? = nil,
        isFollowing: Bool? = nil,
        relationshipStatus: String? = nil
    ) {
        self.id = id
        self.userName = userName
        self.fullName = fullName
        self.profilePicture = profilePicture
        self.isOnline = isOnline
        self.lastOnline = lastOnline
        self.bio = bio
        self.verified = verified
        self.isFollowing = isFollowing
        self.relationshipStatus = relationshipStatus
    }
}

// MARK: - NEW Channels API (FE `src/lib/channels.ts`)

struct ChannelSettingsAPI: Codable {
    let isMuted: Bool?
    let isPinned: Bool?
    let isArchived: Bool?
    let lastReadMessageId: String?
    let lastReadAt: String?
    let unreadCount: Int?
}

struct ChannelMemberAPI: Codable, Hashable {
    let id: String?
    let username: String?
    let userName: String?
    let fullName: String?
    let profilePicture: String?
    let isVerified: Bool?
    let role: String?
    let joinedAt: String?

    /// Stable identity for SwiftUI lists
    var stableId: String {
        if let id, !id.isEmpty { return id }
        if let userName, !userName.isEmpty { return "uname:\(userName)" }
        if let username, !username.isEmpty { return "username:\(username)" }
        if let fullName, !fullName.isEmpty { return "name:\(fullName)" }
        return "member:\(role ?? "unknown"):\(joinedAt ?? "")"
    }

    var displayName: String {
        let name = (fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let uname = (username ?? userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !uname.isEmpty { return uname }
        return "Unknown"
    }

    var handle: String {
        let uname = (username ?? userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return uname.isEmpty ? "" : "@\(uname)"
    }

    var roleLabel: String {
        switch (role ?? "").lowercased() {
        case "owner": return "Owner"
        case "admin": return "Admin"
        case "follower": return "Follower"
        default: return role?.capitalized ?? ""
        }
    }

    init(
        id: String? = nil,
        username: String? = nil,
        userName: String? = nil,
        fullName: String? = nil,
        profilePicture: String? = nil,
        isVerified: Bool? = nil,
        role: String? = nil,
        joinedAt: String? = nil
    ) {
        self.id = id
        self.username = username
        self.userName = userName
        self.fullName = fullName
        self.profilePicture = profilePicture
        self.isVerified = isVerified
        self.role = role
        self.joinedAt = joinedAt
    }

    init?(fromFollower follower: Followers) {
        let uid = follower.userId ?? follower.user?.id ?? follower.id
        guard let uid, !uid.isEmpty else { return nil }
        self.init(
            id: uid,
            username: follower.user?.userName,
            userName: follower.user?.userName,
            fullName: follower.user?.fullName,
            profilePicture: follower.user?.profilePicture,
            isVerified: follower.user?.verified,
            role: follower.role ?? "follower",
            joinedAt: follower.joinedAt
        )
    }
}

struct ChannelLastMessageAPI: Codable {
    let id: String?
    let body: String?
    let content: String?
    let contentPreview: String?
    let type: String?
    let messageType: String?
    let senderId: String?

    var preview: String? {
        let raw = (contentPreview ?? body ?? content)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    var resolvedType: String? { messageType ?? type }

    enum CodingKeys: String, CodingKey {
        case id, body, content, contentPreview, type, messageType, senderId
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            id = try container.decodeIfPresent(String.self, forKey: .id)
            body = try container.decodeIfPresent(String.self, forKey: .body)
            content = try container.decodeIfPresent(String.self, forKey: .content)
            contentPreview = try container.decodeIfPresent(String.self, forKey: .contentPreview)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            messageType = try container.decodeIfPresent(String.self, forKey: .messageType)
            senderId = try container.decodeIfPresent(String.self, forKey: .senderId)
            return
        }
        let single = try decoder.singleValueContainer()
        let text = try? single.decode(String.self)
        id = nil
        body = text
        content = text
        contentPreview = text
        type = nil
        messageType = nil
        senderId = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(contentPreview, forKey: .contentPreview)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(messageType, forKey: .messageType)
        try container.encodeIfPresent(senderId, forKey: .senderId)
    }
}

/// FE `Channel` / create-update detail payload
struct ChannelDetailAPI: Codable {
    let id: String
    let name: String
    let description: String?
    let avatarPath: String?
    let icon: String?
    let isPublic: Bool?
    let inviteSlug: String?
    let followersCount: Int?
    let followerCount: Int?
    let adminsCount: Int?
    let lastMessageAt: String?
    let lastMessagePreview: String?
    let lastMessageType: String?
    let lastMessageSenderId: String?
    let lastMessage: ChannelLastMessageAPI?
    let settings: ChannelSettingsAPI?
    let myRole: String?
    let createdAt: String?
    let updatedAt: String?
    let members: [ChannelMemberAPI]?
    let isFollowing: Bool?
    let hasFollowed: Bool?

    var resolvedAvatarPath: String? { avatarPath ?? icon }
    var resolvedFollowersCount: Int { followersCount ?? followerCount ?? 0 }
    var resolvedIsFollowing: Bool { isFollowing ?? hasFollowed ?? false }
    var resolvedLastMessagePreview: String? {
        let nested = lastMessage?.preview
        let flat = lastMessagePreview?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nested, !nested.isEmpty { return nested }
        if let flat, !flat.isEmpty { return flat }
        return nil
    }
    var resolvedLastMessageType: String? {
        lastMessageType ?? lastMessage?.resolvedType
    }
}

struct ChannelDetailEnvelope: Codable {
    let channel: ChannelDetailAPI?

    enum CodingKeys: String, CodingKey {
        case channel
    }

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           let nested = try keyed.decodeIfPresent(ChannelDetailAPI.self, forKey: .channel) {
            channel = nested
            return
        }
        // Some responses return the channel object directly as `data`
        channel = try? ChannelDetailAPI(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(channel, forKey: .channel)
    }
}

/// FE `ChannelsPage` — GET /chat/channels inbox (owned + following)
struct ChannelsListPage: Codable {
    let rows: [ChannelDetailAPI]
    let nextCursor: String?
    let limit: Int?

    enum CodingKeys: String, CodingKey {
        case rows, nextCursor, limit, channels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decoded = try container.decodeIfPresent([ChannelDetailAPI].self, forKey: .rows) {
            rows = decoded
        } else if let decoded = try container.decodeIfPresent([ChannelDetailAPI].self, forKey: .channels) {
            rows = decoded
        } else {
            rows = []
        }
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rows, forKey: .rows)
        try container.encodeIfPresent(nextCursor, forKey: .nextCursor)
        try container.encodeIfPresent(limit, forKey: .limit)
    }
}

/// FE `ChannelBrowseItem`
struct ChannelBrowseItemAPI: Codable {
    let id: String
    let name: String
    let description: String?
    let avatarPath: String?
    let icon: String?
    let isPublic: Bool?
    let inviteSlug: String?
    let followersCount: Int?
    let followerCount: Int?
    let isFollowing: Bool?
    let hasFollowed: Bool?
    let createdAt: String?

    var resolvedAvatarPath: String? { avatarPath ?? icon }
    var resolvedFollowersCount: Int { followersCount ?? followerCount ?? 0 }
    var resolvedIsFollowing: Bool { isFollowing ?? hasFollowed ?? false }
}

/// FE `ChannelBrowsePage`
struct ChannelsBrowsePage: Codable {
    let rows: [ChannelBrowseItemAPI]
    let nextCursor: String?
    let limit: Int?

    enum CodingKeys: String, CodingKey {
        case rows, nextCursor, limit, channels, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decoded = try container.decodeIfPresent([ChannelBrowseItemAPI].self, forKey: .rows) {
            rows = decoded
        } else if let decoded = try container.decodeIfPresent([ChannelBrowseItemAPI].self, forKey: .channels) {
            rows = decoded
        } else {
            rows = []
        }
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rows, forKey: .rows)
        try container.encodeIfPresent(nextCursor, forKey: .nextCursor)
        try container.encodeIfPresent(limit, forKey: .limit)
    }
}
