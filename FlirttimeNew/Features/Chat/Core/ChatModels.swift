import Foundation
import UIKit

struct UserRes: DataClass, Codable, Equatable {
    var id, userId, userName, fullName, link, bio, type: String?
    var profilePicture: String?
    var isPrivate, verified: Bool?
    var profilePictureDetails: ProfilePictureDetails?
    var follower_profile: FollowerProfile?
    var isFollowing: Bool?
    var isOwnerFollowingVisitor: Bool?
    /// NEW relationship flags (same as ChatUserProfileData / users/{id})
    var isRequestedByMe: Bool?
    var isRequestedToMe: Bool?
    var isSelected:Bool?
    let searchedAt: Date?
    var user_profile_data: ChatUserProfileData?
    /// NEW GET /users/ — e.g. `https://flagcdn.com/au.svg`
    var nationalityFlag: String?
    /// NEW GET /users/ — display country name (prefer over nationality)
    var country: String?
    /// NEW GET /users/
    var distanceKm: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, userId, fullName, displayName, link, bio, type
        case userName, username // NEW API uses username
        case profilePicture, avatarUrl, image, isPrivate, verified, isVerified, profilePictureDetails
        case follower_profile, isFollowing, isOwnerFollowingVisitor, isSelected
        case isRequestedByMe, isRequestedToMe
        case searchedAt, user_profile_data
        case relationship // NEW API
        // NEW GET /users/ flat profile fields (SearchFilter / discover)
        case nationality, nationalityFlag, country, profession, gender, dob, statusText, living
        case stats, distanceKm
    }
    
    init(
        id: String? = nil,
        userId: String? = nil,
        userName: String? = nil,
        fullName: String? = nil,
        link: String? = nil,
        bio: String? = nil,
        type: String? = nil,
        profilePicture: String? = nil,
        isPrivate: Bool? = nil,
        verified: Bool? = nil,
        profilePictureDetails: ProfilePictureDetails? = nil,
        follower_profile: FollowerProfile? = nil,
        isFollowing: Bool? = nil,
        isOwnerFollowingVisitor: Bool? = nil,
        isRequestedByMe: Bool? = nil,
        isRequestedToMe: Bool? = nil,
        isSelected: Bool? = nil,
        searchedAt: Date? = nil,
        user_profile_data: ChatUserProfileData? = nil,
        nationalityFlag: String? = nil,
        country: String? = nil,
        distanceKm: Double? = nil
    ) {
        self.id = id
        self.userId = userId ?? id
        self.userName = userName
        self.fullName = fullName
        self.link = link
        self.bio = bio
        self.type = type
        self.profilePicture = profilePicture
        self.isPrivate = isPrivate
        self.verified = verified
        if let profilePictureDetails {
            self.profilePictureDetails = profilePictureDetails
        } else if let profilePicture, !profilePicture.isEmpty {
            self.profilePictureDetails = ProfilePictureDetails(filePath: profilePicture)
        } else {
            self.profilePictureDetails = nil
        }
        self.follower_profile = follower_profile
        self.isFollowing = isFollowing
        self.isOwnerFollowingVisitor = isOwnerFollowingVisitor
        self.isRequestedByMe = isRequestedByMe
        self.isRequestedToMe = isRequestedToMe
        self.isSelected = isSelected
        self.searchedAt = searchedAt
        self.user_profile_data = user_profile_data
        self.nationalityFlag = nationalityFlag
        self.country = country
        self.distanceKm = distanceKm
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? id
        userName = try c.decodeIfPresent(String.self, forKey: .userName)
            ?? c.decodeIfPresent(String.self, forKey: .username)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
            ?? c.decodeIfPresent(String.self, forKey: .displayName)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        // NEW users/ list has no type — treat as user so old filters still work
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "user"
        profilePicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
            ?? c.decodeIfPresent(String.self, forKey: .avatarUrl)
            ?? c.decodeIfPresent(String.self, forKey: .image)
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate)
        // NEW API `isVerified` | OLD `verified`
        verified = try c.decodeIfPresent(Bool.self, forKey: .verified)
            ?? c.decodeIfPresent(Bool.self, forKey: .isVerified)
        profilePictureDetails = try c.decodeIfPresent(ProfilePictureDetails.self, forKey: .profilePictureDetails)
        if profilePictureDetails == nil, let profilePicture, !profilePicture.isEmpty {
            profilePictureDetails = ProfilePictureDetails(filePath: profilePicture)
        }
        follower_profile = try c.decodeIfPresent(FollowerProfile.self, forKey: .follower_profile)
        let rel = try c.decodeIfPresent(DiscoverPeopleRelationship.self, forKey: .relationship)
        let status = (rel?.status ?? "").lowercased()
        let requestedByMe = rel?.isRequestedByMe == true || status == "requested"
        isFollowing = try c.decodeIfPresent(Bool.self, forKey: .isFollowing)
            ?? rel?.isFollowing ?? rel?.following
        if isFollowing == true && requestedByMe {
            isFollowing = false
        }
        isOwnerFollowingVisitor = try c.decodeIfPresent(Bool.self, forKey: .isOwnerFollowingVisitor)
            ?? rel?.followedBy
        isRequestedByMe = try c.decodeIfPresent(Bool.self, forKey: .isRequestedByMe)
            ?? (requestedByMe ? true : nil)
        isRequestedToMe = try c.decodeIfPresent(Bool.self, forKey: .isRequestedToMe)
            ?? rel?.isRequestedToMe
        isSelected = try c.decodeIfPresent(Bool.self, forKey: .isSelected)
        searchedAt = try c.decodeIfPresent(Date.self, forKey: .searchedAt)
        var profile = try c.decodeIfPresent(ChatUserProfileData.self, forKey: .user_profile_data)

        // NEW flat /users/ row — synthesize profile so Explore / search cells keep working
        let nationality = try c.decodeIfPresent(String.self, forKey: .nationality)
        nationalityFlag = try c.decodeIfPresent(String.self, forKey: .nationalityFlag)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        if let km = try? c.decodeIfPresent(Double.self, forKey: .distanceKm) {
            distanceKm = km
        } else if let kmString = try? c.decodeIfPresent(String.self, forKey: .distanceKm),
                  let value = Double(kmString) {
            distanceKm = value
        } else {
            distanceKm = nil
        }
        let profession = try c.decodeIfPresent(String.self, forKey: .profession)
        let gender = try c.decodeIfPresent(String.self, forKey: .gender)
        let dob = try c.decodeIfPresent(String.self, forKey: .dob)
        let living = try c.decodeIfPresent(String.self, forKey: .statusText)
            ?? c.decodeIfPresent(String.self, forKey: .living)
        let stats = try c.decodeIfPresent(DiscoverPeopleStats.self, forKey: .stats)

        if profile == nil,
           nationality != nil || country != nil || profession != nil || verified != nil || stats != nil || rel != nil {
            profile = ChatUserProfileData(
                userId: userId ?? id,
                postCount: stats?.posts,
                posts: stats?.posts,
                reels: stats?.reels,
                content: nil,
                followerCount: stats?.followers,
                followingCount: stats?.following,
                profileImage: profilePicture,
                bio: bio,
                profession: profession,
                fullName: fullName,
                userName: userName,
                link: link,
                isFollowing: isFollowing,
                isOwnerFollowingVisitor: isOwnerFollowingVisitor,
                isRequestedByMe: isRequestedByMe,
                isRequestedToMe: isRequestedToMe,
                isPrivate: isPrivate,
                isBlock: rel?.isBlocked,
                isBlockedByOwner: rel?.blockedByOwner,
                followId: nil,
                verified: verified,
                gender: gender,
                nationality: nationality ?? country,
                dob: dob,
                age: nil,
                livingAddress: living
            )
        } else if var p = profile {
            if p.verified == nil { p.verified = verified }
            if p.nationality == nil { p.nationality = nationality ?? country }
            if p.isBlock == nil { p.isBlock = rel?.isBlocked }
            if p.isBlockedByOwner == nil { p.isBlockedByOwner = rel?.blockedByOwner }
            profile = p
        }
        user_profile_data = profile
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(userName, forKey: .userName)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(link, forKey: .link)
        try c.encodeIfPresent(bio, forKey: .bio)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(profilePicture, forKey: .profilePicture)
        try c.encodeIfPresent(isPrivate, forKey: .isPrivate)
        try c.encodeIfPresent(verified, forKey: .verified)
        try c.encodeIfPresent(profilePictureDetails, forKey: .profilePictureDetails)
        try c.encodeIfPresent(follower_profile, forKey: .follower_profile)
        try c.encodeIfPresent(isFollowing, forKey: .isFollowing)
        try c.encodeIfPresent(isOwnerFollowingVisitor, forKey: .isOwnerFollowingVisitor)
        try c.encodeIfPresent(isRequestedByMe, forKey: .isRequestedByMe)
        try c.encodeIfPresent(isRequestedToMe, forKey: .isRequestedToMe)
        try c.encodeIfPresent(isSelected, forKey: .isSelected)
        try c.encodeIfPresent(searchedAt, forKey: .searchedAt)
        try c.encodeIfPresent(user_profile_data, forKey: .user_profile_data)
        try c.encodeIfPresent(nationalityFlag, forKey: .nationalityFlag)
        try c.encodeIfPresent(country, forKey: .country)
        try c.encodeIfPresent(distanceKm, forKey: .distanceKm)
    }

    static func == (lhs: UserRes, rhs: UserRes) -> Bool {
        return lhs.id == rhs.id &&
        lhs.userId == rhs.userId &&
        lhs.userName == rhs.userName &&
        lhs.fullName == rhs.fullName &&
        lhs.link == rhs.link &&
        lhs.bio == rhs.bio &&
        lhs.type == rhs.type &&
        lhs.profilePicture == rhs.profilePicture &&
        
        lhs.isPrivate == rhs.isPrivate &&
        lhs.verified == rhs.verified &&
       
        lhs.profilePictureDetails?.filePath == rhs.profilePictureDetails?.filePath &&
        lhs.isFollowing == rhs.isFollowing &&
        lhs.isSelected == rhs.isSelected &&
        lhs.searchedAt == rhs.searchedAt &&
        lhs.user_profile_data == rhs.user_profile_data &&
        lhs.nationalityFlag == rhs.nationalityFlag &&
        lhs.country == rhs.country &&
        lhs.distanceKm == rhs.distanceKm
    }
}

extension UserRes {
    var displayAvatarURL: String? {
        profilePictureDetails?.filePath ?? profilePicture
    }
}

struct StoryResponseModel: Codable {
    let userID, userName, fullName: String?
    let profilePicture: String?
    let isPrivate, verified: Bool?
    let profilePictureDetails: ProfilePictureDetails?
    var isAllStoryScene:Bool? = false
    var stories: [Story]?
    let userID1: String?
    var currentStoryindex:Int?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case userName, fullName, profilePicture, isPrivate, verified, profilePictureDetails, stories,currentStoryindex
        case userID1 = "userId"
    }
}

struct OtherUserResponse : DataClass, Codable, Equatable {
    let userId, userName, fullName, link, bio: String?
    let isPrivate, verified: Bool?
    let profilePicture, profession: String?
    let follow: Follow?
    let content: Content?
    let profilePictureDetails: ProfilePictureResponse?
    let posts, reels: Int?
    var isOwnerFollowingVisitor: Bool?
    var isFollowing: Bool?
    var user_profile_data: ChatUserProfileData?
    /// NEW API — users/{id} | users/me
    let displayName: String?
    let statusText: String?
    let nationality: String?
    let gender: String?
    /// NEW relationship.status (e.g. requested / following)
    var relationshipStatus: String?
    var isRequestedByMe: Bool?
    /// NEW users/{id} relationship extras
    var isRequestedToMe: Bool?
    var isBlocked: Bool?
    var isBlockedByOwner: Bool?
    var isSelf: Bool?
    var dob: String?
    /// True when NEW `relationship` object was present on users/{id} (source of truth for follow UI).
    var hasDecodedRelationship: Bool = false
    /// Peer presence privacy from NEW users/{id} (everyone | my_contacts | nobody | …).
    var lastSeenVisibility: String?
    var onlineVisibility: String?
    var isOnline: Bool?
    var lastSeenAt: String?
    /// NEW users/{id} — server-built profile share URL.
    var shareLink: String?

    enum CodingKeys: String, CodingKey {
        case userId, id
        case userName, username
        case fullName, displayName, link, bio, statusText
        case isPrivate, verified
        case isVerified // NEW users/me | users/{id}
        case profilePicture, profession, nationality, gender
        case follow, content, profilePictureDetails
        case posts, reels
        case isOwnerFollowingVisitor, isFollowing
        case user_profile_data
        case stats, relationship
        case avatarUrl, avatar
        case user // NEW users/me | users/{id} wrap
        case status // NEW relationship alternate at root
        case dob
        case lastSeenVisibility, onlineVisibility, isOnline, online, lastSeenAt, lastSeen, lastOnline
        case shareLink
    }

    init(
        userId: String? = nil,
        userName: String? = nil,
        fullName: String? = nil,
        link: String? = nil,
        bio: String? = nil,
        isPrivate: Bool? = nil,
        verified: Bool? = nil,
        profilePicture: String? = nil,
        profession: String? = nil,
        follow: Follow? = nil,
        content: Content? = nil,
        profilePictureDetails: ProfilePictureResponse? = nil,
        posts: Int? = nil,
        reels: Int? = nil,
        isOwnerFollowingVisitor: Bool? = nil,
        isFollowing: Bool? = nil,
        user_profile_data: ChatUserProfileData? = nil,
        displayName: String? = nil,
        statusText: String? = nil,
        nationality: String? = nil,
        gender: String? = nil,
        relationshipStatus: String? = nil,
        isRequestedByMe: Bool? = nil,
        isRequestedToMe: Bool? = nil,
        isBlocked: Bool? = nil,
        isBlockedByOwner: Bool? = nil,
        isSelf: Bool? = nil,
        dob: String? = nil,
        hasDecodedRelationship: Bool = false,
        lastSeenVisibility: String? = nil,
        onlineVisibility: String? = nil,
        isOnline: Bool? = nil,
        lastSeenAt: String? = nil,
        shareLink: String? = nil
    ) {
        self.userId = userId
        self.userName = userName
        self.fullName = fullName
        self.link = link
        self.bio = bio
        self.isPrivate = isPrivate
        self.verified = verified
        self.profilePicture = profilePicture
        self.profession = profession
        self.follow = follow
        self.content = content
        self.profilePictureDetails = profilePictureDetails
        self.posts = posts
        self.reels = reels
        self.isOwnerFollowingVisitor = isOwnerFollowingVisitor
        self.isFollowing = isFollowing
        self.user_profile_data = user_profile_data
        self.displayName = displayName
        self.statusText = statusText
        self.nationality = nationality
        self.gender = gender
        self.relationshipStatus = relationshipStatus
        self.isRequestedByMe = isRequestedByMe
        self.isRequestedToMe = isRequestedToMe
        self.isBlocked = isBlocked
        self.isBlockedByOwner = isBlockedByOwner
        self.isSelf = isSelf
        self.dob = dob
        self.hasDecodedRelationship = hasDecodedRelationship
        self.lastSeenVisibility = lastSeenVisibility
        self.onlineVisibility = onlineVisibility
        self.isOnline = isOnline
        self.lastSeenAt = lastSeenAt
        self.shareLink = shareLink
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        // NEW: { user: { ...profile } } — same shape as users/me
        let c = (try? root.nestedContainer(keyedBy: CodingKeys.self, forKey: .user)) ?? root
        
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
            ?? c.decodeIfPresent(String.self, forKey: .id)
        userName = try c.decodeIfPresent(String.self, forKey: .userName)
            ?? c.decodeIfPresent(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName) ?? displayName
        link = try c.decodeIfPresent(String.self, forKey: .link)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        statusText = try c.decodeIfPresent(String.self, forKey: .statusText)
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate)
        // NEW `isVerified` | OLD `verified`
        verified = try c.decodeIfPresent(Bool.self, forKey: .verified)
            ?? c.decodeIfPresent(Bool.self, forKey: .isVerified)
        dob = try c.decodeIfPresent(String.self, forKey: .dob)
        let pic = try c.decodeIfPresent(String.self, forKey: .profilePicture)
            ?? c.decodeIfPresent(String.self, forKey: .avatarUrl)
            ?? c.decodeIfPresent(String.self, forKey: .avatar)
        profilePicture = pic
        profession = try c.decodeIfPresent(String.self, forKey: .profession)
        nationality = try c.decodeIfPresent(String.self, forKey: .nationality)
        gender = try c.decodeIfPresent(String.self, forKey: .gender)

        let stats = try c.decodeIfPresent(DiscoverPeopleStats.self, forKey: .stats)
        var decodedFollow = try c.decodeIfPresent(Follow.self, forKey: .follow)
        if decodedFollow == nil, let stats {
            decodedFollow = Follow(following: stats.following, followers: stats.followers, hideFollowersAndFollowing: nil)
        }
        follow = decodedFollow

        var decodedContent = try c.decodeIfPresent(Content.self, forKey: .content)
        posts = try c.decodeIfPresent(Int.self, forKey: .posts) ?? stats?.posts ?? decodedContent?.post
        reels = try c.decodeIfPresent(Int.self, forKey: .reels) ?? stats?.reels ?? decodedContent?.reel
        if decodedContent == nil, posts != nil || reels != nil {
            decodedContent = Content(post: posts, reel: reels)
        }
        content = decodedContent

        var details = try c.decodeIfPresent(ProfilePictureResponse.self, forKey: .profilePictureDetails)
        if details == nil, let pic, !pic.isEmpty {
            details = ProfilePictureResponse(filePath: pic, id: nil)
        }
        profilePictureDetails = details

        let rel = try c.decodeIfPresent(DiscoverPeopleRelationship.self, forKey: .relationship)
        hasDecodedRelationship = rel != nil
        isFollowing = try c.decodeIfPresent(Bool.self, forKey: .isFollowing)
            ?? rel?.isFollowing ?? rel?.following
        isOwnerFollowingVisitor = try c.decodeIfPresent(Bool.self, forKey: .isOwnerFollowingVisitor)
            ?? rel?.followedBy
        relationshipStatus = try c.decodeIfPresent(String.self, forKey: .status)
            ?? rel?.status
        // Prefer explicit NEW flags from relationship object
        isRequestedByMe = rel?.isRequestedByMe
            ?? ((relationshipStatus?.lowercased() == "requested")
                || (rel?.isRequested == true && (isFollowing != true)))
        isRequestedToMe = rel?.isRequestedToMe
        isBlocked = rel?.isBlocked
        isBlockedByOwner = rel?.blockedByOwner
        isSelf = rel?.isSelf
        user_profile_data = try c.decodeIfPresent(ChatUserProfileData.self, forKey: .user_profile_data)

        lastSeenVisibility = try c.decodeIfPresent(String.self, forKey: .lastSeenVisibility)
        onlineVisibility = try c.decodeIfPresent(String.self, forKey: .onlineVisibility)
        isOnline = try c.decodeIfPresent(Bool.self, forKey: .isOnline)
            ?? c.decodeIfPresent(Bool.self, forKey: .online)
        lastSeenAt = try c.decodeIfPresent(String.self, forKey: .lastSeenAt)
            ?? c.decodeIfPresent(String.self, forKey: .lastSeen)
            ?? c.decodeIfPresent(String.self, forKey: .lastOnline)
        shareLink = try c.decodeIfPresent(String.self, forKey: .shareLink)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(userName, forKey: .userName)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(link, forKey: .link)
        try c.encodeIfPresent(bio, forKey: .bio)
        try c.encodeIfPresent(statusText, forKey: .statusText)
        try c.encodeIfPresent(isPrivate, forKey: .isPrivate)
        try c.encodeIfPresent(verified, forKey: .verified)
        try c.encodeIfPresent(profilePicture, forKey: .profilePicture)
        try c.encodeIfPresent(profession, forKey: .profession)
        try c.encodeIfPresent(nationality, forKey: .nationality)
        try c.encodeIfPresent(gender, forKey: .gender)
        try c.encodeIfPresent(follow, forKey: .follow)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(profilePictureDetails, forKey: .profilePictureDetails)
        try c.encodeIfPresent(posts, forKey: .posts)
        try c.encodeIfPresent(reels, forKey: .reels)
        try c.encodeIfPresent(isOwnerFollowingVisitor, forKey: .isOwnerFollowingVisitor)
        try c.encodeIfPresent(isFollowing, forKey: .isFollowing)
        try c.encodeIfPresent(user_profile_data, forKey: .user_profile_data)
        try c.encodeIfPresent(lastSeenVisibility, forKey: .lastSeenVisibility)
        try c.encodeIfPresent(onlineVisibility, forKey: .onlineVisibility)
        try c.encodeIfPresent(isOnline, forKey: .isOnline)
        try c.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
        try c.encodeIfPresent(shareLink, forKey: .shareLink)
    }
}

struct OtherStoryResponseModel: Codable {
    let count: Int?
    var rows: [StoryResponseModel]?
}

struct ProfilePictureDetails: DataClass, Codable {
    var filePath: String?
    var id:String?
    
    init(filePath: String? = nil, id: String? = nil) {
        self.filePath = filePath
        self.id = id
    }
}

struct ReelResponse: Codable {
    let caption: String?
    let fileData: [ReelFileData]?
    let id: String?
    let type: String?
    let user: ReelChatUser?
    let userId: String?

    enum CodingKeys: String, CodingKey {
        case caption, fileData, id, type, user
        case userId = "user_id"
    }

    init(dictionary: [String: Any]) {
        caption = dictionary["caption"] as? String
        if let fileDataArray = dictionary["fileData"] as? [[String: Any]] {
            fileData = fileDataArray.map { ReelFileData(dictionary: $0) }
        } else {
            fileData = []
        }
        id = dictionary["id"] as? String
        type = dictionary["type"] as? String
        user = (dictionary["user"] as? [String: Any]).flatMap { ReelChatUser(dictionary: $0) }
        userId = dictionary["user_id"] as? String
    }
}

struct Post: Codable {
    let caption: String?
    let fileData: [PostFileData]?
    let id: String?
    let type: String?
    let user: PostUser?
    let userId: String?

    enum CodingKeys: String, CodingKey {
        case caption, fileData, files, id, type, user
        case userId
        case user_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        fileData = (try? c.decodeIfPresent([PostFileData].self, forKey: .fileData))
            ?? (try? c.decodeIfPresent([PostFileData].self, forKey: .files))
            ?? nil
        id = try c.decodeIfPresent(String.self, forKey: .id)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        user = try? c.decodeIfPresent(PostUser.self, forKey: .user)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
            ?? c.decodeIfPresent(String.self, forKey: .user_id)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(caption, forKey: .caption)
        try c.encodeIfPresent(fileData, forKey: .fileData)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(user, forKey: .user)
        try c.encodeIfPresent(userId, forKey: .userId)
    }

    init(dictionary: [String: Any]) {
        caption = dictionary["caption"] as? String
        if let fileDataArray = dictionary["fileData"] as? [[String: Any]]
            ?? dictionary["files"] as? [[String: Any]] {
            fileData = fileDataArray.map { PostFileData(dictionary: $0) }
        } else {
            fileData = []
        }
        id = dictionary["id"] as? String
        type = dictionary["type"] as? String
        user = (dictionary["user"] as? [String: Any]).flatMap { PostUser(dictionary: $0) }
        userId = dictionary["userId"] as? String ?? dictionary["user_id"] as? String
    }
}

struct MediaUploadSessionData: Codable {
    // MARK: - NEW API keys (media/uploads)
    let mediaId: String?                    // NEW API
    let id: String?                         // NEW API (legacy/alias)
    let strategy: String?                   // NEW API — put | multipart
    let status: String?                     // NEW API
    let key: String?                        // NEW API
    let publicUrl: String?                  // NEW API
    let expiresIn: Int?                     // NEW API
    let upload: MediaUploadPutInfo?         // NEW API — PUT target
    let media: MediaUploadMediaInfo?        // NEW API
    let reused: Bool?                       // NEW API
    let uploadId: String?                   // NEW API — multipart upload id
    let partCount: Int?                     // NEW API — server-chosen part count
    let partSize: Int?                      // NEW API — bytes per part (e.g. 16MB)

    // Older/flat aliases kept for decode compatibility
    let uploadUrl: String?                  // OLD/alias
    let url: String?                        // OLD/alias
    let putUrl: String?                     // OLD/alias
    let fileUrl: String?                    // OLD/alias
    
    /// Presigned PUT URL from `upload.url`
    var resolvedUploadUrl: String? {
        upload?.url ?? uploadUrl ?? url ?? putUrl
    }
    
    /// Content-Type from upload.headers, fallback image/jpeg
    var resolvedContentType: String? {
        upload?.headers?.contentType
    }
    
    var resolvedMediaId: String? {
        mediaId ?? id ?? media?.mediaId ?? media?.id
    }
    
    var resolvedMediaUrl: String? {
        publicUrl ?? media?.publicUrl ?? media?.url ?? fileUrl ?? key ?? resolvedMediaId
    }

    /// HTTP(S) public URL only — for channel `avatarPath` (not mediaId / S3 key).
    var resolvedPublicUrl: String? {
        let candidates = [publicUrl, media?.publicUrl, media?.url, url, fileUrl]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return candidates.first { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") }
    }

    /// Prefer server-provided multipart sizing from create response.
    var resolvedPartCount: Int? {
        partCount ?? media?.partCount
    }

    var resolvedPartSize: Int? {
        partSize ?? media?.partSize
    }
}

protocol DataClass: AutoEquatable { }

struct ChatStory: Codable {
    let createdAt:String?
    let deletedAt:String?
    let enableComments:Bool?
    let enableLikes:Bool?
    let meta:ChatStoryMeta?
    let filePath:String?
    let id:String?
    let isStoryAvailable:Bool?
    let postId:String?
    let type:String?
    let updatedAt:String?
    let user:ChatStoryUser?

    enum CodingKeys: String, CodingKey {
        case createdAt, deletedAt, filePath, id, postId, type, updatedAt, user
        case enableComments = "enable_comments"
        case enableLikes = "enable_likes"
        case isStoryAvailable, meta
    }

    init(dictionary: [String: Any]) {
        createdAt = dictionary["createdAt"] as? String
        deletedAt = dictionary["deletedAt"] as? String
        enableComments = dictionary["enable_comments"] as? Bool
        enableLikes = dictionary["enable_likes"] as? Bool
        meta = (dictionary["meta"] as? [String: Any]).flatMap { ChatStoryMeta(dictionary: $0) }
        filePath = dictionary["filePath"] as? String
        id = dictionary["id"] as? String
        isStoryAvailable = dictionary["isStoryAvailable"] as? Bool
        postId = dictionary["postId"] as? String
        type = dictionary["type"] as? String
        updatedAt = dictionary["updatedAt"] as? String
        user = (dictionary["user"] as? [String: Any]).flatMap { ChatStoryUser(dictionary: $0) }
    }
}

struct PaginatedUsersResponse: Codable {
    let totalResults: Int
    let page: Int
    let limit: Int
    let users: [UserRes]
}

struct MessageInfoData : Codable {
    let message : GroupLinkMessage?
    let readBy : [ReadBy]?
    let deliveredTo : [DeliveredTo]?
    let counts : MessageInfoCounts?
    /// NEW API — `data.info` with `recipients[]`
    let info : MessageInfoDetail?

    enum CodingKeys: String, CodingKey {
        case message, readBy, seenBy, deliveredTo, counts, info
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        message = try values.decodeIfPresent(GroupLinkMessage.self, forKey: .message)
        if let read = try values.decodeIfPresent([ReadBy].self, forKey: .readBy) {
            readBy = read
        } else {
            readBy = try values.decodeIfPresent([ReadBy].self, forKey: .seenBy)
        }
        deliveredTo = try values.decodeIfPresent([DeliveredTo].self, forKey: .deliveredTo)
        counts = try values.decodeIfPresent(MessageInfoCounts.self, forKey: .counts)
        info = try values.decodeIfPresent(MessageInfoDetail.self, forKey: .info)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(message, forKey: .message)
        try values.encodeIfPresent(readBy, forKey: .readBy)
        try values.encodeIfPresent(deliveredTo, forKey: .deliveredTo)
        try values.encodeIfPresent(counts, forKey: .counts)
        try values.encodeIfPresent(info, forKey: .info)
    }
}

class checkBlockedUserodel: DataClass,Codable {
    var isBlocked: Bool?
    var blockId:String?
}

struct ReportReasonsData: Codable {
    let reasons: [String: String]
    let version: String
}

struct PresignedData: Decodable {
    let key: String?
    let uploadUrl: String?
    let uploadId: String?
    let message: String?
}

struct MessageResponse {
    //    var chatStream: Int?
    var createdAt: String?
    var deliveredAt: String?
    var fromSelf: Bool?
    var id: String?
    var isDeleted: Bool?
    var isEdited: Bool?
    var isStreamAvailable: Bool?
    var message: String?
    var messageType: String?
    var type: String?
    var message_type: String?
    var content: String?
    var meta: Metadata?
    var receiver: String?
    var seenAt: String?
    var sender: String?
    var sentAt: String?
    var status: String?
    var streamId: String?
    var updatedAt: String?
    var lastMessage:MessageResponse1?
    var post:Post?
    var reel:ReelResponse?
    var story: ChatStory?


    init(dictionary: [String: Any]) {
        createdAt = dictionary["createdAt"] as? String
        deliveredAt = dictionary["delevired_at"] as? String
        fromSelf = dictionary["fromSelf"] as? Bool ?? false
        id = dictionary["id"] as? String
        isDeleted = dictionary["is_deleted"] as? Bool
        isEdited = dictionary["is_edited"] as? Bool
        isStreamAvailable = dictionary["is_stream_available"] as? Bool
        message = dictionary["message"] as? String
        messageType = dictionary["message_type"] as? String
        type = dictionary["type"] as? String
        message_type = dictionary["message_type"] as? String
        content = dictionary["content"] as? String
        meta = (dictionary["meta"] as? [String: Any]).flatMap { Metadata(dictionary: $0) }
        receiver = dictionary["receiver"] as? String
        seenAt = dictionary["seen_at"] as? String
        sender = dictionary["sender"] as? String
        sentAt = dictionary["sent_at"] as? String
        status = dictionary["status"] as? String
        streamId = dictionary["streamId"] as? String
        updatedAt = dictionary["updatedAt"] as? String
        post = (dictionary["post"] as? [String: Any]).flatMap { Post(dictionary: $0) }
        reel = (dictionary["reel"] as? [String: Any]).flatMap { ReelResponse(dictionary: $0) }
        story = (dictionary["story"] as? [String: Any]).flatMap { ChatStory(dictionary: $0) }
        lastMessage = (dictionary["last_message"] as? [String: Any]).flatMap { MessageResponse1(dictionary: $0) }
    }
}

struct MessageInfoModel : Codable {
    let success : Bool?
    let data : MessageInfoData?
    let message : String?

    enum CodingKeys: String, CodingKey {
        case success, data, message
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        success = try values.decodeIfPresent(Bool.self, forKey: .success)
        data = try values.decodeIfPresent(MessageInfoData.self, forKey: .data)
        message = try values.decodeIfPresent(String.self, forKey: .message)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(success, forKey: .success)
        try values.encodeIfPresent(data, forKey: .data)
        try values.encodeIfPresent(message, forKey: .message)
    }
}

struct MediaUploadPartsData: Codable {
    let parts: [MediaUploadPartInfo]?
    let uploadId: String?
    let mediaId: String?
    let id: String?
    
    enum CodingKeys: String, CodingKey {
        case parts, uploadId, mediaId, id, data, urls
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try c.decodeIfPresent([MediaUploadPartInfo].self, forKey: .parts) {
            parts = list
        } else if let list = try c.decodeIfPresent([MediaUploadPartInfo].self, forKey: .urls) {
            parts = list
        } else if let nested = try? c.nestedContainer(keyedBy: CodingKeys.self, forKey: .data) {
            if let list = try nested.decodeIfPresent([MediaUploadPartInfo].self, forKey: .parts) {
                parts = list
            } else {
                parts = try nested.decodeIfPresent([MediaUploadPartInfo].self, forKey: .urls)
            }
            uploadId = try nested.decodeIfPresent(String.self, forKey: .uploadId)
            if let value = try nested.decodeIfPresent(String.self, forKey: .mediaId) {
                mediaId = value
            } else {
                mediaId = try nested.decodeIfPresent(String.self, forKey: .id)
            }
            id = try nested.decodeIfPresent(String.self, forKey: .id)
            return
        } else {
            parts = nil
        }
        uploadId = try c.decodeIfPresent(String.self, forKey: .uploadId)
        mediaId = try c.decodeIfPresent(String.self, forKey: .mediaId)
        id = try c.decodeIfPresent(String.self, forKey: .id)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(parts, forKey: .parts)
        try c.encodeIfPresent(uploadId, forKey: .uploadId)
        try c.encodeIfPresent(mediaId, forKey: .mediaId)
        try c.encodeIfPresent(id, forKey: .id)
    }
}

class BlockListUserDataModel : DataClass, Codable {
    var user: UserRes?
    var id: String?
    var updatedAt: String?
    var userId: String?
    var blockUserId: String?
    var createdAt: String?
    var userName: String?
    var profilePicture: String?
    var fullName: String?
    var blockedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case user, id, updatedAt, userId, blockUserId, createdAt
        case userName, username, profilePicture, avatarUrl, fullName, displayName, blockedAt
    }
    
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        // OLD shape: nested `user`
        if let nested = try? c.decodeIfPresent(UserRes.self, forKey: .user) {
            user = nested
        } else {
            // NEW `users/me/blocked` rows are flat public profiles (+ blockedAt)
            let flat = try? UserRes(from: decoder)
            if let flat, flat.userId != nil || flat.id != nil || flat.userName != nil {
                user = flat
            } else {
                user = nil
            }
        }
        
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? user?.id ?? user?.userId
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? user?.userId ?? user?.id
        blockUserId = try c.decodeIfPresent(String.self, forKey: .blockUserId) ?? userId
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        blockedAt = try c.decodeIfPresent(String.self, forKey: .blockedAt)
        
        if let value = try c.decodeIfPresent(String.self, forKey: .userName) {
            userName = value
        } else if let value = try c.decodeIfPresent(String.self, forKey: .username) {
            userName = value
        } else {
            userName = user?.userName
        }
        
        if let value = try c.decodeIfPresent(String.self, forKey: .fullName) {
            fullName = value
        } else if let value = try c.decodeIfPresent(String.self, forKey: .displayName) {
            fullName = value
        } else {
            fullName = user?.fullName
        }
        
        if let value = try c.decodeIfPresent(String.self, forKey: .profilePicture) {
            profilePicture = value
        } else if let value = try c.decodeIfPresent(String.self, forKey: .avatarUrl) {
            profilePicture = value
        } else {
            profilePicture = user?.profilePicture ?? user?.profilePictureDetails?.filePath
        }
        
        // Ensure nested user has ids for unblock UI
        if user == nil, let uid = userId ?? id {
            user = UserRes(
                id: uid,
                userId: uid,
                userName: userName,
                fullName: fullName,
                profilePicture: profilePicture
            )
        } else if var existing = user {
            if existing.userId == nil { existing.userId = userId ?? id }
            if existing.id == nil { existing.id = id ?? userId }
            if existing.userName == nil { existing.userName = userName }
            if existing.fullName == nil { existing.fullName = fullName }
            if existing.profilePictureDetails == nil, let profilePicture, !profilePicture.isEmpty {
                existing.profilePictureDetails = ProfilePictureDetails(filePath: profilePicture)
            }
            user = existing
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(user, forKey: .user)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(blockUserId, forKey: .blockUserId)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(userName, forKey: .userName)
        try c.encodeIfPresent(profilePicture, forKey: .profilePicture)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(blockedAt, forKey: .blockedAt)
    }
}

struct VideoSize : DataClass, Codable {
    var mHeight: String?
    var mWidth: String?
}

struct DiscoverPeopleRelationship: Codable {
    let following: Bool? // NEW API
    let followedBy: Bool? // NEW API (+ isFollowedBy)
    let isFollowing: Bool? // NEW API
    let status: String? // NEW API
    let isRequested: Bool? // NEW API (legacy alias)
    let isSelf: Bool? // NEW API users/me
    /// NEW users/{id} relationship flags
    let isRequestedByMe: Bool?
    let isRequestedToMe: Bool?
    let isBlocked: Bool?
    let blockedByOwner: Bool?

    enum CodingKeys: String, CodingKey {
        case following, followedBy, isFollowedBy
        case isFollowing, status, isRequested, isSelf
        case isRequestedByMe, isRequestedToMe
        case isBlocked, blockedByOwner, isBlockedByOwner
    }

    init(
        following: Bool? = nil,
        followedBy: Bool? = nil,
        isFollowing: Bool? = nil,
        status: String? = nil,
        isRequested: Bool? = nil,
        isSelf: Bool? = nil,
        isRequestedByMe: Bool? = nil,
        isRequestedToMe: Bool? = nil,
        isBlocked: Bool? = nil,
        blockedByOwner: Bool? = nil
    ) {
        self.following = following
        self.followedBy = followedBy
        self.isFollowing = isFollowing
        self.status = status
        self.isRequested = isRequested
        self.isSelf = isSelf
        self.isRequestedByMe = isRequestedByMe
        self.isRequestedToMe = isRequestedToMe
        self.isBlocked = isBlocked
        self.blockedByOwner = blockedByOwner
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        following = try c.decodeIfPresent(Bool.self, forKey: .following)
        followedBy = try c.decodeIfPresent(Bool.self, forKey: .followedBy)
            ?? c.decodeIfPresent(Bool.self, forKey: .isFollowedBy)
        isFollowing = try c.decodeIfPresent(Bool.self, forKey: .isFollowing) ?? following
        status = try c.decodeIfPresent(String.self, forKey: .status)
        isRequested = try c.decodeIfPresent(Bool.self, forKey: .isRequested)
        isSelf = try c.decodeIfPresent(Bool.self, forKey: .isSelf)
        isRequestedByMe = try c.decodeIfPresent(Bool.self, forKey: .isRequestedByMe)
            ?? isRequested
        isRequestedToMe = try c.decodeIfPresent(Bool.self, forKey: .isRequestedToMe)
        isBlocked = try c.decodeIfPresent(Bool.self, forKey: .isBlocked)
        blockedByOwner = try c.decodeIfPresent(Bool.self, forKey: .blockedByOwner)
            ?? c.decodeIfPresent(Bool.self, forKey: .isBlockedByOwner)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(following, forKey: .following)
        try c.encodeIfPresent(followedBy, forKey: .followedBy)
        try c.encodeIfPresent(isFollowing, forKey: .isFollowing)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(isRequested, forKey: .isRequested)
        try c.encodeIfPresent(isSelf, forKey: .isSelf)
        try c.encodeIfPresent(isRequestedByMe, forKey: .isRequestedByMe)
        try c.encodeIfPresent(isRequestedToMe, forKey: .isRequestedToMe)
        try c.encodeIfPresent(isBlocked, forKey: .isBlocked)
        try c.encodeIfPresent(blockedByOwner, forKey: .blockedByOwner)
    }
}

struct DiscoverPeopleStats: Codable {
    let followers: Int? // NEW API (+ followerCount)
    let following: Int? // NEW API (+ followingCount)
    let posts: Int? // NEW API (+ postCount)
    let reels: Int? // NEW API (+ reelCount)

    enum CodingKeys: String, CodingKey {
        case followers, following, posts, reels
        case followerCount, followingCount, postCount, reelCount
    }

    init(followers: Int? = nil, following: Int? = nil, posts: Int? = nil, reels: Int? = nil) {
        self.followers = followers
        self.following = following
        self.posts = posts
        self.reels = reels
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        followers = try c.decodeIfPresent(Int.self, forKey: .followers)
            ?? c.decodeIfPresent(Int.self, forKey: .followerCount)
        following = try c.decodeIfPresent(Int.self, forKey: .following)
            ?? c.decodeIfPresent(Int.self, forKey: .followingCount)
        posts = try c.decodeIfPresent(Int.self, forKey: .posts)
            ?? c.decodeIfPresent(Int.self, forKey: .postCount)
        reels = try c.decodeIfPresent(Int.self, forKey: .reels)
            ?? c.decodeIfPresent(Int.self, forKey: .reelCount)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(followers, forKey: .followers)
        try c.encodeIfPresent(following, forKey: .following)
        try c.encodeIfPresent(posts, forKey: .posts)
        try c.encodeIfPresent(reels, forKey: .reels)
    }
}

struct FollowerProfile: Codable {
    let userId: String?
    let userName: String?
    var id: String?
    let profilePicture: String?
    let profilePictureDetails: ProfilePictureDetails?
    let verified: Bool?
    let fullName: String?
    let isPrivate: Bool?
    let status, following, follower, requestedAt, followedAt,updatedAt,createdAt : String?
    let following_user_id,follower_user_id : String?
    
    enum CodingKeys: String, CodingKey {
        case userId, userName, id, profilePicture, profilePictureDetails
        case verified, isVerified, fullName, isPrivate
        case status, following, follower, requestedAt, followedAt, updatedAt, createdAt
        case following_user_id, follower_user_id
        case username // NEW
    }
    
    init(
        userId: String? = nil,
        userName: String? = nil,
        id: String? = nil,
        profilePicture: String? = nil,
        profilePictureDetails: ProfilePictureDetails? = nil,
        verified: Bool? = nil,
        fullName: String? = nil,
        isPrivate: Bool? = nil,
        status: String? = nil,
        following: String? = nil,
        follower: String? = nil,
        requestedAt: String? = nil,
        followedAt: String? = nil,
        updatedAt: String? = nil,
        createdAt: String? = nil,
        following_user_id: String? = nil,
        follower_user_id: String? = nil
    ) {
        self.userId = userId
        self.userName = userName
        self.id = id
        self.profilePicture = profilePicture
        self.profilePictureDetails = profilePictureDetails
        self.verified = verified
        self.fullName = fullName
        self.isPrivate = isPrivate
        self.status = status
        self.following = following
        self.follower = follower
        self.requestedAt = requestedAt
        self.followedAt = followedAt
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.following_user_id = following_user_id
        self.follower_user_id = follower_user_id
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? c.decodeIfPresent(String.self, forKey: .id)
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? c.decodeIfPresent(String.self, forKey: .username)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        profilePicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
        var details = try c.decodeIfPresent(ProfilePictureDetails.self, forKey: .profilePictureDetails)
        if details == nil, let profilePicture, !profilePicture.isEmpty {
            details = ProfilePictureDetails(filePath: profilePicture)
        }
        profilePictureDetails = details
        verified = try c.decodeIfPresent(Bool.self, forKey: .verified)
            ?? c.decodeIfPresent(Bool.self, forKey: .isVerified)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        following = try c.decodeIfPresent(String.self, forKey: .following)
        follower = try c.decodeIfPresent(String.self, forKey: .follower)
        requestedAt = try c.decodeIfPresent(String.self, forKey: .requestedAt)
        followedAt = try c.decodeIfPresent(String.self, forKey: .followedAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        following_user_id = try c.decodeIfPresent(String.self, forKey: .following_user_id)
        follower_user_id = try c.decodeIfPresent(String.self, forKey: .follower_user_id)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(userName, forKey: .userName)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(profilePicture, forKey: .profilePicture)
        try c.encodeIfPresent(profilePictureDetails, forKey: .profilePictureDetails)
        try c.encodeIfPresent(verified, forKey: .verified)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(isPrivate, forKey: .isPrivate)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(following, forKey: .following)
        try c.encodeIfPresent(follower, forKey: .follower)
        try c.encodeIfPresent(requestedAt, forKey: .requestedAt)
        try c.encodeIfPresent(followedAt, forKey: .followedAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(following_user_id, forKey: .following_user_id)
        try c.encodeIfPresent(follower_user_id, forKey: .follower_user_id)
    }
}

struct Story: Codable {
    let filePath: String?
    let thumbnail:String?
    let id: String?
    //    let postID: JSONNull?
    let enableComments, enableLikes: Bool?
    let type: String?
    var meta: StoryMeta?
    //   let deletedAt: JSONNull?
    let createdAt, updatedAt: String?
    var isStoryViewed:Bool?
    var storyLike:Bool?
    var seenUser: StorySeenUser?
    var storyLikedBy: StoryLikedBy?

    enum CodingKeys: String, CodingKey {
        case filePath, id
        //        case postID = "postId"
        case enableComments = "enable_comments"
        case enableLikes = "enable_likes"
        case isStoryViewed = "is_story_viewed"
        case type, meta, createdAt, updatedAt, seenUser,storyLike,storyLikedBy,thumbnail
    }
}

struct Follow : DataClass, Codable, Equatable {
    let following: Int?
    let followers: Int?
    var hideFollowersAndFollowing: Bool?
    
    init(following: Int? = nil, followers: Int? = nil, hideFollowersAndFollowing: Bool? = nil) {
        self.following = following
        self.followers = followers
        self.hideFollowersAndFollowing = hideFollowersAndFollowing
    }
}

struct Content: DataClass,Codable,Equatable {
    let post, reel: Int?
    
    init(post: Int? = nil, reel: Int? = nil) {
        self.post = post
        self.reel = reel
    }
}

struct ProfilePictureResponse : DataClass, Codable, Equatable {
    let filePath: String?
    let id: String?
    
    init(filePath: String? = nil, id: String? = nil) {
        self.filePath = filePath
        self.id = id
    }
}

struct ReelFileData: Codable {
    let filePath: String?
    let id: String?
    let isStreamAvailable: Int?
    let stream: Stream?
    let streamId: String?
    let thumbnail: String?

    enum CodingKeys: String, CodingKey {
        case filePath, id, isStreamAvailable, stream, thumbnail
        case streamId = "stream_id"
    }

    init(dictionary: [String: Any]) {
        filePath = dictionary["filePath"] as? String
        id = dictionary["id"] as? String
        isStreamAvailable = dictionary["isStreamAvailable"] as? Int
        stream = (dictionary["stream"] as? [String: Any]).flatMap { Stream(dictionary: $0) }
        streamId = dictionary["stream_id"] as? String
        thumbnail = dictionary["thumbnail"] as? String
    }
}

struct ReelChatUser: Codable {
    let fullName: String?
    let id: String?
    let isPrivate: Int?
    let profilePicture: String?
    let profilePictureDetails: PostProfilePictureDetails?
    let userId: String?
    let userName: String?
    let userIdAlias: String?
    let verified: Int?

    enum CodingKeys: String, CodingKey {
        case fullName, id, isPrivate, profilePicture, profilePictureDetails, userName, verified
        case userId, userIdAlias = "user_id"
    }

    init(dictionary: [String: Any]) {
        fullName = dictionary["fullName"] as? String
        id = dictionary["id"] as? String
        isPrivate = dictionary["isPrivate"] as? Int
        profilePicture = dictionary["profilePicture"] as? String
        profilePictureDetails = (dictionary["profilePictureDetails"] as? [String: Any]).flatMap { PostProfilePictureDetails(dictionary: $0) }
        userId = dictionary["userId"] as? String
        userName = dictionary["userName"] as? String
        userIdAlias = dictionary["user_id"] as? String
        verified = dictionary["verified"] as? Int
    }
}

struct PostFileData: Codable {
    let filePath: String?
    let id: String?
    let position: Int?
    let thumbnail: String?

    init(dictionary: [String: Any]) {
        filePath = dictionary["filePath"] as? String
        id = dictionary["id"] as? String
        position = dictionary["position"] as? Int
        thumbnail = dictionary["thumbnail"] as? String
    }
}

struct PostUser: Codable {
    let fullName: String?
    let id: String?
    let isPrivate: Bool?
    let profilePicture: String?
    let profilePictureDetails: PostProfilePictureDetails?
    let userId: String?
    let userName: String?
    let verified: Bool?

    enum CodingKeys: String, CodingKey {
        case fullName, id, isPrivate, profilePicture, profilePictureDetails, userName, verified
        case userId
        case user_id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate)
        profilePicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
        profilePictureDetails = try? c.decodeIfPresent(PostProfilePictureDetails.self, forKey: .profilePictureDetails)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
            ?? c.decodeIfPresent(String.self, forKey: .user_id)
        userName = try c.decodeIfPresent(String.self, forKey: .userName)
        verified = try c.decodeIfPresent(Bool.self, forKey: .verified)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(isPrivate, forKey: .isPrivate)
        try c.encodeIfPresent(profilePicture, forKey: .profilePicture)
        try c.encodeIfPresent(profilePictureDetails, forKey: .profilePictureDetails)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(userName, forKey: .userName)
        try c.encodeIfPresent(verified, forKey: .verified)
    }

    init(dictionary: [String: Any]) {
        fullName = dictionary["fullName"] as? String
        id = dictionary["id"] as? String
        isPrivate = dictionary["isPrivate"] as? Bool
        profilePicture = dictionary["profilePicture"] as? String
        profilePictureDetails = (dictionary["profilePictureDetails"] as? [String: Any]).flatMap { PostProfilePictureDetails(dictionary: $0) }
        userId = dictionary["userId"] as? String ?? dictionary["user_id"] as? String
        userName = dictionary["userName"] as? String
        verified = dictionary["verified"] as? Bool
    }
}

struct MediaUploadMediaInfo: Codable {
    let id: String?
    let mediaId: String?
    let kind: String?
    let purpose: String?
    let strategy: String?
    let status: String?
    let mimeType: String?
    let contentType: String?
    let key: String?
    let url: String?
    let publicUrl: String?
    let thumbnailUrl: String?
    let partCount: Int?
    let partSize: Int?
}

struct MediaUploadPutInfo: Codable {
    let method: String?                     // NEW API — PUT
    let url: String?                        // NEW API — S3 presigned URL
    let headers: MediaUploadPutHeaders?     // NEW API
}

protocol AutoEquatable { }

struct ChatStoryUser: Codable {
    let fullName: String?
    let isPrivate: Bool?
    let profilePicture: String?
    let profilePictureDetails: PostProfilePictureDetails?
    let userId: String?
    let userName: String?
    let verified: Bool?

    enum CodingKeys: String, CodingKey {
        case fullName, isPrivate, profilePicture, profilePictureDetails, userName, verified
        case userId
    }

    init(dictionary: [String: Any]) {
        fullName = dictionary["fullName"] as? String
        isPrivate = dictionary["isPrivate"] as? Bool
        profilePicture = dictionary["profilePicture"] as? String
        profilePictureDetails = (dictionary["profilePictureDetails"] as? [String: Any]).flatMap { PostProfilePictureDetails(dictionary: $0) }
        userId = dictionary["userId"] as? String
        userName = dictionary["userName"] as? String
        verified = dictionary["verified"] as? Bool
    }
}

struct ChatStoryMeta: Codable {
    let audioVolume: Int?
    let emojis: [String]?
    let fileType: String?
    let gifs: [String]?
    let texts: [String]?
    var hasAudio: Bool?
    var videoDuration: Int?
    var videoSize: ChatStoryVideoSize?

    enum CodingKeys: String, CodingKey {
        case audioVolume, emojis, gifs, texts, hasAudio, videoDuration
        case fileType = "file_type"
        case videoSize = "video_size"
    }

    init(dictionary: [String: Any]) {
        audioVolume = dictionary["audio_volume"] as? Int
        emojis = dictionary["emojis"] as? [String]
        fileType = dictionary["file_type"] as? String
        gifs = dictionary["gifs"] as? [String]
        texts = dictionary["texts"] as? [String]
        hasAudio = dictionary["has_audio"] as? Bool
        videoDuration = dictionary["video_duration"] as? Int
        videoSize = (dictionary["video_size"] as? [String: Any]).flatMap { ChatStoryVideoSize(dictionary: $0) }
    }
}

struct GroupLinkMessage : Codable {
    let id : String?
    let conversationId : String?
    let senderId : String?
    let messageType : String?
    let content : String?
    let isEdited : Bool?
    let metadata : MessageInfoMetadata?
    let sentAt : String?
    let updatedAt : String?

    enum CodingKeys: String, CodingKey {
        case id, conversationId, senderId, messageType, content, isEdited, metadata, sentAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id)
        conversationId = try values.decodeIfPresent(String.self, forKey: .conversationId)
        senderId = try values.decodeIfPresent(String.self, forKey: .senderId)
        messageType = try values.decodeIfPresent(String.self, forKey: .messageType)
        content = try values.decodeIfPresent(String.self, forKey: .content)
        isEdited = try values.decodeIfPresent(Bool.self, forKey: .isEdited)
        metadata = try values.decodeIfPresent(MessageInfoMetadata.self, forKey: .metadata)
        sentAt = try values.decodeIfPresent(String.self, forKey: .sentAt)
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(id, forKey: .id)
        try values.encodeIfPresent(conversationId, forKey: .conversationId)
        try values.encodeIfPresent(senderId, forKey: .senderId)
        try values.encodeIfPresent(messageType, forKey: .messageType)
        try values.encodeIfPresent(content, forKey: .content)
        try values.encodeIfPresent(isEdited, forKey: .isEdited)
        try values.encodeIfPresent(metadata, forKey: .metadata)
        try values.encodeIfPresent(sentAt, forKey: .sentAt)
        try values.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

struct MessageInfoCounts : Codable {
    let read : Int?
    let delivered : Int?
    let total : Int?

    enum CodingKeys: String, CodingKey {
        case read
        case delivered
        case total = "totalRecipients"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        read = try values.decodeIfPresent(Int.self, forKey: .read)
        delivered = try values.decodeIfPresent(Int.self, forKey: .delivered)
        total = try values.decodeIfPresent(Int.self, forKey: .total)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(read, forKey: .read)
        try values.encodeIfPresent(delivered, forKey: .delivered)
        try values.encodeIfPresent(total, forKey: .total)
    }
}

struct ReadBy : Codable {
    let userId : String?
    let userName : String?
    let fullName : String?
    let profileImage : String?
    let at : String?

    enum CodingKeys: String, CodingKey {
        case userId, userName, fullName, profileImage, profilePicture, avatarUrl, at, readAt, seenAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userId = try values.decodeIfPresent(String.self, forKey: .userId)
        userName = try values.decodeIfPresent(String.self, forKey: .userName)
        fullName = try values.decodeIfPresent(String.self, forKey: .fullName)
        if let img = try values.decodeIfPresent(String.self, forKey: .profileImage) {
            profileImage = img
        } else if let img = try values.decodeIfPresent(String.self, forKey: .profilePicture) {
            profileImage = img
        } else {
            profileImage = try values.decodeIfPresent(String.self, forKey: .avatarUrl)
        }
        if let ts = try values.decodeIfPresent(String.self, forKey: .at) {
            at = ts
        } else if let ts = try values.decodeIfPresent(String.self, forKey: .readAt) {
            at = ts
        } else {
            at = try values.decodeIfPresent(String.self, forKey: .seenAt)
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(userId, forKey: .userId)
        try values.encodeIfPresent(userName, forKey: .userName)
        try values.encodeIfPresent(fullName, forKey: .fullName)
        try values.encodeIfPresent(profileImage, forKey: .profileImage)
        try values.encodeIfPresent(at, forKey: .at)
    }
}

struct MessageInfoDetail : Codable {
    let messageId: String?
    let conversationId: String?
    let conversationType: String?
    let status: String?
    let type: String?
    let body: String?
    let sentAt: String?
    let deliveredAt: String?
    let readAt: String?
    let recipients: [MessageInfoRecipient]?

    enum CodingKeys: String, CodingKey {
        case messageId, conversationId, conversationType, status, type, body
        case sentAt, deliveredAt, readAt, recipients
    }
}

struct DeliveredTo : Codable {
    let userId : String?
    let userName : String?
    let fullName : String?
    let profileImage : String?
    let at : String?

    enum CodingKeys: String, CodingKey {
        case userId, userName, fullName, profileImage, profilePicture, avatarUrl, at, deliveredAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userId = try values.decodeIfPresent(String.self, forKey: .userId)
        userName = try values.decodeIfPresent(String.self, forKey: .userName)
        fullName = try values.decodeIfPresent(String.self, forKey: .fullName)
        if let img = try values.decodeIfPresent(String.self, forKey: .profileImage) {
            profileImage = img
        } else if let img = try values.decodeIfPresent(String.self, forKey: .profilePicture) {
            profileImage = img
        } else {
            profileImage = try values.decodeIfPresent(String.self, forKey: .avatarUrl)
        }
        if let ts = try values.decodeIfPresent(String.self, forKey: .at) {
            at = ts
        } else {
            at = try values.decodeIfPresent(String.self, forKey: .deliveredAt)
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(userId, forKey: .userId)
        try values.encodeIfPresent(userName, forKey: .userName)
        try values.encodeIfPresent(fullName, forKey: .fullName)
        try values.encodeIfPresent(profileImage, forKey: .profileImage)
        try values.encodeIfPresent(at, forKey: .at)
    }
}

struct Metadata {
    var audioDuration: String?
    var fileName: String?
    
    // Add dictionary storage for flexible access
    private var dictionary: [String: Any]
    
    // Add subscript support for dictionary-like access
    subscript(key: String) -> Any? {
        return dictionary[key]
    }

    init(dictionary: [String: Any]) {
        self.dictionary = dictionary
        audioDuration = dictionary["audio_duration"] as? String
        fileName = dictionary["file_name"] as? String
    }
}

struct MessageResponse1 {
    //    var chatStream: Int?
    var createdAt: String?
    var deliveredAt: String?
    var fromSelf: Bool?
    var id: String?
    var isDeleted: Bool?
    var isEdited: Bool?
    var isStreamAvailable: Bool?
    var message: String?
    var messageType: String?
    var meta: Metadata?
    var receiver: String?
    var seenAt: String?
    var sender: String?
    var sentAt: String?
    var status: String?
    var streamId: String?
    var updatedAt: String?
    var post:Post?
    var reel:ReelResponse?
    let story: ChatStory?


    init(dictionary: [String: Any]) {
        createdAt = dictionary["createdAt"] as? String
        deliveredAt = dictionary["delevired_at"] as? String
        fromSelf = dictionary["fromSelf"] as? Bool ?? false
        id = dictionary["id"] as? String
        isDeleted = dictionary["is_deleted"] as? Bool
        isEdited = dictionary["is_edited"] as? Bool
        isStreamAvailable = dictionary["is_stream_available"] as? Bool
        message = dictionary["message"] as? String
        messageType = dictionary["message_type"] as? String
        meta = (dictionary["meta"] as? [String: Any]).flatMap { Metadata(dictionary: $0) }
        receiver = dictionary["receiver"] as? String
        seenAt = dictionary["seen_at"] as? String
        sender = dictionary["sender"] as? String
        sentAt = dictionary["sent_at"] as? String
        status = dictionary["status"] as? String
        streamId = dictionary["streamId"] as? String
        updatedAt = dictionary["updatedAt"] as? String
        post = (dictionary["post"] as? [String: Any]).flatMap { Post(dictionary: $0) }
        reel = (dictionary["reel"] as? [String: Any]).flatMap { ReelResponse(dictionary: $0) }
        story = (dictionary["story"] as? [String: Any]).flatMap { ChatStory(dictionary: $0) }
    }
}

struct MediaUploadPartInfo: Codable {
    let partNumber: Int?
    let url: String?
    let uploadUrl: String?
    let signedUrl: String?
    let headers: MediaUploadPutHeaders?

    enum CodingKeys: String, CodingKey {
        case partNumber, url, uploadUrl, signedUrl, headers
        case signed_url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        partNumber = try c.decodeIfPresent(Int.self, forKey: .partNumber)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        uploadUrl = try c.decodeIfPresent(String.self, forKey: .uploadUrl)
        signedUrl = try c.decodeIfPresent(String.self, forKey: .signedUrl)
            ?? c.decodeIfPresent(String.self, forKey: .signed_url)
        headers = try c.decodeIfPresent(MediaUploadPutHeaders.self, forKey: .headers)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(partNumber, forKey: .partNumber)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(uploadUrl, forKey: .uploadUrl)
        try c.encodeIfPresent(signedUrl, forKey: .signedUrl)
        try c.encodeIfPresent(headers, forKey: .headers)
    }

    var resolvedUrl: String? { url ?? uploadUrl ?? signedUrl }
}

struct StoryLikedBy: Codable {
    let id, userID, storyID: String?
    let user: UserData?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case storyID = "story_id"
        case user
    }
}

struct StorySeenUser: Codable {
    let count: Int?
    var users: [StoryUser]?
}

struct StoryMeta: Codable {
    let audioVolume: Int?
    //    let emojis: [JSONAny]
    let fileType, filterType: String?
    //    let gifs: [JSONAny]
    let hasAudio: Bool?
    //    let texts: [JSONAny]
    let videoDuration: Int?
    let videoSize: StoryVideoSize?

    enum CodingKeys: String, CodingKey {
        case audioVolume = "audio_volume"
        //        case emojis
        case fileType = "file_type"
        case filterType = "filter_type"
        //        case gifs
        case hasAudio = "has_audio"
        //        case texts
        case videoDuration = "video_duration"
        case videoSize = "video_size"
    }
}

struct Stream: Codable {
    let id: String?
    let streamFilePath: String?
    let thumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id, thumbnail
        case streamFilePath = "stream_file_path"
    }

    init(dictionary: [String: Any]) {
        id = dictionary["id"] as? String
        streamFilePath = dictionary["stream_file_path"] as? String
        thumbnail = dictionary["thumbnail"] as? String
    }
}

struct PostProfilePictureDetails: Codable {
    let filePath: String?
    init(dictionary: [String: Any]) {
        filePath = dictionary["filePath"] as? String
    }
}

struct MediaUploadPutHeaders: Codable {
    let contentType: String?                // NEW API — "Content-Type"
    
    enum CodingKeys: String, CodingKey {
        case contentType = "Content-Type"
    }
}

struct ChatStoryVideoSize: Codable {
    var mHeight: String?
    var mWidth: String?

    init(dictionary: [String: Any]) {
        mHeight = dictionary["mHeight"] as? String
        mWidth = dictionary["mWidth"] as? String
    }
}

struct MessageInfoMetadata : Codable {
    let clientTempId : String?
    let mentions : [String]?

    enum CodingKeys: String, CodingKey {
        case clientTempId, mentions
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clientTempId = try values.decodeIfPresent(String.self, forKey: .clientTempId)
        mentions = try values.decodeIfPresent([String].self, forKey: .mentions)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(clientTempId, forKey: .clientTempId)
        try values.encodeIfPresent(mentions, forKey: .mentions)
    }
}

struct MessageInfoRecipient : Codable {
    let id: String?
    let username: String?
    let fullName: String?
    let profilePicture: String?
    let isVerified: Bool?
    let status: String?
    let deliveredAt: String?
    let readAt: String?

    enum CodingKeys: String, CodingKey {
        case id, username, userName, fullName, profilePicture, profileImage
        case isVerified, status, deliveredAt, readAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        if let u = try c.decodeIfPresent(String.self, forKey: .username) {
            username = u
        } else {
            username = try c.decodeIfPresent(String.self, forKey: .userName)
        }
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        if let img = try c.decodeIfPresent(String.self, forKey: .profilePicture) {
            profilePicture = img
        } else {
            profilePicture = try c.decodeIfPresent(String.self, forKey: .profileImage)
        }
        isVerified = try c.decodeIfPresent(Bool.self, forKey: .isVerified)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        deliveredAt = try c.decodeIfPresent(String.self, forKey: .deliveredAt)
        readAt = try c.decodeIfPresent(String.self, forKey: .readAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(profilePicture, forKey: .profilePicture)
        try c.encodeIfPresent(isVerified, forKey: .isVerified)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(deliveredAt, forKey: .deliveredAt)
        try c.encodeIfPresent(readAt, forKey: .readAt)
    }
}

struct UserData: Codable {
    let userID: String?
    let userName, fullName: String?
    let profilePicture: String?
    let isPrivate, verified: Bool?
    let userUserID: String?
    let profilePictureDetails: ProfilePictureDetails?

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case userName, fullName, profilePicture, isPrivate, verified
        case userUserID = "user_id"
        case profilePictureDetails
    }
}

struct StoryUser: Codable {
    let storyID, userID: String?
    let storyLike:Bool?
    let seenUser: StoryResponseModel?

    enum CodingKeys: String, CodingKey {
        case storyID = "story_id"
        case userID = "user_id"
        case seenUser,storyLike
    }
}

struct StoryVideoSize: Codable {
    let mHeight, mWidth: String?
}


// MARK: - Profile

struct ChatUserProfileData: DataClass, Codable, Equatable {
    let userId: String?
    let postCount: Int?
    let posts: Int?
    let reels: Int?
    let content: ContentPost?
    let followerCount: Int?
    let followingCount: Int?
    let profileImage: String?
    let bio: String?
    let profession: String?
    let fullName: String?
    let userName: String?
    let link: String?
    var isFollowing: Bool?
    var isOwnerFollowingVisitor: Bool?
    var isRequestedByMe: Bool?
    var isRequestedToMe: Bool?
    var isPrivate: Bool?
    var isBlock: Bool?
    var isBlockedByOwner: Bool?
    var followId: String?
    var verified: Bool?
    var gender: String?
    var nationality: String?
    var dob: String?
    var age: Int?
    var livingAddress:String?
    var shareLink: String? = nil
    
    
    enum CodingKeys: String, CodingKey {
        case userId
        case postCount
        case posts
        case reels
        case content
        case followerCount
        case followingCount
        case bio
        case profession
        case fullName
        case userName = "username"
        case link
        case isFollowing
        case isOwnerFollowingVisitor
        case isPrivate
        case profileImage
        case isRequestedToMe
        case isRequestedByMe
        case isBlock
        case isBlockedByOwner
        case followId
        case gender
        case nationality
        case verified
        case dob
        case age
        case livingAddress
        case shareLink
    }
}

struct ContentPost : Codable, Equatable {
    var post : Int?
    var reel : Int?

    enum CodingKeys: String, CodingKey {
        case post = "post"
        case reel = "reel"
    }

    init(post: Int? = nil, reel: Int? = nil) {
        self.post = post
        self.reel = reel
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        post = try values.decodeIfPresent(Int.self, forKey: .post)
        reel = try values.decodeIfPresent(Int.self, forKey: .reel)
    }
    
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(post, forKey: .post)
        try values.encodeIfPresent(reel, forKey: .reel)
    }
}

extension ChatUserProfileData {
    static func from(otherUser: OtherUserResponse) -> ChatUserProfileData {
        let postCount = otherUser.posts ?? otherUser.content?.post
        let reelCount = otherUser.reels ?? otherUser.content?.reel
        let status = otherUser.relationshipStatus?.lowercased()
        let requestedByMe = otherUser.isRequestedByMe == true || status == "requested"
        let following = otherUser.isFollowing == true && !requestedByMe
        return ChatUserProfileData(
            userId: otherUser.userId,
            postCount: postCount,
            posts: postCount,
            reels: reelCount,
            content: ContentPost(post: postCount, reel: reelCount),
            followerCount: otherUser.follow?.followers,
            followingCount: otherUser.follow?.following,
            profileImage: otherUser.profilePictureDetails?.filePath ?? otherUser.profilePicture,
            bio: otherUser.bio,
            profession: otherUser.profession,
            fullName: otherUser.fullName ?? otherUser.displayName,
            userName: otherUser.userName,
            link: otherUser.link,
            isFollowing: following,
            isOwnerFollowingVisitor: otherUser.isOwnerFollowingVisitor,
            isRequestedByMe: requestedByMe,
            isRequestedToMe: otherUser.isRequestedToMe,
            isPrivate: otherUser.isPrivate,
            isBlock: otherUser.isBlocked,
            isBlockedByOwner: otherUser.isBlockedByOwner,
            followId: nil,
            verified: otherUser.verified,
            gender: otherUser.gender,
            nationality: otherUser.nationality,
            dob: otherUser.dob,
            age: nil,
            livingAddress: otherUser.statusText,
            shareLink: otherUser.shareLink
        )
    }
}


struct UserListResponse : DataClass, Codable {
    var count: Int?
    var rows: [UserRes]?
    var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case count, total, rows, nextCursor, cursor
        case users, items, data // NEW API alternate list keys
    }

    init(count: Int? = nil, rows: [UserRes]? = nil, nextCursor: String? = nil) {
        self.count = count
        self.rows = rows
        self.nextCursor = nextCursor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
            ?? c.decodeIfPresent(String.self, forKey: .cursor)

        if let r = try c.decodeIfPresent([UserRes].self, forKey: .rows) {
            rows = r
        } else if let r = try c.decodeIfPresent([UserRes].self, forKey: .users) {
            rows = r
        } else if let r = try c.decodeIfPresent([UserRes].self, forKey: .items) {
            rows = r
        } else if let r = try c.decodeIfPresent([UserRes].self, forKey: .data) {
            rows = r
        } else {
            rows = nil
        }
        // NEW API uses `total`; OLD used `count`
        count = try c.decodeIfPresent(Int.self, forKey: .count)
            ?? c.decodeIfPresent(Int.self, forKey: .total)
            ?? rows?.count
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(count, forKey: .count)
        try c.encodeIfPresent(rows, forKey: .rows)
        try c.encodeIfPresent(nextCursor, forKey: .nextCursor)
    }
}
