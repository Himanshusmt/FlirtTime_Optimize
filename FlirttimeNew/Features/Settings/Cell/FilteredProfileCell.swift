//
//  FilteredProfileCell.swift
//  FlirttimeNew
//

import UIKit

final class FilteredProfileCell: UITableViewCell {

    static let identifier = "FilteredProfileCell"

    @IBOutlet private weak var avatarImageView: UIImageView!
    @IBOutlet private weak var nameLabel: UILabel!
    @IBOutlet private weak var subtitleLabel: UILabel!
    @IBOutlet private weak var actionButton: UIButton!
    @IBOutlet private weak var statusBadgeLabel: UILabel!

    var onAction: (() -> Void)?

    override func prepareForReuse() {
        super.prepareForReuse()
        onAction = nil
        avatarImageView.image = nil
    }

    func configure(with profile: FilteredProfile, kind: FilteredProfileKind) {
        nameLabel.text = profile.name
        avatarImageView.loadImage(path: profile.photo, placeholder: UIImage(named: "ProfileBlur"))
        actionButton.isHidden = kind != .blocked
        statusBadgeLabel.isHidden = kind != .reported
        switch kind {
        case .blocked:
            subtitleLabel.text = profile.location ?? "Can't see or message you"
            actionButton.accessibilityLabel = "Unblock \(profile.name)"
        case .reported:
            subtitleLabel.text = "Our team is reviewing this profile"
        }
    }

    @IBAction private func actionTapped(_ sender: UIButton) {
        onAction?()
    }
}
