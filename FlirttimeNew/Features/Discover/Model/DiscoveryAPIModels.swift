//
//  DiscoveryAPIModels.swift
//  FlirttimeNew
//
//  Models for GET `discovery/people`, POST `discovery/actions` and GET `users/:userId/profile`.
//

import Foundation

// MARK: - Feed

/// The `data` of GET `discovery/people`.
struct DiscoveryPeopleResponse: Codable {
    let users: [DiscoveryPerson]?
    let pagination: DiscoveryPagination?
}

struct DiscoveryPagination: Codable {
    let page: Int?
    let limit: Int?
    let total: Int?
    let hasMore: Bool?
}

struct DiscoveryPerson: Codable {
    let userId: String?
    let username: String?
    let name: String?
    let age: Int?
    let city: String?
    let distanceKm: Double?
    let isVerified: Bool?
    /// Relative S3 key, e.g. "verifications/<userId>/<file>.jpg"; `nil` when the user has no photo.
    let profilePhoto: String?
    let interestTags: [DiscoveryTag]?
    let sharedInterests: [DiscoveryTag]?
    let vibeScore: Int?
}

/// An interest as a plain string or an object such as `{ "id": "...", "name": "Cooking", "emoji": "🍳" }`
/// (`id` may be a number and the emoji may come as `icon`).
struct DiscoveryTag: Codable {
    let id: String?
    let name: String
    let emoji: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, emoji
    }

    init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            id = nil
            self.name = name
            emoji = nil
            return
        }
        let container = try decoder.container(keyedBy: QMKey.self)
        id = container.string("id")
        name = container.string("name", "title") ?? ""
        emoji = container.string("emoji", "icon")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(emoji, forKey: .emoji)
    }
}

// MARK: - Discovery filters (GET filters/options, GET / PUT filters, POST filters/reset)

/// `{ value, label }`; the live server sends `id` instead of `value`.
struct DiscoveryFilterOption: Codable {
    let value: String
    let label: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        value = c.string("value", "id") ?? ""
        label = c.string("label")
    }
}

struct DiscoveryFilterInterest: Codable {
    /// UUID sent back in `interestIds`.
    let id: String
    let name: String
    let icon: String?
    let displayOrder: Int?
}

struct DiscoveryFilterOptions: Codable {
    struct AgeBounds: Codable {
        let minAllowed: Int?
        let maxAllowed: Int?
        let defaultMin: Int?
        let defaultMax: Int?
    }

    struct DistanceBounds: Codable {
        let minKm: Int?
        let maxKm: Int?
        let defaultKm: Int?
    }

    let genders: [DiscoveryFilterOption]?
    let age: AgeBounds?
    let distance: DistanceBounds?
    let lookingFor: [DiscoveryFilterOption]?
    let interests: [DiscoveryFilterInterest]?

    var sortedInterests: [DiscoveryFilterInterest] {
        (interests ?? []).sorted { ($0.displayOrder ?? .max, $0.name) < ($1.displayOrder ?? .max, $1.name) }
    }
}

/// Saved filters. `maxDistanceKm == nil` means Anywhere.
struct DiscoveryFilterPreferences: Codable {
    var genders: [String]
    var ageMin: Int
    var ageMax: Int
    var maxDistanceKm: Int?
    var lookingFor: [String]
    var interestIds: [String]
    var verifiedOnly: Bool
    var onlineOnly: Bool

    init(genders: [String], ageMin: Int, ageMax: Int, maxDistanceKm: Int?, lookingFor: [String],
         interestIds: [String], verifiedOnly: Bool, onlineOnly: Bool) {
        self.genders = genders
        self.ageMin = ageMin
        self.ageMax = ageMax
        self.maxDistanceKm = maxDistanceKm
        self.lookingFor = lookingFor
        self.interestIds = interestIds
        self.verifiedOnly = verifiedOnly
        self.onlineOnly = onlineOnly
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        genders = c.first([String].self, "genders") ?? []
        ageMin = c.int("ageMin") ?? FilterModel.ageBounds.lowerBound
        ageMax = c.int("ageMax") ?? FilterModel.ageBounds.upperBound
        let isAnywhere = c.bool("isAnywhere") ?? false
        maxDistanceKm = isAnywhere ? nil : c.int("maxDistanceKm")
        lookingFor = c.first([String].self, "lookingFor") ?? []
        interestIds = c.first([String].self, "interestIds") ?? []
        verifiedOnly = c.bool("verifiedOnly") ?? false
        onlineOnly = c.bool("onlineOnly") ?? false
    }

    /// Body for PUT `discovery/filters` and the `filters` of POST `discovery/search`.
    var body: [String: Any] {
        ["genders": genders,
         "ageMin": ageMin,
         "ageMax": ageMax,
         "maxDistanceKm": maxDistanceKm.map { $0 as Any } ?? NSNull(),
         "lookingFor": lookingFor,
         "interestIds": interestIds,
         "verifiedOnly": verifiedOnly,
         "onlineOnly": onlineOnly]
    }
}

// MARK: - Discovery search (POST discovery/search)

struct DiscoverySearchPhoto: Codable {
    let url: String?
    let thumbnailUrl: String?
    let isPrimary: Bool?
    let displayOrder: Int?
}

struct DiscoverySearchProfile: Codable {
    let id: String?
    let userId: String?
    let name: String?
    let username: String?
    let age: Int?
    /// "female" | "male" | ...
    let gender: String?
    let bio: String?
    let isFaceVerified: Bool?
    let isVerified: Bool?
    let isOnline: Bool?
    let distanceKm: Double?
    let city: String?
    /// "long_term" | "casual" | "not_sure"
    let lookingFor: String?
    let primaryPhotoUrl: String?
    let photos: [DiscoverySearchPhoto]?
    let interests: [DiscoveryTag]?
    let sharedInterests: [DiscoveryTag]?
    let vibeScore: Int?
}

struct DiscoverySearchData: Codable {
    struct Pagination: Codable {
        let page: Int?
        let limit: Int?
        let totalCount: Int?
        let totalPages: Int?
        let hasMore: Bool?
    }

    let profiles: [DiscoverySearchProfile]?
    let pagination: Pagination?
    let totalCount: Int?
}

// MARK: - Connection request

/// The `data` of POST `connections/request`.
struct ConnectionRequestResult: Codable {
    let requestId: String?
    let targetUserId: String?
    /// "pending" until the other person accepts.
    let status: String?
    let isMatched: Bool?
    let matchId: String?
    let reason: String?
    let message: String?
    let momentId: String?

    var didMatch: Bool {
        isMatched == true || ["accepted", "matched", "connected"].contains(status?.lowercased() ?? "")
    }
}

// MARK: - Interests catalog

/// The `data` of GET `interests`.
struct InterestsCatalogData: Codable {
    let interests: [InterestCatalogItem]
}

struct InterestCatalogItem: Codable, Equatable {
    /// Backend UUID, sent as `interestId` to `discovery/people`.
    let id: String
    let name: String
    let icon: String?
    let category: String?
    let isActive: Bool?

    var vibeInterest: MomentsInterest? {
        MomentsInterestCatalog.interest(named: name, emoji: icon)
    }
}

// MARK: - Actions

/// The `data` of POST `discovery/actions`.
struct DiscoveryActionResult: Codable {
    /// "like" | "nope" | "super_like"
    let action: String?
    let targetUserId: String?
    let isMatched: Bool?
    let matchId: String?
}

// MARK: - Profile detail

/// The `data` of GET `users/:userId/profile`. The payload differs between users (e.g. `moments`,
/// `voiceIntro` or `moreAboutMe` can be missing or null), so every field is optional and an
/// unexpected shape is skipped rather than failing the whole profile.
struct OtherUserProfile: Codable {
    let userId: String?
    let username: String?
    /// Nickname; `fullName` is the registered full name.
    let name: String?
    let fullName: String?
    let age: Int?
    let gender: String?
    let city: String?
    let distanceKm: Double?
    /// Ready-made label such as "5.2 km away".
    let distance: String?
    let isVerified: Bool?
    let isOnline: Bool?
    /// ISO 8601
    let lastSeen: String?
    /// Full URL or relative S3 key.
    let profilePhoto: String?
    let coverPhoto: String?
    let bio: String?
    let vibeScore: Int?
    let vibeExplanation: String?
    let voiceIntro: OtherUserVoiceIntro?
    let moments: [OtherUserMoment]?
    let interests: [DiscoveryTag]?
    let sharedInterests: [DiscoveryTag]?
    let moreAboutMe: [OtherUserAboutItem]?
    /// "like" | "nope" | "super_like" once the signed-in user has acted on this profile.
    let myAction: String?
    /// "none" | "pending" | "matched" ...
    let matchStatus: String?
    let hasLiked: Bool?
    let isMatched: Bool?
    let canConnect: Bool?

    private enum CodingKeys: String, CodingKey {
        case userId, username, name, fullName, age, gender, city, distanceKm, distance, isVerified, isOnline, lastSeen,
             profilePhoto, coverPhoto, bio, vibeScore, vibeExplanation, voiceIntro, moments, interests, sharedInterests,
             moreAboutMe, myAction, matchStatus, hasLiked, isMatched, canConnect
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        userId = c.string("userId", "id")
        username = c.string("username", "userName")
        name = c.string("name", "nickName")
        fullName = c.string("fullName")
        age = c.int("age")
        gender = c.string("gender")
        city = c.string("city")
        distanceKm = c.first(Double.self, "distanceKm")
        distance = c.string("distance")
        isVerified = c.bool("isVerified", "isFaceVerified")
        isOnline = c.bool("isOnline")
        lastSeen = c.string("lastSeen")
        profilePhoto = c.string("profilePhoto", "profilePicture")
        coverPhoto = c.string("coverPhotoUrl", "coverPhoto", "banner")
        bio = c.string("bio", "about")
        vibeScore = c.int("vibeScore")
        voiceIntro = c.first(OtherUserVoiceIntro.self, "voiceIntro")
        moments = c.first([OtherUserMoment].self, "moments")
        interests = c.first([DiscoveryTag].self, "interests")
        myAction = c.string("myAction")
        matchStatus = c.string("matchStatus")
        hasLiked = c.bool("hasLiked")
        isMatched = c.bool("isMatched", "isMutualMatch")
        canConnect = c.bool("canConnect")
        moreAboutMe = OtherUserAboutItem.decodeList(from: c, key: "moreAboutMe")

        // `vibeExplanation` is either a sentence or `{ "text": "...", "sharedInterests": [...] }`.
        let explanation = try? c.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("vibeExplanation"))
        vibeExplanation = c.string("vibeExplanation") ?? explanation?.string("text", "explanation")
        sharedInterests = c.first([DiscoveryTag].self, "sharedInterests")
            ?? explanation?.first([DiscoveryTag].self, "sharedInterests")
    }
}

/// One "More about me" answer, e.g. `drinking` → "Socially".
struct OtherUserAboutItem: Codable {
    /// Attribute alias such as `height` or `smoking`.
    let key: String
    let value: String

    /// Accepts `{ "height": "5'7\"", ... }` or `[{ "key": "height", "value": "5'7\"" }, ...]`; empty answers are dropped.
    static func decodeList(from container: KeyedDecodingContainer<QMKey>, key: String) -> [OtherUserAboutItem]? {
        if let list = container.first([OtherUserAboutItem].self, key) {
            return list.filter { !$0.value.isEmpty }
        }
        guard let object = try? container.nestedContainer(keyedBy: QMKey.self, forKey: QMKey(key)) else { return nil }
        return object.allKeys.compactMap { field in
            guard let value = object.string(field.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return OtherUserAboutItem(key: field.stringValue, value: value)
        }
    }

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        guard let key = c.string("key", "alias", "title", "label") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "About item without key"))
        }
        self.key = key
        value = c.string("value", "answer", "option")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// `voiceIntro` as an audio URL string or an object such as `{ "url": "...", "durationSeconds": 12 }`.
struct OtherUserVoiceIntro: Codable {
    let url: String?
    /// Seconds
    let duration: Double?
    let transcript: String?

    private enum CodingKeys: String, CodingKey {
        case url, duration, transcript
    }

    init(from decoder: Decoder) throws {
        if let url = try? decoder.singleValueContainer().decode(String.self) {
            self.url = url
            duration = nil
            transcript = nil
            return
        }
        let container = try decoder.container(keyedBy: QMKey.self)
        url = container.string("url", "audioUrl")
        duration = container.first(Double.self, "durationSeconds", "duration")
        transcript = container.string("transcript")
    }

    /// `nil` when there's neither audio nor a transcript to show.
    var momentsIntro: MomentsVoiceIntro? {
        let audioURL = url.flatMap { URL(string: $0.hasPrefix("http") ? $0 : ApiName.imgBaseURL + $0) }
        let text = transcript ?? ""
        guard audioURL != nil || !text.isEmpty else { return nil }
        return MomentsVoiceIntro(transcript: text, duration: duration ?? 0, audioURL: audioURL)
    }
}

struct OtherUserMoment: Codable {
    let id: String?
    let momentId: String?
    /// Full media URL or relative S3 key.
    let mediaUrl: String?
    let thumbnailUrl: String?
    /// Every photo, when the backend sends them.
    let media: [MomentMedia]?
    /// "image" | "video"
    let mediaType: String?
    let mediaCount: Int?
    let hasMultipleMedia: Bool?
    let caption: String?
    let createdAt: String?
    let likesCount: Int?
    let commentsCount: Int?
    let sharesCount: Int?
    let giftsCount: Int?
    let isLiked: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, momentId, mediaUrl, thumbnailUrl, media, mediaType, mediaCount, hasMultipleMedia, caption, createdAt,
             likesCount, commentsCount, sharesCount, giftsCount, isLiked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        id = c.string("id")
        momentId = c.string("momentId")
        mediaUrl = c.string("mediaUrl", "imageUrl", "photo", "url")
        thumbnailUrl = c.string("thumbnailUrl")
        media = c.first([MomentMedia].self, "media")
        mediaType = c.string("mediaType", "type")
        mediaCount = c.int("mediaCount")
        hasMultipleMedia = c.bool("hasMultipleMedia")
        caption = c.string("caption", "text")
        createdAt = c.string("createdAt", "publishedAt")
        likesCount = c.int("likesCount")
        commentsCount = c.int("commentsCount")
        sharesCount = c.int("sharesCount")
        giftsCount = c.int("giftsCount")
        isLiked = c.bool("isLiked", "hasLiked")
    }

    /// The moment as shown in the profile's Moments grid and feed.
    func vibe(author: MomentsAuthor) -> MomentsPost? {
        let photos = (media ?? []).enumerated().compactMap { index, item -> MomentsMedia? in
            guard let url = item.imageUrl ?? item.mediaUrl ?? item.publicUrl ?? item.url ?? item.thumbnailUrl,
                  !url.isEmpty else { return nil }
            return MomentsMedia(id: item.mediaId ?? item.id ?? "\(index)", filePath: url,
                                fileType: item.mediaType ?? "image", thumbnailPath: item.thumbnailUrl)
        }
        let cover = (mediaUrl ?? thumbnailUrl).map {
            [MomentsMedia(id: "0", filePath: $0, fileType: mediaType ?? "image", thumbnailPath: thumbnailUrl)]
        } ?? []
        let allMedia = photos.isEmpty ? cover : photos
        let text = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let id = momentId ?? id ?? allMedia.first?.filePath, !allMedia.isEmpty || !text.isEmpty else { return nil }
        return MomentsPost(id: id,
                           userId: author.userId,
                           caption: caption,
                           media: allMedia,
                           likesCount: likesCount,
                           commentsCount: commentsCount,
                           giftCount: giftsCount,
                           hasLiked: isLiked,
                           createdAt: createdAt,
                           author: author)
    }
}

// MARK: - Safety

/// The `data` of POST `users/:userId/block`.
struct UserBlockResult: Codable {
    let userId: String?
    let isBlocked: Bool?
}

// MARK: - Local ids

extension String {
    /// Same value on every launch (unlike `hashValue`), so a UUID or tag name maps to one local `Int` id.
    var stableID: Int {
        var hash: UInt64 = 5381
        for byte in utf8 {
            hash = (hash &<< 5) &+ hash &+ UInt64(byte)
        }
        return Int(hash & 0x3FFF_FFFF_FFFF_FFFF)
    }
}
