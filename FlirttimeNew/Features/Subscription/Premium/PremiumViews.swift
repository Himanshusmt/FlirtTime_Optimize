//
//  PremiumViews.swift
//  FlirttimeNew
//
//  Pieces of the Premium paywall, in the app's red / blush palette.
//

import UIKit

enum PremiumTheme {
    static let accent = AppColor.Punch
    static let accentSoft = AppColor.Lavenderblush
    static let stroke = AppColor.Iron
    static let primaryText = AppColor.MineShaft
    static let secondaryText = AppColor.DoveGray
    static let tertiaryText = AppColor.Boulder
    static let savings = AppColor.OceanGreen

    /// Blush circle with a red symbol, like the interest chips.
    static func iconBubble(_ symbol: String?, size: CGFloat, pointSize: CGFloat) -> UIView {
        let bubble = UIView()
        bubble.backgroundColor = accentSoft
        bubble.layer.cornerRadius = size / 2
        let icon = UIImageView(image: UIImage(systemName: symbol ?? "") ?? UIImage(systemName: "heart.fill"))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        icon.tintColor = accent
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(icon)
        NSLayoutConstraint.activate([
            bubble.widthAnchor.constraint(equalToConstant: size),
            bubble.heightAnchor.constraint(equalToConstant: size),
            icon.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: bubble.centerYAnchor)
        ])
        bubble.isAccessibilityElement = false
        return bubble
    }

    static func applyCardShadow(to view: UIView) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.06
        view.layer.shadowRadius = 12
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
    }
}

// MARK: - Hero

/// Brand-gradient header with the Flirttime mark, like the tab bar's centre button.
final class PremiumHeroView: UIView {

    init(title: NSAttributedString, subtitle: String) {
        super.init(frame: .zero)
        layer.cornerRadius = 28
        clipsToBounds = true
        let background = VibeGradientView(colors: VibeTheme.brandGradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 1))
        addSubview(background)
        background.pinEdges(to: self)
        addFloatingHearts()

        let logo = makeLogo()
        let chip = UILabel.vibeLabel(.bold, 12, style: .caption1, color: .white)
        chip.text = "  FLIRTTIME PREMIUM  "
        chip.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        chip.layer.cornerRadius = 12
        chip.clipsToBounds = true
        chip.textAlignment = .center
        chip.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let titleLabel = UILabel.vibeLabel(.bold, 26, style: .title1, color: .white, lines: 0)
        titleLabel.attributedText = title
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits = .header
        let subtitleLabel = UILabel.vibeLabel(.regular, 15, color: UIColor.white.withAlphaComponent(0.9), lines: 0)
        subtitleLabel.text = subtitle
        subtitleLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [logo, chip, titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(16, after: logo)
        stack.setCustomSpacing(12, after: chip)
        addSubview(stack)
        stack.pinEdges(to: self, insets: UIEdgeInsets(top: 26, left: 22, bottom: 24, right: 22))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeLogo() -> UIView {
        let ring = UIView()
        ring.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        ring.layer.cornerRadius = 46
        let core = VibeGradientView(colors: [AppColor.MexicanRed, AppColor.Punch], start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 1))
        core.layer.cornerRadius = 36
        core.clipsToBounds = true
        core.layer.borderWidth = 3
        core.layer.borderColor = UIColor.white.cgColor
        let mark = UIImageView(image: UIImage(named: "LogoFT"))
        mark.contentMode = .scaleAspectFit
        let crown = UIImageView(image: UIImage(systemName: "crown.fill"))
        crown.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        crown.tintColor = AppColor.Punch
        crown.contentMode = .center
        crown.backgroundColor = .white
        crown.layer.cornerRadius = 15
        crown.layer.shadowColor = UIColor.black.cgColor
        crown.layer.shadowOpacity = 0.15
        crown.layer.shadowRadius = 4
        crown.layer.shadowOffset = CGSize(width: 0, height: 2)

        [core, mark, crown].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            ring.addSubview($0)
        }
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 92),
            ring.heightAnchor.constraint(equalToConstant: 92),
            core.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            core.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            core.widthAnchor.constraint(equalToConstant: 72),
            core.heightAnchor.constraint(equalToConstant: 72),
            mark.centerXAnchor.constraint(equalTo: core.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: core.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: 34),
            mark.heightAnchor.constraint(equalToConstant: 34),
            crown.widthAnchor.constraint(equalToConstant: 30),
            crown.heightAnchor.constraint(equalToConstant: 30),
            crown.topAnchor.constraint(equalTo: ring.topAnchor, constant: 2),
            crown.trailingAnchor.constraint(equalTo: ring.trailingAnchor, constant: -2)
        ])
        ring.isAccessibilityElement = false
        return ring
    }

    private func addFloatingHearts() {
        let hearts: [(x: CGFloat, y: CGFloat, size: CGFloat, alpha: CGFloat, angle: CGFloat)] = [
            (0.08, 0.14, 26, 0.18, -0.3), (0.86, 0.10, 34, 0.16, 0.25), (0.92, 0.62, 22, 0.2, 0.4),
            (0.05, 0.70, 30, 0.14, -0.2), (0.24, 0.40, 14, 0.22, 0.1), (0.76, 0.36, 16, 0.2, -0.15)
        ]
        for heart in hearts {
            let view = UIImageView(image: UIImage(systemName: "heart.fill"))
            view.tintColor = UIColor.white.withAlphaComponent(heart.alpha)
            view.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: heart.size)
            view.transform = CGAffineTransform(rotationAngle: heart.angle)
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                NSLayoutConstraint(item: view, attribute: .centerX, relatedBy: .equal, toItem: self, attribute: .trailing, multiplier: heart.x, constant: 0),
                NSLayoutConstraint(item: view, attribute: .centerY, relatedBy: .equal, toItem: self, attribute: .bottom, multiplier: heart.y, constant: 0)
            ])
            if !UIAccessibility.isReduceMotionEnabled {
                UIView.animate(withDuration: Double.random(in: 2.2...3.4), delay: Double.random(in: 0...1),
                               options: [.autoreverse, .repeat, .curveEaseInOut, .allowUserInteraction]) {
                    view.transform = view.transform.translatedBy(x: 0, y: -8)
                }
            }
        }
    }
}

// MARK: - CTA

/// Solid app-red capsule, matching the app's primary buttons.
final class PremiumCTAButton: UIButton {

    init() {
        super.init(frame: .zero)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColor.Punch
        config.baseForegroundColor = .white
        config.image = UIImage(systemName: "crown.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))
        config.imagePadding = 10
        config.activityIndicatorColorTransformer = UIConfigurationColorTransformer { _ in .white }
        configuration = config

        layer.shadowColor = AppColor.Punch.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 6)
        configurationUpdateHandler = { button in
            UIView.animate(withDuration: 0.15) {
                button.transform = button.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
        heightAnchor.constraint(equalToConstant: 56).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitle(_ title: String) {
        configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: VibeFont.scaled(.bold, 18)]))
        accessibilityLabel = title
    }
}

// MARK: - Restore

/// Outlined capsule for restoring App Store purchases.
final class PremiumRestoreButton: UIButton {

    init() {
        super.init(frame: .zero)
        var config = UIButton.Configuration.plain()
        config.cornerStyle = .capsule
        config.baseForegroundColor = PremiumTheme.accent
        config.image = UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        config.attributedTitle = AttributedString("Restore", attributes: AttributeContainer([.font: VibeFont.scaled(.bold, 15)]))
        config.background.backgroundColor = AppColor.AppWhite
        config.background.strokeColor = PremiumTheme.accent.withAlphaComponent(0.35)
        config.background.strokeWidth = 1.2
        config.activityIndicatorColorTransformer = UIConfigurationColorTransformer { _ in PremiumTheme.accent }
        configuration = config
        accessibilityLabel = "Restore purchases"
        configurationUpdateHandler = { button in
            button.alpha = button.isEnabled ? (button.isHighlighted ? 0.7 : 1) : 0.5
        }
        heightAnchor.constraint(equalToConstant: 40).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isLoading = false {
        didSet {
            configuration?.showsActivityIndicator = isLoading
            isUserInteractionEnabled = !isLoading
        }
    }
}

// MARK: - Benefit card

struct PremiumBenefit {
    let symbol: String
    let title: String
    let detail: String
}

final class PremiumBenefitCard: UIView {

    init(_ benefit: PremiumBenefit) {
        super.init(frame: .zero)
        let card = UIView()
        card.backgroundColor = AppColor.AppWhite
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 1
        card.layer.borderColor = PremiumTheme.stroke.cgColor
        PremiumTheme.applyCardShadow(to: card)

        let icon = PremiumTheme.iconBubble(benefit.symbol, size: 48, pointSize: 20)
        let title = UILabel.vibeLabel(.bold, 17, style: .headline, color: PremiumTheme.primaryText)
        title.text = benefit.title
        let detail = UILabel.vibeLabel(.regular, 14, style: .subheadline, color: PremiumTheme.secondaryText, lines: 2)
        detail.text = benefit.detail
        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 3
        let row = UIStackView(arrangedSubviews: [icon, text])
        row.spacing = 14
        row.alignment = .center
        card.addSubview(row)
        row.pinEdges(to: card, insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
        addSubview(card)
        card.pinEdges(to: self, insets: UIEdgeInsets(top: 4, left: 2, bottom: 10, right: 2))
        isAccessibilityElement = true
        accessibilityLabel = "\(benefit.title). \(benefit.detail)"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Plan tile

/// `1 / month / ₹499 / ₹116/wk`
final class PremiumPlanTile: UIControl {

    private let card = UIView()
    private let countLabel = UILabel.vibeLabel(.bold, 34, style: .largeTitle, color: PremiumTheme.primaryText)
    private let unitLabel = UILabel.vibeLabel(.medium, 15, style: .subheadline, color: PremiumTheme.secondaryText)
    private let divider = UIView()
    private let priceLabel = UILabel.vibeLabel(.bold, 17, style: .headline, color: PremiumTheme.primaryText)
    private let weeklyLabel = UILabel.vibeLabel(.regular, 12, style: .caption1, color: PremiumTheme.tertiaryText)
    private let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    private var ribbon: StoreBadgeView?

    override var isSelected: Bool { didSet { updateAppearance() } }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.card.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    init() {
        super.init(frame: .zero)
        card.isUserInteractionEnabled = false
        card.layer.cornerRadius = 20
        PremiumTheme.applyCardShadow(to: card)

        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        [countLabel, unitLabel, priceLabel, weeklyLabel].forEach { $0.textAlignment = .center }
        check.tintColor = PremiumTheme.accent
        check.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        check.backgroundColor = .white
        check.layer.cornerRadius = 9

        let stack = UIStackView(arrangedSubviews: [countLabel, unitLabel, divider, priceLabel, weeklyLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.setCustomSpacing(12, after: unitLabel)
        stack.setCustomSpacing(12, after: divider)

        addSubview(card)
        card.pinEdges(to: self, insets: UIEdgeInsets(top: 12, left: 0, bottom: 4, right: 0))
        [stack, check].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview($0)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 112),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -14),
            check.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            check.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8)
        ])
        isAccessibilityElement = true
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with option: PremiumViewModel.PlanOption, savings: Int?) {
        let parts = option.durationParts
        countLabel.text = parts.count
        unitLabel.text = parts.unit
        priceLabel.text = option.displayPrice
        weeklyLabel.text = option.pricePerWeek ?? "billed weekly"

        ribbon?.removeFromSuperview()
        let isPopular = option.plan.isPopular == true
        let ribbonText = isPopular ? "MOST POPULAR" : savings.map { "SAVE \($0)%" }
        if let ribbonText {
            let badge = StoreBadgeView(text: ribbonText, colors: isPopular ? VibeTheme.brandGradient : [PremiumTheme.savings])
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.centerYAnchor.constraint(equalTo: card.topAnchor),
                badge.centerXAnchor.constraint(equalTo: card.centerXAnchor),
                badge.widthAnchor.constraint(lessThanOrEqualTo: card.widthAnchor, constant: 8)
            ])
            ribbon = badge
        }
        accessibilityLabel = [option.title, ribbonText?.capitalized, option.displayPrice, option.pricePerWeek]
            .compactMap { $0 }.joined(separator: ", ")
    }

    private func updateAppearance() {
        card.backgroundColor = isSelected ? PremiumTheme.accentSoft : AppColor.AppWhite
        card.layer.borderWidth = isSelected ? 2 : 1
        card.layer.borderColor = (isSelected ? PremiumTheme.accent : PremiumTheme.stroke).cgColor
        card.layer.shadowOpacity = isSelected ? 0.12 : 0.05
        card.layer.shadowColor = (isSelected ? PremiumTheme.accent : UIColor.black).cgColor
        divider.backgroundColor = isSelected ? PremiumTheme.accent.withAlphaComponent(0.2) : PremiumTheme.stroke
        countLabel.textColor = isSelected ? PremiumTheme.accent : PremiumTheme.primaryText
        check.isHidden = !isSelected
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

// MARK: - Free vs Premium

final class PremiumComparisonCard: UIView {

    private let titleLabel = UILabel.vibeLabel(.bold, 17, style: .headline, color: PremiumTheme.primaryText)
    private let rows = UIStackView()

    init() {
        super.init(frame: .zero)
        backgroundColor = AppColor.AppWhite
        layer.cornerRadius = 22
        layer.borderWidth = 1
        layer.borderColor = PremiumTheme.stroke.cgColor
        PremiumTheme.applyCardShadow(to: self)
        titleLabel.accessibilityTraits = .header
        titleLabel.numberOfLines = 0
        rows.axis = .vertical
        rows.spacing = 14

        let freeHeader = UILabel.vibeLabel(.medium, 12, style: .caption1, color: PremiumTheme.tertiaryText)
        freeHeader.text = "Free"
        freeHeader.textAlignment = .center
        let premiumHeader = UILabel.vibeLabel(.bold, 12, style: .caption1, color: .white)
        premiumHeader.text = "Premium"
        premiumHeader.textAlignment = .center
        premiumHeader.backgroundColor = PremiumTheme.accent
        premiumHeader.layer.cornerRadius = 11
        premiumHeader.clipsToBounds = true
        let header = UIStackView(arrangedSubviews: [titleLabel, freeHeader, premiumHeader])
        header.alignment = .center
        header.spacing = 8
        NSLayoutConstraint.activate([
            freeHeader.widthAnchor.constraint(equalToConstant: 44),
            premiumHeader.widthAnchor.constraint(equalToConstant: 66),
            premiumHeader.heightAnchor.constraint(equalToConstant: 22)
        ])

        let divider = UIView()
        divider.backgroundColor = PremiumTheme.stroke
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let stack = UIStackView(arrangedSubviews: [header, divider, rows])
        stack.axis = .vertical
        stack.spacing = 14
        addSubview(stack)
        stack.pinEdges(to: self, insets: UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(planTitle: String, features: [PlanFeature], bonusCoins: Int) {
        titleLabel.text = "Included in \(planTitle)"
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for feature in features {
            rows.addArrangedSubview(row(icon: feature.image, text: feature.text ?? ""))
        }
        if bonusCoins > 0 {
            rows.addArrangedSubview(row(icon: nil, text: "\(bonusCoins) bonus coins", coin: true))
        }
    }

    private func row(icon: String?, text: String, coin: Bool = false) -> UIView {
        let iconView: UIView
        if coin {
            let image = UIImageView(image: UIImage(named: "singleCoin"))
            image.contentMode = .scaleAspectFit
            image.translatesAutoresizingMaskIntoConstraints = false
            let bubble = UIView()
            bubble.addSubview(image)
            NSLayoutConstraint.activate([
                bubble.widthAnchor.constraint(equalToConstant: 32),
                bubble.heightAnchor.constraint(equalToConstant: 32),
                image.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
                image.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 26),
                image.heightAnchor.constraint(equalToConstant: 26)
            ])
            iconView = bubble
        } else if let icon, icon.hasPrefix("http") || icon.contains("/") {
            let bubble = PremiumTheme.iconBubble(nil, size: 32, pointSize: 13)
            let remote = UIImageView()
            remote.contentMode = .scaleAspectFit
            remote.loadImage(path: icon)
            remote.frame = CGRect(x: 7, y: 7, width: 18, height: 18)
            bubble.subviews.forEach { $0.isHidden = true }
            bubble.addSubview(remote)
            iconView = bubble
        } else {
            iconView = PremiumTheme.iconBubble(icon, size: 32, pointSize: 13)
        }
        let label = UILabel.vibeLabel(.medium, 15, color: PremiumTheme.primaryText, lines: 0)
        label.text = text
        let free = UIImageView(image: UIImage(systemName: "lock.fill"))
        free.tintColor = AppColor.Silver
        free.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        free.contentMode = .center
        let premium = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        premium.tintColor = PremiumTheme.accent
        premium.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        premium.contentMode = .center
        let row = UIStackView(arrangedSubviews: [iconView, label, free, premium])
        row.spacing = 8
        row.alignment = .center
        row.setCustomSpacing(12, after: iconView)
        NSLayoutConstraint.activate([
            free.widthAnchor.constraint(equalToConstant: 44),
            premium.widthAnchor.constraint(equalToConstant: 66)
        ])
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(text): locked on Free, included with Premium"
        return row
    }
}

// MARK: - Coin shop shortcut

/// Uses the Shop icon from the original card-swipe screen.
final class PremiumShopCard: UIControl {

    init() {
        super.init(frame: .zero)
        backgroundColor = AppColor.AppWhite
        layer.cornerRadius = 20
        layer.borderWidth = 1
        layer.borderColor = PremiumTheme.stroke.cgColor
        PremiumTheme.applyCardShadow(to: self)

        let title = UILabel.vibeLabel(.bold, 15, style: .subheadline, color: PremiumTheme.primaryText)
        title.text = "Just need a few coins?"
        let subtitle = UILabel.vibeLabel(.regular, 13, style: .footnote, color: PremiumTheme.secondaryText, lines: 0)
        subtitle.text = "Top up for Super Vibes, compliments and calls."
        let text = UIStackView(arrangedSubviews: [title, subtitle])
        text.axis = .vertical
        text.spacing = 2
        let shop = UIImageView(image: UIImage(named: "delete-shop"))
        shop.contentMode = .scaleAspectFit
        shop.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [text, shop])
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 14))
        NSLayoutConstraint.activate([
            shop.widthAnchor.constraint(equalToConstant: 88),
            shop.heightAnchor.constraint(equalToConstant: 31)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Coin shop. Top up for Super Vibes, compliments and calls."
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }
}

// MARK: - Member banner

final class PremiumMemberBanner: UIView {

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 18
        layer.borderWidth = 1
        layer.borderColor = PremiumTheme.accent.withAlphaComponent(0.3).cgColor
        backgroundColor = PremiumTheme.accentSoft

        let icon = PremiumTheme.iconBubble("crown.fill", size: 40, pointSize: 17)
        icon.backgroundColor = .white
        let title = UILabel.vibeLabel(.bold, 16, style: .headline, color: PremiumTheme.accent)
        title.text = "You're a Premium member"
        let subtitle = UILabel.vibeLabel(.regular, 13, style: .footnote, color: PremiumTheme.secondaryText, lines: 0)
        subtitle.text = "Everything is unlocked. Enjoy the vibes!"
        let text = UIStackView(arrangedSubviews: [title, subtitle])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [icon, text])
        row.spacing = 12
        row.alignment = .center
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
        isAccessibilityElement = true
        accessibilityLabel = "You're a Premium member. Everything is unlocked."
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
