//
//  ImageLoader.swift
//  FlirttimeNew
//

import UIKit

final class ImageLoader {

    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let session = URLSession(configuration: .default)

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

    func cachedImage(for url: URL) -> UIImage? {
        localImage(for: url) ?? cache.object(forKey: url as NSURL)
    }

    @discardableResult
    func load(_ url: URL, completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {
        if let image = cachedImage(for: url) {
            completion(image)
            return nil
        }
        let task = session.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(UIImage.init(data:))
            if let image {
                self?.cache.setObject(image, forKey: url as NSURL)
            }
            DispatchQueue.main.async { completion(image) }
        }
        task.resume()
        return task
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
        let urlString = path.hasPrefix("http") ? path : ApiName.imgBaseURL + path
        loadImage(with: URL(string: urlString), placeholder: placeholder, completion: completion)
    }
}
