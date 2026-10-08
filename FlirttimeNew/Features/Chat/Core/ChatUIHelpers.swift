//
//  ChatUIHelpers.swift
//  FlirttimeNew
//

import Kingfisher
import UIKit

// MARK: - Image loading

struct ChatImageOptions: OptionSet {
    let rawValue: Int
    static let retryFailed = ChatImageOptions(rawValue: 1 << 0)
    static let highPriority = ChatImageOptions(rawValue: 1 << 1)
}

extension UIImageView {
    func setChatImage(
        with url: URL?,
        placeholderImage: UIImage? = nil,
        options: ChatImageOptions = [],
        completed: ((UIImage?, Error?, Int, URL?) -> Void)? = nil
    ) {
        var kfOptions: KingfisherOptionsInfo = [.backgroundDecode]
        if options.contains(.retryFailed) {
            kfOptions.append(.retryStrategy(DelayRetryStrategy(maxRetryCount: 2, retryInterval: .seconds(1))))
        }
        if options.contains(.highPriority) {
            kfOptions.append(.downloadPriority(URLSessionTask.highPriority))
        }
        kf.setImage(with: url, placeholder: placeholderImage, options: kfOptions) { result in
            switch result {
            case .success(let value):
                completed?(value.image, nil, 0, url)
            case .failure(let error):
                completed?(nil, error, 0, url)
            }
        }
    }

    func cancelChatImageLoad() {
        kf.cancelDownloadTask()
    }
}

// MARK: - Progress HUD

/// Full-screen loader backed by FlirtTime's `ActivityIndicator`.
enum ChatHUD {
    private static var indicator: ActivityIndicator?

    static func show() {
        DispatchQueue.main.async {
            guard indicator == nil else { return }
            let view = ActivityIndicator(frame: UIScreen.main.bounds)
            indicator = view
            view.show()
        }
    }

    static func dismiss() {
        DispatchQueue.main.async {
            indicator?.hide()
            indicator = nil
        }
    }
}
