//
//  MediaStorageManager.swift
//  FlirttimeNew
//
//  Created by Awais on 30/09/25.
//

import Foundation
import UIKit
import Photos
import Combine
import AVFoundation

// MARK: - Media Storage Error

enum MediaStorageError: Error, LocalizedError {
    case invalidData
    case downloadFailed
    case saveFailed
    case fileNotFound
    case permissionDenied
    case diskSpaceInsufficient
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .invalidData: return "Invalid media data"
        case .downloadFailed: return "Failed to download media"
        case .saveFailed: return "Failed to save media"
        case .fileNotFound: return "Media file not found"
        case .permissionDenied: return "Permission denied to access media"
        case .diskSpaceInsufficient: return "Not enough storage space"
        case .invalidURL: return "Invalid media URL"
        }
    }
}

// MARK: - Media Type

enum MediaStorageType: String {
    case image = "Images"
    case video = "Videos"
    case audio = "Audio"
    case document = "Documents"
    
    var subdirectory: String {
        return "FlirtTimeChat/Media/\(rawValue)"
    }
    
    var fileExtension: String {
        switch self {
        case .image: return "jpg"
        case .video: return "mp4"
        case .audio: return "m4a"
        case .document: return "pdf"
        }
    }
}

// MARK: - Download Progress

struct MediaDownloadProgress {
    let messageId: String
    let progress: Double
    let totalBytes: Int64
    let downloadedBytes: Int64
}

// MARK: - Media Storage Manager

class MediaStorageManager: NSObject, ObservableObject {
        
    static let shared = MediaStorageManager()
        
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading: [String: Bool] = [:]

    private var downloadedMessageIds: Set<String> = []
    private let downloadedIdsQueue = DispatchQueue(label: "com.yandexgram.downloadedIds")
    private var failedDownloadIds = Set<String>()

    private let fileManager = FileManager.default
    private lazy var documentsDirectory: URL = {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()
    
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    private var downloadStorageTypes: [String: MediaStorageType] = [:]
    private let syncQueue = DispatchQueue(label: "com.yandexgram.mediaStorage.sync")
    private let maxConcurrentDownloads = 3
    private var pendingDownloads: [(urlString: String, messageId: String, type: MediaStorageType, completion: (Result<URL, MediaStorageError>) -> Void)] = []
    var backgroundSessionCompletionHandler: (() -> Void)?
    private static let backgroundSessionId = "com.yandexgram.mediaDownload.bg"
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionId)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.httpMaximumConnectionsPerHost = maxConcurrentDownloads

        let opQueue = OperationQueue()
        opQueue.maxConcurrentOperationCount = 1
        opQueue.underlyingQueue = DispatchQueue(label: "com.yandexgram.mediaDownload", qos: .utility)

        return URLSession(configuration: config, delegate: self, delegateQueue: opQueue)
    }()
    
    private var cancellables = Set<AnyCancellable>()

    private func setDownloadingState(_ isActive: Bool, for messageId: String) {
        let apply: () -> Void = { [weak self] in
            self?.isDownloading[messageId] = isActive
        }
        if Thread.isMainThread { apply() }
        else { DispatchQueue.main.async(execute: apply) }
    }

    private func setDownloadProgressValue(_ progress: Double, for messageId: String) {
        let apply: () -> Void = { [weak self] in
            self?.downloadProgress[messageId] = progress
        }
        if Thread.isMainThread { apply() }
        else { DispatchQueue.main.async(execute: apply) }
    }

    private func clearDownloadProgressValue(for messageId: String) {
        let apply: () -> Void = { [weak self] in
            self?.downloadProgress.removeValue(forKey: messageId)
        }
        if Thread.isMainThread { apply() }
        else { DispatchQueue.main.async(execute: apply) }
    }
    
    private override init() {
        super.init()
        setupMediaDirectories()
    }
        
    private func setupMediaDirectories() {
        let mediaTypes: [MediaStorageType] = [.image, .video, .audio, .document]
        
        for type in mediaTypes {
            let directory = documentsDirectory.appendingPathComponent(type.subdirectory)
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                AppLogger.debug("Created media directory: \(type.rawValue)")
            } catch {
                AppLogger.debug("Failed to create directory for \(type.rawValue): \(error)")
            }
        }
    }
        
    func getMediaPath(messageId: String, type: MediaStorageType) -> URL {
        let directory = documentsDirectory.appendingPathComponent(type.subdirectory)
        return directory.appendingPathComponent("\(messageId).\(type.fileExtension)")
    }
    
    func mediaExists(messageId: String, type: MediaStorageType) -> Bool {
        let path = getMediaPath(messageId: messageId, type: type)
        return fileManager.fileExists(atPath: path.path)
    }
    
    func getMediaURL(messageId: String, type: MediaStorageType) -> URL? {
        let path = getMediaPath(messageId: messageId, type: type)
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        return path
    }

    // Thumbnail helpers for video previews
    func getVideoThumbnailPath(messageId: String) -> URL {
        let directory = documentsDirectory.appendingPathComponent(MediaStorageType.video.subdirectory)
        return directory.appendingPathComponent("\(messageId)_thumb.jpg")
    }

    func videoThumbnailExists(messageId: String) -> Bool {
        let path = getVideoThumbnailPath(messageId: messageId)
        return fileManager.fileExists(atPath: path.path)
    }

    func getVideoThumbnail(messageId: String) -> UIImage? {
        let thumbPath = getVideoThumbnailPath(messageId: messageId)
        guard fileManager.fileExists(atPath: thumbPath.path) else { return nil }
        guard let data = try? Data(contentsOf: thumbPath) else { return nil }
        return UIImage(data: data)
    }

    func saveVideoThumbnail(_ image: UIImage, messageId: String) -> Result<URL, MediaStorageError> {
        let path = getVideoThumbnailPath(messageId: messageId)
        // Use slightly higher quality for thumbnails to avoid visible compression artifacts
        guard let imageData = image.jpegData(compressionQuality: 0.92) else {
            return .failure(.invalidData)
        }

        do {
            try imageData.write(to: path, options: [.atomic])
            return .success(path)
        } catch {
            return .failure(.saveFailed)
        }
    }

    func getImageThumbnailPath(messageId: String) -> URL {
        let directory = documentsDirectory.appendingPathComponent(MediaStorageType.image.subdirectory)
        return directory.appendingPathComponent("\(messageId)_thumb.jpg")
    }

    func imageThumbnailExists(messageId: String) -> Bool {
        let path = getImageThumbnailPath(messageId: messageId)
        return fileManager.fileExists(atPath: path.path)
    }

    func getImageThumbnail(messageId: String) -> UIImage? {
        let thumbPath = getImageThumbnailPath(messageId: messageId)
        guard fileManager.fileExists(atPath: thumbPath.path) else { return nil }
        guard let data = try? Data(contentsOf: thumbPath) else { return nil }
        return UIImage(data: data)
    }

    @discardableResult
    func saveImageThumbnail(_ image: UIImage, messageId: String) -> Result<URL, MediaStorageError> {
        let path = getImageThumbnailPath(messageId: messageId)
        guard let imageData = image.jpegData(compressionQuality: 0.92) else {
            return .failure(.invalidData)
        }

        do {
            try imageData.write(to: path, options: [.atomic])
            return .success(path)
        } catch {
            return .failure(.saveFailed)
        }
    }

    @discardableResult
    func moveVideoThumbnail(from oldMessageId: String, to newMessageId: String) -> Result<URL, MediaStorageError> {
        let sourcePath = getVideoThumbnailPath(messageId: oldMessageId)
        let destPath = getVideoThumbnailPath(messageId: newMessageId)
        guard fileManager.fileExists(atPath: sourcePath.path) else {
            return .failure(.fileNotFound)
        }
        do {
            if fileManager.fileExists(atPath: destPath.path) {
                try fileManager.removeItem(at: destPath)
            }
            try fileManager.moveItem(at: sourcePath, to: destPath)
            return .success(destPath)
        } catch {
            return .failure(.saveFailed)
        }
    }
    
    // MARK: - Save Media (Sending)
    
    func saveMedia(data: Data, messageId: String, type: MediaStorageType) -> Result<URL, MediaStorageError> {
        // Check available disk space
        guard hasEnoughDiskSpace(requiredBytes: Int64(data.count)) else {
            return .failure(.diskSpaceInsufficient)
        }

        let filePath = getMediaPath(messageId: messageId, type: type)

        do {
            try data.write(to: filePath, options: [.atomic])
            let bytes = Int64(data.count)
            AppLogger.debug("Saved \(type.rawValue) to Documents: \(messageId) (\(formatBytes(Int64(data.count))))")
            return .success(filePath)
        } catch {
            AppLogger.debug("Failed to save media: \(error)")
            return .failure(.saveFailed)
        }
    }

    /// Moves a media file from one messageId to another (zero-copy rename).
    /// Avoids loading the entire file into memory.
    func moveMedia(from oldMessageId: String, to newMessageId: String, type: MediaStorageType) -> Result<URL, MediaStorageError> {
        let sourcePath = getMediaPath(messageId: oldMessageId, type: type)
        let destPath = getMediaPath(messageId: newMessageId, type: type)

        guard fileManager.fileExists(atPath: sourcePath.path) else {
            return .failure(.fileNotFound)
        }

        do {
            // Try rename first (instant, same filesystem)
            try fileManager.moveItem(at: sourcePath, to: destPath)
            AppLogger.debug("Moved \(type.rawValue): \(oldMessageId) -> \(newMessageId)")
            return .success(destPath)
        } catch {
            // Fallback: copy then delete
            do {
                try fileManager.copyItem(at: sourcePath, to: destPath)
                try? fileManager.removeItem(at: sourcePath)
                AppLogger.debug("Copied \(type.rawValue): \(oldMessageId) -> \(newMessageId)")
                return .success(destPath)
            } catch {
                AppLogger.debug("Failed to move media: \(error)")
                return .failure(.saveFailed)
            }
        }
    }

    /// Copies a media file to a second messageId so both temp and server ids resolve locally.
    @discardableResult
    func copyMedia(from oldMessageId: String, to newMessageId: String, type: MediaStorageType) -> Result<URL, MediaStorageError> {
        if oldMessageId == newMessageId {
            if let url = getMediaURL(messageId: newMessageId, type: type) { return .success(url) }
            return .failure(.fileNotFound)
        }
        if let existing = getMediaURL(messageId: newMessageId, type: type) {
            return .success(existing)
        }
        let sourcePath = getMediaPath(messageId: oldMessageId, type: type)
        let destPath = getMediaPath(messageId: newMessageId, type: type)
        guard fileManager.fileExists(atPath: sourcePath.path) else {
            return .failure(.fileNotFound)
        }
        do {
            try fileManager.copyItem(at: sourcePath, to: destPath)
            markDownloaded(messageId: newMessageId)
            return .success(destPath)
        } catch {
            AppLogger.debug("Failed to copy media: \(error)")
            return .failure(.saveFailed)
        }
    }
    
    func saveImage(_ image: UIImage, messageId: String, compressionQuality: CGFloat = 0.75) -> Result<URL, MediaStorageError> {
        guard let imageData = image.jpegData(compressionQuality: compressionQuality) else {
            return .failure(.invalidData)
        }
        return saveMedia(data: imageData, messageId: messageId, type: .image)
    }
    
    func saveVideo(from sourceURL: URL, messageId: String) -> Result<URL, MediaStorageError> {
        let destinationPath = getMediaPath(messageId: messageId, type: .video)
        
        do {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                return .failure(.fileNotFound)
            }
            
            let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            guard hasEnoughDiskSpace(requiredBytes: fileSize) else {
                return .failure(.diskSpaceInsufficient)
            }
            
            if fileManager.fileExists(atPath: destinationPath.path) {
                try fileManager.removeItem(at: destinationPath)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationPath)
            
            AppLogger.debug("Saved video to Documents: \(messageId) (\(formatBytes(fileSize)))")
            return .success(destinationPath)
        } catch {
            AppLogger.debug("Failed to save video: \(error)")
            return .failure(.saveFailed)
        }
    }
    
    // MARK: - Download Media (Receiving)
    
    func downloadMedia(from urlString: String, messageId: String, type: MediaStorageType, completion: @escaping (Result<URL, MediaStorageError>) -> Void) {
        // Presigned URL already returned an HTTP error this session — don't retry.
        if syncQueue.sync(execute: { failedDownloadIds.contains(messageId) }) {
            completion(.failure(.downloadFailed))
            return
        }
        if isAlreadyDownloaded(messageId: messageId) {
            if let existingURL = getMediaURL(messageId: messageId, type: type) {
                completion(.success(existingURL))
                return
            }
            // File was removed from disk (e.g. after logout) — clear stale tracking and re-download.
            downloadedIdsQueue.sync(flags: .barrier) { _ = downloadedMessageIds.remove(messageId) }
        }

        if let existingURL = getMediaURL(messageId: messageId, type: type) {
            markDownloaded(messageId: messageId)
            completion(.success(existingURL))
            return
        }
        for fallbackType in [MediaStorageType.audio, .image, .video, .document] where fallbackType != type {
            if let existingURL = getMediaURL(messageId: messageId, type: fallbackType) {
                markDownloaded(messageId: messageId)
                completion(.success(existingURL))
                return
            }
        }
        
        let alreadyQueuedOrDownloading = syncQueue.sync {
            activeDownloads[messageId] != nil || pendingDownloads.contains(where: { $0.messageId == messageId })
        }
        if alreadyQueuedOrDownloading {
            syncQueue.sync(flags: .barrier) {
                downloadCompletionHandlers[messageId, default: []].append(completion)
            }
            return
        }
        
        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidURL))
            return
        }
        
        let queued = syncQueue.sync(flags: .barrier) { () -> Bool in
            if activeDownloads.count >= maxConcurrentDownloads {
                if !pendingDownloads.contains(where: { $0.messageId == messageId }) {
                    pendingDownloads.append((urlString: urlString, messageId: messageId, type: type, completion: completion))
                }
                return true
            }
            downloadStorageTypes[messageId] = type
            return false
        }
        if queued {
            return
        }

        startDownloadTask(url: url, messageId: messageId, completion: completion)
    }
    
    private func startDownloadTask(url: URL, messageId: String, completion: @escaping (Result<URL, MediaStorageError>) -> Void) {
        setDownloadingState(true, for: messageId)
        setDownloadProgressValue(0.0, for: messageId)
        
        let downloadTask = downloadSession.downloadTask(with: url)
        syncQueue.sync(flags: .barrier) {
            activeDownloads[messageId] = downloadTask
        }
        downloadTask.resume()

        syncQueue.sync(flags: .barrier) {
            downloadCompletionHandlers[messageId, default: []].append(completion)
        }
    }
    
    private func startNextPendingDownload() {
        let next = syncQueue.sync(flags: .barrier) { () -> (urlString: String, messageId: String, type: MediaStorageType, completion: (Result<URL, MediaStorageError>) -> Void)? in
            guard activeDownloads.count < maxConcurrentDownloads, !pendingDownloads.isEmpty else { return nil }
            return pendingDownloads.removeFirst()
        }
        guard let next else { return }
        guard let url = URL(string: next.urlString) else {
            completeDownload(messageId: next.messageId, result: .failure(.invalidURL))
            return
        }
        startDownloadTask(url: url, messageId: next.messageId, completion: next.completion)
    }
    
    func autoDownloadIfNeeded(message: ConversationMessage) {
        let messageId = message.id
        guard !messageId.isEmpty else { return }

        if syncQueue.sync(execute: { failedDownloadIds.contains(messageId) }) { return }

        let messageType = (message.messageType ?? message.type ?? "").lowercased()
        var storageType: MediaStorageType?
        
        switch messageType {
        case "image": storageType = .image
        case "video": storageType = .video
        case "audio": storageType = .audio
        default: return
        }
        
        guard let type = storageType else { return }
        
        if mediaExists(messageId: messageId, type: type) {
            markDownloaded(messageId: messageId)
            return
        }
        
        // If stale tracking says "downloaded" but file is gone, clear the flag and re-download.
        if isAlreadyDownloaded(messageId: messageId) {
            downloadedIdsQueue.sync(flags: .barrier) { _ = downloadedMessageIds.remove(messageId) }
        }
        
        let alreadyQueuedOrDownloading = syncQueue.sync {
            activeDownloads[messageId] != nil || pendingDownloads.contains(where: { $0.messageId == messageId })
        }
        if alreadyQueuedOrDownloading {
            syncQueue.sync(flags: .barrier) {
                downloadCompletionHandlers[messageId, default: []].append { result in
                    if case .success = result {
                        NotificationCenter.default.post(
                            name: .mediaDownloadCompleted,
                            object: nil,
                            userInfo: ["messageId": messageId]
                        )
                    }
                }
            }
            return
        }
        
        guard let urlString = message.media?.first?.url ?? message.content,
              !urlString.isEmpty else {
            return
        }
        
        downloadMedia(from: urlString, messageId: messageId, type: type) { result in
            switch result {
            case .success(_):
                NotificationCenter.default.post(
                    name: .mediaDownloadCompleted,
                    object: nil,
                    userInfo: ["messageId": messageId]
                )
            case .failure(_):
                break
            }
        }
    }
    
    // MARK: - Load Media from Documents
    
    func loadMedia(messageId: String, type: MediaStorageType) -> Result<Data, MediaStorageError> {
        let filePath = getMediaPath(messageId: messageId, type: type)
        
        guard fileManager.fileExists(atPath: filePath.path) else {
            return .failure(.fileNotFound)
        }
        
        do {
            let data = try Data(contentsOf: filePath)
            return .success(data)
        } catch {
            AppLogger.debug("Failed to load media: \(error)")
            return .failure(.fileNotFound)
        }
    }
    
    func loadImage(messageId: String) -> UIImage? {
        let result = loadMedia(messageId: messageId, type: .image)
        switch result {
        case .success(let data):
            return UIImage(data: data)
        case .failure:
            return nil
        }
    }
    
    // MARK: - Save to Gallery
    
    func saveToGallery(messageId: String, type: MediaStorageType, completion: @escaping (Result<Void, MediaStorageError>) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        
        guard status == .authorized else {
            if status == .notDetermined {
                PHPhotoLibrary.requestAuthorization { newStatus in
                    if newStatus == .authorized {
                        self.performSaveToGallery(messageId: messageId, type: type, completion: completion)
                    } else {
                        completion(.failure(.permissionDenied))
                    }
                }
            } else {
                completion(.failure(.permissionDenied))
            }
            return
        }
        
        performSaveToGallery(messageId: messageId, type: type, completion: completion)
    }
    
    private func performSaveToGallery(messageId: String, type: MediaStorageType, completion: @escaping (Result<Void, MediaStorageError>) -> Void) {
        guard let mediaURL = getMediaURL(messageId: messageId, type: type) else {
            completion(.failure(.fileNotFound))
            return
        }
        
        PHPhotoLibrary.shared().performChanges({
            switch type {
            case .image:
                if let image = UIImage(contentsOfFile: mediaURL.path) {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            case .video:
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: mediaURL)
            default:
                break
            }
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    AppLogger.debug("Saved to gallery: \(messageId)")
                    completion(.success(()))
                } else {
                    AppLogger.debug("Failed to save to gallery: \(error?.localizedDescription ?? "unknown")")
                    completion(.failure(.saveFailed))
                }
            }
        }
    }
    
    // MARK: - Delete Media
    
    func deleteMedia(messageId: String, type: MediaStorageType) -> Result<Void, MediaStorageError> {
        let filePath = getMediaPath(messageId: messageId, type: type)
        
        guard fileManager.fileExists(atPath: filePath.path) else {
            return .failure(.fileNotFound)
        }
        
        do {
            try fileManager.removeItem(at: filePath)
            AppLogger.debug("Deleted media: \(messageId)")
            return .success(())
        } catch {
            AppLogger.debug("Failed to delete media: \(error)")
            return .failure(.saveFailed)
        }
    }
    
    // MARK: - Storage Management
    
    func getTotalStorageSize() -> Int64 {
        var totalSize: Int64 = 0
        let mediaTypes: [MediaStorageType] = [.image, .video, .audio, .document]
        
        for type in mediaTypes {
            let directory = documentsDirectory.appendingPathComponent(type.subdirectory)
            if let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) {
                for file in files {
                    if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                       let size = attributes[.size] as? Int64 {
                        totalSize += size
                    }
                }
            }
        }
        
        return totalSize
    }
    
    func getStorageSize(for type: MediaStorageType) -> Int64 {
        var size: Int64 = 0
        let directory = documentsDirectory.appendingPathComponent(type.subdirectory)
        
        if let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files {
                if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                   let fileSize = attributes[.size] as? Int64 {
                    size += fileSize
                }
            }
        }
        
        return size
    }
    
    func getMediaCount(for type: MediaStorageType) -> Int {
        let directory = documentsDirectory.appendingPathComponent(type.subdirectory)
        if let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            return files.count
        }
        return 0
    }
    
    private func hasEnoughDiskSpace(requiredBytes: Int64) -> Bool {
        guard let systemAttributes = try? fileManager.attributesOfFileSystem(forPath: documentsDirectory.path),
              let freeSpace = systemAttributes[.systemFreeSize] as? Int64 else {
            return false
        }
        
        let minimumBuffer: Int64 = 100 * 1024 * 1024 // Keep 100MB free
        return freeSpace > (requiredBytes + minimumBuffer)
    }
    
    // MARK: - Utility Methods
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    func generateThumbnailFromVideoFile(messageId: String) -> UIImage? {
        guard let videoURL = getMediaURL(messageId: messageId, type: .video) else {
            return nil
        }
        return Self.generateVideoThumbnailImage(from: videoURL)
    }

    /// Poster frame for a local or remote video. Tries ~0.1s then t=0 (first frame is often black).
    static func generateVideoThumbnailImage(from url: URL, duration: Double = 0) -> UIImage? {
        if url.absoluteString.lowercased().contains(".m3u8") { return nil }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let maxSide: CGFloat = 200 * UIScreen.main.scale
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)
        let seekSeconds = min(1, max(0.0, duration > 0 ? duration * 0.1 : 0.1))
        let times = [
            CMTime(seconds: seekSeconds, preferredTimescale: 600),
            CMTime.zero
        ]
        for time in times {
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
    
    func printStorageStatistics() {
        AppLogger.debug("\n MEDIA STORAGE STATISTICS")
        AppLogger.debug("================================")
        
        let mediaTypes: [MediaStorageType] = [.image, .video, .audio, .document]
        var totalSize: Int64 = 0
        var totalCount = 0
        
        for type in mediaTypes {
            let size = getStorageSize(for: type)
            let count = getMediaCount(for: type)
            totalSize += size
            totalCount += count
            
            AppLogger.debug("   \(type.rawValue):")
            AppLogger.debug("   Files: \(count)")
            AppLogger.debug("   Size: \(formatBytes(size))")
        }
        
        AppLogger.debug("--------------------------------")
        AppLogger.debug("   Total:")
        AppLogger.debug("   Files: \(totalCount)")
        AppLogger.debug("   Size: \(formatBytes(totalSize))")
        AppLogger.debug("================================\n")
    }
        
    private var downloadCompletionHandlers: [String: [(Result<URL, MediaStorageError>) -> Void]] = [:]

    private func completeDownload(messageId: String, result: Result<URL, MediaStorageError>) {
        let handlers = syncQueue.sync(flags: .barrier) { downloadCompletionHandlers.removeValue(forKey: messageId) } ?? []
        setDownloadingState(false, for: messageId)
        clearDownloadProgressValue(for: messageId)
        syncQueue.sync(flags: .barrier) {
            activeDownloads.removeValue(forKey: messageId)
        }
        for handler in handlers {
            handler(result)
        }
        startNextPendingDownload()
    }

    // MARK: - Downloaded Tracking

    func isAlreadyDownloaded(messageId: String) -> Bool {
        downloadedIdsQueue.sync { downloadedMessageIds.contains(messageId) }
    }

    func markDownloaded(messageId: String) {
        downloadedIdsQueue.sync { _ = downloadedMessageIds.insert(messageId) }
    }

    /// Clears all in-memory download tracking. Call after logout so the next
    /// session re-downloads any media whose files were deleted from disk.
    func resetForNewSession() {
        downloadedIdsQueue.sync(flags: .barrier) { downloadedMessageIds.removeAll() }
        syncQueue.sync(flags: .barrier) { failedDownloadIds.removeAll() }
    }

    /// Allow re-download for a message that previously failed
    func clearFailedDownload(messageId: String) {
        syncQueue.sync(flags: .barrier) { failedDownloadIds.remove(messageId) }
    }

    func cancelDownload(messageId: String) {
        syncQueue.sync(flags: .barrier) {
            activeDownloads[messageId]?.cancel()
            activeDownloads.removeValue(forKey: messageId)
            pendingDownloads.removeAll { $0.messageId == messageId }
        }
        completeDownload(messageId: messageId, result: .failure(.downloadFailed))
    }
}

// MARK: - URLSessionDownloadDelegate

extension MediaStorageManager: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Find message ID from active downloads (thread-safe)
        let messageId: String? = syncQueue.sync {
            return activeDownloads.first(where: { $0.value == downloadTask })?.key
        }
        guard let messageId = messageId else {
            AppLogger.debug("Could not find message ID for completed download")
            return
        }

        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            // Presigned S3 URLs (X-Amz-Signature) expire after 15 minutes and return 403.
            // Do NOT permanently block them in failedDownloadIds — the background sync
            // will refresh the URL and the view's onChange handler will retry automatically.
            let isPresigned = downloadTask.originalRequest?.url?.query?.contains("X-Amz-Signature") == true
            AppLogger.debug("❌ Download rejected (HTTP \(httpResponse.statusCode)): \(messageId) presigned=\(isPresigned)")
            syncQueue.sync(flags: .barrier) {
                downloadStorageTypes.removeValue(forKey: messageId)
                if !isPresigned {
                    failedDownloadIds.insert(messageId)
                }
            }
            completeDownload(messageId: messageId, result: .failure(.downloadFailed))
            return
        }

        let storageType: MediaStorageType
        let storedType = syncQueue.sync(flags: .barrier) { () -> MediaStorageType? in
            let type = downloadStorageTypes[messageId]
            downloadStorageTypes.removeValue(forKey: messageId)
            return type
        }
        if let storedType {
            storageType = storedType
        } else {
            let contentType = downloadTask.response?.mimeType ?? ""
            if contentType.contains("video") {
                storageType = .video
            } else if contentType.contains("audio") {
                storageType = .audio
            } else if contentType.contains("application") {
                storageType = .document
            } else {
                storageType = .image
            }
        }
        
        let destinationPath = getMediaPath(messageId: messageId, type: storageType)
        
        do {
            if fileManager.fileExists(atPath: destinationPath.path) {
                try fileManager.removeItem(at: destinationPath)
            }
            try fileManager.moveItem(at: location, to: destinationPath)

            markDownloaded(messageId: messageId)

            AppLogger.debug("Download completed: \(messageId)")

            completeDownload(messageId: messageId, result: .success(destinationPath))
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .mediaDownloadCompleted, object: nil, userInfo: ["messageId": messageId, "url": destinationPath])
            }
        } catch {
            AppLogger.debug("Failed to move downloaded file: \(error)")
            completeDownload(messageId: messageId, result: .failure(.saveFailed))
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .mediaDownloadFailed, object: nil, userInfo: ["messageId": messageId, "error": error])
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let messageId: String? = syncQueue.sync {
            return activeDownloads.first(where: { $0.value == downloadTask })?.key
        }
        guard let messageId = messageId else { return }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        setDownloadProgressValue(progress, for: messageId)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let messageId: String? = syncQueue.sync {
            return activeDownloads.first(where: { $0.value == task })?.key
        }
        guard let messageId = messageId else { return }

        if error != nil {
            completeDownload(messageId: messageId, result: .failure(.downloadFailed))
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .mediaDownloadFailed,
                    object: nil,
                    userInfo: ["messageId": messageId, "error": error]
                )
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundSessionCompletionHandler?()
            self.backgroundSessionCompletionHandler = nil
        }
    }
}

extension Notification.Name {
    static let mediaDownloadCompleted = Notification.Name("mediaDownloadCompleted")
    static let mediaDownloadFailed = Notification.Name("mediaDownloadFailed")
    static let mediaSavedToGallery = Notification.Name("mediaSavedToGallery")
}


class MediaURLResolver {

    static let shared = MediaURLResolver()

    private init() {}
    
    func resolveMediaURL(for message: ConversationMessage) -> URL? {
        var candidateIds: [String] = []
        let add: (String?) -> Void = { value in
            guard let value, !value.isEmpty, !candidateIds.contains(value) else { return }
            candidateIds.append(value)
        }
        add(message.id)
        add(message.stableId)
        add(message.metadata?["clientTempId"]?.value as? String)

        let messageType = (message.messageType ?? message.type ?? "").lowercased()
        var storageType: MediaStorageType?

        switch messageType {
        case "image": storageType = .image
        case "video": storageType = .video
        case "audio": storageType = .audio
        default: break
        }

        // 1. If already downloaded to local storage, use local file
        if let type = storageType {
            for id in candidateIds {
                if let localURL = MediaStorageManager.shared.getMediaURL(messageId: id, type: type) {
                    return localURL
                }
            }
        }

        // 2. Use the server-provided CDN URL directly
        if let mediaURL = message.media?.first?.url, mediaURL.lowercased().hasPrefix("http"), let url = URL(string: mediaURL) {
            return url
        }

        if let content = message.content, content.lowercased().hasPrefix("http"), let url = URL(string: content) {
            return url
        }

        return nil
    }
}

// MARK: - Extension for ConversationMessage

extension ConversationMessage {
    var resolvedMediaURL: URL? {
        return MediaURLResolver.shared.resolveMediaURL(for: self)
    }
    
    var hasLocalMedia: Bool {
        let messageType = (self.messageType ?? self.type ?? "").lowercased()
        var storageType: MediaStorageType?

        switch messageType {
        case "image": storageType = .image
        case "video": storageType = .video
        case "audio": storageType = .audio
        default: return false
        }

        guard let type = storageType else { return false }

        var candidateIds: [String] = []
        let add: (String?) -> Void = { value in
            guard let value, !value.isEmpty, !candidateIds.contains(value) else { return }
            candidateIds.append(value)
        }
        add(id)
        add(stableId)
        add(metadata?["clientTempId"]?.value as? String)

        return candidateIds.contains { MediaStorageManager.shared.mediaExists(messageId: $0, type: type) }
    }
}
