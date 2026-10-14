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

/// An interest as a plain string or an object such as `{ "id": "...", "name": "Cooking", "emoji": "🍳" }`.
struct DiscoveryTag: Codable {
    let id: String?
    let name: String
    let emoji: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, title, emoji
    }

    init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            id = nil
            self.name = name
            emoji = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        name = (try? container.decodeIfPresent(String.self, forKey: .name))
            ?? (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        emoji = try? container.decodeIfPresent(String.self, forKey: .emoji)
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

    var vibeInterest: VibeInterest? {
        VibeInterestCatalog.interest(named: name, emoji: icon)
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

/// The `data` of GET `users/:userId/profile`.
struct OtherUserProfile: Codable {
    let userId: String?
    let name: String?
    let age: Int?
    let city: String?
    let distanceKm: Double?
    let isVerified: Bool?
    /// Relative S3 key, e.g. "photos/<userId>/<file>.jpg".
    let profilePhoto: String?
    let bio: String?
    let vibeScore: Int?
    let vibeExplanation: String?
    let voiceIntro: OtherUserVoiceIntro?
    let moments: [OtherUserMoment]?
    let interests: [DiscoveryTag]?
    let sharedInterests: [DiscoveryTag]?
    /// "like" | "nope" | "super_like" once the signed-in user has acted on this profile.
    let myAction: String?
    let isMatched: Bool?
    let canConnect: Bool?

    private enum CodingKeys: String, CodingKey {
        case userId, name, age, city, distanceKm, isVerified, profilePhoto, bio, vibeScore, vibeExplanation,
             voiceIntro, moments, interests, sharedInterests, myAction, isMatched, canConnect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        distanceKm = try container.decodeIfPresent(Double.self, forKey: .distanceKm)
        isVerified = try container.decodeIfPresent(Bool.self, forKey: .isVerified)
        profilePhoto = try container.decodeIfPresent(String.self, forKey: .profilePhoto)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        vibeScore = try container.decodeIfPresent(Int.self, forKey: .vibeScore)
        moments = try container.decodeIfPresent([OtherUserMoment].self, forKey: .moments)
        interests = try container.decodeIfPresent([DiscoveryTag].self, forKey: .interests)
        sharedInterests = try container.decodeIfPresent([DiscoveryTag].self, forKey: .sharedInterests)
        myAction = try container.decodeIfPresent(String.self, forKey: .myAction)
        isMatched = try container.decodeIfPresent(Bool.self, forKey: .isMatched)
        canConnect = try container.decodeIfPresent(Bool.self, forKey: .canConnect)
        // Only seen as null so far; an unexpected shape is skipped rather than failing the whole profile.
        vibeExplanation = try? container.decodeIfPresent(String.self, forKey: .vibeExplanation)
        voiceIntro = try? container.decodeIfPresent(OtherUserVoiceIntro.self, forKey: .voiceIntro)
    }
}

/// `voiceIntro` as an audio URL string or an object such as `{ "url": "...", "duration": 12 }`.
struct OtherUserVoiceIntro: Codable {
    let url: String?
    /// Seconds
    let duration: Double?
    let transcript: String?

    private enum CodingKeys: String, CodingKey {
        case url, audioUrl, duration, transcript
    }

    init(from decoder: Decoder) throws {
        if let url = try? decoder.singleValueContainer().decode(String.self) {
            self.url = url
            duration = nil
            transcript = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = (try? container.decodeIfPresent(String.self, forKey: .url))
            ?? (try? container.decodeIfPresent(String.self, forKey: .audioUrl))
        duration = try? container.decodeIfPresent(Double.self, forKey: .duration)
        transcript = try? container.decodeIfPresent(String.self, forKey: .transcript)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(transcript, forKey: .transcript)
    }
}

struct OtherUserMoment: Codable {
    let id: String?
    let momentId: String?
    /// Relative S3 key of the full media.
    let mediaUrl: String?
    let thumbnailUrl: String?
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
