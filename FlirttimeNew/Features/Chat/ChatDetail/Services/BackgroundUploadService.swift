//
//  BackgroundUploadService.swift
//  FlirttimeNew
//

import Foundation
import Combine
import Swinject
import RxSwift

// MARK: - Models

enum UploadTaskStatus: String, Codable {
    case pending
    case compressing
    case gettingURL
    case uploading
    case sending
    case completed
    case failed
}

/// One item inside a multi-media album upload (WhatsApp-style).
struct AlbumUploadItem: Codable {
    let index: Int
    let localFileURL: String
    let filename: String
    let messageType: String // "image" | "video"
    let cropAspect: Double?
    var cachedMediaId: String?
}

struct UploadTask: Codable {
    let tempId: String
    let conversationId: String
    let messageType: String        // "image" | "video"
    let localFileURL: String
    let filename: String
    let filesize: String
    let replyToId: String?
    let senderId: String
    let createdAt: String
    let isChannel: Bool
    let channelId: String
    let cropAspect: Double?
    var status: UploadTaskStatus
    var retryCount: Int = 0
    /// When non-empty, upload all items then send one message with every mediaId.
    var albumItems: [AlbumUploadItem]? = nil

    var isAlbum: Bool { (albumItems?.count ?? 0) > 1 }
}

struct UploadResult {
    let tempId: String
    let conversationId: String
    let serverMessage: ConversationMessage
    let messageType: String
}

// MARK: - Concurrency Limiter

private actor UploadConcurrencyLimiter {
    private var activeCount = 0
    private let maxConcurrent: Int
    private var waiters: [CheckedContinuation<Void, Error>] = []

    init(maxConcurrent: Int = 3) {
        self.maxConcurrent = maxConcurrent
    }

    func acquire() async throws {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func cancelWaiting() {
        for waiter in waiters {
            waiter.resume(throwing: CancellationError())
        }
        waiters.removeAll()
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            activeCount = max(activeCount - 1, 0)
        }
    }

    /// Reset after stuck-task cancellation so waiting uploads are not blocked forever.
    func reset() {
        for waiter in waiters {
            waiter.resume(throwing: CancellationError())
        }
        waiters.removeAll()
        activeCount = 0
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let backgroundUploadDidComplete = Notification.Name("BackgroundUploadDidComplete")
}

// MARK: - BackgroundUploadService

@MainActor
final class BackgroundUploadService: ObservableObject {

    static let shared = BackgroundUploadService()

    // MARK: - Events

    let taskProgressChanged = PassthroughSubject<String, Never>()       // tempId
    let uploadDidComplete = PassthroughSubject<UploadResult, Never>()

    // MARK: - State

    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var taskStatuses: [String: UploadTaskStatus] = [:]
    private var acquiredSlots: Set<String> = []
    private let limiter = UploadConcurrencyLimiter(maxConcurrent: 3)
    private var socketListenerIds: [UUID] = []
    private var cancellables = Set<AnyCancellable>()
    private let sessionManager: SessionManager?

    private var isListeningForAcks = false

    // MARK: - Init

    private init() {
        self.sessionManager = Container.sharedContainer.resolve(SessionManager.self)
    }

    // MARK: - Public API

    func enqueue(_ task: UploadTask) {
        guard activeTasks[task.tempId] == nil else {
            AppLogger.debug("[BGUpload] Already enqueued: \(task.tempId)")
            return
        }
        taskStatuses[task.tempId] = task.status
        startListeningForAcks()

        let uploadTask = Task { [weak self] in
            guard let self else { return }
            await self.runUpload(task: task)
        }
        activeTasks[task.tempId] = uploadTask
        taskProgressChanged.send(task.tempId)
    }

    func cancel(tempId: String) {
        activeTasks[tempId]?.cancel()
        activeTasks.removeValue(forKey: tempId)
        taskStatuses.removeValue(forKey: tempId)
        retryCounts.removeValue(forKey: tempId)
        if acquiredSlots.remove(tempId) != nil {
            Task { await limiter.release() }
        }

        // Clean up local media files
        let types: [MediaStorageType] = [.image, .video]
        for type in types {
            if let url = MediaStorageManager.shared.getMediaURL(messageId: tempId, type: type) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        // Album item files
        for i in 0..<10 {
            for type in types {
                if let url = MediaStorageManager.shared.getMediaURL(messageId: "\(tempId)_\(i)", type: type) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            InMemoryMediaCache.shared.remove(key: "\(tempId)_\(i)")
        }
        InMemoryMediaCache.shared.remove(key: tempId)
        InMemoryMediaCache.shared.remove(key: tempId + "_thumb")
    }

    func retry(tempId: String) {
        // Allow retry of failed tasks, or re-enqueue tasks from PendingMessageStore
        let entry = PendingMessageStore.shared.pendingMessagesForAll()
            .first(where: { $0.tempId == tempId })
        guard let entry else { return }
        // Cancel any existing task
        activeTasks[tempId]?.cancel()
        activeTasks.removeValue(forKey: tempId)
        taskStatuses.removeValue(forKey: tempId)
        retryCounts.removeValue(forKey: tempId)

        var task = taskFromMessage(tempId: tempId, message: entry.message, conversationId: entry.conversationId)
        task.retryCount = 0
        task.status = .pending
        enqueue(task)
    }

    func status(for tempId: String) -> UploadTaskStatus? {
        taskStatuses[tempId]
    }

    func activeTaskIds(for conversationId: String) -> Set<String> {
        let ids = taskStatuses.filter { $0.value != .completed && $0.value != .failed }
            .compactMap { tempId, status -> String? in
                guard status != .completed && status != .failed else { return nil }
                return tempId
            }
        // Can't easily filter by conversationId from status alone, return all active
        return Set(ids)
    }

    func isActive(tempId: String) -> Bool {
        activeTasks[tempId] != nil && taskStatuses[tempId] != .completed && taskStatuses[tempId] != .failed
    }

    func cancelStuckTasks() {
        let stuckStates: Set<UploadTaskStatus> = [.gettingURL, .uploading, .compressing]
        var releasedAny = false
        for (tempId, status) in taskStatuses where stuckStates.contains(status) {
            AppLogger.debug("[BGUpload] Cancelling stuck task \(tempId) in state \(status.rawValue)")
            activeTasks[tempId]?.cancel()
            activeTasks.removeValue(forKey: tempId)
            taskStatuses.removeValue(forKey: tempId)
            retryCounts.removeValue(forKey: tempId)
            if acquiredSlots.remove(tempId) != nil {
                releasedAny = true
            }
        }
        if releasedAny {
            Task { await limiter.reset() }
        }
    }

    func restorePendingUploads() {
        let pending = PendingMessageStore.shared.pendingMessagesForAll()
        let mediaTypes: Set<String> = ["image", "video"]

        for entry in pending {
            let type = (entry.message.messageType ?? entry.message.type ?? "text").lowercased()
            guard mediaTypes.contains(type) else { continue }
            guard entry.message.status != "failed" else { continue }
            guard activeTasks[entry.tempId] == nil else { continue }

            let isAlbum = (entry.message.media?.count ?? 0) > 1
            if isAlbum {
                let hasAnyFile = (entry.message.media ?? []).enumerated().contains { index, item in
                    let itemType = (item.type ?? type).lowercased()
                    let storage: MediaStorageType = itemType == "video" ? .video : .image
                    return MediaStorageManager.shared.getMediaURL(messageId: "\(entry.tempId)_\(index)", type: storage) != nil
                }
                guard hasAnyFile else {
                    AppLogger.debug("[BGUpload] restorePending: no album files for \(entry.tempId)")
                    continue
                }
            } else {
                let localPath = resolveLocalMediaPath(tempId: entry.tempId, messageType: type)
                guard localPath != nil else {
                    AppLogger.debug("[BGUpload] restorePending: no local file for \(entry.tempId)")
                    continue
                }
            }

            let task = taskFromMessage(tempId: entry.tempId, message: entry.message, conversationId: entry.conversationId)
            enqueue(task)
            AppLogger.debug("[BGUpload] Restored pending upload: \(entry.tempId) type=\(type) album=\(isAlbum)")
        }
    }

    // MARK: - Core Upload Flow

    private func runUpload(task: UploadTask) async {
        do {
            try await limiter.acquire()
            acquiredSlots.insert(task.tempId)
        } catch {
            return
        }

        await performUpload(task: task)

        if acquiredSlots.remove(task.tempId) != nil {
            await limiter.release()
        }
    }

    private func performUpload(task: UploadTask) async {
        if task.isAlbum {
            await runAlbumUpload(task: task)
            return
        }

        var currentTask = task

        // Check if media upload was already completed in a previous attempt
        let cachedMediaId: String? = PendingMessageStore.shared
            .pendingMessagesForAll()
            .first(where: { $0.tempId == currentTask.tempId })?
            .message.metadata?["cachedMediaId"]?.value as? String
            ?? PendingMessageStore.shared
            .pendingMessagesForAll()
            .first(where: { $0.tempId == currentTask.tempId })?
            .message.metadata?["cachedS3Key"]?.value as? String
        let cachedFileSize: String? = PendingMessageStore.shared
            .pendingMessagesForAll()
            .first(where: { $0.tempId == currentTask.tempId })?
            .message.metadata?["cachedFileSize"]?.value as? String

        if let mediaId = cachedMediaId, !mediaId.isEmpty {
            AppLogger.debug("[BGUpload] Skipping upload for \(currentTask.tempId) — using cached mediaId")
            updateStatus(tempId: currentTask.tempId, status: .sending)
            await sendMediaMessageREST(
                task: currentTask,
                mediaIds: [mediaId],
                filename: currentTask.filename,
                filesize: cachedFileSize ?? currentTask.filesize
            )
            return
        }

        // Step 1: Validate local file exists
        let fileURL = URL(fileURLWithPath: currentTask.localFileURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            markFailed(tempId: currentTask.tempId, reason: "local file missing")
            return
        }

        // Step 2: Compress video if needed
        var uploadFileURL = fileURL
        var compressedFileSize = currentTask.filesize
        var isCompressedCopy = false

        if currentTask.messageType == "video" {
            updateStatus(tempId: currentTask.tempId, status: .compressing)

            let originalSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0

            do {
                let result = try await VideoCompressor.shared.compress(fileURL, cropAspect: currentTask.cropAspect.map { CGFloat($0) })
                uploadFileURL = result.url
                compressedFileSize = "\(result.fileSize)"
                isCompressedCopy = result.isCompressedCopy
                AppLogger.debug("[BGUpload] Video compressed: \(MediaStorageManager.shared.formatBytes(originalSize)) → \(MediaStorageManager.shared.formatBytes(result.fileSize))")
            } catch {
                AppLogger.debug("[BGUpload] Video compression skipped: \(error.localizedDescription)")
            }
        }

        guard !Task.isCancelled else { return }

        // Step 3–4: NEW media pipeline — media/images or media/uploads (purpose: chat) → mediaId
        updateStatus(tempId: currentTask.tempId, status: .uploading)

        guard let mediaId = await uploadChatMedia(task: currentTask, fileURL: uploadFileURL) else {
            if isCompressedCopy {
                try? FileManager.default.removeItem(at: uploadFileURL)
            }
            markFailed(tempId: currentTask.tempId, reason: "media upload failed")
            return
        }

        if isCompressedCopy {
            try? FileManager.default.removeItem(at: uploadFileURL)
        }

        // Cache mediaId so retry can skip upload
        if let entry = PendingMessageStore.shared.pendingMessagesForAll()
            .first(where: { $0.tempId == currentTask.tempId }) {
            var updatedMsg = entry.message
            var meta = updatedMsg.metadata ?? [:]
            meta["cachedMediaId"] = AnyCodable(mediaId)
            meta["cachedFileSize"] = AnyCodable(compressedFileSize)
            updatedMsg.metadata = meta
            PendingMessageStore.shared.save(
                tempId: currentTask.tempId, message: updatedMsg,
                conversationId: entry.conversationId)
        }

        guard !Task.isCancelled else { return }

        // Guard against deletion after upload completed
        guard activeTasks[currentTask.tempId] != nil else { return }

        // Step 5: POST chat/messages with mediaIds (FE parity)
        updateStatus(tempId: currentTask.tempId, status: .sending)

        await sendMediaMessageREST(
            task: currentTask,
            mediaIds: [mediaId],
            filename: currentTask.filename,
            filesize: compressedFileSize
        )
    }

    /// Upload every album item, then send one chat message with all mediaIds.
    private func runAlbumUpload(task: UploadTask) async {
        guard var items = task.albumItems, !items.isEmpty else {
            markFailed(tempId: task.tempId, reason: "empty album")
            return
        }

        // Restore any previously uploaded mediaIds from metadata
        if let entry = PendingMessageStore.shared.pendingMessagesForAll()
            .first(where: { $0.tempId == task.tempId }),
           let cached = entry.message.metadata?["cachedAlbumMediaIds"]?.value as? [String],
           cached.count == items.count,
           cached.allSatisfy({ !$0.isEmpty }) {
            AppLogger.debug("[BGUpload] Album \(task.tempId) using cached mediaIds")
            updateStatus(tempId: task.tempId, status: .sending)
            await sendMediaMessageREST(
                task: task,
                mediaIds: cached,
                filename: task.filename,
                filesize: task.filesize
            )
            return
        }

        updateStatus(tempId: task.tempId, status: .uploading)
        var mediaIds = Array(repeating: "", count: items.count)

        for i in items.indices {
            guard !Task.isCancelled else { return }
            guard activeTasks[task.tempId] != nil else { return }

            if let cached = items[i].cachedMediaId, !cached.isEmpty {
                mediaIds[i] = cached
                continue
            }

            let item = items[i]
            let fileURL = URL(fileURLWithPath: item.localFileURL)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                markFailed(tempId: task.tempId, reason: "album item \(i) missing")
                return
            }

            var uploadFileURL = fileURL
            var isCompressedCopy = false
            if item.messageType == "video" {
                updateStatus(tempId: task.tempId, status: .compressing)
                do {
                    let result = try await VideoCompressor.shared.compress(
                        fileURL,
                        cropAspect: item.cropAspect.map { CGFloat($0) }
                    )
                    uploadFileURL = result.url
                    isCompressedCopy = result.isCompressedCopy
                } catch {
                    AppLogger.debug("[BGUpload] Album video compress skipped [\(i)]: \(error.localizedDescription)")
                }
            }

            updateStatus(tempId: task.tempId, status: .uploading)
            let itemTask = UploadTask(
                tempId: "\(task.tempId)_\(i)",
                conversationId: task.conversationId,
                messageType: item.messageType,
                localFileURL: uploadFileURL.path,
                filename: item.filename,
                filesize: "0",
                replyToId: nil,
                senderId: task.senderId,
                createdAt: task.createdAt,
                isChannel: task.isChannel,
                channelId: task.channelId,
                cropAspect: item.cropAspect,
                status: .uploading
            )

            guard let mediaId = await uploadChatMedia(task: itemTask, fileURL: uploadFileURL) else {
                if isCompressedCopy { try? FileManager.default.removeItem(at: uploadFileURL) }
                markFailed(tempId: task.tempId, reason: "album item \(i) upload failed")
                return
            }
            if isCompressedCopy { try? FileManager.default.removeItem(at: uploadFileURL) }

            mediaIds[i] = mediaId
            items[i].cachedMediaId = mediaId

            // Persist progress so retry can skip finished items
            if let entry = PendingMessageStore.shared.pendingMessagesForAll()
                .first(where: { $0.tempId == task.tempId }) {
                var updatedMsg = entry.message
                var meta = updatedMsg.metadata ?? [:]
                meta["cachedAlbumMediaIds"] = AnyCodable(mediaIds)
                updatedMsg.metadata = meta
                PendingMessageStore.shared.save(
                    tempId: task.tempId,
                    message: updatedMsg,
                    conversationId: entry.conversationId
                )
            }
        }

        guard mediaIds.allSatisfy({ !$0.isEmpty }) else {
            markFailed(tempId: task.tempId, reason: "album incomplete uploads")
            return
        }

        guard !Task.isCancelled, activeTasks[task.tempId] != nil else { return }

        updateStatus(tempId: task.tempId, status: .sending)
        await sendMediaMessageREST(
            task: task,
            mediaIds: mediaIds,
            filename: task.filename,
            filesize: task.filesize
        )
    }

    // MARK: - Socket Ack Handling

    private func startListeningForAcks() {
        guard !isListeningForAcks else { return }
        isListeningForAcks = true

        // Listen for conversation message acks
        let convId = ChatSocketManager.shared.listenToEvent(SocketEvent.sendConversationMessageAck.rawValue) { [weak self] data in
            Task { @MainActor in
                self?.handleSocketAck(data: data)
            }
        }

        // Listen for channel message acks
        let chanId = ChatSocketManager.shared.listenToEvent(SocketEvent.sendMessageToChannelAck.rawValue) { [weak self] data in
            Task { @MainActor in
                self?.handleChannelAck(data: data)
            }
        }

        socketListenerIds = [convId, chanId]
    }

    private func handleSocketAck(data: [Any]) {
        guard let message = SocketAckParser.parseMessage(from: data),
              let ack = data.first as? [String: Any],
              let messageData = SocketAckParser.messagePayload(from: ack) else { return }

        // Find matching task by clientTempId — could be in metadata or at top level
        let metadata = messageData["metadata"] as? [String: Any]
        let clientTempId = metadata?["clientTempId"] as? String
            ?? messageData["clientMsgId"] as? String
            ?? messageData["clientTempId"] as? String
            ?? message.metadata?["clientTempId"]?.value as? String
            ?? ""

        guard !clientTempId.isEmpty, activeTasks[clientTempId] != nil else { return }

        // Cancel the ack timeout (task will see status changed and exit)
        updateStatus(tempId: clientTempId, status: .completed)

        finalizeUpload(tempId: clientTempId, serverMessage: message)
    }

    private func handleChannelAck(data: [Any]) {
        guard let ack = data.first as? [String: Any],
              SocketAckParser.isSuccess(ack) || ack["data"] != nil,
              let ackData = SocketAckParser.messagePayload(from: ack) ?? (ack["data"] as? [String: Any]) else { return }

        let metaObj = ackData["metadata"] as? [String: Any]
        let clientTempId = metaObj?["clientTempId"] as? String
            ?? ackData["clientMsgId"] as? String
            ?? ackData["clientTempId"] as? String
            ?? ""
        guard !clientTempId.isEmpty, activeTasks[clientTempId] != nil else { return }

        var merged: [String: Any] = ackData
        // Channel acks don't always include channelId — preserve from task
        merged["channelId"] = merged["channelId"] ?? nil
        merged["status"] = "sent"
        merged["statuses"] = nil
        if (merged["sentAt"] as? String ?? "").isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            merged["sentAt"] = formatter.string(from: Date())
        }

        guard let serverMessage = ConversationMessage.fromDictionary(merged) else { return }
        updateStatus(tempId: clientTempId, status: .completed)
        finalizeUpload(tempId: clientTempId, serverMessage: serverMessage)
    }

    // MARK: - Finalization

    private func finalizeUpload(tempId: String, serverMessage: ConversationMessage) {
        let serverId = serverMessage.id
        let messageType = (serverMessage.messageType ?? serverMessage.type ?? "").lowercased()
        let albumCount = serverMessage.media?.count
            ?? (PendingMessageStore.shared.pendingMessagesForAll()
                .first(where: { $0.tempId == tempId })?.message.media?.count)

        if let count = albumCount, count > 1 {
            for i in 0..<count {
                let fromKey = "\(tempId)_\(i)"
                let toKey = "\(serverId)_\(i)"
                let itemType = serverMessage.media?[i].type?.lowercased()
                    ?? (PendingMessageStore.shared.pendingMessagesForAll()
                        .first(where: { $0.tempId == tempId })?.message.media?[i].type?.lowercased())
                let storageType: MediaStorageType = itemType == "video" ? .video : .image
                if case .success = MediaStorageManager.shared.moveMedia(from: fromKey, to: toKey, type: storageType) {
                    if storageType == .video {
                        MediaStorageManager.shared.moveVideoThumbnail(from: fromKey, to: toKey)
                    }
                }
                InMemoryMediaCache.shared.transfer(from: fromKey, to: toKey)
            }
            InMemoryMediaCache.shared.transfer(from: tempId, to: serverId)
        } else if messageType == "image" {
            let moveResult = MediaStorageManager.shared.moveMedia(from: tempId, to: serverId, type: .image)
            if case .failure = moveResult {
                // Fallback: try saving from InMemoryMediaCache
                if let image = InMemoryMediaCache.shared.getCachedImage(for: tempId),
                   let data = image.jpegData(compressionQuality: 0.8) {
                    _ = MediaStorageManager.shared.saveMedia(data: data, messageId: serverId, type: .image)
                }
            }
        } else if messageType == "video" {
            let moveResult = MediaStorageManager.shared.moveMedia(from: tempId, to: serverId, type: .video)
            if case .success = moveResult {
                MediaStorageManager.shared.moveVideoThumbnail(from: tempId, to: serverId)
            }
        }

        // Transfer in-memory cache
        InMemoryMediaCache.shared.transfer(from: tempId, to: serverId)
        InMemoryMediaCache.shared.transfer(from: tempId + "_thumb", to: serverId + "_thumb")

        // Save to CoreData
        let repo = MessageRepository()
        Task {
            try? await repo.saveMessages([serverMessage], conversationId: serverMessage.conversationId)
        }

        // Remove from PendingMessageStore
        PendingMessageStore.shared.remove(tempId: tempId)

        // Clean up task
        activeTasks.removeValue(forKey: tempId)

        // Notify: active ChatDetailViewModels replace their temp message
        let result = UploadResult(
            tempId: tempId,
            conversationId: serverMessage.conversationId ?? "",
            serverMessage: serverMessage,
            messageType: messageType
        )
        uploadDidComplete.send(result)
        taskProgressChanged.send(tempId)

        // Notify: ChatListViewModel updates last message
        NotificationCenter.default.post(
            name: .backgroundUploadDidComplete,
            object: nil,
            userInfo: ["result": result]
        )

        // Also post ChatLastMessageUpdated so chat list refreshes
        if !serverMessage.conversationId.isEmpty {
            NotificationCenter.default.post(
                name: NSNotification.Name("ChatLastMessageUpdated"),
                object: nil,
                userInfo: ["conversationId": serverMessage.conversationId, "message": serverMessage]
            )
        }

        AppLogger.debug("[BGUpload] Finalized: \(tempId) → \(serverId)")
    }

    // MARK: - REST Send after media upload

    private func sendMediaMessageREST(task: UploadTask, mediaIds: [String], filename: String, filesize: String) async {
        let resolvedType = mediaIds.count > 1 ? "image" : task.messageType
        if task.isChannel {
            await sendChannelMediaMessageREST(task: task, mediaIds: mediaIds, messageType: resolvedType)
            return
        }

        guard let sessionManager else {
            markFailed(tempId: task.tempId, reason: "no session")
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _ = sessionManager.sendChatMessage(
                conversationId: task.conversationId,
                body: nil,
                type: resolvedType,
                mediaIds: mediaIds,
                location: nil,
                poll: nil,
                postId: nil,
                clientMessageId: task.tempId,
                replyToId: task.replyToId
            )
            .subscribe(
                onSuccess: { [weak self] message in
                    Task { @MainActor in
                        guard let self else {
                            continuation.resume()
                            return
                        }
                        var serverMessage = message
                        var meta = serverMessage.metadata ?? [:]
                        if meta["clientTempId"] == nil {
                            meta["clientTempId"] = AnyCodable(task.tempId)
                            serverMessage.metadata = meta
                        }
                        let statusLower = (serverMessage.status ?? "").lowercased()
                        if statusLower.isEmpty || statusLower == "sending" || statusLower == "pending" {
                            serverMessage.status = "sent"
                        }
                        self.updateStatus(tempId: task.tempId, status: .completed)
                        self.finalizeUpload(tempId: task.tempId, serverMessage: serverMessage)
                        continuation.resume()
                    }
                },
                onFailure: { [weak self] error in
                    Task { @MainActor in
                        AppLogger.debug("[BGUpload] REST send failed: \(error.localizedDescription)")
                        self?.markFailed(tempId: task.tempId, reason: "rest send failed")
                        continuation.resume()
                    }
                }
            )
        }
    }

    /// FE: POST chat/channels/messages with mediaIds
    private func sendChannelMediaMessageREST(task: UploadTask, mediaIds: [String], messageType: String) async {
        guard let sessionManager else {
            markFailed(tempId: task.tempId, reason: "no session")
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _ = sessionManager.sendChannelChatMessage(
                channelId: task.channelId,
                body: nil,
                type: messageType,
                mediaIds: mediaIds,
                clientMessageId: task.tempId,
                replyToId: task.replyToId
            )
            .subscribe(
                onSuccess: { [weak self] message in
                    Task { @MainActor in
                        guard let self else {
                            continuation.resume()
                            return
                        }
                        var serverMessage = message
                        var meta = serverMessage.metadata ?? [:]
                        if meta["clientTempId"] == nil {
                            meta["clientTempId"] = AnyCodable(task.tempId)
                            serverMessage.metadata = meta
                        }
                        let statusLower = (serverMessage.status ?? "").lowercased()
                        if statusLower.isEmpty || statusLower == "sending" || statusLower == "pending" {
                            serverMessage.status = "sent"
                        }
                        self.updateStatus(tempId: task.tempId, status: .completed)
                        self.finalizeUpload(tempId: task.tempId, serverMessage: serverMessage)
                        continuation.resume()
                    }
                },
                onFailure: { [weak self] error in
                    Task { @MainActor in
                        AppLogger.debug("[BGUpload] Channel REST send failed: \(error.localizedDescription)")
                        self?.markFailed(tempId: task.tempId, reason: "channel rest send failed")
                        continuation.resume()
                    }
                }
            )
        }
    }

    // MARK: - NEW Media Upload (purpose: chat)

    /// Uploads image/video via NEW media APIs and returns `mediaId` for `chat:message:send`.
    private func uploadChatMedia(task: UploadTask, fileURL: URL) async -> String? {
        guard let sessionManager else { return nil }

        if task.messageType == "video" {
            return await withCheckedContinuation { continuation in
                var resumed = false
                let finish: (String?) -> Void = { id in
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: id)
                }
                _ = sessionManager.uploadVideoFileViaChunkedUploads(
                    fileURL: fileURL,
                    purpose: "chat",
                    contentType: "video/mp4",
                    fileName: task.filename
                )
                .subscribe(
                    onSuccess: { mediaId in
                        AppLogger.debug("[BGUpload] Video mediaId=\(mediaId)")
                        finish(mediaId)
                    },
                    onFailure: { error in
                        AppLogger.debug("[BGUpload] Video upload failed: \(error.localizedDescription)")
                        finish(nil)
                    }
                )
            }
        }

        // Image — prefer media/images (purpose: chat), fallback media/uploads
        guard let imageData = try? Data(contentsOf: fileURL), !imageData.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            var resumed = false
            let finish: (String?) -> Void = { id in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: id)
            }

            _ = sessionManager.uploadPostImageDirect(imageData: imageData, purpose: "chat")
                .map { session -> String in
                    if let id = session.resolvedMediaId, !id.isEmpty { return id }
                    throw APIError.apiError("media/images did not return mediaId")
                }
                .catch { _ -> Single<String> in
                    sessionManager.uploadViaMediaUploadsSession(
                        data: imageData,
                        purpose: "chat",
                        kind: "image",
                        contentType: "image/jpeg",
                        fileName: task.filename
                    )
                }
                .subscribe(
                    onSuccess: { mediaId in
                        AppLogger.debug("[BGUpload] Image mediaId=\(mediaId)")
                        finish(mediaId)
                    },
                    onFailure: { error in
                        AppLogger.debug("[BGUpload] Image upload failed: \(error.localizedDescription)")
                        finish(nil)
                    }
                )
        }
    }

    // MARK: - Status Management

    private func updateStatus(tempId: String, status: UploadTaskStatus) {
        taskStatuses[tempId] = status
        taskProgressChanged.send(tempId)
    }

    private func markFailed(tempId: String, reason: String) {
        // Retry up to 2 times
        if let task = activeTasks[tempId] {
            // Check retry count from PendingMessageStore
            let currentRetry = retryCounts[tempId, default: 0]
            if currentRetry < 2 {
                retryCounts[tempId] = currentRetry + 1
                AppLogger.debug("[BGUpload] Retry \(currentRetry + 1)/2 for \(tempId): \(reason)")

                // Re-enqueue
                activeTasks.removeValue(forKey: tempId)
                taskStatuses.removeValue(forKey: tempId)

                if let entry = PendingMessageStore.shared.pendingMessagesForAll()
                    .first(where: { $0.tempId == tempId }) {
                    var retryTask = taskFromMessage(tempId: tempId, message: entry.message, conversationId: entry.conversationId)
                    retryTask.retryCount = currentRetry + 1
                    retryTask.status = .pending
                    enqueue(retryTask)
                }
                return
            }
        }

        retryCounts.removeValue(forKey: tempId)
        updateStatus(tempId: tempId, status: .failed)
        activeTasks.removeValue(forKey: tempId)

        // Update PendingMessageStore with failed status
        if let entry = PendingMessageStore.shared.pendingMessagesForAll()
            .first(where: { $0.tempId == tempId }) {
            var failedMessage = entry.message
            failedMessage.status = "failed"
            PendingMessageStore.shared.save(tempId: tempId, message: failedMessage, conversationId: entry.conversationId)
        }

        AppLogger.debug("[BGUpload] Failed: \(tempId) — \(reason)")
    }

    private var retryCounts: [String: Int] = [:]

    // MARK: - Task Construction Helpers

    private func taskFromMessage(tempId: String, message: ConversationMessage, conversationId: String) -> UploadTask {
        let type = (message.messageType ?? message.type ?? "text").lowercased()
        let channelId = message.channelId ?? ""
        let isChannel = !channelId.isEmpty

        var albumItems: [AlbumUploadItem]? = nil
        if let media = message.media, media.count > 1 {
            albumItems = media.enumerated().compactMap { index, item in
                let itemType = (item.type ?? type).lowercased()
                let storageType: MediaStorageType = itemType == "video" ? .video : .image
                let key = "\(tempId)_\(index)"
                guard let path = MediaStorageManager.shared.getMediaURL(messageId: key, type: storageType)?.path
                        ?? (item.url.flatMap { URL(string: $0) }?.isFileURL == true ? URL(string: item.url!)?.path : nil)
                else { return nil }
                let cachedIds = message.metadata?["cachedAlbumMediaIds"]?.value as? [String]
                return AlbumUploadItem(
                    index: index,
                    localFileURL: path,
                    filename: item.fileName ?? (itemType == "video" ? "video_\(index).mp4" : "image_\(index).jpg"),
                    messageType: itemType == "video" ? "video" : "image",
                    cropAspect: nil,
                    cachedMediaId: (cachedIds?.indices.contains(index) == true) ? cachedIds?[index] : nil
                )
            }
            if albumItems?.count != media.count {
                albumItems = nil
            }
        }

        let localPath = albumItems?.first?.localFileURL
            ?? resolveLocalMediaPath(tempId: tempId, messageType: type)
            ?? ""

        return UploadTask(
            tempId: tempId,
            conversationId: isChannel ? channelId : conversationId,
            messageType: type,
            localFileURL: localPath,
            filename: type == "image" ? "image_\(Int(Date().timeIntervalSince1970)).jpg" : "video_\(Int(Date().timeIntervalSince1970)).mp4",
            filesize: message.metadata?["filesize"]?.value as? String ?? "0",
            replyToId: message.replyToId?.id,
            senderId: message.senderId ?? message.sender?.id ?? "",
            createdAt: message.createdAt ?? "",
            isChannel: isChannel,
            channelId: channelId,
            cropAspect: nil,
            status: .pending,
            albumItems: albumItems
        )
    }

    private func resolveLocalMediaPath(tempId: String, messageType: String) -> String? {
        let type: MediaStorageType = messageType == "video" ? .video : .image
        if let url = MediaStorageManager.shared.getMediaURL(messageId: tempId, type: type) {
            return url.path
        }
        // Check if content URL is a local file
        if let entry = PendingMessageStore.shared.pendingMessagesForAll()
            .first(where: { $0.tempId == tempId }),
           let content = entry.message.content,
           let url = URL(string: content), url.isFileURL {
            return url.path
        }
        return nil
    }
}

// MARK: - PendingMessageStore Extension

extension PendingMessageStore {
    func pendingMessagesForAll() -> [(tempId: String, message: ConversationMessage, conversationId: String)] {
        return allPendingEntriesWithConversationId()
    }
}
