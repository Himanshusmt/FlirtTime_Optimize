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

    override func prepareForReuse() {
        super.prepareForReuse()
        iconImageView.image = nil
    }

    /// Attribute icons already include their own ring, so they fill the bubble; answers without one get a symbol.
    func configure(info: OtherUserBasicInfo, isLast: Bool) {
        if let iconPath = info.iconPath, !iconPath.isEmpty {
            iconImageView.contentMode = .scaleAspectFit
            iconImageView.loadImage(path: iconPath)
        } else {
            iconImageView.contentMode = .center
            iconImageView.tintColor = AppColor.Punch
            iconImageView.image = UIImage(systemName: "sparkles",
                                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        }
        titleLabel.text = info.title
        valueLabel.text = info.value
        separatorView.isHidden = isLast
        accessibilityLabel = "\(info.title): \(info.value)"
    }
}
