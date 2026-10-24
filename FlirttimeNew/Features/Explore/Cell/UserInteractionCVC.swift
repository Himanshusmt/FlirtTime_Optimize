//
//  UserInteractionCVC.swift
//  FlirtTime
//
//  Created by Smt MacMini on 13/01/25.
//

import UIKit

class UserInteractionCVC: UICollectionViewCell {
    
    static let identifier = "UserInteractionCVC"

    let userImage = UIImageView()
    let imgVerify = UIImageView()
    let lblName = UILabel()
    let lblSubtitle = UILabel()
    let lblDistance = UILabel()
    let superLikeImgView = UIImageView()
    private let superLikeBadge = UIView()

    private let cardView = UIView()
    private let gradientLayer = CAGradientLayer()
    private let onlineBadge = UIView()
    private let distanceRow = UIStackView()
    var blurEffectView: UIVisualEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)

        cardView.backgroundColor = AppColor.AthensGray
        cardView.layer.cornerRadius = 18
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        userImage.contentMode = .scaleAspectFill
        userImage.clipsToBounds = true
        userImage.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(userImage)

        gradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.75).cgColor]
        gradientLayer.locations = [0.45, 1]
        cardView.layer.addSublayer(gradientLayer)

        lblName.font = .fredoka(.bold, size: 16)
        lblName.textColor = .white
        lblName.adjustsFontSizeToFitWidth = true
        lblName.minimumScaleFactor = 0.8

        imgVerify.image = UIImage(named: "verified")
        imgVerify.contentMode = .scaleAspectFit
        imgVerify.setContentHuggingPriority(.required, for: .horizontal)
        imgVerify.setContentCompressionResistancePriority(.required, for: .horizontal)

        let nameRow = UIStackView(arrangedSubviews: [lblName, imgVerify])
        nameRow.spacing = 4
        nameRow.alignment = .center

        let distanceIcon = UIImageView(image: UIImage(systemName: "figure.walk"))
        distanceIcon.tintColor = UIColor.white.withAlphaComponent(0.85)
        distanceIcon.contentMode = .scaleAspectFit
        distanceIcon.setContentHuggingPriority(.required, for: .horizontal)
        distanceIcon.setContentCompressionResistancePriority(.required, for: .horizontal)

        lblDistance.font = .fredoka(.medium, size: 12)
        lblDistance.textColor = UIColor.white.withAlphaComponent(0.85)

        distanceRow.addArrangedSubview(distanceIcon)
        distanceRow.addArrangedSubview(lblDistance)
        distanceRow.spacing = 4
        distanceRow.alignment = .center
        distanceRow.isHidden = true

        lblSubtitle.font = .fredoka(.regular, size: 12)
        lblSubtitle.textColor = UIColor.white.withAlphaComponent(0.85)
        lblSubtitle.numberOfLines = 2

        let infoStack = UIStackView(arrangedSubviews: [nameRow, distanceRow, lblSubtitle])
        infoStack.axis = .vertical
        infoStack.spacing = 2
        infoStack.alignment = .leading
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(infoStack)

        setUpOnlineBadge()

        contentView.clipsToBounds = false
        clipsToBounds = false

        superLikeImgView.image = UIImage(named: MomentsProfileActionButton.imageName)
        superLikeImgView.contentMode = .scaleAspectFit
        superLikeImgView.backgroundColor = .clear
        superLikeImgView.clipsToBounds = true
        superLikeImgView.isHidden = true
        superLikeImgView.translatesAutoresizingMaskIntoConstraints = false

        superLikeBadge.backgroundColor = .clear
        superLikeBadge.isHidden = true
        superLikeBadge.layer.shadowColor = UIColor.black.cgColor
        superLikeBadge.layer.shadowOpacity = 0.35
        superLikeBadge.layer.shadowRadius = 6
        superLikeBadge.layer.shadowOffset = CGSize(width: 0, height: 2)
        superLikeBadge.translatesAutoresizingMaskIntoConstraints = false
        superLikeBadge.addSubview(superLikeImgView)
        contentView.addSubview(superLikeBadge)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            userImage.topAnchor.constraint(equalTo: cardView.topAnchor),
            userImage.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            userImage.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            userImage.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            imgVerify.widthAnchor.constraint(equalToConstant: 14),
            imgVerify.heightAnchor.constraint(equalToConstant: 14),

            distanceIcon.widthAnchor.constraint(equalToConstant: 11),
            distanceIcon.heightAnchor.constraint(equalToConstant: 11),

            infoStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            infoStack.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -12),
            infoStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),

            superLikeBadge.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            superLikeBadge.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            superLikeBadge.widthAnchor.constraint(equalToConstant: 32),
            superLikeBadge.heightAnchor.constraint(equalToConstant: 32),

            superLikeImgView.topAnchor.constraint(equalTo: superLikeBadge.topAnchor),
            superLikeImgView.leadingAnchor.constraint(equalTo: superLikeBadge.leadingAnchor),
            superLikeImgView.trailingAnchor.constraint(equalTo: superLikeBadge.trailingAnchor),
            superLikeImgView.bottomAnchor.constraint(equalTo: superLikeBadge.bottomAnchor)
        ])
    }

    private func setUpOnlineBadge() {
        let dot = UIView()
        dot.backgroundColor = UIColor.systemGreen
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Online"
        label.font = .fredoka(.medium, size: 11)
        label.textColor = .white

        let row = UIStackView(arrangedSubviews: [dot, label])
        row.spacing = 5
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false

        onlineBadge.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        onlineBadge.layer.cornerRadius = 11
        onlineBadge.isHidden = true
        onlineBadge.translatesAutoresizingMaskIntoConstraints = false
        onlineBadge.addSubview(row)
        cardView.addSubview(onlineBadge)

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            row.leadingAnchor.constraint(equalTo: onlineBadge.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: onlineBadge.trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: onlineBadge.centerYAnchor),
            onlineBadge.heightAnchor.constraint(equalToConstant: 22),
            onlineBadge.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            onlineBadge.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = cardView.bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 18).cgPath
        superLikeBadge.layer.shadowPath = UIBezierPath(ovalIn: superLikeBadge.bounds).cgPath
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        removeBlur()
        userImage.image = nil
        lblSubtitle.text = nil
        lblDistance.text = nil
        distanceRow.isHidden = true
        superLikeImgView.isHidden = true
        superLikeBadge.isHidden = true
        onlineBadge.isHidden = true
    }

    func configure(imagePath: String?, name: String?, age: Int?, distanceText: String?, subtitle: String?, isVerified: Bool, isOnline: Bool, isSuperLike: Bool, isLocked: Bool) {
        lblDistance.text = distanceText
        distanceRow.isHidden = distanceText == nil
        userImage.loadImage(path: imagePath)
        let displayName = name ?? ""
        if let age, age > 0 {
            lblName.text = "\(displayName), \(age)"
        } else {
            lblName.text = displayName
        }
        lblSubtitle.text = subtitle
        lblSubtitle.isHidden = subtitle?.isEmpty ?? true
        imgVerify.isHidden = !isVerified
        onlineBadge.isHidden = !isOnline || isLocked
        superLikeImgView.isHidden = !isSuperLike
        superLikeBadge.isHidden = !isSuperLike
        if isLocked {
            applyBlur()
        } else {
            removeBlur()
        }
    }

    func applyBlur() {
        // Prevent multiple blur layers
        if blurEffectView == nil {
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
            blurView.frame = cardView.bounds
            blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            let lockIcon = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)))
            lockIcon.tintColor = .white
            let lockLabel = UILabel()
            lockLabel.text = "Unlock to see"
            lockLabel.font = .fredoka(.medium, size: 12)
            lockLabel.textColor = .white
            let lockStack = UIStackView(arrangedSubviews: [lockIcon, lockLabel])
            lockStack.axis = .vertical
            lockStack.alignment = .center
            lockStack.spacing = 6
            lockStack.translatesAutoresizingMaskIntoConstraints = false
            blurView.contentView.addSubview(lockStack)
            NSLayoutConstraint.activate([
                lockStack.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor),
                lockStack.centerYAnchor.constraint(equalTo: blurView.contentView.centerYAnchor)
            ])

            cardView.addSubview(blurView)
            blurEffectView = blurView
        }
    }
    
    func removeBlur() {
        blurEffectView?.removeFromSuperview()
        blurEffectView = nil
    }
}
