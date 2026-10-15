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
    /// Gallery photos, primary first and then in `displayOrder`.
    let photos: [OtherUserPhoto]?
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
             moreAboutMe, photos, myAction, matchStatus, hasLiked, isMatched, canConnect
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        // Some responses keep the user's details in a nested `profile` object next to `moments`,
        // `quickMoments` and `voiceIntro`; a top-level value wins when both are present.
        let profile = try? c.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("profile"))
        func value<T>(_ read: (KeyedDecodingContainer<QMKey>) -> T?) -> T? {
            read(c) ?? profile.flatMap(read)
        }
        let location = value { try? $0.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("location")) }

        userId = value { $0.string("userId", "id") }
        username = value { $0.string("username", "userName") }
        name = value { $0.string("name", "displayName", "nickName") }
        fullName = value { $0.string("fullName") }
        age = value { $0.int("age") }
        gender = value { $0.string("gender") }
        city = value { $0.string("city") } ?? location?.string("city", "label", "name")
        distanceKm = value { $0.first(Double.self, "distanceKm") }
        distance = value { $0.string("distance") }
        isVerified = value { $0.bool("isVerified", "isFaceVerified") }
        isOnline = value { $0.bool("isOnline") }
        lastSeen = value { $0.string("lastSeen") }
        profilePhoto = value { $0.string("profilePhoto", "profilePicture") ?? $0.mediaURL("profilePhoto") }
        coverPhoto = value { $0.string("coverPhotoUrl", "coverPhoto", "coverPicture", "banner") ?? $0.mediaURL("coverPhoto") }
        bio = value { $0.string("bio", "about") }
        vibeScore = value { $0.int("vibeScore") }
        voiceIntro = value { $0.first(OtherUserVoiceIntro.self, "voiceIntro") }
        moments = value { $0.first([OtherUserMoment].self, "moments") }
        interests = value { $0.first([DiscoveryTag].self, "interests") }
        photos = value { $0.first([OtherUserPhoto].self, "photos", "images", "gallery") }.map(OtherUserPhoto.ordered)
        myAction = value { $0.string("myAction") }
        matchStatus = value { $0.string("matchStatus") }
        hasLiked = value { $0.bool("hasLiked") }
        isMatched = value { $0.bool("isMatched", "isMutualMatch") }
        canConnect = value { $0.bool("canConnect") }
        moreAboutMe = value { OtherUserAboutItem.decodeList(from: $0, key: "moreAboutMe") }

        // `vibeExplanation` is either a sentence or `{ "text": "...", "sharedInterests": [...] }`.
        let explanation = try? c.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("vibeExplanation"))
        vibeExplanation = c.string("vibeExplanation") ?? explanation?.string("text", "explanation")
        sharedInterests = c.first([DiscoveryTag].self, "sharedInterests")
            ?? explanation?.first([DiscoveryTag].self, "sharedInterests")
    }
}

/// A gallery photo as a URL string or an object such as
/// `{ "id": "...", "url": "...", "thumbnailUrl": "...", "isPrimary": true, "displayOrder": 0 }`.
struct OtherUserPhoto: Codable {
    let id: String?
    /// Full URL or relative S3 key.
    let url: String
    let thumbnailUrl: String?
    let isPrimary: Bool
    let displayOrder: Int?

    private enum CodingKeys: String, CodingKey {
        case id, url, thumbnailUrl, isPrimary, displayOrder
    }

    init(from decoder: Decoder) throws {
        if let url = try? decoder.singleValueContainer().decode(String.self) {
            id = nil
            self.url = url
            thumbnailUrl = nil
            isPrimary = false
            displayOrder = nil
            return
        }
        let c = try decoder.container(keyedBy: QMKey.self)
        let thumbnail = c.string("thumbnailUrl", "thumbnail")
        guard let url = c.string("url", "imageUrl", "photoUrl", "image", "filename") ?? thumbnail else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Photo without url"))
        }
        id = c.string("id", "photoId")
        self.url = url
        thumbnailUrl = thumbnail
        isPrimary = c.bool("isPrimary", "is_primary") ?? false
        displayOrder = c.int("displayOrder", "order", "position")
    }

    /// Primary photo first, then by `displayOrder`; photos without an order keep their API order at the end.
    static func ordered(_ photos: [OtherUserPhoto]) -> [OtherUserPhoto] {
        photos.enumerated().sorted { lhs, rhs in
            if lhs.element.isPrimary != rhs.element.isPrimary { return lhs.element.isPrimary }
            let lhsOrder = lhs.element.displayOrder ?? Int.max
            let rhsOrder = rhs.element.displayOrder ?? Int.max
            return lhsOrder != rhsOrder ? lhsOrder < rhsOrder : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

private extension KeyedDecodingContainer where Key == QMKey {
    /// The `url` of a media object such as `"profilePhoto": { "url": "...", "thumbnailUrl": "..." }`.
    func mediaURL(_ key: String) -> String? {
        guard let media = try? nestedContainer(keyedBy: QMKey.self, forKey: QMKey(key)) else { return nil }
        return media.string("url", "thumbnailUrl")
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
        url = container.string("url", "audioUrl", "playbackUrl")
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
        mediaUrl = c.string("mediaUrl", "imageUrl", "firstImageUrl", "photo", "url")
        thumbnailUrl = c.string("thumbnailUrl")
        media = c.first([MomentMedia].self, "media")
        mediaType = c.string("mediaType", "type")
        mediaCount = c.int("mediaCount")
        hasMultipleMedia = c.bool("hasMultipleMedia")
        caption = c.string("caption", "text")
        createdAt = c.string("createdAt", "publishedAt")
        likesCount = c.int("likesCount", "likeCount")
        commentsCount = c.int("commentsCount", "commentCount")
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

/// POST `users/:userId/compliment`.
struct SentCompliment {
    let complimentId: String?
    /// The response's top-level `message`, e.g. "Compliment sent successfully".
    let message: String?
    let isMatched: Bool
    let matchId: String?

    init(json: [String: Any]) {
        let data = json["data"] as? [String: Any] ?? [:]
        complimentId = data["complimentId"] as? String
        message = json["message"] as? String
        isMatched = data["isMatched"] as? Bool ?? false
        matchId = data["matchId"] as? String
    }
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
