//
//  MomentsMediaCollectionViewCell.swift
//  FlirttimeNew
//

import UIKit

/// Photo tile used by the moment feed carousel.
final class MomentsMediaCollectionViewCell: UICollectionViewCell {

    static let identifier = "MomentsMediaCollectionViewCell"

    var previewImageView: UIImageView { imageView }

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = AppColor.AthensGray
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        InstaImageZoom.shared.gestureStateChanged(gesture, withZoomImageView: imageView)
    }

    /// Shows the thumbnail immediately, then swaps in the full-size photo when it arrives.
    func configure(thumbnailPath: String?, filePath: String?) {
        let thumbnail = thumbnailPath?.isEmpty == false ? thumbnailPath : nil
        let full = filePath?.isEmpty == false ? filePath : nil

        if let full, let url = Self.imageURL(for: full), ImageLoader.shared.cachedImage(for: url) != nil {
            imageView.loadImage(path: full)
            return
        }

        guard let full, full != thumbnail else {
            imageView.loadImage(path: thumbnail ?? full)
            return
        }

        if let thumbnail {
            imageView.loadImage(path: thumbnail) { [weak self] _ in
                self?.imageView.loadImage(path: full)
            }
        } else {
            imageView.loadImage(path: full)
        }
    }

    private static func imageURL(for path: String) -> URL? {
        URL(string: path.hasPrefix("http") ? path : ApiName.imgBaseURL + path)
    }
}
