//
//  QuickMomentModel.swift
//  FlirttimeNew
//
//  Quick Moments: short story-style photo or text posts that other users react to and reply on.
//  Separate from Moments (the vibe feed).
//

import Foundation

// MARK: - List (GET quick-moments/?userId=)
struct QuickMomentListResponse: Codable {
    let success: Bool?
    let message: String?
    let data: [QuickMoment]?
}

// MARK: - Create (POST quick-moments/)
struct CreateQuickMomentResponse: Codable {
    let success: Bool?
    let message: String?
    let data: QuickMoment?
}

struct QuickMoment: Codable {
    let id: String
    let userId: String?
    /// `nil` for a text Quick Moment.
    let mediaPath: String?
    /// The text of a text Quick Moment, or the caption of a photo one.
    let text: String?
    /// Index into `VibeTheme.storyBackgrounds` for text Quick Moments.
    let background: Int?
    let createdAt: String?
    var reactions: [QuickMomentReaction]?
    var replies: [QuickMomentReply]?

    var isText: Bool { (mediaPath ?? "").isEmpty }
}

struct QuickMomentReaction: Codable {
    let id: String
    let emoji: String
    let createdAt: String?
    let author: VibeAuthor?
}

struct QuickMomentReply: Codable {
    let id: String
    let body: String
    let createdAt: String?
    let author: VibeAuthor?
}

extension QuickMoment {
    /// Story frame for `VibeMomentsViewController` and the profile bubbles.
    func storyMoment(id: Int) -> VibeMoment {
        let caption = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VibeMoment(id: id,
                          imagePath: mediaPath ?? "",
                          isVideo: false,
                          caption: caption?.isEmpty == false ? caption : nil,
                          postedAt: VibeDate.date(from: createdAt),
                          textBackground: background ?? 0,
                          reactionsCount: reactions?.count ?? 0,
                          repliesCount: replies?.count ?? 0,
                          topReactions: QuickMoment.topEmojis(in: reactions ?? []))
    }

    /// Most used reaction emojis first, at most three.
    static func topEmojis(in reactions: [QuickMomentReaction]) -> [String] {
        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        for (index, reaction) in reactions.enumerated() {
            counts[reaction.emoji, default: 0] += 1
            if firstSeen[reaction.emoji] == nil { firstSeen[reaction.emoji] = index }
        }
        return counts.keys
            .sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : firstSeen[$0]! < firstSeen[$1]! }
            .prefix(3)
            .map { $0 }
    }
}
