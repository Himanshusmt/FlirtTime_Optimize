//
//  VibeComponents.swift
//  FlirttimeNew
//
//  Reusable pieces shared by the Vibe Card and the full Vibe Profile.
//

import UIKit

// MARK: - Fonts

enum VibeFont {
    /// Fredoka scaled for Dynamic Type.
    static func scaled(_ type: UIFont.Fredoka, _ size: CGFloat, style: UIFont.TextStyle = .body) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont.fredoka(type, size: size))
    }
}

extension UILabel {
    static func vibeLabel(_ type: UIFont.Fredoka, _ size: CGFloat, style: UIFont.TextStyle = .body,
                          color: UIColor = AppColor.MineShaft, lines: Int = 1) -> UILabel {
        let label = UILabel()
        label.font = VibeFont.scaled(type, size, style: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = lines
        return label
    }
}

// MARK: - Interest chips

/// Left-aligned wrapping chips. Shared interests are highlighted.
final class VibeChipsView: UIView {

    enum Style {
        case light
        /// Translucent chips for gradients.
        case onDark
        /// Solid white chips over photos.
        case onPhoto
        /// White outlined chips on light backgrounds.
        case outlined
    }

    var onTap: ((VibeInterest) -> Void)?
    /// 0 = unlimited.
    var maxLines = 0
    var style: Style = .light
    var isCentered = false
    /// Chips act as toggles: highlighted = selected.
    var isSelectable = false

    private var chips: [(interest: VibeInterest, button: UIButton)] = []
    private let spacing: CGFloat = 8
    private var lastLayoutWidth: CGFloat = 0

    func configure(_ interests: [VibeInterest], highlighted: Set<Int>, maxCount: Int = .max) {
        chips.forEach { $0.button.removeFromSuperview() }
        chips = interests.prefix(maxCount).map { interest in
            let isShared = highlighted.contains(interest.id)
            var config = UIButton.Configuration.filled()
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            switch style {
            case .light:
                config.baseBackgroundColor = isShared ? AppColor.Lavenderblush : AppColor.AthensGray
                config.baseForegroundColor = isShared ? AppColor.Punch : AppColor.MineShaft
            case .onDark:
                config.baseBackgroundColor = isShared ? UIColor.white : UIColor.white.withAlphaComponent(0.22)
                config.baseForegroundColor = isShared ? AppColor.Punch : UIColor.white
            case .onPhoto:
                config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.94)
                config.baseForegroundColor = isShared ? AppColor.Punch : AppColor.MineShaft
            case .outlined:
                config.baseBackgroundColor = AppColor.AppWhite
                config.baseForegroundColor = AppColor.MineShaft
                config.background.strokeColor = AppColor.Punch.withAlphaComponent(0.25)
                config.background.strokeWidth = 1
            }
            config.attributedTitle = AttributedString(interest.chipTitle, attributes: AttributeContainer([
                .font: VibeFont.scaled(.medium, 13, style: .footnote)
            ]))
            if isSelectable && isShared {
                config.background.strokeColor = AppColor.Punch
                config.background.strokeWidth = 1.5
            }
            let button = UIButton(configuration: config)
            if isSelectable {
                button.accessibilityLabel = interest.title
                button.accessibilityTraits = isShared ? [.button, .selected] : .button
            } else {
                button.accessibilityLabel = interest.title + (isShared ? ", shared interest" : "")
                button.accessibilityHint = "Discover more people into \(interest.title)"
            }
            button.addAction(UIAction { [weak self] _ in self?.onTap?(interest) }, for: .touchUpInside)
            addSubview(button)
            return (interest, button)
        }
        lastLayoutWidth = 0
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 64
        return CGSize(width: UIView.noIntrinsicMetric, height: layoutChips(width: width, apply: false))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        _ = layoutChips(width: bounds.width, apply: true)
        if lastLayoutWidth != bounds.width {
            lastLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            invalidateIntrinsicContentSize()
        }
    }

    @discardableResult
    private func layoutChips(width: CGFloat, apply: Bool) -> CGFloat {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line = 1
        var rowHeight: CGFloat = 0
        var visibleHeight: CGFloat = 0
        for chip in chips {
            let size = chip.button.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let chipWidth = min(size.width, width)
            if x > 0 && x + chipWidth > width {
                line += 1
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            let visible = maxLines == 0 || line <= maxLines
            if apply {
                chip.button.isHidden = !visible
                chip.button.frame = CGRect(x: x, y: y, width: chipWidth, height: size.height)
            }
            rowHeight = max(rowHeight, size.height)
            if visible {
                visibleHeight = max(visibleHeight, y + size.height)
            }
            x += chipWidth + spacing
        }
        if apply && isCentered {
            centerRows(width: width)
        }
        return visibleHeight
    }

    private func centerRows(width: CGFloat) {
        let rows = Dictionary(grouping: chips.map(\.button).filter { !$0.isHidden }, by: { $0.frame.minY })
        for buttons in rows.values {
            let rowWidth = (buttons.map(\.frame.maxX).max() ?? 0) - (buttons.map(\.frame.minX).min() ?? 0)
            let offset = max(0, (width - rowWidth) / 2)
            buttons.forEach { $0.frame.origin.x += offset }
        }
    }
}

// MARK: - Moments preview

/// `[Photo] [Photo] [Photo] [+2]`
final class MomentsPreviewView: UIView {

    var onTap: ((Int) -> Void)?

    private let stack = UIStackView()
    private let tileSize: CGFloat

    init(tileSize: CGFloat = 52) {
        self.tileSize = tileSize
        super.init(frame: .zero)
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: tileSize)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with moments: [VibeMoment], name: String, visibleCount: Int = 3) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let visible = moments.prefix(visibleCount)
        for (index, moment) in visible.enumerated() {
            let button = tile()
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.isUserInteractionEnabled = false
            imageView.frame = CGRect(x: 0, y: 0, width: tileSize, height: tileSize)
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.loadImage(path: moment.imagePath)
            button.addSubview(imageView)
            if moment.isVideo {
                let play = UIImageView(image: UIImage(systemName: "play.fill"))
                play.tintColor = .white
                play.frame = CGRect(x: tileSize / 2 - 9, y: tileSize / 2 - 9, width: 18, height: 18)
                button.addSubview(play)
            }
            button.accessibilityLabel = "\(name)'s moment \(index + 1) of \(moments.count)" + (moment.isVideo ? ", video" : "")
            button.addAction(UIAction { [weak self] _ in self?.onTap?(index) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        let remaining = moments.count - visible.count
        if remaining > 0 {
            let button = tile()
            button.backgroundColor = AppColor.AthensGray
            button.setTitle("+\(remaining)", for: .normal)
            button.setTitleColor(AppColor.MineShaft, for: .normal)
            button.titleLabel?.font = VibeFont.scaled(.bold, 15, style: .subheadline)
            button.accessibilityLabel = "\(remaining) more moments"
            button.addAction(UIAction { [weak self] _ in self?.onTap?(visible.count) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    private func tile() -> UIButton {
        let button = UIButton(type: .custom)
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: tileSize),
            button.heightAnchor.constraint(equalToConstant: tileSize)
        ])
        return button
    }
}

