//
//  ExploreSegmentHeaderView.swift
//  FlirttimeNew
//

import UIKit

enum ExploreTab: Int, CaseIterable {
    case likes
    case youLiked
    case matches
    case compliments

    init?(interactionType: String?) {
        switch interactionType {
        case Constants.UserInteractionTypes.likeYou: self = .likes
        case Constants.UserInteractionTypes.myLike: self = .youLiked
        case Constants.UserInteractionTypes.matches: self = .matches
        case Constants.UserInteractionTypes.compliment: self = .compliments
        default: return nil
        }
    }

    var interactionType: String {
        switch self {
        case .likes: return Constants.UserInteractionTypes.likeYou
        case .youLiked: return Constants.UserInteractionTypes.myLike
        case .matches: return Constants.UserInteractionTypes.matches
        case .compliments: return Constants.UserInteractionTypes.compliment
        }
    }

    var title: String {
        switch self {
        case .likes: return "Likes"
        case .youLiked: return "You Liked"
        case .matches: return "Matches"
        case .compliments: return "Compliments"
        }
    }

    var iconName: String {
        switch self {
        case .likes: return "heart.fill"
        case .youLiked: return "arrow.up.heart.fill"
        case .matches: return "flame.fill"
        case .compliments: return "sparkles"
        }
    }

    var emptyTitle: String {
        switch self {
        case .likes: return "No likes yet"
        case .youLiked: return "You haven't liked anyone yet"
        case .matches: return "No matches yet"
        case .compliments: return "No compliments yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .likes: return "Keep your profile fresh. People who like you will show up here."
        case .youLiked: return "Start swiping on Discover and the people you like will appear here."
        case .matches: return "When you and someone like each other, it's a match. They'll appear here."
        case .compliments: return "Sweet words from your admirers will land here."
        }
    }
}

final class ExploreSegmentHeaderView: UIView {

    var onSelect: ((ExploreTab) -> Void)?

    private let stackView = UIStackView()
    private let trackView = UIView()
    private let indicatorView = UIView()
    private var items: [ExploreSegmentItemView] = []
    private(set) var progress: CGFloat = 0

    private let indicatorHeight: CGFloat = 3
    private let indicatorExtraWidth: CGFloat = 18

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .clear
        clipsToBounds = false

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.clipsToBounds = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        trackView.backgroundColor = AppColor.AthensGray
        trackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trackView)

        indicatorView.backgroundColor = AppColor.Punch
        indicatorView.layer.cornerRadius = indicatorHeight / 2
        addSubview(indicatorView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: trackView.topAnchor, constant: -4),

            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            trackView.heightAnchor.constraint(equalToConstant: 1)
        ])

        for tab in ExploreTab.allCases {
            let item = ExploreSegmentItemView(tab: tab)
            item.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
            items.append(item)
            stackView.addArrangedSubview(item)
        }
        applyProgress()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutIndicator()
    }

    @objc private func itemTapped(_ sender: ExploreSegmentItemView) {
        onSelect?(sender.tab)
    }

    /// `progress` is the fractional page index (0 = first tab, 3 = last tab).
    func setProgress(_ progress: CGFloat) {
        let maxIndex = CGFloat(items.count - 1)
        self.progress = min(max(progress, 0), maxIndex)
        applyProgress()
        layoutIndicator()
    }

    func select(_ tab: ExploreTab, animated: Bool) {
        let update = { self.setProgress(CGFloat(tab.rawValue)) }
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5, options: [.beginFromCurrentState, .allowUserInteraction], animations: update)
        } else {
            update()
        }
    }

    func setCount(_ count: Int, for tab: ExploreTab) {
        items[tab.rawValue].setCount(count)
    }

    private func applyProgress() {
        for (index, item) in items.enumerated() {
            let weight = max(0, 1 - abs(progress - CGFloat(index)))
            item.setHighlight(weight)
        }
    }

    private func layoutIndicator() {
        guard !items.isEmpty, bounds.width > 0 else { return }
        stackView.layoutIfNeeded()

        let lower = Int(progress.rounded(.down))
        let upper = min(lower + 1, items.count - 1)
        let fraction = progress - CGFloat(lower)

        let fromFrame = indicatorFrame(for: items[lower])
        let toFrame = indicatorFrame(for: items[upper])

        indicatorView.frame = CGRect(
            x: fromFrame.minX + (toFrame.minX - fromFrame.minX) * fraction,
            y: trackView.frame.midY - indicatorHeight / 2,
            width: fromFrame.width + (toFrame.width - fromFrame.width) * fraction,
            height: indicatorHeight
        )
    }

    private func indicatorFrame(for item: ExploreSegmentItemView) -> CGRect {
        let itemFrame = item.convert(item.bounds, to: self)
        let width = min(item.titleWidth + indicatorExtraWidth, itemFrame.width - 8)
        return CGRect(x: itemFrame.midX - width / 2, y: 0, width: width, height: indicatorHeight)
    }
}

final class ExploreSegmentItemView: UIControl {

    let tab: ExploreTab

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let badgeLabel = ExploreBadgeLabel()
    private let contentStack = UIStackView()

    private let activeIconColor = AppColor.Punch
    private let activeTitleColor = AppColor.MineShaft
    private let inactiveColor = AppColor.LabelTextColor

    var titleWidth: CGFloat {
        titleLabel.intrinsicContentSize.width
    }

    init(tab: ExploreTab) {
        self.tab = tab
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        clipsToBounds = false
        iconView.image = UIImage(systemName: tab.iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = tab.title
        titleLabel.font = .fredoka(.medium, size: 13)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8

        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 4
        contentStack.isUserInteractionEnabled = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(titleLabel)
        addSubview(contentStack)

        badgeLabel.font = .fredoka(.medium, size: 10)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.backgroundColor = AppColor.Punch
        badgeLabel.layer.cornerRadius = 9
        badgeLabel.layer.borderWidth = 1.5
        badgeLabel.layer.borderColor = UIColor.white.cgColor
        badgeLabel.clipsToBounds = true
        badgeLabel.isHidden = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(badgeLabel)

        let badgeCenterX = badgeLabel.centerXAnchor.constraint(equalTo: iconView.trailingAnchor)
        badgeCenterX.priority = .defaultHigh
        NSLayoutConstraint.activate([
            iconView.heightAnchor.constraint(equalToConstant: 22),
            iconView.widthAnchor.constraint(equalToConstant: 24),

            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),

            badgeCenterX,
            badgeLabel.centerYAnchor.constraint(equalTo: iconView.topAnchor, constant: 2),
            badgeLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            badgeLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -1),
            badgeLabel.heightAnchor.constraint(equalToConstant: 18),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = tab.title
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.contentStack.alpha = self.isHighlighted ? 0.6 : 1
            }
        }
    }

    func setCount(_ count: Int) {
        badgeLabel.text = count > 99 ? "99+" : "\(count)"
        badgeLabel.isHidden = count <= 0
        badgeLabel.invalidateIntrinsicContentSize()
        accessibilityValue = count > 0 ? "\(count)" : nil
    }

    /// `weight` is 1 for the fully selected tab and 0 for a fully unselected tab.
    func setHighlight(_ weight: CGFloat) {
        iconView.tintColor = inactiveColor.blended(with: activeIconColor, fraction: weight)
        titleLabel.textColor = inactiveColor.blended(with: activeTitleColor, fraction: weight)
        let scale = 1 + 0.12 * weight
        iconView.transform = CGAffineTransform(scaleX: scale, y: scale)
        if weight >= 0.5 {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }
    }
}

private final class ExploreBadgeLabel: UILabel {

    var insets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

private extension UIColor {
    func blended(with other: UIColor, fraction: CGFloat) -> UIColor {
        let fraction = min(max(fraction, 0), 1)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            return fraction < 0.5 ? self : other
        }
        return UIColor(
            red: r1 + (r2 - r1) * fraction,
            green: g1 + (g2 - g1) * fraction,
            blue: b1 + (b2 - b1) * fraction,
            alpha: a1 + (a2 - a1) * fraction
        )
    }
}
