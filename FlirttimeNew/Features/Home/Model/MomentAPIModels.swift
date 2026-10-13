//
//  MomentAPIModels.swift
//  FlirttimeNew
//
//  `api/v1/moments` models, mapped onto the existing `Vibe` models so the feed UI stays unchanged.
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
    let location: String?
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
    let profilePhoto: String?
    let isVerified: Bool?
}

struct MomentFeedPage {
    let vibes: [Vibe]
    let hasMore: Bool
    /// Total moments across all pages.
    let total: Int?
}

// MARK: - Mapping

extension VibeAuthor {
    /// The signed-in user, from the saved `auth/me` response.
    static var currentUser: VibeAuthor {
        let user = UserDataManager.shared.appUser
        let nickName = user?.nickName?.trimmingCharacters(in: .whitespaces) ?? ""
        return VibeAuthor(userId: user?.id,
                          userName: nickName.isEmpty ? user?.username : nickName,
                          fullName: user?.fullName ?? "You",
                          profilePicture: user?.profilePicture,
                          verified: user?.isFaceVerified,
                          location: user?.city)
    }
}

extension MomentFeedData {
    /// `fallbackAuthor` is used for moments that come without a creator (e.g. `moments/me`).
    func page(fallbackAuthor: VibeAuthor? = nil) -> MomentFeedPage {
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
    func vibe(fallbackAuthor: VibeAuthor? = nil) -> Vibe? {
        guard let id = momentId ?? id, !id.isEmpty else { return nil }
        let place = locationLabel ?? location
        let author: VibeAuthor
        if let creator {
            author = VibeAuthor(userId: creator.userId ?? creator.id,
                                userName: creator.name ?? creator.username,
                                fullName: creator.fullName ?? creator.name,
                                profilePicture: creator.profilePhoto,
                                verified: creator.isVerified,
                                location: place)
        } else {
            let fallback = fallbackAuthor ?? .currentUser
            author = VibeAuthor(userId: creatorId ?? fallback.userId, userName: fallback.userName, fullName: fallback.fullName,
                                profilePicture: fallback.profilePicture, verified: fallback.verified,
                                location: place ?? fallback.location)
        }

        let ordered = (media ?? []).sorted {
            ($0.orderIndex ?? $0.displayOrder ?? 0) < ($1.orderIndex ?? $1.displayOrder ?? 0)
        }
        var vibeMedia = ordered.enumerated().compactMap { index, item -> VibeMedia? in
            guard let url = item.imageUrl ?? item.mediaUrl ?? item.publicUrl ?? item.url ?? item.thumbnailUrl,
                  !url.isEmpty else { return nil }
            return VibeMedia(id: item.mediaId ?? item.id ?? "\(index)", filePath: url, fileType: item.mediaType ?? "image",
                             thumbnailPath: item.thumbnailUrl)
        }
        if vibeMedia.isEmpty, let cover = imageUrl ?? photo ?? thumbnailUrl, !cover.isEmpty {
            vibeMedia = [VibeMedia(id: "0", filePath: cover, fileType: "image", thumbnailPath: thumbnailUrl)]
        }

        return Vibe(id: id,
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
    let fullName: String?
    let profilePhoto: String?
    let avatar: String?
    let isVerified: Bool?
    let city: String?

    var author: VibeAuthor {
        VibeAuthor(userId: id ?? userId, userName: name, fullName: fullName ?? name,
                   profilePicture: profilePhoto ?? avatar, verified: isVerified, location: city)
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

    func vibeComment(momentId: String) -> VibeComment? {
        guard let id = commentId ?? id else { return nil }
        return VibeComment(id: id, vibeId: momentId, body: comment ?? message, createdAt: createdAt,
                           author: user?.author ?? (isMyComment == true ? .currentUser : nil))
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
