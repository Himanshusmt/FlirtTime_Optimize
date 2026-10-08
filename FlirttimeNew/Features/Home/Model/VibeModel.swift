//
//  VibeModel.swift
//  FlirttimeNew
//
//  Shapes follow the OneVibe `vibes/` endpoints (feed, comments, gifts) so the mock
//  view models can be swapped for the real API without touching the UI.
//

import Foundation

// MARK: - Feed (GET vibes/)
struct VibeFeedResponse: Codable {
    let success: Bool?
    let message: String?
    let data: VibeFeedData?
}

struct VibeFeedData: Codable {
    var rows: [Vibe]?
    let count: Int?
    let hasMore: Bool?
    let page: Int?
    let limit: Int?
}

struct Vibe: Codable {
    let id: String
    let userId: String?
    let caption: String?
    let media: [VibeMedia]?
    var likesCount: Int?
    var commentsCount: Int?
    var giftCount: Int?
    var hasLiked: Bool?
    let createdAt: String?
    let author: VibeAuthor?

    enum CodingKeys: String, CodingKey {
        case id, userId, caption, media, likesCount, commentsCount, hasLiked, createdAt, author
        case giftCount = "gift_count"
    }
}

struct VibeMedia: Codable {
    let id: String?
    let filePath: String?
    let fileType: String?
}

struct VibeAuthor: Codable {
    let userId: String?
    let userName: String?
    let fullName: String?
    let profilePicture: String?
    let verified: Bool?

    var displayName: String {
        let name = (userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? (fullName ?? "") : name
    }
}

// MARK: - Create (POST vibes/)
struct CreateVibeResponse: Codable {
    let success: Bool?
    let message: String?
    let data: Vibe?
}

// MARK: - Delete (DELETE vibes/{id}) / Report (POST vibes/{id}/report)
struct VibeActionResponse: Codable {
    let success: Bool?
    let message: String?
}

// MARK: - Like (POST / DELETE vibes/{id}/likes)
struct VibeLikeResponse: Codable {
    let success: Bool?
    let message: String?
    let data: VibeLikeData?
}

struct VibeLikeData: Codable {
    let likesCount: Int?
    let hasLiked: Bool?
}

// MARK: - Comments (GET / POST vibes/{id}/comments)
struct VibeCommentListResponse: Codable {
    let success: Bool?
    let message: String?
    let data: VibeCommentData?
}

struct VibeCommentData: Codable {
    var rows: [VibeComment]?
    let count: Int?
    let hasMore: Bool?
}

struct VibeComment: Codable {
    let id: String
    let vibeId: String?
    let body: String?
    let createdAt: String?
    let author: VibeAuthor?
}

struct CreateVibeCommentResponse: Codable {
    let success: Bool?
    let message: String?
    let data: VibeComment?
}

// MARK: - Gifts (GET gifts/, POST vibes/{id}/gifts, GET vibes/{id}/gifts)
struct VibeGiftCatalogResponse: Codable {
    let success: Bool?
    let data: VibeGiftCatalogData?
}

struct VibeGiftCatalogData: Codable {
    let gifts: [VibeGift]?
    let coinBalance: Int?
}

struct VibeGift: Codable {
    let id: Int
    let title: String?
    /// Remote icon URL from the API; the mock catalog uses an emoji instead.
    let icon: String?
    let amount: Int?
}

struct VibeSendGiftResponse: Codable {
    let success: Bool?
    let message: String?
    let data: VibeSendGiftData?
}

struct VibeSendGiftData: Codable {
    let giftCount: Int?
    let coinBalance: Int?
}

struct VibeReceivedGiftsResponse: Codable {
    let success: Bool?
    let totalGifts: Int?
    let totalCoins: Int?
    let gifts: [VibeReceivedGift]?
}

struct VibeReceivedGift: Codable {
    let id: String
    let giftId: Int?
    let coinsUsed: Int?
    let createdAt: String?
    let gift: VibeGift?
    let sender: VibeAuthor?
}

// MARK: - Helpers
struct VibeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum VibeDate {

    private static let parser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        parser.string(from: date)
    }

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return parser.date(from: string) ?? fallbackParser.date(from: string)
    }

    /// Short relative time the way the vibe feed shows it ("now", "5m", "3h", "2d", "4w").
    static func timeAgo(from string: String?) -> String {
        guard let date = date(from: string) else { return "" }
        let seconds = max(Int(Date().timeIntervalSince(date)), 0)
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        case ..<604800: return "\(seconds / 86400)d"
        default: return "\(seconds / 604800)w"
        }
    }
}

extension Int {
    /// Compact counter used on the vibe action bar (1.2K, 3.4M).
    var vibeCountText: String {
        switch self {
        case ..<1000: return "\(Swift.max(self, 0))"
        case ..<1_000_000: return Self.compact(Double(self) / 1000, suffix: "k")
        default: return Self.compact(Double(self) / 1_000_000, suffix: "m")
        }
    }

    private static func compact(_ value: Double, suffix: String) -> String {
        let rounded = (value * 10).rounded(.down) / 10
        let text = rounded.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(rounded)) : String(rounded)
        return text + suffix
    }
}
