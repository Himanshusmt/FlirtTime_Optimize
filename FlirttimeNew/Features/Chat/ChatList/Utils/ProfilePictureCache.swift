//
//  ProfilePictureCache.swift
//  FlirttimeNew
//
//  Created by Awais on 30/09/25.
//

import UIKit
import SwiftUI
import Combine

class ProfilePictureCache: ObservableObject {

    static let shared = ProfilePictureCache()

    @Published private(set) var cacheUpdateCounter: Int = 0

    private let memoryCache = NSCache<NSString, UIImage>()
    
    private lazy var diskCacheURL: URL = {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return cacheDir.appendingPathComponent("ProfilePictureCache")
    }()
    
    private let fileManager = FileManager.default
    
    private let downloadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "ProfilePictureDownloadQueue"
        queue.maxConcurrentOperationCount = 5
        queue.qualityOfService = .userInitiated
        return queue
    }()
    
    private var pendingCallbacks: [String: [(UIImage?) -> Void]] = [:]
    private let downloadLock = NSLock()
    /// Tracks which URL is stored in the memory cache for each userId.
    private var memoryCacheURLs: [String: String] = [:]
    private let urlTrackLock = NSLock()
    
    private let maxMemoryCacheCount = 50
    private let maxDiskCacheSize = 50 * 1024 * 1024
    private let cacheExpirationDays = 7
        
    private init() {
        setupCache()
        AppLogger.debug("ProfilePictureCache initialized (memory + disk)")
    }
        
    private func setupCache() {
        memoryCache.name = "ProfilePictureMemoryCache"
        memoryCache.countLimit = maxMemoryCacheCount
        memoryCache.totalCostLimit = 20 * 1024 * 1024

        if !fileManager.fileExists(atPath: diskCacheURL.path) {
            try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        }
    }

    private func diskImageURL(for userId: String) -> URL {
        return diskCacheURL.appendingPathComponent("\(userId).jpg")
    }

    private func diskURLFileURL(for userId: String) -> URL {
        return diskCacheURL.appendingPathComponent("\(userId).url")
    }

    private func loadFromDisk(userId: String, expectedURL: String) -> UIImage? {
        let urlFile = diskURLFileURL(for: userId)
        let imageFile = diskImageURL(for: userId)

        guard let storedURL = try? String(contentsOf: urlFile, encoding: .utf8),
              storedURL == expectedURL else {
            try? fileManager.removeItem(at: imageFile)
            try? fileManager.removeItem(at: urlFile)
            return nil
        }

        guard let data = try? Data(contentsOf: imageFile),
              let image = UIImage(data: data) else {
            return nil
        }

        return image
    }

    private func saveToDisk(userId: String, image: UIImage, sourceURL: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let imageFile = diskImageURL(for: userId)
        let urlFile = diskURLFileURL(for: userId)
        try? data.write(to: imageFile, options: .atomic)
        try? sourceURL.write(to: urlFile, atomically: true, encoding: .utf8)
    }

    private func removeFromDisk(userId: String) {
        try? fileManager.removeItem(at: diskImageURL(for: userId))
        try? fileManager.removeItem(at: diskURLFileURL(for: userId))
    }
    

        
    func getImage(userId: String, urlString: String?, completion: @escaping (UIImage?) -> Void) {
        guard !userId.isEmpty else {
            completion(nil)
            return
        }
        
        guard let urlString = urlString, !urlString.isEmpty else {
            completion(nil)
            return
        }
        
        let fullURL: String
        if urlString.starts(with: "http://") || urlString.starts(with: "https://") {
            fullURL = urlString
        } else {
            fullURL = "\(ChatConfig.mediaBaseURL)/\(urlString)"
        }
        
        let cacheKey = userId as NSString

        let memoryHit: UIImage? = {
            urlTrackLock.lock()
            let storedURL = memoryCacheURLs[userId]
            urlTrackLock.unlock()
            guard storedURL == fullURL else {
                if storedURL != nil {
                    // URL changed — bust memory and disk cache immediately
                    memoryCache.removeObject(forKey: cacheKey)
                    removeFromDisk(userId: userId)
                    urlTrackLock.lock()
                    memoryCacheURLs.removeValue(forKey: userId)
                    urlTrackLock.unlock()
                }
                return nil
            }
            return memoryCache.object(forKey: cacheKey)
        }()
        if let cachedImage = memoryHit {
            AppLogger.debug("Profile picture loaded from memory cache: \(userId)")
            completion(cachedImage)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if let diskImage = self.loadFromDisk(userId: userId, expectedURL: fullURL) {
                self.memoryCache.setObject(diskImage, forKey: cacheKey)
                self.urlTrackLock.lock()
                self.memoryCacheURLs[userId] = fullURL
                self.urlTrackLock.unlock()
                AppLogger.debug("Profile picture loaded from disk cache: \(userId)")
                DispatchQueue.main.async {
                    self.cacheUpdateCounter += 1
                    completion(diskImage)
                }
                return
            }
            self.downloadImage(userId: userId, urlString: fullURL, completion: completion)
        }
    }
    
    func preCacheProfilePictures(_ items: [(userId: String, urlString: String?)]) {
        guard !items.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var downloadCount = 0
            for item in items {
                guard let self = self else { return }

                guard let urlString = item.urlString, !urlString.isEmpty else { continue }

                let fullURL: String
                if urlString.starts(with: "http://") || urlString.starts(with: "https://") {
                    fullURL = urlString
                } else {
                    fullURL = "\(ChatConfig.mediaBaseURL)/\(urlString)"
                }

                let cacheKey = item.userId as NSString
                // Skip only if memory cache holds the same URL — avoids serving stale images
                self.urlTrackLock.lock()
                let cachedURL = self.memoryCacheURLs[item.userId]
                self.urlTrackLock.unlock()
                if cachedURL == fullURL && self.memoryCache.object(forKey: cacheKey) != nil {
                    continue
                }

                if let diskImage = self.loadFromDisk(userId: item.userId, expectedURL: fullURL) {
                    self.memoryCache.setObject(diskImage, forKey: cacheKey)
                    self.urlTrackLock.lock()
                    self.memoryCacheURLs[item.userId] = fullURL
                    self.urlTrackLock.unlock()
                    DispatchQueue.main.async {
                        self.cacheUpdateCounter += 1
                    }
                    continue
                }

                downloadCount += 1
                self.downloadImage(userId: item.userId, urlString: fullURL, completion: { _ in })
            }
            if downloadCount > 0 {
                AppLogger.debug("ProfilePictureCache: Downloading \(downloadCount) profile pictures...")
            }
        }
    }
    
    func removeCachedImage(userId: String) {
        memoryCache.removeObject(forKey: userId as NSString)
        urlTrackLock.lock()
        memoryCacheURLs.removeValue(forKey: userId)
        urlTrackLock.unlock()
        removeFromDisk(userId: userId)
        AppLogger.debug("Removed cached profile picture: \(userId)")
    }

    func getCachedImageSync(userId: String, urlString: String?) -> UIImage? {
        guard !userId.isEmpty else { return nil }

        let fullURL: String
        if let u = urlString, !u.isEmpty {
            fullURL = u.hasPrefix("http://") || u.hasPrefix("https://") ? u : "\(ChatConfig.mediaBaseURL)/\(u)"
        } else {
            return nil
        }

        let cacheKey = userId as NSString

        // Memory check with URL validation
        urlTrackLock.lock()
        let storedURL = memoryCacheURLs[userId]
        urlTrackLock.unlock()

        if storedURL == fullURL, let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        // Disk check (synchronous, fast for small images)
        if let diskImage = loadFromDisk(userId: userId, expectedURL: fullURL) {
            memoryCache.setObject(diskImage, forKey: cacheKey)
            urlTrackLock.lock()
            memoryCacheURLs[userId] = fullURL
            urlTrackLock.unlock()
            return diskImage
        }

        return nil
    }

    func isImageCached(userId: String) -> Bool {
        return memoryCache.object(forKey: userId as NSString) != nil
    }

    func getCachedImage(userId: String) -> UIImage? {
        return memoryCache.object(forKey: userId as NSString)
    }

    func clearAllCache() {
        AppLogger.debug("Clearing all profile picture cache (memory + disk)...")
        memoryCache.removeAllObjects()
        urlTrackLock.lock()
        memoryCacheURLs.removeAll()
        urlTrackLock.unlock()
        if let contents = try? fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil) {
            for file in contents { try? fileManager.removeItem(at: file) }
        }
        AppLogger.debug("Cleared memory and disk cache")
    }
        
    private func downloadImage(userId: String, urlString: String, completion: @escaping (UIImage?) -> Void) {
        downloadLock.lock()
        if pendingCallbacks[userId] != nil {
            pendingCallbacks[userId]?.append(completion)
            downloadLock.unlock()
            return
        }
        pendingCallbacks[userId] = [completion]
        downloadLock.unlock()

        guard let url = URL(string: urlString) else {
            downloadLock.lock()
            let callbacks = pendingCallbacks.removeValue(forKey: userId) ?? []
            downloadLock.unlock()
            DispatchQueue.main.async {
                for cb in callbacks { cb(nil) }
            }
            return
        }

        AppLogger.debug("Downloading profile picture: \(userId) from \(urlString)")

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            func drainCallbacks(with image: UIImage?) {
                self.downloadLock.lock()
                let callbacks = self.pendingCallbacks.removeValue(forKey: userId) ?? []
                self.downloadLock.unlock()
                DispatchQueue.main.async {
                    for cb in callbacks { cb(image) }
                }
            }

            if let error = error {
                AppLogger.debug("Failed to download profile picture \(userId): \(error)")
                drainCallbacks(with: nil)
                return
            }

            guard let data = data, let image = UIImage(data: data) else {
                AppLogger.debug("Invalid image data for profile picture: \(userId)")
                drainCallbacks(with: nil)
                return
            }

            let cacheKey = userId as NSString
            self.memoryCache.setObject(image, forKey: cacheKey)
            self.urlTrackLock.lock()
            self.memoryCacheURLs[userId] = urlString
            self.urlTrackLock.unlock()
            self.saveToDisk(userId: userId, image: image, sourceURL: urlString)

            AppLogger.debug("Downloaded and cached profile picture: \(userId)")

            DispatchQueue.main.async {
                self.cacheUpdateCounter += 1
            }

            drainCallbacks(with: image)
        }.resume()
    }
    
    deinit {
        downloadQueue.cancelAllOperations()
        AppLogger.debug("ProfilePictureCache deinitialized")
    }
}

final class ConversationIconCache: ObservableObject {

    static let shared = ConversationIconCache()

    @Published private(set) var version: Int = 0

    private var store: [String: UIImage] = [:]
    private let lock = NSLock()

    private init() {}

    func setImage(_ image: UIImage, forId id: String) {
        lock.lock()
        store[id] = image
        lock.unlock()
        DispatchQueue.main.async { self.version += 1 }
    }

    func image(forId id: String?) -> UIImage? {
        guard let id else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return store[id]
    }

    func removeImage(forId id: String) {
        lock.lock()
        store.removeValue(forKey: id)
        lock.unlock()
        DispatchQueue.main.async { self.version += 1 }
    }
}

// MARK: - UserProfileCache

final class UserProfileCache {
    static let shared = UserProfileCache()
    private var store: [String: ChatUserProfileData] = [:]
    private let lock = NSLock()
    private init() {}

    func set(_ profile: ChatUserProfileData, forUserId userId: String) {
        lock.lock()
        store[userId] = profile
        lock.unlock()
    }

    func get(forUserId userId: String) -> ChatUserProfileData? {
        lock.lock()
        defer { lock.unlock() }
        return store[userId]
    }
}

@MainActor
final class ConversationPresentationStore: ObservableObject {

    struct Snapshot: Equatable {
        let conversationId: String
        var title: String?
        var avatarURL: String?
        var description: String?
        var updatedAt: Date

        init(conversationId: String,
             title: String? = nil,
             avatarURL: String? = nil,
             description: String? = nil,
             updatedAt: Date = Date()) {
            self.conversationId = conversationId
            self.title = title
            self.avatarURL = avatarURL
            self.description = description
            self.updatedAt = updatedAt
        }
    }

    static let shared = ConversationPresentationStore()

    @Published private(set) var snapshots: [String: Snapshot] = [:]

    private init() {}

    func update(conversationId: String,
                title: String? = nil,
                avatarURL: String? = nil,
                description: String? = nil) {
        guard !conversationId.isEmpty else { return }

        var snapshot = snapshots[conversationId] ?? Snapshot(conversationId: conversationId)
        if let title {
            snapshot.title = title
        }
        if let avatarURL {
            snapshot.avatarURL = avatarURL
        }
        if let description {
            snapshot.description = description
        }
        snapshot.updatedAt = Date()
        snapshots[conversationId] = snapshot
    }

    func snapshot(for conversationId: String) -> Snapshot? {
        snapshots[conversationId]
    }

    func latestSnapshot(for ids: [String]) -> Snapshot? {
        ids
            .compactMap { id in snapshots[id] }
            .max(by: { $0.updatedAt < $1.updatedAt })
    }
}
