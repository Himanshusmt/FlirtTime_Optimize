//
//  MediaGalleryModels.swift
//  FlirttimeNew
//

import Foundation
import UIKit

// MARK: - Data Models

struct GalleryMediaItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let s3Path: String?
    let isVideo: Bool
    let messageId: String
    let senderName: String?
    let timestamp: Date?
    let thumbnailURL: URL?
    /// Progressive / non-HLS file for Photos save when `url` is an HLS play URL.
    let downloadURL: URL?

    init(
        id: String,
        url: URL,
        s3Path: String?,
        isVideo: Bool,
        messageId: String,
        senderName: String?,
        timestamp: Date?,
        thumbnailURL: URL?,
        downloadURL: URL? = nil
    ) {
        self.id = id
        self.url = url
        self.s3Path = s3Path
        self.isVideo = isVideo
        self.messageId = messageId
        self.senderName = senderName
        self.timestamp = timestamp
        self.thumbnailURL = thumbnailURL
        self.downloadURL = downloadURL
    }

    static func == (lhs: GalleryMediaItem, rhs: GalleryMediaItem) -> Bool {
        lhs.id == rhs.id
    }

    /// Disk / memory key — unique per album slide (`messageId_index`); equals `messageId` for singles.
    var storageKey: String { id }

    func localMediaURL(type: MediaStorageType) -> URL? {
        if let url = MediaStorageManager.shared.getMediaURL(messageId: storageKey, type: type) {
            return url
        }
        // Legacy single-media fallback when storage key ever differs from message id.
        if storageKey != messageId {
            return MediaStorageManager.shared.getMediaURL(messageId: messageId, type: type)
        }
        return nil
    }

    func localVideoThumbnail() -> UIImage? {
        if let thumb = MediaStorageManager.shared.getVideoThumbnail(messageId: storageKey) {
            return thumb
        }
        if storageKey != messageId {
            return MediaStorageManager.shared.getVideoThumbnail(messageId: messageId)
        }
        return nil
    }
}

struct MediaGalleryContext: Identifiable {
    let id = UUID().uuidString
    let items: [GalleryMediaItem]
    let initialIndex: Int
    let title: String?
    let sourceFrame: CGRect?

    init(items: [GalleryMediaItem], initialIndex: Int, title: String?, sourceFrame: CGRect? = nil) {
        self.items = items
        self.initialIndex = initialIndex
        self.title = title
        self.sourceFrame = sourceFrame
    }
}

enum MediaGalleryBuilder {
    static func buildGalleryItems(from messages: [ConversationMessage]) -> [GalleryMediaItem] {
        var items: [GalleryMediaItem] = []
        var skippedNoType = 0, skippedViewOnce = 0, skippedNoURL = 0
        for msg in messages {
            let msgType = (msg.messageType ?? msg.type ?? "").lowercased()
            guard msgType == "image" || msgType == "video" || msgType == "photo" else {
                skippedNoType += 1
                continue
            }
            guard msg.isViewOnce != true, msg.isDeleted != true else {
                skippedViewOnce += 1
                continue
            }

            let senderName = msg.sender?.fullName ?? msg.sender?.userName
            let timestamp = parseDate(msg.createdAt)
            let mediaList = msg.media ?? []

            if mediaList.count > 1 {
                for (index, media) in mediaList.enumerated() {
                    let isVideo = (media.type ?? "").lowercased() == "video"
                        || (media.url?.lowercased().hasSuffix(".mp4") == true)
                        || (media.url?.lowercased().hasSuffix(".mov") == true)
                    guard let url = resolveMediaURL(media: media, message: msg, index: index) else {
                        skippedNoURL += 1
                        continue
                    }
                    var thumbURL: URL? = nil
                    if isVideo {
                        if let t = media.thumbnail, let u = URL(string: t) { thumbURL = u }
                    }
                    items.append(GalleryMediaItem(
                        id: "\(msg.id)_\(index)",
                        url: url,
                        s3Path: extractS3Path(from: media.url ?? msg.content),
                        isVideo: isVideo,
                        messageId: msg.id,
                        senderName: senderName,
                        timestamp: timestamp,
                        thumbnailURL: thumbURL
                    ))
                }
                continue
            }

            let isVideo = msgType == "video"
            guard let url = resolveURL(for: msg) else {
                skippedNoURL += 1
                AppLogger.debug("[buildGalleryItems] skipped id=\(msg.id ?? "nil") type=\(msgType) — resolveURL returned nil. media=\(msg.media?.first?.url ?? "<nil>") content=\(msg.content ?? "<nil>")")
                continue
            }
            var thumbURL: URL? = nil
            if isVideo {
                if let t = msg.thumbnail, let u = URL(string: t) { thumbURL = u }
                else if let t = msg.media?.first?.thumbnail, let u = URL(string: t) { thumbURL = u }
            }
            items.append(GalleryMediaItem(
                id: msg.id,
                url: url,
                s3Path: extractS3Path(from: msg),
                isVideo: isVideo,
                messageId: msg.id,
                senderName: senderName,
                timestamp: timestamp,
                thumbnailURL: thumbURL
            ))
        }
        AppLogger.debug("🖼️ [buildGalleryItems] input=\(messages.count) output=\(items.count) skippedType=\(skippedNoType) skippedViewOnce=\(skippedViewOnce) skippedNoURL=\(skippedNoURL)")
        return items
    }

    static func resolveURL(for msg: ConversationMessage) -> URL? {
        if let resolved = msg.resolvedMediaURL { return resolved }
        if let u = msg.media?.first?.url, u.lowercased().hasPrefix("http"), let url = URL(string: u) { return url }
        if let c = msg.content, c.lowercased().hasPrefix("http"), let url = URL(string: c) { return url }
        if let u = msg.media?.first?.url, u.hasPrefix("file://"), let url = URL(string: u) { return url }
        if let c = msg.content, c.hasPrefix("file://"), let url = URL(string: c) { return url }
        return nil
    }

    private static func resolveMediaURL(media: ConversationMedia, message: ConversationMessage, index: Int) -> URL? {
        if let u = media.url, let url = URL(string: u), u.hasPrefix("http") || u.hasPrefix("file://") {
            return url
        }
        let key = "\(message.id)_\(index)"
        let type: MediaStorageType = (media.type ?? "").lowercased() == "video" ? .video : .image
        if let local = MediaStorageManager.shared.getMediaURL(messageId: key, type: type) {
            return local
        }
        if let id = media.id, !id.isEmpty,
           let local = MediaStorageManager.shared.getMediaURL(messageId: id, type: type) {
            return local
        }
        return nil
    }

    static func extractS3Path(from msg: ConversationMessage) -> String? {
        extractS3Path(from: msg.media?.first?.url ?? msg.content)
    }

    static func extractS3Path(from httpURL: String?) -> String? {
        guard let raw = httpURL, raw.lowercased().hasPrefix("https://"), let url = URL(string: raw) else { return nil }
        var path = url.path
        if path.hasPrefix("/") { path = String(path.dropFirst()) }
        return path.isEmpty ? nil : path
    }

    static func parseDate(_ str: String?) -> Date? {
        guard let str = str, !str.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: str) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: str)
    }
}
