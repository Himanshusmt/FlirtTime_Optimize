//
//  LocalImageStore.swift
//  FlirttimeNew
//

import UIKit

/// Keeps images picked by the user on disk so screens can reference them by file name
/// the same way they reference server image paths.
final class LocalImageStore {

    static let shared = LocalImageStore()

    private let cache = NSCache<NSString, UIImage>()
    private let directory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LocalImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func save(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "local_\(UUID().uuidString).jpg"
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            return nil
        }
        cache.setObject(image, forKey: name as NSString)
        return name
    }

    func image(named name: String) -> UIImage? {
        guard name.hasPrefix("local_") else { return nil }
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    func remove(_ name: String) {
        guard name.hasPrefix("local_") else { return }
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    func removeAll() {
        cache.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
