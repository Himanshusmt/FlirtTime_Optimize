//
//  OtherUserPhotoCell.swift
//  FlirttimeNew
//
//  Photo card in the "Photos" carousel. Layout lives in OtherUserProfile.storyboard.
//

import UIKit

final class OtherUserPhotoCell: UICollectionViewCell {
    static let identifier = "OtherUserPhotoCell"

    @IBOutlet private weak var photoImageView: UIImageView!

    func configure(photoPath: String?, index: Int, total: Int, name: String) {
        photoImageView.loadImage(path: photoPath, placeholder: UIImage(named: "ProfileBlur"))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(name)'s photo \(index + 1) of \(total)"
    }
}
