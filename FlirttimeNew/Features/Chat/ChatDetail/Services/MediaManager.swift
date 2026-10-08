//
//  MediaManager.swift
//  FlirttimeNew
//

import Foundation
import UIKit
import Combine

// MARK: - Context Protocol

@MainActor
protocol MediaManagerContext: AnyObject {
    var selectedId: String { get }
    var isChannel: Bool { get }
    var channelId: String { get }
    var stateManager: ChatStateManagerProtocol { get }
    var tempMessageMapping: [String: ConversationMessage] { get set }
    var activeMediaUploads: Set<String> { get set }
    var isoFormatter: ISO8601DateFormatter { get }
    var userListViewModel: ChatUserListViewModel { get }
    var messageService: ChatMessageServiceProtocol { get }
    var mediaService: ChatMediaServiceProtocol { get }
    var messages: [ConversationMessage] { get }
    var groupedMessages: [MessageGroup] { get set }
    var shouldAutoScroll: Bool { get set }
    var cancellables: Set<AnyCancellable> { get set }
    var replyingToMessage: ConversationMessage? { get set }

    func getCurrentUserId() -> String
    func handleError(_ error: ChatError, context: String)
    func markMessageAsFailed(tempId: String)
    func scheduleFailureTimeout(for tempId: String)
    func resolvedDisplayName(for senderId: String) -> String
    func ensureConversationReady(completion: @escaping (Bool) -> Void)
    func handleMessageListUpdate(_ newMessages: [ConversationMessage])
}

// MARK: - Media Manager

@MainActor
final class MediaManager {

    private weak var context: MediaManagerContext?

    // In-memory LRU media cache
    var mediaCacheData: [String: Data] = [:]
    var mediaCacheInsertionOrder: [String] = []
    let maxMediaCacheCount = 50


    init(context: MediaManagerContext) {
        self.context = context
    }

    // MARK: - Send Image

    func sendImage(_ image: UIImage) {
        guard let ctx = context else { return }

        if ctx.selectedId.isEmpty && !ctx.isChannel {
            ctx.ensureConversationReady { [weak self] success in
                guard let self = self, let ctx = self.context else { return }
                if success {
                    self.sendImage(image)
                } else {
                    ctx.handleError(.mediaUploadFailed, context: "sendImage.ensureConversationReady")
                }
            }
            return
        }

        let tempId = UUID().uuidString
        let filename = "image_\(Int(Date().timeIntervalSince1970)).jpg"

        let selectedId = ctx.selectedId
        let isChannel = ctx.isChannel
        let channelId = ctx.channelId
        let senderId = ctx.getCurrentUserId()
        let nowISO = ctx.isoFormatter.string(from: Date())
        let replyToId = ctx.replyingToMessage?.id
        let replyDict = replyData(for: ctx)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            let resizedImage = self.resizeImage(image, maxDimension: 1600)
            guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
                await MainActor.run { [weak self] in
                    self?.context?.handleError(.invalidMessageContent, context: "sendImage.encode")
                }
                return
            }

            let storageResult = MediaStorageManager.shared.saveMedia(
                data: imageData,
                messageId: tempId,
                type: .image
            )

            guard case .success(let localURL) = storageResult else {
                await MainActor.run { [weak self] in
                    self?.context?.handleError(.mediaUploadFailed, context: "sendImage.saveToDocuments")
                }
                return
            }

            InMemoryMediaCache.shared.cacheImage(resizedImage, for: tempId)

            let filesize = "\(imageData.count)"

            await MainActor.run { [weak self] in
                guard let self = self, let ctx = self.context else { return }

                AppLogger.debug("Saved image to Documents: \(tempId) (\(MediaStorageManager.shared.formatBytes(Int64(imageData.count))))")

                var optimisticDict: [String: Any] = [
                    "id": tempId,
                    (isChannel ? "channelId" : "conversationId"): (isChannel ? channelId : selectedId),
                    "content": localURL.absoluteString,
                    "messageType": "image",
                    "senderId": senderId,
                    "createdAt": nowISO,
                    "updatedAt": nowISO,
                    "isEdited": false,
                    "isDeleted": false,
                    "status": "sending",
                    "localMediaURL": localURL.absoluteString,
                    "isTemporary": true,
                    "clientMessageId": tempId,
                    "metadata": [
                        "clientTempId": tempId,
                        "isTemporary": true
                    ],
                    "media": [
                        [
                            "id": tempId,
                            "url": localURL.absoluteString,
                            "type": "image",
                            "fileName": filename,
                            "fileSize": imageData.count
                        ]
                    ]
                ]
                if let reply = replyDict {
                    optimisticDict["replyToId"] = reply
                }

                if let optimistic = ConversationMessage.fromDictionary(optimisticDict) {
                    ctx.stateManager.addMessages([optimistic])
                    ctx.tempMessageMapping[tempId] = optimistic
                    ctx.shouldAutoScroll = true
                    PendingMessageStore.shared.save(tempId: tempId, message: optimistic, conversationId: selectedId)

                    let snapshot = ctx.stateManager.getGroupedMessagesSnapshot()
                    if snapshot != ctx.groupedMessages {
                        ctx.groupedMessages = snapshot
                        ctx.handleMessageListUpdate(snapshot.flatMap { $0.messages })
                    }
                }

                ctx.activeMediaUploads.insert(tempId)
                let uploadTask = UploadTask(
                    tempId: tempId,
                    conversationId: selectedId,
                    messageType: "image",
                    localFileURL: localURL.path,
                    filename: filename,
                    filesize: filesize,
                    replyToId: replyToId,
                    senderId: senderId,
                    createdAt: nowISO,
                    isChannel: isChannel,
                    channelId: channelId,
                    cropAspect: nil,
                    status: .pending
                )
                BackgroundUploadService.shared.enqueue(uploadTask)
                ctx.replyingToMessage = nil
            }
        }
    }

    // finalizeImageSend removed — handled by BackgroundUploadService

    // MARK: - Send Video

    func sendVideo(_ url: URL, cropAspect: CGFloat? = nil) {
        guard let ctx = context else { return }

        if ctx.selectedId.isEmpty && !ctx.isChannel {
            let aspectCopy = cropAspect
            ctx.ensureConversationReady { [weak self] success in
                guard let self = self, let ctx = self.context else { return }
                if success {
                    self.sendVideo(url, cropAspect: aspectCopy)
                } else {
                    ctx.handleError(.mediaUploadFailed, context: "sendVideo.ensureConversationReady")
                }
            }
            return
        }

        let tempId = UUID().uuidString
        let filename = "video_\(Int(Date().timeIntervalSince1970)).mp4"

        // Capture @MainActor state before hopping off the actor.
        let selectedId = ctx.selectedId
        let isChannel = ctx.isChannel
        let channelId = ctx.channelId
        let senderId = ctx.getCurrentUserId()
        let nowISO = ctx.isoFormatter.string(from: Date())
        let replyToId = ctx.replyingToMessage?.id
        let replyDict = replyData(for: ctx)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            let storageResult = MediaStorageManager.shared.saveVideo(from: url, messageId: tempId)

            guard case .success(let localURL) = storageResult else {
                await MainActor.run { [weak self] in
                    self?.context?.handleError(.mediaUploadFailed, context: "sendVideo.saveToDocuments")
                }
                return
            }

            var thumbnailPath: String? = nil
            if let thumbnail = MediaStorageManager.shared.generateThumbnailFromVideoFile(messageId: tempId) {
                if case .success(let thumbURL) = MediaStorageManager.shared.saveVideoThumbnail(thumbnail, messageId: tempId) {
                    thumbnailPath = thumbURL.absoluteString
                }
                InMemoryMediaCache.shared.cacheImage(thumbnail, for: tempId)
            }

            // Insert the optimistic bubble on the main actor.
            await MainActor.run { [weak self] in
                guard let self = self, let ctx = self.context else { return }
                var mediaEntry: [String: Any] = [
                    "id": tempId,
                    "url": localURL.absoluteString,
                    "type": "video",
                    "fileName": filename
                ]
                if let thumbnailPath = thumbnailPath {
                    mediaEntry["thumbnail"] = thumbnailPath
                }
                var optimisticDict: [String: Any] = [
                    "id": tempId,
                    (isChannel ? "channelId" : "conversationId"): (isChannel ? channelId : selectedId),
                    "content": localURL.absoluteString,
                    "messageType": "video",
                    "senderId": senderId,
                    "createdAt": nowISO,
                    "updatedAt": nowISO,
                    "isEdited": false,
                    "isDeleted": false,
                    "status": "sending",
                    "localMediaURL": localURL.absoluteString,
                    "isTemporary": true,
                    "clientMessageId": tempId,
                    "metadata": [
                        "clientTempId": tempId,
                        "isTemporary": true
                    ],
                    "thumbnail": thumbnailPath as Any,
                    "media": [mediaEntry]
                ]
                
                if let reply = replyDict {
                    optimisticDict["replyToId"] = reply
                }
                
                if let optimistic = ConversationMessage.fromDictionary(optimisticDict) {
                    ctx.stateManager.addMessages([optimistic])
                    ctx.tempMessageMapping[tempId] = optimistic
                    ctx.shouldAutoScroll = true
                    PendingMessageStore.shared.save(tempId: tempId, message: optimistic, conversationId: selectedId)

                    // Bypass throttle — push optimistic message to UI immediately
                    let snapshot = ctx.stateManager.getGroupedMessagesSnapshot()
                    if snapshot != ctx.groupedMessages {
                        ctx.groupedMessages = snapshot
                        ctx.handleMessageListUpdate(snapshot.flatMap { $0.messages })
                    }
                }
            }

            await MainActor.run { [weak self] in
                guard let self = self, let ctx = self.context else { return }
                ctx.activeMediaUploads.insert(tempId)

                let uploadTask = UploadTask(
                    tempId: tempId,
                    conversationId: selectedId,
                    messageType: "video",
                    localFileURL: localURL.path,
                    filename: filename,
                    filesize: "0",
                    replyToId: replyToId,
                    senderId: senderId,
                    createdAt: nowISO,
                    isChannel: isChannel,
                    channelId: channelId,
                    cropAspect: cropAspect.map { Double($0) },
                    status: .pending
                )
                BackgroundUploadService.shared.enqueue(uploadTask)
                ctx.replyingToMessage = nil
            }
        }
    }

    // finalizeVideoSend removed — handled by BackgroundUploadService

    // MARK: - Send Media Album (WhatsApp-style)

    /// Sends multiple images/videos as a single grouped message.
    func sendMediaAlbum(_ items: [MediaPickerResult]) {
        guard let ctx = context else { return }
        guard items.count > 1 else {
            if let only = items.first {
                switch only {
                case .image(let image): sendImage(image)
                case .video(let url): sendVideo(url)
                }
            }
            return
        }

        if ctx.selectedId.isEmpty && !ctx.isChannel {
            ctx.ensureConversationReady { [weak self] success in
                guard let self = self, let ctx = self.context else { return }
                if success {
                    self.sendMediaAlbum(items)
                } else {
                    ctx.handleError(.mediaUploadFailed, context: "sendMediaAlbum.ensureConversationReady")
                }
            }
            return
        }

        let tempId = UUID().uuidString
        let selectedId = ctx.selectedId
        let isChannel = ctx.isChannel
        let channelId = ctx.channelId
        let senderId = ctx.getCurrentUserId()
        let nowISO = ctx.isoFormatter.string(from: Date())
        let replyToId = ctx.replyingToMessage?.id
        let replyDict = replyData(for: ctx)
        let capped = Array(items.prefix(10))

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            var mediaEntries: [[String: Any]] = []
            var albumUploadItems: [AlbumUploadItem] = []
            var hasVideo = false
            var nextIndex = 0

            for item in capped {
                let index = nextIndex
                let itemKey = "\(tempId)_\(index)"
                switch item {
                case .image(let image):
                    let resized = self.resizeImage(image, maxDimension: 1600)
                    guard let imageData = resized.jpegData(compressionQuality: 0.8) else { continue }
                    let storageResult = MediaStorageManager.shared.saveMedia(
                        data: imageData,
                        messageId: itemKey,
                        type: .image
                    )
                    guard case .success(let localURL) = storageResult else { continue }
                    InMemoryMediaCache.shared.cacheImage(resized, for: itemKey)
                    _ = MediaStorageManager.shared.saveImageThumbnail(resized, messageId: itemKey)

                    let filename = "image_\(Int(Date().timeIntervalSince1970))_\(index).jpg"
                    mediaEntries.append([
                        "id": itemKey,
                        "url": localURL.absoluteString,
                        "type": "image",
                        "fileName": filename,
                        "fileSize": imageData.count,
                        "thumbnail": localURL.absoluteString
                    ])
                    albumUploadItems.append(AlbumUploadItem(
                        index: index,
                        localFileURL: localURL.path,
                        filename: filename,
                        messageType: "image",
                        cropAspect: nil,
                        cachedMediaId: nil
                    ))
                    nextIndex += 1

                case .video(let url):
                    hasVideo = true
                    let storageResult = MediaStorageManager.shared.saveVideo(from: url, messageId: itemKey)
                    guard case .success(let localURL) = storageResult else { continue }

                    var thumbnailPath: String? = nil
                    if let thumbnail = MediaStorageManager.shared.generateThumbnailFromVideoFile(messageId: itemKey) {
                        if case .success(let thumbURL) = MediaStorageManager.shared.saveVideoThumbnail(thumbnail, messageId: itemKey) {
                            thumbnailPath = thumbURL.absoluteString
                        }
                        InMemoryMediaCache.shared.cacheImage(thumbnail, for: itemKey)
                    }

                    let filename = "video_\(Int(Date().timeIntervalSince1970))_\(index).mp4"
                    var entry: [String: Any] = [
                        "id": itemKey,
                        "url": localURL.absoluteString,
                        "type": "video",
                        "fileName": filename
                    ]
                    if let thumbnailPath {
                        entry["thumbnail"] = thumbnailPath
                    }
                    mediaEntries.append(entry)
                    albumUploadItems.append(AlbumUploadItem(
                        index: index,
                        localFileURL: localURL.path,
                        filename: filename,
                        messageType: "video",
                        cropAspect: nil,
                        cachedMediaId: nil
                    ))
                    nextIndex += 1
                }
            }

            guard mediaEntries.count > 1, albumUploadItems.count == mediaEntries.count else {
                // Fall back to individual sends if album prep failed
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    for item in capped {
                        switch item {
                        case .image(let image): self.sendImage(image)
                        case .video(let url): self.sendVideo(url)
                        }
                    }
                }
                return
            }

            let messageType = mediaEntries.count > 1 ? "image" : (hasVideo ? "video" : "image")
            let firstURL = (mediaEntries.first?["url"] as? String) ?? ""

            await MainActor.run { [weak self] in
                guard let self = self, let ctx = self.context else { return }

                var optimisticDict: [String: Any] = [
                    "id": tempId,
                    (isChannel ? "channelId" : "conversationId"): (isChannel ? channelId : selectedId),
                    "content": firstURL,
                    "messageType": messageType,
                    "senderId": senderId,
                    "createdAt": nowISO,
                    "updatedAt": nowISO,
                    "isEdited": false,
                    "isDeleted": false,
                    "status": "sending",
                    "localMediaURL": firstURL,
                    "isTemporary": true,
                    "clientMessageId": tempId,
                    "metadata": [
                        "clientTempId": tempId,
                        "isTemporary": true
                    ],
                    "media": mediaEntries
                ]
                if let thumb = mediaEntries.first?["thumbnail"] as? String {
                    optimisticDict["thumbnail"] = thumb
                }
                if let reply = replyDict {
                    optimisticDict["replyToId"] = reply
                }

                if let optimistic = ConversationMessage.fromDictionary(optimisticDict) {
                    ctx.stateManager.addMessages([optimistic])
                    ctx.tempMessageMapping[tempId] = optimistic
                    ctx.shouldAutoScroll = true
                    PendingMessageStore.shared.save(tempId: tempId, message: optimistic, conversationId: selectedId)

                    let snapshot = ctx.stateManager.getGroupedMessagesSnapshot()
                    if snapshot != ctx.groupedMessages {
                        ctx.groupedMessages = snapshot
                        ctx.handleMessageListUpdate(snapshot.flatMap { $0.messages })
                    }
                }

                ctx.activeMediaUploads.insert(tempId)
                let uploadTask = UploadTask(
                    tempId: tempId,
                    conversationId: selectedId,
                    messageType: messageType,
                    localFileURL: albumUploadItems[0].localFileURL,
                    filename: albumUploadItems[0].filename,
                    filesize: "0",
                    replyToId: replyToId,
                    senderId: senderId,
                    createdAt: nowISO,
                    isChannel: isChannel,
                    channelId: channelId,
                    cropAspect: nil,
                    status: .pending,
                    albumItems: albumUploadItems
                )
                BackgroundUploadService.shared.enqueue(uploadTask)
                ctx.replyingToMessage = nil
            }
        }
    }

    // MARK: - Media Cache

    func getCachedMediaData(for messageId: String) -> Data? {
        guard let ctx = context else { return nil }

        // Priority 1: Check Documents directory for images
        if let _ = MediaStorageManager.shared.getMediaURL(messageId: messageId, type: .image) {
            let result = MediaStorageManager.shared.loadMedia(messageId: messageId, type: .image)
            if case .success(let data) = result {
                return data
            }
        }

        // Priority 2: Check Documents directory for videos
        if let _ = MediaStorageManager.shared.getMediaURL(messageId: messageId, type: .video) {
            if let thumbnail = MediaStorageManager.shared.getVideoThumbnail(messageId: messageId),
               let thumbnailData = thumbnail.jpegData(compressionQuality: 0.7) {
                return thumbnailData
            }
            return Data()
        }

        // Priority 3: Check Documents directory for audio
        if let _ = MediaStorageManager.shared.getMediaURL(messageId: messageId, type: .audio) {
            let result = MediaStorageManager.shared.loadMedia(messageId: messageId, type: .audio)
            if case .success(let data) = result {
                return data
            }
        }

        // Priority 4: Check temp messages with local file URLs
        if let tempMessage = ctx.tempMessageMapping[messageId],
           let contentURL = tempMessage.content,
           let url = URL(string: contentURL),
           url.isFileURL {
            return try? Data(contentsOf: url)
        }

        // Priority 5: Check existing messages with local file URLs
        if let message = ctx.messages.first(where: { $0.id == messageId }),
           let contentURL = message.content,
           let url = URL(string: contentURL),
           url.isFileURL {
            return try? Data(contentsOf: url)
        }

        // Priority 6: in-memory cache
        return mediaCacheData[messageId]
    }

    func mediaCacheFirstMatch(forKeyLike key: String) -> Data? {
        if let match = mediaCacheData.first(where: { (k, _) in key.contains(k) || k.contains(key) }) {
            return match.value
        }
        return nil
    }

    func setCachedMediaData(for messageId: String, data: Data) {
        if mediaCacheData[messageId] == nil {
            mediaCacheInsertionOrder.append(messageId)
        }
        mediaCacheData[messageId] = data
        while mediaCacheInsertionOrder.count > maxMediaCacheCount {
            let oldest = mediaCacheInsertionOrder.removeFirst()
            mediaCacheData.removeValue(forKey: oldest)
        }
    }

    func transferCachedMedia(from oldKey: String, to newKey: String) {
        if let cached = mediaCacheData[oldKey] {
            mediaCacheData[newKey] = cached
            mediaCacheData.removeValue(forKey: oldKey)
        }
    }

    func removeCachedMediaData(for messageId: String) {
        mediaCacheData.removeValue(forKey: messageId)
        mediaCacheInsertionOrder.removeAll { $0 == messageId }
    }

    // MARK: - Media Refresh

    func updateExistingMessagesWithFreshMedia(_ freshMessages: [ConversationMessage]) {
        guard let ctx = context else { return }
        for freshMessage in freshMessages {
            if let existingIndex = ctx.messages.firstIndex(where: { $0.id == freshMessage.id }),
               ctx.mediaService.hasMediaURLChanges(existing: ctx.messages[existingIndex], fresh: freshMessage) {
                ctx.stateManager.updateMessage(freshMessage)
                autoDownloadMediaIfNeeded(freshMessage)
            }
        }
    }

    func autoDownloadMediaIfNeeded(_ message: ConversationMessage) {
        guard let ctx = context else { return }
        let messageId = message.id
        guard !messageId.isEmpty else { return }

        let senderId = message.sender?.id ?? message.senderId ?? ""
        if senderId == ctx.getCurrentUserId() {
            return
        }

        let messageType = (message.messageType ?? message.type ?? "").lowercased()
        guard messageType == "image" || messageType == "video" || messageType == "audio" else {
            return
        }

        MediaStorageManager.shared.autoDownloadIfNeeded(message: message)
    }

    func upgradeMediaContentIfNeeded(_ message: ConversationMessage) {
        // No-op: backend now provides CDN links directly, no manual presigned URL needed
    }

    // MARK: - Helpers

    func getFileSize(for url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[FileAttributeKey.size] as? UInt64 ?? 0
            return "\(fileSize)"
        } catch {
            return "0"
        }
    }

    func saveMediaToGallery(messageId: String, type: MediaStorageType, completion: @escaping (Bool, String?) -> Void) {
        MediaStorageManager.shared.saveToGallery(messageId: messageId, type: type) { result in
            switch result {
            case .success:
                completion(true, nil)
            case .failure(let error):
                completion(false, error.localizedDescription)
            }
        }
    }

    // retryMediaUpload removed — handled by BackgroundUploadService

    // MARK: - Cleanup

    func clearCache() {
        mediaCacheData.removeAll()
        mediaCacheInsertionOrder.removeAll()
    }

    nonisolated private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }

        let aspectRatio = size.width / size.height
        let newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Reply Data Helper

    private func replyData(for ctx: MediaManagerContext) -> [String: Any]? {
        guard let r = ctx.replyingToMessage else { return nil }
        let senderId = r.sender?.id ?? r.senderId ?? ""
        let resolvedName = ctx.resolvedDisplayName(for: senderId)
        let fullName = r.sender?.fullName ?? r.sender?.userDetails?.dataValues?.fullName ?? (resolvedName.contains(" ") ? resolvedName : "")
        let userName = r.sender?.userName ?? r.sender?.userDetails?.dataValues?.userName ?? (resolvedName.contains(" ") ? "" : resolvedName)
        let resolvedFullName = fullName.isEmpty ? resolvedName : fullName
        let resolvedUserName = userName.isEmpty ? resolvedName : userName
        return [
            "id": r.id ?? "",
            "content": r.content ?? "",
            "type": r.messageType ?? r.type ?? "text",
            "sender": [
                "id": senderId,
                "userName": resolvedUserName,
                "fullName": resolvedFullName
            ] as [String: Any]
        ] as [String: Any]
    }
}
