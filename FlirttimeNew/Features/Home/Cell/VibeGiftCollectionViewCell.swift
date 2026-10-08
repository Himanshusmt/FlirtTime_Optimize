//
//  VibeGiftCollectionViewCell.swift
//  FlirttimeNew
//

import UIKit

final class VibeGiftCollectionViewCell: UICollectionViewCell {

    static let identifier = "VibeGiftCollectionViewCell"

    private let iconLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 34)
        label.textAlignment = .center
        return label
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 12)
        label.textColor = AppColor.DoveGray
        label.textAlignment = .center
        return label
    }()

    private let coinImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "singleCoin"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.medium, size: 13)
        label.textColor = AppColor.MineShaft
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        contentView.layer.cornerRadius = 12
        contentView.layer.borderWidth = 1
        contentView.backgroundColor = AppColor.WildSand

        let amountStack = UIStackView(arrangedSubviews: [coinImageView, amountLabel])
        amountStack.axis = .horizontal
        amountStack.spacing = 3
        amountStack.alignment = .center

        let iconContainer = UIView()
        [iconLabel, iconImageView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            iconContainer.addSubview($0)
            NSLayoutConstraint.activate([
                $0.topAnchor.constraint(equalTo: iconContainer.topAnchor),
                $0.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
                $0.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
                $0.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor)
            ])
        }

        let stack = UIStackView(arrangedSubviews: [iconContainer, titleLabel, amountStack])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 4),
            iconContainer.widthAnchor.constraint(equalToConstant: 40),
            iconContainer.heightAnchor.constraint(equalToConstant: 40),
            coinImageView.widthAnchor.constraint(equalToConstant: 14),
            coinImageView.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with gift: VibeGift, isSelected: Bool) {
        let icon = gift.icon ?? ""
        if icon.hasPrefix("http") {
            iconLabel.text = nil
            iconImageView.loadImage(path: icon)
        } else {
            iconImageView.image = nil
            iconLabel.text = icon
        }
        titleLabel.text = gift.title
        amountLabel.text = "\(gift.amount ?? 0)"
        contentView.layer.borderColor = (isSelected ? AppColor.Punch : UIColor.clear).cgColor
        contentView.backgroundColor = isSelected ? AppColor.Lavenderblush : AppColor.WildSand
        accessibilityLabel = "\(gift.title ?? "Gift"), \(gift.amount ?? 0) coins"
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
