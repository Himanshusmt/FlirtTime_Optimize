//
//  VibeMediaCollectionViewCell.swift
//  FlirttimeNew
//

import UIKit

/// Photo tile used by the vibe feed carousel.
final class VibeMediaCollectionViewCell: UICollectionViewCell {

    static let identifier = "VibeMediaCollectionViewCell"

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

    func configure(path: String?) {
        imageView.loadImage(path: path)
    }
}
