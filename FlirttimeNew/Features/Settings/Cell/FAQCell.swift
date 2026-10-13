//
//  FAQCell.swift
//  FlirttimeNew
//

import UIKit

final class FAQCell: UITableViewCell {

    static let identifier = "FAQCell"

    @IBOutlet private weak var questionLabel: UILabel!
    @IBOutlet private weak var answerLabel: UILabel!
    @IBOutlet private weak var chevronImageView: UIImageView!

    func configure(with item: FAQItem, isExpanded: Bool, animated: Bool = false) {
        questionLabel.text = item.question
        answerLabel.text = item.answer
        answerLabel.isHidden = !isExpanded
        accessibilityTraits = .button
        accessibilityValue = isExpanded ? "Expanded" : "Collapsed"
        let rotation = isExpanded ? CGAffineTransform(rotationAngle: .pi) : .identity
        if animated {
            UIView.animate(withDuration: 0.25) { self.chevronImageView.transform = rotation }
        } else {
            chevronImageView.transform = rotation
        }
    }
}
