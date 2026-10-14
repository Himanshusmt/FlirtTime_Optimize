//
//  InteractionAPIModels.swift
//  FlirttimeNew
//
//  Models for GET `interactions?type=`, GET `interactions/counts` and POST `interactions/:id/read`.
//  Decoders accept several key names because the responses aren't documented yet.
//

import Foundation

// MARK: - List

/// The `data` of GET `interactions?type=likes|you_liked|matches|compliments`.
struct InteractionPage: Codable {
    let items: [InteractionCard]
    let nextCursor: String?
    let hasMore: Bool

    init(from decoder: Decoder) throws {
        if let array = try? [InteractionCard](from: decoder) {
            items = array
            nextCursor = nil
            hasMore = false
            return
        }
        let c = try decoder.container(keyedBy: QMKey.self)
        items = c.first([InteractionCard].self, "items", "interactions", "users", "results",
                        "likes", "matches", "compliments", "data") ?? []
        let pagination = c.first(InteractionPagination.self, "pagination", "meta", "pageInfo")
        nextCursor = c.string("nextCursor", "cursor", "next_cursor") ?? pagination?.nextCursor
        hasMore = c.bool("hasMore", "has_more") ?? pagination?.hasMore ?? (nextCursor != nil)
    }
}

private struct InteractionPagination: Codable {
    let nextCursor: String?
    let hasMore: Bool?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        nextCursor = c.string("nextCursor", "cursor", "next_cursor")
        hasMore = c.bool("hasMore", "has_more")
    }
}

// MARK: - Card

/// One person on an Explore tab, plus how they interacted with the signed-in user.
struct InteractionCard: Codable {
    let id: String?
    let userId: String?
    let name: String?
    let age: Int?
    let city: String?
    let distanceKm: Double?
    let photo: String?
    let isVerified: Bool?
    let isOnline: Bool?
    let isMatched: Bool?
    let isSuperLike: Bool?
    /// Compliment badge, e.g. "Love their vibe".
    let category: String?
    let message: String?
    let momentPreview: String?
    var isRead: Bool?
    let createdAt: String?

    /// Items look like `{ "interactionId", "user": { ... }, "interaction": { "action", "isMatched", "createdAt", ... } }`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        let person = c.first(InteractionPerson.self, "user", "profile", "counterpart", "sender",
                             "fromUser", "toUser", "targetUser", "otherUser")
        let flat = try? InteractionPerson(from: decoder)
        let detail = c.first(InteractionDetail.self, "interaction")
        let root = try? InteractionDetail(from: decoder)

        id = c.string("interactionId", "id", "requestId", "matchId")
        userId = person?.userId ?? c.string("userId", "senderId", "targetUserId") ?? flat?.userId
        name = person?.name ?? flat?.name
        age = person?.age ?? flat?.age
        city = person?.city ?? flat?.city
        distanceKm = person?.distanceKm ?? flat?.distanceKm
        photo = person?.photo ?? flat?.photo
        isVerified = person?.isVerified ?? flat?.isVerified
        isOnline = person?.isOnline ?? flat?.isOnline
        isMatched = detail?.isMatched ?? root?.isMatched
        isSuperLike = (detail?.action ?? root?.action) == "super_like"
        category = detail?.category ?? root?.category
        message = detail?.message ?? root?.message
        momentPreview = detail?.momentPreview ?? root?.momentPreview
        isRead = detail?.isRead ?? root?.isRead
        createdAt = detail?.createdAt ?? root?.createdAt
    }
}

/// The `interaction` object: what happened, when, and (for compliments) the message.
private struct InteractionDetail: Codable {
    /// "like" | "super_like"
    let action: String?
    let isMatched: Bool?
    let isRead: Bool?
    let category: String?
    let message: String?
    let momentPreview: String?
    let createdAt: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        action = c.string("action")?.lowercased()
        isMatched = c.bool("isMatched", "matched")
        isRead = c.bool("isRead", "read")
        category = c.string("categoryLabel", "category", "badge", "reasonLabel", "reason")
        message = c.string("message", "content", "text", "note")
        momentPreview = c.first(InteractionMomentPreview.self, "momentPreview", "moment")?.thumbnail
            ?? c.string("momentThumbnail", "momentImage")
        createdAt = c.string("createdAt", "matchedAt", "likedAt")
    }
}

/// The other person's card fields, nested or flat.
private struct InteractionPerson: Codable {
    let userId: String?
    let name: String?
    let age: Int?
    let city: String?
    let distanceKm: Double?
    let photo: String?
    let isVerified: Bool?
    let isOnline: Bool?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        userId = c.string("id", "userId")
        name = c.string("username", "name", "fullName")
        age = c.int("age")
        city = c.string("locationLabel", "city", "location")
        distanceKm = c.first(Double.self, "distanceKm")
        photo = c.string("profilePhotoUrl", "profilePicture", "profilePhoto")
        isVerified = c.bool("isVerified", "isFaceVerified", "verified")
        isOnline = c.bool("isOnline", "online")
    }
}

private struct InteractionMomentPreview: Codable {
    let thumbnail: String?

    init(from decoder: Decoder) throws {
        if let url = try? decoder.singleValueContainer().decode(String.self) {
            thumbnail = url
            return
        }
        let c = try decoder.container(keyedBy: QMKey.self)
        thumbnail = c.string("thumbnailUrl", "imageUrl", "mediaUrl", "url")
    }
}

// MARK: - Counts

/// The `data` of GET `interactions/counts`.
struct InteractionCounts: Codable {
    let likes: Int
    let youLiked: Int
    let matches: Int
    let compliments: Int
    let total: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        if let nested = c.first(InteractionCounts.self, "counts") {
            self = nested
            return
        }
        likes = c.int("likes") ?? 0
        youLiked = c.int("you_liked", "youLiked") ?? 0
        matches = c.int("matches") ?? 0
        compliments = c.int("compliments") ?? 0
        total = c.int("total") ?? likes + youLiked + matches + compliments
    }
}
