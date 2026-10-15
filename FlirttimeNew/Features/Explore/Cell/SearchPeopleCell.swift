//
//  SearchPeopleCell.swift
//  FlirttimeNew
//
//  Profile card on the Search People screen. The layout lives in SearchPeople.storyboard.
//

import UIKit

final class SearchPeopleCell: UICollectionViewCell {

    static let identifier = "SearchPeopleCell"

    @IBOutlet private weak var photoImageView: UIImageView!
    @IBOutlet private weak var nameLabel: UILabel!
    @IBOutlet private weak var verifiedImageView: UIImageView!
    @IBOutlet private weak var locationStackView: UIStackView!
    @IBOutlet private weak var locationLabel: UILabel!
    @IBOutlet private weak var onlineBadgeView: UIView!
    @IBOutlet private weak var distanceStackView: UIStackView!
    @IBOutlet private weak var distanceLabel: UILabel!

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 18).cgPath
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        photoImageView.image = nil
    }

    func configure(with person: UserSearchResult) {
        photoImageView.loadImage(path: person.profilePhoto)
        let name = person.displayName
        if let age = person.age, age > 0 {
            nameLabel.text = "\(name), \(age)"
        } else {
            nameLabel.text = name
        }
        verifiedImageView.isHidden = person.isVerified != true
        locationLabel.text = person.city
        locationStackView.isHidden = person.city?.isEmpty ?? true
        onlineBadgeView.isHidden = person.isOnline != true

        let distanceText = person.distanceKm?.kmAwayText
        distanceLabel.text = distanceText
        distanceStackView.isHidden = distanceText == nil
    }
}
