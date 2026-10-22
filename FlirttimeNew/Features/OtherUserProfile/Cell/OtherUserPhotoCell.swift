//
//  OtherUserPhotoCell.swift
//  FlirttimeNew
//
//  Photo card in the "Photos" carousel. Layout lives in OtherUserProfile.storyboard.
//

import UIKit

final class OtherUserPhotoCell: UICollectionViewCell {
    static let identifier = "OtherUserPhotoCell"
    private static let cornerRadius: CGFloat = 20

    @IBOutlet private weak var photoImageView: UIImageView!

    override func awakeFromNib() {
        super.awakeFromNib()
        clipsToBounds = false
        contentView.clipsToBounds = false
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
        photoImageView.layer.cornerRadius = Self.cornerRadius
        photoImageView.clipsToBounds = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Self.cornerRadius).cgPath
    }

    func configure(photoPath: String?, index: Int, total: Int, name: String) {
        photoImageView.loadImage(path: photoPath, placeholder: UIImage(named: "ProfileBlur"))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(name)'s photo \(index + 1) of \(total)"
    }
}
