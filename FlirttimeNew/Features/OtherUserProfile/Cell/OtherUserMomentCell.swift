//
//  OtherUserMomentCell.swift
//  FlirttimeNew
//
//  Tile in the "Moments" grid. Layout lives in OtherUserProfile.storyboard.
//

import UIKit

final class OtherUserMomentCell: UICollectionViewCell {
    static let identifier = "OtherUserMomentCell"

    @IBOutlet private weak var momentImageView: UIImageView!
    @IBOutlet private weak var textBackgroundView: UIView!
    @IBOutlet private weak var textMomentLabel: UILabel!
    @IBOutlet private weak var likeCountLabel: UILabel!

    /// Photo moments show their first photo; text-only moments show the caption on a gradient.
    func configure(vibe: MomentsPost, index: Int, total: Int) {
        let photo = (vibe.media ?? []).compactMap(\.filePath).first { !$0.isEmpty }
        let caption = vibe.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        momentImageView.isHidden = photo == nil
        textBackgroundView.isHidden = photo != nil
        textMomentLabel.isHidden = photo != nil
        textMomentLabel.text = caption
        if let photo {
            momentImageView.loadImage(path: photo, placeholder: UIImage(named: "ProfileBlur"))
        } else {
            momentImageView.image = nil
        }

        let likes = vibe.likesCount ?? 0
        let comments = vibe.commentsCount ?? 0
        likeCountLabel.text = "♥ \(likes.vibeCountText)  💬 \(comments.vibeCountText)"

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Moment \(index + 1) of \(total)"
            + (caption.isEmpty ? "" : ". \(caption)")
            + ", \(likes) likes, \(comments) comments"
    }
}

/// Last tile of the "Moments" grid when the user has more moments than the grid shows.
/// Built in code (not in the storyboard) and registered by `OtherUserProfileViewController`.
final class OtherUserSeeAllMomentsCell: UICollectionViewCell {
    static let identifier = "OtherUserSeeAllMomentsCell"

    private let backgroundImageView = UIImageView()
    private let dimView = UIView()
    private let countLabel = UILabel()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        contentView.layer.cornerRadius = 14
        contentView.clipsToBounds = true
        contentView.backgroundColor = AppColor.Punch

        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        countLabel.font = MomentsFont.scaled(.bold, 26, style: .title2)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = .white
        countLabel.textAlignment = .center

        titleLabel.font = MomentsFont.scaled(.medium, 15, style: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.text = "See all"

        let stack = UIStackView(arrangedSubviews: [countLabel, titleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center

        [backgroundImageView, dimView, stack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        backgroundImageView.pinEdges(to: contentView)
        dimView.pinEdges(to: contentView)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    /// `previewVibe` is the first hidden moment; its photo sits dimmed behind the label.
    func configure(remainingCount: Int, previewVibe: MomentsPost?) {
        countLabel.text = "+\(remainingCount)"
        let photo = (previewVibe?.media ?? []).compactMap(\.filePath).first { !$0.isEmpty }
        if let photo {
            backgroundImageView.loadImage(path: photo, placeholder: nil)
        } else {
            backgroundImageView.image = nil
        }
        dimView.isHidden = photo == nil
        accessibilityLabel = "See all moments, \(remainingCount) more"
    }
}
