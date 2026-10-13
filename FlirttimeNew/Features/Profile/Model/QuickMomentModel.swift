//
//  QuickMomentModel.swift
//  FlirttimeNew
//
//  Quick Moments: 24-hour story-style photo or text posts that other users react to and reply on.
//  Separate from Moments (the vibe feed). Decoders accept several key names because the
//  `api/v1/quick-moments` responses aren't documented yet.
//

import UIKit

// MARK: - Decoding helpers

struct QMKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer where Key == QMKey {
    /// The first of `keys` that holds a `T`.
    func first<T: Decodable>(_ type: T.Type, _ keys: String...) -> T? {
        for key in keys {
            if let value = try? decodeIfPresent(T.self, forKey: QMKey(key)) { return value }
        }
        return nil
    }

    func string(_ keys: String...) -> String? {
        for key in keys {
            if let value = try? decodeIfPresent(String.self, forKey: QMKey(key)), !value.isEmpty { return value }
            if let value = try? decodeIfPresent(Int.self, forKey: QMKey(key)) { return String(value) }
        }
        return nil
    }

    func int(_ keys: String...) -> Int? {
        for key in keys {
            if let value = try? decodeIfPresent(Int.self, forKey: QMKey(key)) { return value }
            if let value = try? decodeIfPresent(String.self, forKey: QMKey(key)), let int = Int(value) { return int }
        }
        return nil
    }

    func bool(_ keys: String...) -> Bool? {
        for key in keys {
            if let value = try? decodeIfPresent(Bool.self, forKey: QMKey(key)) { return value }
        }
        return nil
    }
}

/// A list sent either as `data` itself or nested under one of a few keys.
struct QMList<Item: Codable>: Codable {
    let items: [Item]
    let total: Int?

    init(from decoder: Decoder) throws {
        if let array = try? [Item](from: decoder) {
            items = array
            total = nil
            return
        }
        let container = try decoder.container(keyedBy: QMKey.self)
        items = container.first([Item].self, "quickMoments", "moments", "stories", "items",
                                "reactions", "viewers", "users", "results", "data") ?? []
        total = container.int("totalCount", "total", "count")
    }
}

// MARK: - User

struct QuickMomentUser: Codable {
    let id: String?
    let name: String?
    let fullName: String?
    let photo: String?
    let isVerified: Bool?
    let location: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        id = c.string("userId", "id", "_id")
        name = c.string("name", "nickName", "displayName", "username")
        fullName = c.string("fullName", "name")
        photo = c.string("profilePhoto", "profilePicture", "avatar", "photo", "imageUrl")
        isVerified = c.bool("isVerified", "verified", "isFaceVerified")
        location = c.string("locationLabel", "location", "city")
    }

    var author: VibeAuthor {
        VibeAuthor(userId: id, userName: name, fullName: fullName ?? name, profilePicture: photo,
                   verified: isVerified, location: location)
    }
}

/// Item fields can be flat or under `user` / `author` / `creator` / `viewer` / `reactor`.
private func nestedUser(in c: KeyedDecodingContainer<QMKey>, decoder: Decoder) -> QuickMomentUser? {
    c.first(QuickMomentUser.self, "user", "author", "creator", "viewer", "reactor") ?? (try? QuickMomentUser(from: decoder))
}

// MARK: - Quick Moment (GET quick-moments/me, GET quick-moments/user/:userId, POST quick-moments)

struct QuickMoment: Codable {
    static let maxTextLength = 200

    let id: String
    let userId: String?
    /// "text" | "image"
    let type: String?
    /// Full-size image URL from the backend; `nil` for a text Quick Moment.
    let mediaPath: String?
    let thumbnailPath: String?
    /// The text of a text Quick Moment, or the caption of a photo one.
    let text: String?
    /// Hex like "#2d0b1e" for text Quick Moments.
    let backgroundColor: String?
    let textColor: String?
    let locationLabel: String?
    let createdAt: String?
    let expiresAt: String?
    var reactionsCount: Int
    var repliesCount: Int
    var viewsCount: Int
    /// Most used reaction emojis first.
    var topReactions: [String]
    var viewerReaction: String?
    var hasViewed: Bool
    let author: VibeAuthor?

    var isText: Bool { (mediaPath ?? "").isEmpty }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        guard let id = c.string("id", "momentId", "quickMomentId", "_id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Quick moment without id"))
        }
        self.id = id
        type = c.string("type", "mediaType")
        mediaPath = c.string("imageUrl", "mediaUrl", "publicUrl", "url")
        thumbnailPath = c.string("thumbnailUrl")
        text = c.string("text", "caption")
        backgroundColor = c.string("backgroundColor")
        textColor = c.string("textColor")
        locationLabel = c.string("locationLabel", "location")
        createdAt = c.string("createdAt", "publishedAt")
        expiresAt = c.string("expiresAt")
        reactionsCount = c.int("reactionsCount", "reactionCount", "totalReactions") ?? 0
        repliesCount = c.int("repliesCount", "replyCount", "totalReplies") ?? 0
        viewsCount = c.int("viewsCount", "viewCount", "totalViews") ?? 0
        topReactions = QuickMoment.emojis(in: c)
        viewerReaction = c.string("viewerReaction", "myReaction")
        hasViewed = c.bool("hasViewed", "isViewed", "seen") ?? false
        let user = c.first(QuickMomentUser.self, "user", "author", "creator")
        author = user?.author
        userId = c.string("userId", "creatorId", "authorId") ?? user?.id
    }

    /// `topReactions` / `reactionSummary` as `["😍"]`, `[{emoji, count}]` or `"😍🔥"`.
    private static func emojis(in c: KeyedDecodingContainer<QMKey>) -> [String] {
        if let list = c.first([String].self, "topReactions", "reactionSummary", "topEmojis") { return list }
        if let counts = c.first([QuickMomentEmojiCount].self, "topReactions", "reactionSummary", "reactionBreakdown") {
            return counts.sorted { $0.count > $1.count }.map(\.emoji)
        }
        if let text = c.string("topReactions", "reactionSummary", "reactionBadge") {
            return text.filter { $0.unicodeScalars.contains { $0.properties.isEmojiPresentation } }.map(String.init)
        }
        return []
    }
}

struct QuickMomentEmojiCount: Codable {
    let emoji: String
    let count: Int

    init(emoji: String, count: Int) {
        self.emoji = emoji
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        emoji = c.string("emoji", "reaction") ?? ""
        count = c.int("count", "total") ?? 0
    }
}

/// The created Quick Moment, sent either as `data` itself or as `data.quickMoment`.
struct QuickMomentCreateData: Codable {
    let moment: QuickMoment?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        moment = c.first(QuickMoment.self, "quickMoment", "moment", "story") ?? (try? QuickMoment(from: decoder))
    }
}

// MARK: - Reactions (GET quick-moments/:id/reactions)

struct QuickMomentReaction: Codable {
    let emoji: String
    let createdAt: String?
    let author: VibeAuthor?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        emoji = c.string("emoji", "reaction") ?? ""
        createdAt = c.string("reactedAt", "createdAt", "updatedAt")
        author = nestedUser(in: c, decoder: decoder)?.author
    }
}

struct QuickMomentReactionsPage: Codable {
    let total: Int
    let breakdown: [QuickMomentEmojiCount]
    let reactions: [QuickMomentReaction]

    init(from decoder: Decoder) throws {
        let list = try QMList<QuickMomentReaction>(from: decoder)
        reactions = list.items
        let c = try? decoder.container(keyedBy: QMKey.self)
        if let counts = c?.first([QuickMomentEmojiCount].self, "breakdown", "emojiBreakdown", "reactionBreakdown", "summary") {
            breakdown = counts
        } else if let dict = c?.first([String: Int].self, "breakdown", "emojiBreakdown", "reactionBreakdown", "summary") {
            breakdown = dict.map { QuickMomentEmojiCount(emoji: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
        } else {
            breakdown = []
        }
        total = list.total ?? reactions.count
    }
}

// MARK: - Viewers (GET quick-moments/:id/viewers)

struct QuickMomentViewer: Codable {
    let viewedAt: String?
    let author: VibeAuthor?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        viewedAt = c.string("viewedAt", "createdAt", "seenAt")
        author = nestedUser(in: c, decoder: decoder)?.author
    }
}

// MARK: - Tray (GET quick-moments/tray)

struct QuickMomentTrayItem: Codable {
    let user: QuickMomentUser?
    let hasUnread: Bool
    let activeCount: Int
    let previewUrl: String?
    let previewText: String?
    let latestAt: String?
    let topReactions: [String]
    let reactionsCount: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        user = nestedUser(in: c, decoder: decoder)
        hasUnread = c.bool("hasUnread", "isUnread", "unread") ?? false
        activeCount = c.int("activeCount", "storiesCount", "count", "momentsCount") ?? 0
        previewUrl = c.string("previewUrl", "thumbnailUrl", "imageUrl", "mediaUrl")
        previewText = c.string("previewText", "text")
        latestAt = c.string("latestAt", "lastPostedAt", "createdAt")
        topReactions = c.first([String].self, "topReactions") ?? []
        reactionsCount = c.int("reactionsCount", "reactionCount") ?? 0
    }
}

struct QuickMomentTray: Codable {
    let me: QuickMomentTrayItem?
    let users: [QuickMomentTrayItem]

    init(from decoder: Decoder) throws {
        if let array = try? [QuickMomentTrayItem](from: decoder) {
            me = nil
            users = array
            return
        }
        let c = try decoder.container(keyedBy: QMKey.self)
        me = c.first(QuickMomentTrayItem.self, "me", "own", "myStory", "self")
        users = c.first([QuickMomentTrayItem].self, "users", "tray", "stories", "items", "others") ?? []
    }
}

// MARK: - Story frames

extension QuickMoment {
    /// Story frame for `VibeMomentsViewController` and the profile bubbles.
    func storyMoment(id: Int) -> VibeMoment {
        let caption = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VibeMoment(id: id,
                          imagePath: mediaPath ?? "",
                          isVideo: false,
                          caption: caption?.isEmpty == false ? caption : nil,
                          postedAt: VibeDate.date(from: createdAt),
                          textBackground: QuickMomentColors.backgroundIndex(for: backgroundColor),
                          reactionsCount: reactionsCount,
                          repliesCount: repliesCount,
                          topReactions: Array(topReactions.prefix(3)))
    }
}

// MARK: - Text background colors

/// The composer picks a gradient from `VibeTheme.storyBackgrounds`; the API stores one hex color.
enum QuickMomentColors {
    static let textColor = "#ffffff"

    static func hex(forBackground index: Int) -> String {
        hex(VibeTheme.storyBackground(index).first ?? .black)
    }

    static func backgroundIndex(for hex: String?) -> Int {
        guard let hex = hex?.lowercased() else { return 0 }
        return VibeTheme.storyBackgrounds.firstIndex { self.hex($0.first ?? .black) == hex } ?? 0
    }

    private static func hex(_ color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02x%02x%02x", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }
}
