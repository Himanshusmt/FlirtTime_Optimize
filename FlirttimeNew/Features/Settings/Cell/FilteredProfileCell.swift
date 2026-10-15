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
            subtitleLabel.text = profile.subtitle ?? "Can't see or message you"
            actionButton.accessibilityLabel = "Unblock \(profile.name)"
        case .reported:
            subtitleLabel.text = profile.subtitle?.isEmpty == false ? profile.subtitle : "Our team is reviewing this profile"
            let style = Self.statusStyle(for: profile.status)
            statusBadgeLabel.text = style.text
            statusBadgeLabel.textColor = style.color
            statusBadgeLabel.backgroundColor = style.color.withAlphaComponent(0.12)
        }
    }

    private static func statusStyle(for status: String?) -> (text: String, color: UIColor) {
        switch status?.lowercased() {
        case "reviewed": return ("Reviewed", .systemBlue)
        case "resolved": return ("Resolved", .systemGreen)
        case "dismissed": return ("Dismissed", AppColor.DoveGray)
        default: return ("In review", UIColor(red: 0.94, green: 0.56, blue: 0, alpha: 1))
        }
    }

    @IBAction private func actionTapped(_ sender: UIButton) {
        onAction?()
    }
}
