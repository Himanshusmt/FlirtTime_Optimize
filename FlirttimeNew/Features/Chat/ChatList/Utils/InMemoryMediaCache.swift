//
//  InMemoryMediaCache.swift
//  FlirttimeNew
//
//  Created by Awais on 30/09/25.
//

import Foundation
import UIKit

class InMemoryMediaCache {
    
    static let shared = InMemoryMediaCache()
        
    private let maxCacheSize: Int = 5 * 1024 * 1024 // 5MB max per item
    private let maxTotalCacheSize: Int = 50 * 1024 * 1024 // 50MB total
    private let maxItemCount: Int = 100 // Max 100 items
        
    private let imageCache = NSCache<NSString, UIImage>()
    private let dataCache = NSCache<NSString, NSData>()
    private var cacheMetadata: [String: CacheMetadata] = [:]
    private let metadataQueue = DispatchQueue(label: "com.yandexgram.media.metadata", attributes: .concurrent)
        
    private struct CacheMetadata {
        let size: Int
        let timestamp: Date
        let type: MediaCacheType
    }
    
    enum MediaCacheType {
        case image
        case video
        case audio
        case thumbnail
    }
    
    // MARK: - Initialization
    
    private init() {
        setupCache()
    }
    
    private func setupCache() {
        imageCache.name = "InMemoryMediaCache.Images"
        imageCache.totalCostLimit = maxTotalCacheSize
        imageCache.countLimit = maxItemCount
        
        dataCache.name = "InMemoryMediaCache.Data"
        dataCache.totalCostLimit = maxTotalCacheSize / 2
        dataCache.countLimit = maxItemCount / 2
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        dataCache.removeAllObjects()
        metadataQueue.async(flags: .barrier) { [weak self] in
            self?.cacheMetadata = self?.cacheMetadata.filter { $0.value.type != .video && $0.value.type != .audio } ?? [:]
        }
    }
        
    func cacheImage(_ image: UIImage, for key: String) -> Bool {
        let size: Int
        if let cgImage = image.cgImage {
            size = cgImage.bytesPerRow * cgImage.height
        } else {
            let pixels = Int(image.size.width * image.scale) * Int(image.size.height * image.scale)
            size = pixels * 4
        }

        guard size <= maxCacheSize else {
            return false
        }
        
        imageCache.setObject(image, forKey: key as NSString, cost: size)
        
        metadataQueue.async(flags: .barrier) { [weak self] in
            self?.cacheMetadata[key] = CacheMetadata(size: size, timestamp: Date(), type: .image)
        }
        
        return true
    }
    
    func getCachedImage(for key: String) -> UIImage? {
        return imageCache.object(forKey: key as NSString)
    }
        
    func cacheData(_ data: Data, for key: String, type: MediaCacheType = .image) -> Bool {
        let size = data.count
        
        guard size <= maxCacheSize else {
            return false
        }
        
        dataCache.setObject(data as NSData, forKey: key as NSString, cost: size)
        
        metadataQueue.async(flags: .barrier) { [weak self] in
            self?.cacheMetadata[key] = CacheMetadata(size: size, timestamp: Date(), type: type)
        }
        
        return true
    }
    
    func getCachedData(for key: String) -> Data? {
        return dataCache.object(forKey: key as NSString) as Data?
    }
        
    func hasCached(key: String) -> Bool {
        return imageCache.object(forKey: key as NSString) != nil ||
               dataCache.object(forKey: key as NSString) != nil
    }
    
    func remove(key: String) {
        imageCache.removeObject(forKey: key as NSString)
        dataCache.removeObject(forKey: key as NSString)

        metadataQueue.async(flags: .barrier) { [weak self] in
            self?.cacheMetadata.removeValue(forKey: key)
        }
    }

    func transfer(from oldKey: String, to newKey: String) {
        if let image = imageCache.object(forKey: oldKey as NSString) {
            imageCache.setObject(image, forKey: newKey as NSString)
        }
        if let data = dataCache.object(forKey: oldKey as NSString) {
            dataCache.setObject(data, forKey: newKey as NSString)
        }
        metadataQueue.async(flags: .barrier) { [weak self] in
            guard let self, let meta = self.cacheMetadata[oldKey] else { return }
            self.cacheMetadata[newKey] = meta
        }
    }
    
    func clearAll() {
        imageCache.removeAllObjects()
        dataCache.removeAllObjects()
        
        metadataQueue.async(flags: .barrier) { [weak self] in
            self?.cacheMetadata.removeAll()
        }
    }
    
    func clearOldEntries(olderThan interval: TimeInterval = 3600) {
        let cutoffDate = Date().addingTimeInterval(-interval)
        
        metadataQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let oldKeys = self.cacheMetadata.filter { $0.value.timestamp < cutoffDate }.map { $0.key }
            
            for key in oldKeys {
                self.imageCache.removeObject(forKey: key as NSString)
                self.dataCache.removeObject(forKey: key as NSString)
                self.cacheMetadata.removeValue(forKey: key)
            }
        }
    }
        
    func getCacheStats() -> (imageCount: Int, dataCount: Int, totalSize: Int) {
        var stats = (imageCount: 0, dataCount: 0, totalSize: 0)
        
        metadataQueue.sync {
            stats.imageCount = cacheMetadata.filter { $0.value.type == .image }.count
            stats.dataCount = cacheMetadata.filter { $0.value.type != .image }.count
            stats.totalSize = cacheMetadata.values.reduce(0) { $0 + $1.size }
        }
        
        return stats
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
