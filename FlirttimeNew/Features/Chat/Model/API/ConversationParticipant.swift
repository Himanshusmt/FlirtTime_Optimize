//
//  ConversationParticipant.swift
//  FlirttimeNew
//

import Foundation

struct ConversationParticipant: Codable {
    let id: String?
    let conversationId: String?
    let userId: String?
    let role: String?
    let isActive: Bool?
    let user: ConversationParticipantUser?
    let userProfileData: ChatUserProfileData?
    /// NEW flat `members[].isVerified`
    let isVerified: Bool

    var resolvedIsVerified: Bool {
        isVerified
            || user?.verified == true
            || userProfileData?.verified == true
    }

    enum CodingKeys: String, CodingKey {
        case id, conversationId, userId, role, isActive, user, userProfileData
        case username, userName, fullName, profilePicture, isVerified, verified
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        conversationId = try c.decodeIfPresent(String.self, forKey: .conversationId)
        // NEW members: `id` is user id
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? id
        role = try c.decodeIfPresent(String.self, forKey: .role)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive)
        var decodedUser = try c.decodeIfPresent(ConversationParticipantUser.self, forKey: .user)
        userProfileData = try c.decodeIfPresent(ChatUserProfileData.self, forKey: .userProfileData)

        let flatUserName = try c.decodeIfPresent(String.self, forKey: .username)
            ?? c.decodeIfPresent(String.self, forKey: .userName)
        let flatFullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        let flatPicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
        let flatVerified = try c.decodeIfPresent(Bool.self, forKey: .isVerified)
            ?? c.decodeIfPresent(Bool.self, forKey: .verified)

        if decodedUser == nil {
            if flatUserName != nil || flatFullName != nil || flatPicture != nil || userId != nil {
                decodedUser = ConversationParticipantUser(
                    id: userId ?? id,
                    userId: userId ?? id,
                    userDetails: [
                        UserDetail(
                            userName: flatUserName,
                            fullName: flatFullName,
                            profilePicture: flatPicture,
                            profilePictureDetails: flatPicture.map { ProfilePictureDetails(filePath: $0) }
                        )
                    ],
                    username: flatUserName,
                    fullName: flatFullName,
                    profileImage: flatPicture,
                    profilePicture: flatPicture,
                    verified: flatVerified
                )
            }
        }

        // Flat NEW member `isVerified` wins when nested user omitted it
        if let flatVerified, decodedUser?.verified == nil {
            decodedUser?.verified = flatVerified
        }
        user = decodedUser
        isVerified = flatVerified == true || decodedUser?.verified == true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(conversationId, forKey: .conversationId)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(role, forKey: .role)
        try c.encodeIfPresent(isActive, forKey: .isActive)
        try c.encodeIfPresent(user, forKey: .user)
        try c.encodeIfPresent(userProfileData, forKey: .userProfileData)
        if isVerified {
            try c.encode(true, forKey: .isVerified)
        }
    }
}

struct ConversationParticipantUser: Codable {
    let id: String?
    var userId: String?
    var userDetails: [UserDetail]?
    var username: String?
    var fullName: String?
    var profileImage: String?
    var profilePicture: String?
    var isOnline: Bool?
    var isPrivate: Bool?
    var verified: Bool?
    var isFollowing: Bool?
    var isBlock: Bool?
    var lastOnline: String?

    enum CodingKeys: String, CodingKey {
        case id, userId
        case userDetails, username, fullName, profileImage, profilePicture
        case isOnline, isPrivate, verified, isVerified, isFollowing, isBlock, lastOnline
    }

    init(
        id: String? = nil,
        userId: String? = nil,
        userDetails: [UserDetail]? = nil,
        username: String? = nil,
        fullName: String? = nil,
        profileImage: String? = nil,
        profilePicture: String? = nil,
        isOnline: Bool? = nil,
        isPrivate: Bool? = nil,
        verified: Bool? = nil,
        isFollowing: Bool? = nil,
        isBlock: Bool? = nil,
        lastOnline: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.userDetails = userDetails
        self.username = username
        self.fullName = fullName
        self.profileImage = profileImage
        self.profilePicture = profilePicture
        self.isOnline = isOnline
        self.isPrivate = isPrivate
        self.verified = verified
        self.isFollowing = isFollowing
        self.isBlock = isBlock
        self.lastOnline = lastOnline
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? id
        username = try c.decodeIfPresent(String.self, forKey: .username)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        profileImage = try c.decodeIfPresent(String.self, forKey: .profileImage)
        profilePicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
        isOnline = try c.decodeIfPresent(Bool.self, forKey: .isOnline)
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate)
        verified = try c.decodeIfPresent(Bool.self, forKey: .verified)
            ?? c.decodeIfPresent(Bool.self, forKey: .isVerified)
        isFollowing = try c.decodeIfPresent(Bool.self, forKey: .isFollowing)
        isBlock = try c.decodeIfPresent(Bool.self, forKey: .isBlock)
        lastOnline = try c.decodeIfPresent(String.self, forKey: .lastOnline)

        let decoded = try c.decodeIfPresent([UserDetail].self, forKey: .userDetails)
        if let decoded, !decoded.isEmpty {
            userDetails = decoded
        } else if username != nil || fullName != nil || profileImage != nil || profilePicture != nil {
            let pic = profileImage ?? profilePicture
            userDetails = [UserDetail(
                userName: username,
                fullName: fullName,
                profilePicture: pic,
                profilePictureDetails: pic.map { ProfilePictureDetails(filePath: $0) }
            )]
        } else {
            userDetails = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(userDetails, forKey: .userDetails)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(profileImage, forKey: .profileImage)
        try c.encodeIfPresent(profilePicture, forKey: .profilePicture)
        try c.encodeIfPresent(isOnline, forKey: .isOnline)
        try c.encodeIfPresent(isPrivate, forKey: .isPrivate)
        try c.encodeIfPresent(verified, forKey: .verified)
        if verified == true {
            try c.encode(true, forKey: .isVerified)
        }
        try c.encodeIfPresent(isFollowing, forKey: .isFollowing)
        try c.encodeIfPresent(isBlock, forKey: .isBlock)
        try c.encodeIfPresent(lastOnline, forKey: .lastOnline)
    }
}

struct ChannelParticipant: Codable {
    let id: String?
    let channelId: String?
    let userId: String?
    let channel: ChannelParticipantInfo?
    let role: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id, channelId, userId, channel, role, isActive
    }
}

struct ChannelParticipantInfo: Codable {
    let id: String?
    let name: String?
    let icon: String?
    let description: String?
    let ownerId: String?
    let followerCount: Int?
}

struct ChannelDetails: Codable {
    let channelName: String?
    let ownerId: String?
    let isAdmin: Bool?
    let hasFollowed: Bool?
    let description: String?
    let followersCount: Int?
    let followerCount: Int?
    let icon: String?

    var resolvedFollowersCount: Int? {
        return followersCount ?? followerCount
    }

    enum CodingKeys: String, CodingKey {
        case channelName, ownerId, isAdmin, hasFollowed, description, followersCount, followerCount, icon
    }
}
