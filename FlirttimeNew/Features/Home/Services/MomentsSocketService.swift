//
//  MomentsSocketService.swift
//  FlirttimeNew
//
//  Live `moment:*` events for the Moments list and comment sheet.
//

import Combine
import Foundation

enum MomentSocketKind {
    /// Any activity — treat counts here as the source of truth for the feed.
    case updated
    case likeUpdated
    case commentCreated
    case commentDeleted
    case commentLikeUpdated
    case giftSent
    case deleted
}

struct MomentSocketUpdate {
    let kind: MomentSocketKind
    let momentId: String
    let likesCount: Int?
    let commentsCount: Int?
    let giftsCount: Int?
    let sharesCount: Int?
    /// Viewer-specific like, only when the payload is clearly about the signed-in user.
    let viewerHasLiked: Bool?
    let actorId: String?
    let commentId: String?
    let comment: MomentsComment?
    let commentLikesCount: Int?
    let commentIsLiked: Bool?
    /// Full moment when the backend sends one (new post, or a rich `moment:updated`).
    let moment: MomentsPost?
}

/// Shared listener for the Moments sockets listed by the backend.
final class MomentsSocketService {
    static let shared = MomentsSocketService()

    var updates: AnyPublisher<MomentSocketUpdate, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = PassthroughSubject<MomentSocketUpdate, Never>()
    private var listenerIds: [UUID] = []
    private var areListenersConfigured = false

    private init() {}

    func setupSocketListeners() {
        guard !areListenersConfigured else { return }
        areListenersConfigured = true

        listen(.momentCreated, kind: .updated)
        listen(.momentUpdated, kind: .updated)
        listen(.momentLikeUpdated, kind: .likeUpdated)
        listen(.momentCommentCreated, kind: .commentCreated)
        listen(.momentCommentDeleted, kind: .commentDeleted)
        listen(.momentCommentLikeUpdated, kind: .commentLikeUpdated)
        listen(.momentGiftSent, kind: .giftSent)
        listen(.momentDeleted, kind: .deleted)
    }

    func invalidateSocketListeners() {
        for id in listenerIds {
            ChatSocketManager.shared.offEventById(id)
        }
        listenerIds.removeAll()
        areListenersConfigured = false
    }

    private func listen(_ event: SocketEvent, kind: MomentSocketKind) {
        let id = ChatSocketManager.shared.listenToEvent(event.rawValue) { [weak self] data in
            guard let update = MomentSocketUpdate.parse(data, kind: kind) else { return }
            AppLogger.debug("[MomentsSocket] \(event.rawValue) momentId=\(update.momentId)")
            DispatchQueue.main.async {
                self?.subject.send(update)
            }
        }
        listenerIds.append(id)
    }
}

// MARK: - Parsing

private extension MomentSocketUpdate {
    static func parse(_ data: [Any], kind: MomentSocketKind) -> MomentSocketUpdate? {
        guard let body = dictionary(from: data) else { return nil }
        let momentDict = (body["moment"] as? [String: Any]) ?? (body["post"] as? [String: Any])
        let commentDict = (body["comment"] as? [String: Any])
            ?? (body["reply"] as? [String: Any])
            ?? (body["data"] as? [String: Any]).flatMap { nested in
                (nested["comment"] as? [String: Any]) ?? (nested["reply"] as? [String: Any])
            }

        let momentId = string(body["momentId"])
            ?? string(body["vibeId"])
            ?? string(momentDict?["momentId"])
            ?? string(momentDict?["id"])
            ?? string(commentDict?["momentId"])
            ?? string(commentDict?["vibeId"])
            ?? (kind == .deleted ? string(body["id"]) : nil)
        guard let momentId, !momentId.isEmpty else { return nil }

        let actor = (body["actor"] as? [String: Any])
            ?? (body["user"] as? [String: Any])
            ?? (body["sender"] as? [String: Any])
            ?? (body["liker"] as? [String: Any])
        let actorId = string(body["actorId"])
            ?? string(body["likerId"])
            ?? string(body["senderId"])
            ?? string(body["fromUserId"])
            ?? string(actor?["id"])
            ?? string(actor?["userId"])

        let commentId = string(body["commentId"])
            ?? string(body["replyId"])
            ?? string(commentDict?["replyId"])
            ?? string(commentDict?["commentId"])
            ?? string(commentDict?["id"])

        let currentUserId = UserDataManager.shared.appUser?.id
        let isActorCurrentUser = {
            guard let actorId, let currentUserId else { return false }
            return actorId == currentUserId
        }()

        let explicitViewerLike = bool(body["isLikedByMe"])
            ?? bool(body["hasLikedByMe"])
            ?? bool(body["likedByMe"])
            ?? bool(body["viewerHasLiked"])
            ?? bool(momentDict?["isLikedByMe"])
            ?? bool(momentDict?["hasLikedByMe"])
        let viewerReaction = string(body["viewerReaction"]) ?? string(momentDict?["viewerReaction"])
        let rawLiked = bool(body["isLiked"]) ?? bool(body["hasLiked"])
            ?? bool(momentDict?["isLiked"]) ?? bool(momentDict?["hasLiked"])
        let viewerHasLiked = explicitViewerLike
            ?? (viewerReaction != nil ? true : nil)
            ?? (isActorCurrentUser ? rawLiked : nil)

        let commentLikesCount = int(body["commentLikesCount"])
            ?? int(body["commentLikeCount"])
            ?? int(commentDict?["likesCount"])
            ?? int(commentDict?["likeCount"])
        let commentIsLiked = bool(body["commentIsLiked"])
            ?? bool(commentDict?["isLikedByMe"])
            ?? bool(commentDict?["likedByMe"])
            ?? (isActorCurrentUser ? (bool(commentDict?["isLiked"]) ?? bool(body["isLiked"])) : nil)

        var comment: MomentsComment?
        if let commentDict {
            comment = decodeComment(commentDict, momentId: momentId, fallbackId: commentId)
        } else if kind == .commentCreated, let commentId {
            comment = MomentsComment(
                id: commentId,
                vibeId: momentId,
                body: string(body["comment"]) ?? string(body["reply"]) ?? string(body["body"]) ?? string(body["text"]),
                createdAt: string(body["createdAt"]) ?? MomentsDate.string(from: Date()),
                author: actor.map { MomentPerson.from($0).author },
                isMine: isActorCurrentUser,
                parentId: string(body["parentId"]) ?? string(body["parentCommentId"]) ?? string(body["parentReplyId"]),
                likesCount: commentLikesCount ?? 0,
                isLiked: commentIsLiked ?? false,
                repliesCount: 0
            )
        }

        let moment: MomentsPost? = {
            guard let momentDict else { return decodeMoment(body) }
            return decodeMoment(momentDict)
        }()

        return MomentSocketUpdate(
            kind: kind,
            momentId: momentId,
            likesCount: int(body["likesCount"]) ?? int(body["likeCount"])
                ?? int(momentDict?["likesCount"]) ?? int(momentDict?["likeCount"]),
            commentsCount: int(body["commentsCount"]) ?? int(body["commentCount"]) ?? int(body["totalComments"])
                ?? int(momentDict?["commentsCount"]) ?? int(momentDict?["commentCount"]),
            giftsCount: int(body["giftsCount"]) ?? int(body["giftCount"]) ?? int(body["totalMomentGifts"])
                ?? int(momentDict?["giftsCount"]) ?? int(momentDict?["giftCount"]),
            sharesCount: int(body["sharesCount"]) ?? int(body["shareCount"])
                ?? int(momentDict?["sharesCount"]) ?? int(momentDict?["shareCount"]),
            viewerHasLiked: viewerHasLiked,
            actorId: actorId,
            commentId: commentId,
            comment: comment,
            commentLikesCount: commentLikesCount,
            commentIsLiked: commentIsLiked,
            moment: moment
        )
    }

    static func dictionary(from data: [Any]) -> [String: Any]? {
        let root: [String: Any]
        if let dict = data.first as? [String: Any] {
            root = dict
        } else if let array = data.first as? [Any], let dict = array.first as? [String: Any] {
            root = dict
        } else {
            return nil
        }
        let body = (root["data"] as? [String: Any]) ?? root
        if let moment = body["moment"] as? [String: Any] {
            var merged = moment
            for (key, value) in body where merged[key] == nil {
                merged[key] = value
            }
            merged["moment"] = moment
            return merged
        }
        return body
    }

    static func decodeMoment(_ dict: [String: Any]) -> MomentsPost? {
        let hasContent = dict["media"] != nil || dict["imageUrl"] != nil || dict["photo"] != nil
            || dict["thumbnailUrl"] != nil || dict["caption"] != nil || dict["creator"] != nil
        guard hasContent,
              JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let item = try? JSONDecoder().decode(MomentItem.self, from: data),
              let vibe = item.vibe() else { return nil }
        return vibe
    }

    static func decodeComment(_ dict: [String: Any], momentId: String, fallbackId: String?) -> MomentsComment? {
        if JSONSerialization.isValidJSONObject(dict),
           let data = try? JSONSerialization.data(withJSONObject: dict),
           let item = try? JSONDecoder().decode(MomentComment.self, from: data),
           let comment = item.vibeComment(momentId: momentId) {
            return comment
        }
        guard let id = string(dict["replyId"]) ?? string(dict["commentId"]) ?? string(dict["id"]) ?? fallbackId else {
            return nil
        }
        let author = (dict["user"] as? [String: Any])
            ?? (dict["author"] as? [String: Any])
            ?? (dict["commenter"] as? [String: Any])
        return MomentsComment(
            id: id,
            vibeId: momentId,
            body: string(dict["comment"]) ?? string(dict["reply"]) ?? string(dict["body"]) ?? string(dict["text"]),
            createdAt: string(dict["createdAt"]) ?? MomentsDate.string(from: Date()),
            author: author.map { MomentPerson.from($0).author },
            isMine: bool(dict["isMyComment"]) ?? bool(dict["isMine"]),
            parentId: string(dict["parentId"]) ?? string(dict["parentCommentId"]) ?? string(dict["parentReplyId"])
                ?? string(dict["commentId"]).flatMap { $0 == id ? nil : $0 },
            likesCount: int(dict["likesCount"]) ?? int(dict["likeCount"]),
            isLiked: bool(dict["isLiked"]) ?? bool(dict["hasLiked"]),
            repliesCount: int(dict["repliesCount"]) ?? int(dict["replyCount"])
        )
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        case let string as String:
            switch string.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default:
            return nil
        }
    }
}

private extension MomentPerson {
    static func from(_ dict: [String: Any]) -> MomentPerson {
        MomentPerson(
            id: dict["id"] as? String,
            userId: dict["userId"] as? String,
            name: dict["name"] as? String,
            username: dict["username"] as? String,
            fullName: dict["fullName"] as? String,
            profilePicture: dict["profilePicture"] as? String,
            profilePhoto: dict["profilePhoto"] as? String,
            profilePhotoUrl: dict["profilePhotoUrl"] as? String,
            avatar: dict["avatar"] as? String,
            isVerified: dict["isVerified"] as? Bool,
            city: dict["city"] as? String
        )
    }
}
