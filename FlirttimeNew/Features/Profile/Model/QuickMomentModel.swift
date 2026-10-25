//
//  QuickMomentModel.swift
//  FlirttimeNew
//
//  Quick Moments: 24-hour story-style photo or text posts that other users react to and reply on.
//  Separate from Moments (the moment feed). Decoders accept several key names because the
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
            if let value = try? decodeIfPresent(Int.self, forKey: QMKey(key)) { return value != 0 }
            if let value = try? decodeIfPresent(String.self, forKey: QMKey(key)) {
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "1", "yes": return true
                case "false", "0", "no": return false
                default: break
                }
            }
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
                                "reactions", "viewers", "replies", "users", "results", "data") ?? []
        total = container.int("totalStories", "totalCount", "total", "count", "storiesCount")
    }
}

/// `GET quick-moments/user/:userId` — `data: { author, stories, totalStories }`.
struct UserQuickMomentsData: Codable {
    let author: QuickMomentUser?
    let stories: [QuickMoment]
    let totalStories: Int?

    init(from decoder: Decoder) throws {
        // Flat array fallback.
        if let array = try? [QuickMoment](from: decoder) {
            author = nil
            stories = array
            totalStories = array.count
            return
        }
        let c = try decoder.container(keyedBy: QMKey.self)
        author = c.first(QuickMomentUser.self, "author", "user", "creator")
        let list = c.first([QuickMoment].self, "stories", "quickMoments", "moments", "items") ?? []
        // Newest first, matching the profile row / tray.
        stories = list.sorted {
            (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast)
        }
        totalStories = c.int("totalStories", "totalCount", "total", "count") ?? stories.count
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
        name = c.string("username", "name", "nickName", "displayName")
        fullName = c.string("fullName", "name")
        var resolvedPhoto = c.string(
            "profilePhoto", "profilePicture", "profileImage", "profileImageUrl",
            "profilePhotoUrl", "avatarUrl", "avatarPath", "avatar", "photo",
            "photoUrl", "filePath"
        )
        if resolvedPhoto == nil,
           let details = try? c.decodeIfPresent(ProfilePictureDetails.self, forKey: QMKey("profilePictureDetails")) {
            resolvedPhoto = details.filePath
        }
        photo = resolvedPhoto
        isVerified = c.bool("isVerified", "verified", "isFaceVerified")
        location = c.string("locationLabel", "location", "city")
    }

    var author: MomentsAuthor {
        MomentsAuthor(userId: id, userName: name, fullName: fullName ?? name, profilePicture: photo,
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
    let author: MomentsAuthor?

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
        // API uses `isViewed` on user/tray stories; older payloads used `hasViewed` / `seen`.
        hasViewed = c.bool("isViewed", "hasViewed", "seen") ?? false
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
    let timeAgo: String?
    let author: MomentsAuthor?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        emoji = c.string("emoji", "reaction") ?? ""
        createdAt = c.string("reactedAt", "createdAt", "updatedAt")
        timeAgo = c.string("timeAgo")
        author = nestedUser(in: c, decoder: decoder)?.author
    }
}

struct QuickMomentReactionsPage: Codable {
    let total: Int
    let breakdown: [QuickMomentEmojiCount]
    let reactions: [QuickMomentReaction]

    init(from decoder: Decoder) throws {
        let list = try QMList<QuickMomentReaction>(from: decoder)
        let c = try? decoder.container(keyedBy: QMKey.self)
        let pagination = try? c?.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("pagination"))
        reactions = c?.first([QuickMomentReaction].self, "reactors") ?? list.items
        if let counts = c?.first([QuickMomentEmojiCount].self, "breakdown", "emojiBreakdown", "reactionBreakdown", "summary") {
            breakdown = counts
        } else if let dict = c?.first([String: Int].self, "breakdown", "emojiBreakdown", "reactionBreakdown", "summary") {
            breakdown = dict.map { QuickMomentEmojiCount(emoji: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
        } else {
            breakdown = []
        }
        total = c?.int("totalReactions") ?? list.total ?? pagination?.int("total") ?? reactions.count
    }
}

// MARK: - Viewers (GET quick-moments/:id/viewers)

struct QuickMomentViewer: Codable {
    let viewedAt: String?
    let timeAgo: String?
    let author: MomentsAuthor?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        viewedAt = c.string("viewedAt", "createdAt", "seenAt")
        timeAgo = c.string("timeAgo")
        author = nestedUser(in: c, decoder: decoder)?.author
    }
}

struct QuickMomentViewersPage: Codable {
    let viewers: [QuickMomentViewer]
    let total: Int

    init(from decoder: Decoder) throws {
        let list = try QMList<QuickMomentViewer>(from: decoder)
        let c = try? decoder.container(keyedBy: QMKey.self)
        let pagination = try? c?.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("pagination"))
        viewers = c?.first([QuickMomentViewer].self, "viewers") ?? list.items
        total = c?.int("totalViews", "totalViewers", "total") ?? list.total ?? pagination?.int("total") ?? viewers.count
    }
}

// MARK: - Replies (GET quick-moments/:id/replies)

struct QuickMomentReply: Codable {
    let text: String
    let createdAt: String?
    let timeAgo: String?
    let author: MomentsAuthor?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        text = c.string("message", "text", "body", "reply", "content") ?? ""
        createdAt = c.string("createdAt", "repliedAt", "updatedAt")
        timeAgo = c.string("timeAgo")
        author = nestedUser(in: c, decoder: decoder)?.author
    }
}

struct QuickMomentRepliesPage: Codable {
    let replies: [QuickMomentReply]
    let total: Int
    let reactions: [QuickMomentReaction]
    let reactionsTotal: Int
    let viewers: [QuickMomentViewer]
    let viewsTotal: Int

    init(from decoder: Decoder) throws {
        let list = try QMList<QuickMomentReply>(from: decoder)
        let c = try? decoder.container(keyedBy: QMKey.self)
        let pagination = try? c?.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("pagination"))
        let reactionsBox = try? c?.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("reactions"))
        let viewsBox = try? c?.nestedContainer(keyedBy: QMKey.self, forKey: QMKey("views"))
        replies = c?.first([QuickMomentReply].self, "replies", "items", "messages") ?? list.items
        total = c?.int("totalReplies", "repliesCount", "total") ?? list.total ?? pagination?.int("total") ?? replies.count
        reactions = reactionsBox?.first([QuickMomentReaction].self, "reactors", "reactions") ?? []
        reactionsTotal = reactionsBox?.int("total", "totalReactions") ?? reactions.count
        viewers = viewsBox?.first([QuickMomentViewer].self, "viewers") ?? []
        viewsTotal = viewsBox?.int("total", "totalViews") ?? viewers.count
    }
}

// MARK: - Tray (GET quick-moments/tray)

struct QuickMomentTrayItem: Codable {
    let user: QuickMomentUser?
    let hasUnread: Bool
    let activeCount: Int
    let previewUrl: String?
    let previewText: String?
    /// Hex background of a text preview.
    let previewBackground: String?
    let latestAt: String?
    /// "24m", already formatted by the backend.
    let latestTimeAgo: String?
    let topReactions: [String]
    let reactionsCount: Int
    /// Active stories, newest first.
    let stories: [QuickMoment]

    /// `myStatus` sends `hasActive`; other users are only listed while they have stories.
    var hasActive: Bool { activeCount > 0 || !stories.isEmpty }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        user = nestedUser(in: c, decoder: decoder)
        hasUnread = c.bool("hasUnread", "isUnread", "unread") ?? false
        let stories = (c.first([QuickMoment].self, "stories", "quickMoments", "moments") ?? []).sorted {
            (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast)
        }
        self.stories = stories
        let isActive = c.bool("hasActive", "isActive")
        activeCount = isActive == false ? 0 : (c.int("totalActive", "totalStories", "activeCount", "storiesCount", "count", "momentsCount") ?? stories.count)
        let preview = c.first(QuickMomentPreview.self, "preview", "latest", "latestStory")
        previewUrl = preview?.thumbnailUrl ?? preview?.imageUrl ?? c.string("previewUrl", "thumbnailUrl", "imageUrl", "mediaUrl")
        previewText = preview?.text ?? c.string("previewText", "text")
        previewBackground = preview?.backgroundColor ?? c.string("backgroundColor")
        latestAt = c.string("latestAt", "lastPostedAt", "createdAt") ?? stories.first?.createdAt
        latestTimeAgo = c.string("latestTimeAgo", "timeAgo")
        topReactions = c.first([String].self, "topReactions") ?? []
        reactionsCount = c.int("reactionsCount", "reactionCount") ?? 0
    }

    /// Time shown on the card, preferring the backend's own label.
    var timeText: String? {
        latestTimeAgo ?? (latestAt.map { MomentsDate.timeAgo(from: $0) }).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Profile photo for the tray avatar — never the story preview.
    var profilePhotoPath: String? {
        let candidates = [
            user?.photo,
            stories.lazy.compactMap { $0.author?.profilePicture }.first
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

/// `preview` of a tray entry: the latest story without an id.
struct QuickMomentPreview: Codable {
    let imageUrl: String?
    let thumbnailUrl: String?
    let text: String?
    let backgroundColor: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        imageUrl = c.string("imageUrl", "mediaUrl", "publicUrl", "url")
        thumbnailUrl = c.string("thumbnailUrl")
        text = c.string("text", "caption")
        backgroundColor = c.string("backgroundColor")
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
        me = c.first(QuickMomentTrayItem.self, "myStatus", "me", "own", "myStory", "self")
        users = c.first([QuickMomentTrayItem].self, "otherUsers", "users", "tray", "items", "others") ?? []
    }
}

// MARK: - Story frames

extension QuickMoment {
    /// Story frame for `QuickMomentViewController` and the profile bubbles.
    func storyMoment(id: Int) -> MomentsStory {
        let caption = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MomentsStory(id: id,
                          imagePath: mediaPath ?? "",
                          isVideo: false,
                          caption: caption?.isEmpty == false ? caption : nil,
                          postedAt: MomentsDate.date(from: createdAt),
                          textBackground: QuickMomentColors.backgroundIndex(for: backgroundColor),
                          reactionsCount: reactionsCount,
                          repliesCount: repliesCount,
                          topReactions: Array(topReactions.prefix(3)),
                          hasViewed: hasViewed)
    }
}

// MARK: - Text background colors

/// The composer picks a gradient from `MomentsTheme.storyBackgrounds`; the API stores one hex color.
enum QuickMomentColors {
    static let textColor = "#ffffff"

    static func hex(forBackground index: Int) -> String {
        hex(MomentsTheme.storyBackground(index).first ?? .black)
    }

    static func backgroundIndex(for hex: String?) -> Int {
        guard let hex = hex?.lowercased() else { return 0 }
        return MomentsTheme.storyBackgrounds.firstIndex { self.hex($0.first ?? .black) == hex } ?? 0
    }

    /// The palette gradient for a known hex; otherwise that color fading to a darker shade.
    static func gradient(for hex: String?) -> [UIColor] {
        guard let hex = hex?.lowercased(), hex.hasPrefix("#") else { return MomentsTheme.storyBackground(0) }
        if let known = MomentsTheme.storyBackgrounds.first(where: { self.hex($0.first ?? .black) == hex }) { return known }
        let color = UIColor(hex: hex)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return [color, UIColor(hue: hue, saturation: saturation, brightness: brightness * 0.7, alpha: alpha)]
    }

    private static func hex(_ color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02x%02x%02x", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }
}
