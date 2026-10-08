//
//  MediaCacheManager.swift
//  FlirttimeNew
//
//  Enhanced with persistent disk storage for media files
//

import Foundation
import SwiftUI
import Combine

// MARK: - Media Types

enum MediaType: String, CaseIterable {
    case image = "image"
    case video = "video"
    case audio = "audio"
    
    var fileExtension: String {
        switch self {
        case .image: return "jpg"
        case .video: return "mp4"
        case .audio: return "m4a"
        }
    }
    
    var mimeType: String {
        switch self {
        case .image: return "image/jpeg"
        case .video: return "video/mp4"
        case .audio: return "audio/mp4"
        }
    }
}

// MARK: - Upload Status

enum UploadStatus: Equatable {
    case pending
    case uploading(Double)
    case completed
    case failed(String)
    
    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
    
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
    
    var isUploading: Bool {
        if case .uploading = self { return true }
        return false
    }
}

// MARK: - Cache Result

enum CacheResult<T> {
    case success(T)
    case failure(CacheError)
}

enum CacheError: Error, LocalizedError {
    case fileNotFound
    case invalidData
    case cacheLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Media file not found in cache"
        case .invalidData:
            return "Invalid media data"
        case .cacheLimitExceeded:
            return "Cache storage limit exceeded"
        }
    }
}

// MARK: - Media Cache Manager

class MediaCacheManager: ObservableObject {
    
    static let shared = MediaCacheManager()
    
    @Published var uploadProgress: [String: Double] = [:]
    @Published var uploadStatus: [String: UploadStatus] = [:]
    
    private let memoryCache = NSCache<NSString, NSData>()
    
    // MARK: - Persistent Storage
    
    private let fileManager = FileManager.default
    private lazy var documentsDirectory: URL = {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()
    
    private lazy var diskCacheURL: URL = {
        documentsDirectory.appendingPathComponent("FlirtTimeChat/MediaCache", isDirectory: true)
    }()
    
    private func diskCacheURL(for type: MediaType) -> URL {
        return diskCacheURL.appendingPathComponent(type.rawValue, isDirectory: true)
    }
    
    private let uploadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "MediaUploadQueue"
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .userInitiated
        return queue
    }()
    
    private let maxMemoryCacheSize: Int = 50 * 1024 * 1024  // 50MB
    private let maxItemSize: Int = 5 * 1024 * 1024  // 5MB per item
    private let maxDiskCacheSize: Int = 200 * 1024 * 1024  // 200MB total disk cache
    
    private var cancellables = Set<AnyCancellable>()
    private var cleanupTimer: Timer?
    
    private init() {
        setupCache()
        setupCleanupTimer()
        AppLogger.debug("🏗️ MediaCacheManager initialized with persistent storage")
    }
    
    private func setupCache() {
        memoryCache.name = "MediaMemoryCache"
        memoryCache.totalCostLimit = maxMemoryCacheSize
        memoryCache.countLimit = 100
        
        // Create disk cache directories
        setupDiskCacheDirectories()
        
        AppLogger.debug("✅ Media cache configured (Memory: \(maxMemoryCacheSize / 1024 / 1024)MB, Disk: \(maxDiskCacheSize / 1024 / 1024)MB)")
    }
    
    private func setupDiskCacheDirectories() {
        let directories = [
            diskCacheURL,
            diskCacheURL(for: .image),
            diskCacheURL(for: .video),
            diskCacheURL(for: .audio)
        ]
        
        for directory in directories {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                AppLogger.debug("❌ Failed to create cache directory \(directory): \(error)")
            }
        }
    }
    
    private func setupCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.cleanupOldCacheFiles()
            self?.manageDiskCacheSize()
        }
    }
    
    func cacheMedia(_ data: Data, for messageId: String, type: MediaType) -> CacheResult<Void> {
        guard !messageId.isEmpty else {
            return .failure(.invalidData)
        }
        
        guard !data.isEmpty else {
            return .failure(.invalidData)
        }
        
        guard data.count <= maxItemSize else {
            AppLogger.debug("⚠️ Skipping cache: File too large (\(data.count / 1024 / 1024)MB) for message \(messageId)")
            return .failure(.cacheLimitExceeded)
        }
        
        // Cache in memory
        let cacheKey = messageId as NSString
        memoryCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
        
        // Save to disk
        let result = saveToDisk(data: data, messageId: messageId, type: type)
        if case .failure(let error) = result {
            AppLogger.debug("⚠️ Failed to save to disk cache: \(error)")
        }
        
        return .success(())
    }
    
    func getCachedMedia(for messageId: String) -> CacheResult<Data> {
        guard !messageId.isEmpty else {
            return .failure(.invalidData)
        }
        
        // Check memory cache first
        let cacheKey = messageId as NSString
        if let cachedData = memoryCache.object(forKey: cacheKey) {
            return .success(cachedData as Data)
        }
        
        // Check disk cache
        return loadFromDisk(messageId: messageId)
    }
    
    // MARK: - Disk Cache Operations
    
    private func saveToDisk(data: Data, messageId: String, type: MediaType) -> CacheResult<Void> {
        let fileName = "\(messageId).\(type.fileExtension)"
        let fileURL = diskCacheURL(for: type).appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            AppLogger.debug("💾 Saved to disk cache: \(fileName) (\(data.count / 1024)KB)")
            return .success(())
        } catch {
            AppLogger.debug("❌ Failed to save to disk: \(error)")
            return .failure(.invalidData)
        }
    }
    
    private func loadFromDisk(messageId: String) -> CacheResult<Data> {
        // Try each media type
        for type in MediaType.allCases {
            let fileName = "\(messageId).\(type.fileExtension)"
            let fileURL = diskCacheURL(for: type).appendingPathComponent(fileName)
            
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    let data = try Data(contentsOf: fileURL)
                    
                    // Also cache in memory for faster access next time
                    let cacheKey = messageId as NSString
                    memoryCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
                    
                    AppLogger.debug("📁 Loaded from disk cache: \(fileName) (\(data.count / 1024)KB)")
                    return .success(data)
                } catch {
                    AppLogger.debug("❌ Failed to load from disk: \(error)")
                }
            }
        }
        
        return .failure(.fileNotFound)
    }
    
    func hasCachedMedia(for messageId: String) -> Bool {
        guard !messageId.isEmpty else { return false }
        return memoryCache.object(forKey: messageId as NSString) != nil
    }
    
    func removeCachedMedia(for messageId: String) -> CacheResult<Void> {
        guard !messageId.isEmpty else {
            return .failure(.invalidData)
        }
        
        memoryCache.removeObject(forKey: messageId as NSString)
        return .success(())
    }
    
    func clearCache() {
        memoryCache.removeAllObjects()
        
        // Clear disk cache
        do {
            let contents = try fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil, options: [])
            for fileURL in contents {
                try fileManager.removeItem(at: fileURL)
            }
            AppLogger.debug("🧹 Cleared disk cache")
        } catch {
            AppLogger.debug("❌ Failed to clear disk cache: \(error)")
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.uploadProgress.removeAll()
            self?.uploadStatus.removeAll()
        }
    }
    
    // MARK: - Cache Management
    
    private func cleanupOldCacheFiles() {
        let cutoffDate = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days ago
        
        for type in MediaType.allCases {
            let directory = diskCacheURL(for: type)
            
            do {
                let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: [])
                
                for fileURL in contents {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey])
                    if let creationDate = resourceValues.creationDate, creationDate < cutoffDate {
                        try fileManager.removeItem(at: fileURL)
                        AppLogger.debug("🧹 Removed old cache file: \(fileURL.lastPathComponent)")
                    }
                }
            } catch {
                AppLogger.debug("❌ Failed to cleanup old cache files for \(type): \(error)")
            }
        }
    }
    
    private func manageDiskCacheSize() {
        let currentSize = getDiskCacheSize()
        
        if currentSize > maxDiskCacheSize {
            AppLogger.debug("⚠️ Disk cache size (\(currentSize / 1024 / 1024)MB) exceeds limit (\(maxDiskCacheSize / 1024 / 1024)MB)")
            
            // Remove oldest files until under limit
            var filesToRemove: [(URL, Date)] = []
            
            for type in MediaType.allCases {
                let directory = diskCacheURL(for: type)
                
                do {
                    let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: [])
                    
                    for fileURL in contents {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey])
                        if let creationDate = resourceValues.creationDate {
                            filesToRemove.append((fileURL, creationDate))
                        }
                    }
                } catch {
                    AppLogger.debug("❌ Failed to enumerate cache files for \(type): \(error)")
                }
            }
            
            // Sort by creation date (oldest first)
            filesToRemove.sort { $0.1 < $1.1 }
            
            var removedSize = 0
            for (fileURL, _) in filesToRemove {
                do {
                    let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    try fileManager.removeItem(at: fileURL)
                    removedSize += fileSize
                    
                    if currentSize - removedSize <= maxDiskCacheSize * 9 / 10 { // Remove until 90% of limit
                        break
                    }
                } catch {
                    AppLogger.debug("❌ Failed to remove cache file: \(error)")
                }
            }
            
            AppLogger.debug("🧹 Removed \(removedSize / 1024 / 1024)MB from disk cache")
        }
    }
    
    private func getDiskCacheSize() -> Int {
        var totalSize = 0
        
        for type in MediaType.allCases {
            let directory = diskCacheURL(for: type)
            
            do {
                let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [])
                
                for fileURL in contents {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                    totalSize += resourceValues.fileSize ?? 0
                }
            } catch {
                AppLogger.debug("❌ Failed to calculate cache size for \(type): \(error)")
            }
        }
        
        return totalSize
    }
    
    deinit {
        cleanupTimer?.invalidate()
        uploadQueue.cancelAllOperations()
        cancellables.removeAll()
    }
}
