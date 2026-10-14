//
//  MomentAPIModels.swift
//  FlirttimeNew
//
//  `api/v1/moments` models, mapped onto the existing `MomentsPost` models so the feed UI stays unchanged.
//

import Foundation

// MARK: - Feed (GET moments?type=feed, GET moments/me)

struct MomentFeedData: Codable {
    let moments: [MomentItem]?
    let page: Int?
    let limit: Int?
    let totalCount: Int?
    let totalPages: Int?
    let type: String?
}

struct MomentItem: Codable {
    let id: String?
    let momentId: String?
    let creatorId: String?
    let caption: String?
    let audience: String?
    /// "active" once published.
    let status: String?
    let location: MomentLocation?
    let locationLabel: String?
    let timeAgo: String?
    let createdAt: String?
    let publishedAt: String?
    let expiresAt: String?
    /// Cover photo; `media` holds every photo when the backend sends it.
    let photo: String?
    /// Full-size image URL built by the backend from the saved key.
    let imageUrl: String?
    let thumbnailUrl: String?
    let media: [MomentMedia]?
    let likesCount: Int?
    let commentsCount: Int?
    let giftsCount: Int?
    let sharesCount: Int?
    let hasReacted: Bool?
    let isLiked: Bool?
    /// Per-reaction counts ("heart", "fire", ...) plus "total".
    let reactionCounts: [String: Int]?
    /// "heart" | "fire" | "clap" | "laugh" | "wow"; `nil` when the viewer hasn't reacted.
    let viewerReaction: String?
    let creator: MomentCreator?
}

/// `location` as a plain string or an object such as `{ "name": "Mumbai" }`.
struct MomentLocation: Codable {
    let name: String?

    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            name = text
            return
        }
        let c = try decoder.container(keyedBy: QMKey.self)
        name = c.string("name", "label", "city")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

struct MomentMedia: Codable {
    let mediaId: String?
    let id: String?
    /// Full-size S3 image.
    let imageUrl: String?
    let mediaUrl: String?
    let url: String?
    let publicUrl: String?
    /// 400x400 Lambda thumbnail.
    let thumbnailUrl: String?
    /// "image"
    let mediaType: String?
    let displayOrder: Int?
    let orderIndex: Int?
}

struct MomentCreator: Codable {
    let id: String?
    let userId: String?
    let name: String?
    let fullName: String?
    let username: String?
    /// Full-size photo; `profilePhoto` is its thumbnail.
    let profilePicture: String?
    let profilePhoto: String?
    let isVerified: Bool?
}

struct MomentFeedPage {
    let vibes: [MomentsPost]
    let hasMore: Bool
    /// Total moments across all pages.
    let total: Int?
}

// MARK: - Mapping

extension MomentsAuthor {
    /// The signed-in user, from the saved `auth/me` response.
    static var currentUser: MomentsAuthor {
        let user = UserDataManager.shared.appUser
        let username = user?.username?.trimmingCharacters(in: .whitespaces) ?? ""
        return MomentsAuthor(userId: user?.id,
                          userName: username.isEmpty ? user?.nickName : username,
                          fullName: user?.fullName ?? "You",
                          profilePicture: user?.profilePicture,
                          verified: user?.isFaceVerified,
                          location: user?.city)
    }
}

extension MomentFeedData {
    /// `fallbackAuthor` is used for moments that come without a creator (e.g. `moments/me`).
    func page(fallbackAuthor: MomentsAuthor? = nil) -> MomentFeedPage {
        let items = moments ?? []
        let hasMore: Bool
        if let page, let totalPages {
            hasMore = page < totalPages
        } else {
            hasMore = items.count >= (limit ?? Int.max)
        }
        return MomentFeedPage(vibes: items.compactMap { $0.vibe(fallbackAuthor: fallbackAuthor) },
                              hasMore: hasMore,
                              total: totalCount)
    }
}

extension MomentItem {
    func vibe(fallbackAuthor: MomentsAuthor? = nil) -> MomentsPost? {
        guard let id = momentId ?? id, !id.isEmpty else { return nil }
        let place = locationLabel ?? location?.name
        let author: MomentsAuthor
        if let creator {
            author = MomentsAuthor(userId: creator.userId ?? creator.id,
                                userName: creator.username ?? creator.name,
                                fullName: creator.fullName ?? creator.name,
                                profilePicture: creator.profilePicture ?? creator.profilePhoto,
                                verified: creator.isVerified,
                                location: place)
        } else {
            let fallback = fallbackAuthor ?? .currentUser
            author = MomentsAuthor(userId: creatorId ?? fallback.userId, userName: fallback.userName, fullName: fallback.fullName,
                                profilePicture: fallback.profilePicture, verified: fallback.verified,
                                location: place ?? fallback.location)
        }

        let ordered = (media ?? []).sorted {
            ($0.orderIndex ?? $0.displayOrder ?? 0) < ($1.orderIndex ?? $1.displayOrder ?? 0)
        }
        var vibeMedia = ordered.enumerated().compactMap { index, item -> MomentsMedia? in
            guard let url = item.imageUrl ?? item.mediaUrl ?? item.publicUrl ?? item.url ?? item.thumbnailUrl,
                  !url.isEmpty else { return nil }
            return MomentsMedia(id: item.mediaId ?? item.id ?? "\(index)", filePath: url, fileType: item.mediaType ?? "image",
                             thumbnailPath: item.thumbnailUrl)
        }
        if vibeMedia.isEmpty, let cover = imageUrl ?? photo ?? thumbnailUrl, !cover.isEmpty {
            vibeMedia = [MomentsMedia(id: "0", filePath: cover, fileType: "image", thumbnailPath: thumbnailUrl)]
        }

        return MomentsPost(id: id,
                    userId: author.userId,
                    caption: caption,
                    media: vibeMedia,
                    likesCount: likesCount,
                    commentsCount: commentsCount,
                    giftCount: giftsCount,
                    hasLiked: isLiked ?? hasReacted ?? (viewerReaction != nil),
                    createdAt: createdAt ?? publishedAt,
                    author: author)
    }
}

// MARK: - Create (POST moments)

/// The created moment, sent either as `data` itself or as `data.moment`.
struct MomentCreateData: Codable {
    let moment: MomentItem?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try container.decodeIfPresent(MomentItem.self, forKey: .moment) {
            moment = nested
        } else {
            moment = try? MomentItem(from: decoder)
        }
    }
}

// MARK: - Comments (GET / POST moments/:id/comments)

/// The user on a moment comment or like.
struct MomentPerson: Codable {
    let id: String?
    let userId: String?
    let name: String?
    let username: String?
    let fullName: String?
    let profilePicture: String?
    let profilePhoto: String?
    let profilePhotoUrl: String?
    let avatar: String?
    let isVerified: Bool?
    let city: String?

    var author: MomentsAuthor {
        let photo = [profilePicture, profilePhoto, profilePhotoUrl, avatar]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return MomentsAuthor(userId: id ?? userId, userName: username ?? name, fullName: fullName ?? name,
                          profilePicture: photo, verified: isVerified, location: city)
    }
}

struct MomentCommentsData: Codable {
    let totalComments: Int?
    let page: Int?
    let totalPages: Int?
    let comments: [MomentComment]?
}

struct MomentComment: Codable {
    let id: String?
    let commentId: String?
    let comment: String?
    let message: String?
    let createdAt: String?
    let isMyComment: Bool?
    let user: MomentPerson?

    func vibeComment(momentId: String) -> MomentsComment? {
        guard let id = commentId ?? id else { return nil }
        let currentUserId = UserDataManager.shared.appUser?.id
        let authorId = user?.id ?? user?.userId
        let isMine = isMyComment == true || (currentUserId != nil && authorId == currentUserId)
        var author = user?.author ?? (isMine ? .currentUser : nil)
        if isMine, let current = author, current.profilePicture?.isEmpty ?? true {
            author = MomentsAuthor(userId: current.userId, userName: current.userName, fullName: current.fullName,
                                profilePicture: MomentsAuthor.currentUser.profilePicture,
                                verified: current.verified, location: current.location)
        }
        return MomentsComment(id: id, vibeId: momentId, body: comment ?? message, createdAt: createdAt,
                           author: author, isMine: isMine)
    }
}

// MARK: - Likes (GET moments/:id/likes)

struct MomentLikesData: Codable {
    let totalLikes: Int?
    let page: Int?
    let totalPages: Int?
    let likes: [MomentLike]?
}

struct MomentLike: Codable {
    let id: String?
    let reaction: String?
    let createdAt: String?
    let user: MomentPerson?
}

// MARK: - Gifts (GET / POST moments/:id/gifts, GET moments/:id/gifts/received)
// No sample responses yet, so the decoders accept a few key names.

private func giftCoinBalance(in c: KeyedDecodingContainer<QMKey>) -> Int? {
    if let balance = c.int("userBalance", "coinBalance", "balance", "senderBalance", "remainingBalance", "newBalance") {
        return balance
    }
    for key in ["wallet", "sender", "user"] {
        if let nested = try? c.nestedContainer(keyedBy: QMKey.self, forKey: QMKey(key)),
           let balance = nested.int("newBalance", "balance", "coinBalance") {
            return balance
        }
    }
    return nil
}

struct MomentGiftItem: Codable {
    /// Sent as `giftCode`, e.g. "rose".
    let code: String
    let name: String?
    /// Emoji or image URL.
    let icon: String?
    let coins: Int
    let displayOrder: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        displayOrder = c.int("displayOrder", "orderIndex")
        guard let code = c.string("giftCode", "code", "slug", "id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Gift without code"))
        }
        self.code = code
        name = c.string("name", "title", "giftName")
        icon = c.string("icon", "emoji", "iconUrl", "imageUrl")
        coins = c.int("coins", "pricePerUnit", "price", "amount", "coinCost", "cost", "coinsUsed", "totalCoins") ?? 0
    }

    var vibeGift: MomentsGift {
        MomentsGift(id: code.stableID, title: name ?? code.capitalized, icon: icon, amount: coins, code: code)
    }
}

/// The `data` of GET `moments/:id/gifts`.
struct MomentGiftsData: Codable {
    let gifts: [MomentGiftItem]
    let coinBalance: Int?
    let recipientName: String?

    init(from decoder: Decoder) throws {
        if let array = try? [MomentGiftItem](from: decoder) {
            gifts = array
            coinBalance = nil
            recipientName = nil
            return
        }
        let c = try decoder.container(keyedBy: QMKey.self)
        gifts = (c.first([MomentGiftItem].self, "gifts", "catalog", "items", "giftOptions") ?? [])
            .sorted { ($0.displayOrder ?? .max) < ($1.displayOrder ?? .max) }
        coinBalance = giftCoinBalance(in: c)
        let moment = try? c.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("moment"))
        recipientName = c.string("recipientName", "creatorName")
            ?? c.first(QuickMomentUser.self, "recipient", "creator", "author")?.name
            ?? moment?.first(QuickMomentUser.self, "creator", "author", "user")?.name
    }
}

/// The `data` of POST `moments/:id/gifts`.
struct MomentGiftSendData: Codable {
    let coinBalance: Int?
    let giftsCount: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        coinBalance = giftCoinBalance(in: c)
        giftsCount = c.int("totalMomentGifts", "giftsCount", "giftCount", "totalGifts")
    }
}

struct MomentReceivedGift: Codable {
    let id: String
    let createdAt: String?
    let quantity: Int
    let coins: Int?
    let message: String?
    let gift: MomentGiftItem?
    let sender: MomentsAuthor?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        id = c.string("id", "transactionId", "giftTransactionId") ?? UUID().uuidString
        createdAt = c.string("createdAt", "sentAt")
        let nestedGift = try? c.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("gift"))
        quantity = c.int("quantity") ?? nestedGift?.int("quantity") ?? 1
        coins = c.int("totalCoins", "coinsUsed", "coins", "amount") ?? nestedGift?.int("totalCoins")
        message = c.string("message", "note")
        gift = c.first(MomentGiftItem.self, "gift") ?? (try? MomentGiftItem(from: decoder))
        sender = c.first(QuickMomentUser.self, "sender", "user", "from", "fromUser")?.author
    }

    var vibeReceivedGift: MomentsReceivedGift {
        let base = gift?.vibeGift
        let name = quantity > 1 ? "\(quantity) × \(base?.title ?? "gift")" : base?.title
        let shown = base.map { MomentsGift(id: $0.id, title: name, icon: $0.icon, amount: $0.amount, code: $0.code) }
        return MomentsReceivedGift(id: id, giftId: base?.id, coinsUsed: coins ?? (base?.amount ?? 0) * quantity,
                                createdAt: createdAt, gift: shown, sender: sender, message: message)
    }
}

/// The `data` of GET `moments/:id/gifts/received`.
struct MomentReceivedGiftsPage: Codable {
    let gifts: [MomentReceivedGift]
    let total: Int?
    let totalCoins: Int?
    let page: Int?
    let totalPages: Int?

    init(from decoder: Decoder) throws {
        if let array = try? [MomentReceivedGift](from: decoder) {
            gifts = array
            total = nil
            totalCoins = nil
            page = nil
            totalPages = nil
            return
        }
        let c = try decoder.container(keyedBy: QMKey.self)
        gifts = c.first([MomentReceivedGift].self, "gifts", "items", "received", "receivedGifts", "rows") ?? []
        let pagination = try? c.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("pagination"))
        total = c.int("totalGiftsCount", "totalGifts", "total", "count") ?? pagination?.int("total", "totalItems")
        totalCoins = c.int("totalCoins", "coinsReceived", "totalCoinsReceived")
        page = c.int("page") ?? pagination?.int("page", "currentPage")
        totalPages = c.int("totalPages") ?? pagination?.int("totalPages", "pages")
    }
}
