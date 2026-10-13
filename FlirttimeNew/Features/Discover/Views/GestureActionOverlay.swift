//
//  GestureActionOverlay.swift
//  FlirttimeNew
//
//  Sticker shown only while dragging; it swaps when the drag direction changes.
//

import UIKit

final class GestureActionOverlay: UIView {

    private static let stickerSize: CGFloat = 104
    private static let haloInset: CGFloat = 10
    private static let titleSpacing: CGFloat = 10
    private static let titleHeight: CGFloat = 30

    private let tintView = UIView()
    private let badgeView = UIView()
    private let haloView = UIView()
    private let stickerView = UIView()
    private let gradientLayer = CAGradientLayer()
    private let iconView = UIImageView()
    private let sparkleViews = [UIImageView(), UIImageView(), UIImageView()]
    private let titlePill = UIView()
    private let titleLabel = UILabel()
    private(set) var action: MomentsAction?

    /// Area of the card the sticker is positioned in (the photo).
    var anchorRect: CGRect = .zero {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false

        addSubview(tintView)
        addSubview(badgeView)

        let size = Self.stickerSize
        let haloSize = size + Self.haloInset * 2
        haloView.frame = CGRect(x: 0, y: 0, width: haloSize, height: haloSize)
        haloView.layer.cornerRadius = haloSize / 2
        haloView.layer.borderWidth = 3
        haloView.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        badgeView.addSubview(haloView)

        stickerView.frame = CGRect(x: 0, y: 0, width: size, height: size)
        stickerView.layer.cornerRadius = size / 2
        stickerView.layer.borderWidth = 5
        stickerView.layer.borderColor = UIColor.white.cgColor
        stickerView.layer.shadowOpacity = 0.45
        stickerView.layer.shadowRadius = 14
        stickerView.layer.shadowOffset = CGSize(width: 0, height: 6)
        badgeView.addSubview(stickerView)

        gradientLayer.frame = stickerView.bounds
        gradientLayer.cornerRadius = size / 2
        gradientLayer.startPoint = CGPoint(x: 0.15, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.85, y: 1)
        stickerView.layer.insertSublayer(gradientLayer, at: 0)

        iconView.contentMode = .center
        iconView.tintColor = .white
        iconView.layer.shadowColor = UIColor.black.cgColor
        iconView.layer.shadowOpacity = 0.18
        iconView.layer.shadowRadius = 3
        iconView.layer.shadowOffset = CGSize(width: 0, height: 2)
        iconView.frame = stickerView.bounds
        stickerView.addSubview(iconView)

        for (index, sparkle) in sparkleViews.enumerated() {
            let pointSize: CGFloat = [22, 15, 12][index]
            sparkle.image = UIImage(systemName: "sparkle", withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold))
            sparkle.tintColor = .white
            sparkle.layer.shadowColor = UIColor.black.cgColor
            sparkle.layer.shadowOpacity = 0.25
            sparkle.layer.shadowRadius = 3
            sparkle.layer.shadowOffset = .zero
            sparkle.sizeToFit()
            badgeView.addSubview(sparkle)
        }

        titlePill.layer.cornerRadius = Self.titleHeight / 2
        titlePill.layer.borderWidth = 2
        titlePill.layer.borderColor = UIColor.white.cgColor
        titlePill.layer.shadowColor = UIColor.black.cgColor
        titlePill.layer.shadowOpacity = 0.2
        titlePill.layer.shadowRadius = 6
        titlePill.layer.shadowOffset = CGSize(width: 0, height: 3)
        badgeView.addSubview(titlePill)

        titleLabel.font = UIFont.fredoka(.bold, size: 16)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titlePill.addSubview(titleLabel)

        update(action: nil, progress: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(action: MomentsAction?, progress: CGFloat) {
        if action != self.action {
            self.action = action
            if let action {
                let isSuper = action == .superVibe
                iconView.image = UIImage(systemName: action.stickerSymbol,
                                         withConfiguration: UIImage.SymbolConfiguration(pointSize: isSuper ? 50 : 46, weight: .heavy))
                gradientLayer.colors = action.stickerColors.map(\.cgColor)
                stickerView.layer.shadowColor = action.tintColor.cgColor
                tintView.backgroundColor = action.tintColor
                haloView.isHidden = !isSuper
                haloView.backgroundColor = action.tintColor.withAlphaComponent(0.28)
                sparkleViews.forEach { $0.isHidden = !isSuper }
                titleLabel.text = action.displayName.uppercased()
                titlePill.backgroundColor = action.stickerColors.last
            }
            setNeedsLayout()
            layoutIfNeeded()
        }
        let clamped = max(0, min(progress, 1))
        let visible = action == nil ? 0 : clamped
        badgeView.alpha = visible
        tintView.alpha = visible * 0.14
        let scale = 0.55 + 0.45 * visible
        badgeView.transform = CGAffineTransform(rotationAngle: rotation).scaledBy(x: scale, y: scale)
    }

    private var rotation: CGFloat {
        switch action {
        case .interested: return -.pi / 12
        case .notMyVibe: return .pi / 12
        case .superVibe: return -.pi / 30
        case .nope: return .pi / 30
        case .none: return 0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tintView.frame = bounds

        let transform = badgeView.transform
        badgeView.transform = .identity

        let titleWidth = ceil(titleLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: Self.titleHeight)).width) + 32
        let haloSize = haloView.bounds.width
        let width = max(haloSize, titleWidth)
        let height = haloSize + Self.titleSpacing + Self.titleHeight
        badgeView.bounds = CGRect(x: 0, y: 0, width: width, height: height)

        let circleCenter = CGPoint(x: width / 2, y: haloSize / 2)
        haloView.center = circleCenter
        stickerView.center = circleCenter
        let radius = Self.stickerSize / 2
        sparkleViews[0].center = CGPoint(x: circleCenter.x + radius * 0.82, y: circleCenter.y - radius * 0.82)
        sparkleViews[1].center = CGPoint(x: circleCenter.x - radius * 0.95, y: circleCenter.y + radius * 0.55)
        sparkleViews[2].center = CGPoint(x: circleCenter.x - radius * 0.7, y: circleCenter.y - radius * 0.95)

        titlePill.frame = CGRect(x: (width - titleWidth) / 2, y: haloSize + Self.titleSpacing, width: titleWidth, height: Self.titleHeight)
        titleLabel.frame = titlePill.bounds

        let area = anchorRect == .zero ? bounds : anchorRect
        let inset: CGFloat = 20
        let top = area.minY + inset + 36 + height / 2
        switch action {
        case .interested:
            badgeView.center = CGPoint(x: area.minX + inset + width / 2, y: top)
        case .notMyVibe:
            badgeView.center = CGPoint(x: area.maxX - inset - width / 2, y: top)
        case .superVibe, .nope, .none:
            badgeView.center = CGPoint(x: area.midX, y: top)
        }
        badgeView.transform = transform
    }
}

private extension MomentsAction {
    var stickerSymbol: String {
        switch self {
        case .superVibe: return "bolt.heart.fill"
        case .interested: return "heart.fill"
        case .notMyVibe: return "heart.slash.fill"
        case .nope: return "hand.thumbsdown.fill"
        }
    }

    var stickerColors: [UIColor] {
        switch self {
        case .superVibe:
            return [UIColor(red: 1, green: 0.32, blue: 0.29, alpha: 1), UIColor(red: 0.78, green: 0, blue: 0.1, alpha: 1)]
        case .interested:
            return [UIColor(red: 1, green: 0.45, blue: 0.62, alpha: 1), UIColor(red: 0.91, green: 0.12, blue: 0.39, alpha: 1)]
        case .notMyVibe:
            return [UIColor(red: 0.36, green: 0.36, blue: 0.38, alpha: 1), AppColor.MineShaft]
        case .nope:
            return [UIColor(red: 0.66, green: 0.66, blue: 0.68, alpha: 1), AppColor.Boulder]
        }
    }
}
