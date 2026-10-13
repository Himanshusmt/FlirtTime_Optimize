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
