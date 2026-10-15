//
//  ImageLoader.swift
//  FlirttimeNew
//

import CryptoKit
import UIKit

final class ImageLoader {

    static let shared = ImageLoader()

    /// S3 `/thumbnails/` objects currently answer 403. Once one fails and its full-size photo loads,
    /// later loads skip the thumbnail request; a thumbnail that loads switches this back off. Main queue only.
    static var thumbnailsUnavailable = false

    private let cache = NSCache<NSURL, UIImage>()
    private let session = URLSession(configuration: .default)
    private let diskQueue = DispatchQueue(label: "ImageLoader.disk", qos: .utility)
    private let diskDirectory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = caches.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()
    /// Callers waiting on a download already in flight, by cache key. Main queue only.
    private var pending: [NSURL: [(UIImage?) -> Void]] = [:]

    /// Paths that name a bundled asset or a `LocalImageStore` file (used by local mock data)
    /// resolve locally, with or without `ApiName.imgBaseURL` prepended.
    func localImage(for url: URL) -> UIImage? {
        var path = url.absoluteString
        if path.hasPrefix(ApiName.imgBaseURL) {
            path = String(path.dropFirst(ApiName.imgBaseURL.count))
        }
        guard !path.isEmpty, !path.contains("/") else { return nil }
        return LocalImageStore.shared.image(named: path) ?? UIImage(named: path)
    }

    /// Memory only; `load` also checks the disk cache.
    func cachedImage(for url: URL) -> UIImage? {
        localImage(for: url) ?? cache.object(forKey: Self.cacheKey(for: url))
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: Self.cacheKey(for: url))
    }

    /// Starts downloading `path` (same thumbnail handling as `UIImageView.loadImage(path:)`) so it's cached before display.
    func prefetch(path: String?) {
        guard let path, !path.isEmpty else { return }
        let urls = Self.urls(for: path)
        guard let first = urls.preferred else { return }
        load(first) { [weak self] image in
            guard image == nil, let thumbnail = urls.thumbnail, let fullSize = urls.fullSize, first == thumbnail else { return }
            self?.load(fullSize) { fullSizeImage in
                guard let fullSizeImage else { return }
                Self.thumbnailsUnavailable = true
                ImageLoader.shared.store(fullSizeImage, for: thumbnail)
            }
        }
    }

    /// Memory cache, then disk cache, then network. `completion` runs on the main queue.
    func load(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.load(url, completion: completion) }
            return
        }
        if let image = cachedImage(for: url) {
            completion(image)
            return
        }
        let key = Self.cacheKey(for: url)
        if pending[key] != nil {
            pending[key]?.append(completion)
            return
        }
        pending[key] = [completion]

        let diskFile = diskFileURL(for: key)
        diskQueue.async { [weak self] in
            if let diskFile, let data = try? Data(contentsOf: diskFile), let image = UIImage(data: data) {
                DispatchQueue.main.async { self?.finish(key: key, url: url, image: image) }
                return
            }
            self?.download(url, key: key, diskFile: diskFile)
        }
    }

    // MARK: - Private

    private func download(_ url: URL, key: NSURL, diskFile: URL?) {
        session.dataTask(with: url) { [weak self] data, response, _ in
            let isOK = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
            let image = isOK ? data.flatMap(UIImage.init(data:)) : nil
            if image != nil, let data, let diskFile {
                self?.diskQueue.async { try? data.write(to: diskFile, options: .atomic) }
            }
            DispatchQueue.main.async { self?.finish(key: key, url: url, image: image) }
        }.resume()
    }

    private func finish(key: NSURL, url: URL, image: UIImage?) {
        if let image { store(image, for: url) }
        let callbacks = pending.removeValue(forKey: key) ?? []
        callbacks.forEach { $0(image) }
    }

    private func diskFileURL(for key: NSURL) -> URL? {
        guard let diskDirectory, let string = key.absoluteString else { return nil }
        let hash = SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
        return diskDirectory.appendingPathComponent(hash)
    }

    /// Presigned S3 URLs get a new signature on every API response, so they're cached by path.
    private static func cacheKey(for url: URL) -> NSURL {
        guard url.query?.contains("X-Amz-Signature") == true,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url as NSURL
        }
        components.query = nil
        return (components.url ?? url) as NSURL
    }

    /// `thumbnail` and `fullSize` are set only for `/thumbnails/` paths; `preferred` is the URL to try first.
    fileprivate static func urls(for path: String) -> (preferred: URL?, thumbnail: URL?, fullSize: URL?) {
        let urlString = path.hasPrefix("http") ? path : ApiName.imgBaseURL + path
        let fullSizeString = urlString.replacingOccurrences(of: "/thumbnails/", with: "/")
        guard fullSizeString != urlString, let thumbnail = URL(string: urlString), let fullSize = URL(string: fullSizeString) else {
            return (URL(string: urlString), nil, nil)
        }
        return (thumbnailsUnavailable ? fullSize : thumbnail, thumbnail, fullSize)
    }
}

extension UIImageView {

    private static var urlKey: UInt8 = 0

    private var loadingURL: URL? {
        get { objc_getAssociatedObject(self, &UIImageView.urlKey) as? URL }
        set { objc_setAssociatedObject(self, &UIImageView.urlKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func loadImage(with url: URL?, placeholder: UIImage? = nil, completion: ((UIImage?) -> Void)? = nil) {
        loadingURL = url
        guard let url else {
            image = placeholder
            completion?(nil)
            return
        }
        if let cached = ImageLoader.shared.cachedImage(for: url) {
            image = cached
            completion?(cached)
            return
        }
        image = placeholder
        ImageLoader.shared.load(url) { [weak self] loaded in
            guard let self, self.loadingURL == url else { return }
            if let loaded {
                self.image = loaded
            }
            completion?(loaded)
        }
    }

    func loadImage(path: String?, placeholder: UIImage? = nil, completion: ((UIImage?) -> Void)? = nil) {
        guard let path, !path.isEmpty else {
            loadImage(with: nil, placeholder: placeholder, completion: completion)
            return
        }
        let urls = ImageLoader.urls(for: path)
        guard let thumbnailURL = urls.thumbnail, let fullSizeURL = urls.fullSize else {
            loadImage(with: urls.preferred, placeholder: placeholder, completion: completion)
            return
        }
        // A full-size photo loaded in place of a thumbnail is cached under the thumbnail URL too.
        if let cached = ImageLoader.shared.cachedImage(for: thumbnailURL) {
            loadingURL = thumbnailURL
            image = cached
            completion?(cached)
            return
        }
        if ImageLoader.thumbnailsUnavailable {
            loadImage(with: fullSizeURL, placeholder: placeholder) { fullSize in
                if let fullSize { ImageLoader.shared.store(fullSize, for: thumbnailURL) }
                completion?(fullSize)
            }
            return
        }
        // Some S3 thumbnails are not readable (403); the full-size photo usually is.
        loadImage(with: thumbnailURL, placeholder: placeholder) { [weak self] image in
            guard let self else { return }
            if image != nil {
                ImageLoader.thumbnailsUnavailable = false
                completion?(image)
            } else if self.loadingURL == thumbnailURL {
                self.loadImage(with: fullSizeURL, placeholder: placeholder) { fullSize in
                    if let fullSize {
                        ImageLoader.thumbnailsUnavailable = true
                        ImageLoader.shared.store(fullSize, for: thumbnailURL)
                    }
                    completion?(fullSize)
                }
            }
        }
    }
}
