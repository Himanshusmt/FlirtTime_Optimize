//
//  OtherUserBasicInfoCell.swift
//  FlirttimeNew
//
//  Row in the "More about me" card (icon, title, value). Layout lives in OtherUserProfile.storyboard.
//

import UIKit

final class OtherUserBasicInfoCell: UITableViewCell {
    static let identifier = "OtherUserBasicInfoCell"

    @IBOutlet private weak var iconImageView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var valueLabel: UILabel!
    @IBOutlet private weak var separatorView: UIView!

    func configure(info: OtherUserBasicInfo, isLast: Bool) {
        iconImageView.loadImage(path: info.iconPath)
        titleLabel.text = info.title
        valueLabel.text = info.value
        separatorView.isHidden = isLast
        accessibilityLabel = "\(info.title): \(info.value)"
    }
}
