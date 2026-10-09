//
//  CoinViews.swift
//  FlirttimeNew
//

import UIKit

// MARK: - Header pill

/// Coin balance chip for screen headers: sized and shadowed like the round header buttons
/// next to it, with a gold coin, the live balance and a "+" that opens the Coin Shop.
final class CoinBalancePill: UIControl {

    static let height: CGFloat = 42

    private let coinBadge: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 15
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()

    private let coinImage: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "singleCoin"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let amountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.bold, size: 15)
        label.textColor = AppColor.MineShaft
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let plusBadge: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 11
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()

    private var balance: Int?

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = AppColor.AppWhite
        layer.cornerRadius = CoinBalancePill.height / 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)

        let coinGlow = VibeGradientView(colors: [VibeTheme.gold.withAlphaComponent(0.28), AppColor.BrightSun.withAlphaComponent(0.18)])
        coinBadge.addSubview(coinGlow)
        coinGlow.pinEdges(to: coinBadge)
        coinImage.translatesAutoresizingMaskIntoConstraints = false
        coinBadge.addSubview(coinImage)

        let plusGradient = VibeGradientView(colors: VibeTheme.brandGradient)
        plusBadge.addSubview(plusGradient)
        plusGradient.pinEdges(to: plusBadge)
        let plusImage = UIImageView(image: UIImage(systemName: "plus",
                                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .heavy)))
        plusImage.tintColor = .white
        plusImage.translatesAutoresizingMaskIntoConstraints = false
        plusBadge.addSubview(plusImage)

        let row = UIStackView(arrangedSubviews: [coinBadge, amountLabel, plusBadge])
        row.alignment = .center
        row.spacing = 6
        row.setCustomSpacing(8, after: amountLabel)
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: CoinBalancePill.height),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),

            coinBadge.widthAnchor.constraint(equalToConstant: 30),
            coinBadge.heightAnchor.constraint(equalToConstant: 30),
            coinImage.centerXAnchor.constraint(equalTo: coinBadge.centerXAnchor),
            coinImage.centerYAnchor.constraint(equalTo: coinBadge.centerYAnchor),
            coinImage.widthAnchor.constraint(equalToConstant: 20),
            coinImage.heightAnchor.constraint(equalToConstant: 20),

            plusBadge.widthAnchor.constraint(equalToConstant: 22),
            plusBadge.heightAnchor.constraint(equalToConstant: 22),
            plusImage.centerXAnchor.constraint(equalTo: plusBadge.centerXAnchor),
            plusImage.centerYAnchor.constraint(equalTo: plusBadge.centerYAnchor)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Coins"
        accessibilityHint = "Opens the coin shop"
        amountLabel.text = "0"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
    }

    func setBalance(_ newBalance: Int, animated: Bool = true) {
        let previous = balance
        balance = newBalance
        amountLabel.text = newBalance.vibeCountText
        accessibilityValue = "\(newBalance) coins"

        guard animated, let previous, previous != newBalance, !UIAccessibility.isReduceMotionEnabled else { return }
        let transition = CATransition()
        transition.type = .push
        transition.subtype = newBalance > previous ? .fromTop : .fromBottom
        transition.duration = 0.25
        amountLabel.layer.add(transition, forKey: "balance")

        UIView.animateKeyframes(withDuration: 0.5, delay: 0) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                self.coinImage.transform = CGAffineTransform(scaleX: 1.3, y: 1.3).rotated(by: .pi)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5) {
                self.coinImage.transform = .identity
            }
        }
    }
}

// MARK: - Balance

final class CoinBalanceCard: UIView {

    private let amountLabel = UILabel.vibeLabel(.bold, 36, style: .largeTitle, color: .white)
    private let coinImage = UIImageView(image: UIImage(named: "singleCoin"))

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 24
        clipsToBounds = true
        let background = VibeGradientView(colors: VibeTheme.brandGradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 1))
        addSubview(background)
        background.pinEdges(to: self)

        let decoration = UIImageView(image: UIImage(named: "coins"))
        decoration.contentMode = .scaleAspectFit
        decoration.alpha = 0.35
        decoration.transform = CGAffineTransform(rotationAngle: -0.2)
        decoration.translatesAutoresizingMaskIntoConstraints = false
        addSubview(decoration)

        let caption = UILabel.vibeLabel(.medium, 14, style: .subheadline, color: UIColor.white.withAlphaComponent(0.85))
        caption.text = "Your balance"
        coinImage.contentMode = .scaleAspectFit
        coinImage.setContentHuggingPriority(.required, for: .horizontal)
        let amountRow = UIStackView(arrangedSubviews: [coinImage, amountLabel])
        amountRow.spacing = 10
        amountRow.alignment = .center
        let hint = UILabel.vibeLabel(.regular, 13, style: .footnote, color: UIColor.white.withAlphaComponent(0.85), lines: 0)
        hint.text = "Use coins for Super Vibes, compliments and calls."
        let stack = UIStackView(arrangedSubviews: [caption, amountRow, hint])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(10, after: amountRow)
        addSubview(stack)
        stack.pinEdges(to: self, insets: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20))

        NSLayoutConstraint.activate([
            coinImage.widthAnchor.constraint(equalToConstant: 34),
            coinImage.heightAnchor.constraint(equalToConstant: 34),
            decoration.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 10),
            decoration.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            decoration.widthAnchor.constraint(equalToConstant: 130),
            decoration.heightAnchor.constraint(equalToConstant: 76)
        ])
        layer.shadowColor = AppColor.Punch.cgColor
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setBalance(_ balance: Int) {
        amountLabel.text = balance.formatted()
        accessibilityLabel = "Your balance, \(balance) coins"
    }

    func celebrate() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIView.animateKeyframes(withDuration: 0.5, delay: 0) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                self.coinImage.transform = CGAffineTransform(scaleX: 1.35, y: 1.35).rotated(by: .pi)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5) {
                self.coinImage.transform = .identity
            }
        }
    }
}

// MARK: - Premium upsell

final class CoinPremiumUpsellCard: UIControl {

    init() {
        super.init(frame: .zero)
        backgroundColor = AppColor.AppWhite
        layer.cornerRadius = 18
        layer.borderWidth = 1
        layer.borderColor = AppColor.Punch.withAlphaComponent(0.4).cgColor

        let icon = UIImageView(image: UIImage(systemName: "crown.fill"))
        icon.tintColor = VibeTheme.gold
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let title = UILabel.vibeLabel(.bold, 15, style: .subheadline, color: AppColor.AppBlack)
        title.text = "Go Premium"
        let subtitle = UILabel.vibeLabel(.regular, 13, style: .footnote, color: AppColor.DoveGray, lines: 0)
        subtitle.text = "Unlimited Vibes, free chats and bonus coins with every plan."
        let text = UIStackView(arrangedSubviews: [title, subtitle])
        text.axis = .vertical
        text.spacing = 2
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = AppColor.Silver
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [icon, text, chevron])
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Go Premium. Unlimited Vibes, free chats and bonus coins with every plan."
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }
}

// MARK: - Pack card

final class CoinPackCardView: UIControl {

    private(set) var packID: Int?

    private let card = UIView()
    private let coinImage = UIImageView(image: UIImage(named: "singleCoin"))
    private let amountLabel = UILabel.vibeLabel(.bold, 20, style: .title3, color: AppColor.AppBlack)
    private let unitLabel = UILabel.vibeLabel(.medium, 12, style: .caption1, color: AppColor.DoveGray)
    private let bonusLabel = UILabel.vibeLabel(.bold, 11, style: .caption2, color: AppColor.OceanGreen)
    private let priceButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColor.Punch
        config.baseForegroundColor = .white
        config.activityIndicatorColorTransformer = UIConfigurationColorTransformer { _ in .white }
        config.titleLineBreakMode = .byClipping
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
        let button = UIButton(configuration: config)
        button.isUserInteractionEnabled = false
        return button
    }()
    private var badge: StoreBadgeView?

    var isPurchasing = false {
        didSet {
            priceButton.configuration?.showsActivityIndicator = isPurchasing
            accessibilityValue = isPurchasing ? "Purchasing" : nil
        }
    }

    override var isEnabled: Bool {
        didSet { card.alpha = isEnabled || isPurchasing ? 1 : 0.55 }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.card.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    private static let cornerRadius: CGFloat = 18

    /// Rounded, clipped surface inside `card`, so the top tint follows the corners while
    /// `card` keeps its unclipped drop shadow.
    private let surface: UIView = {
        let view = UIView()
        view.backgroundColor = AppColor.AppWhite
        view.layer.cornerRadius = CoinPackCardView.cornerRadius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()

    private let topTint = VibeGradientView(colors: [AppColor.Punch.withAlphaComponent(0.12), AppColor.AppWhite.withAlphaComponent(0)],
                                           start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))

    init() {
        super.init(frame: .zero)
        card.isUserInteractionEnabled = false
        card.backgroundColor = .clear
        card.layer.cornerRadius = CoinPackCardView.cornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 0
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.12
        card.layer.shadowRadius = 12
        card.layer.shadowOffset = CGSize(width: 0, height: 6)

        card.addSubview(surface)
        surface.pinEdges(to: card)
        topTint.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(topTint)
        NSLayoutConstraint.activate([
            topTint.topAnchor.constraint(equalTo: surface.topAnchor),
            topTint.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            topTint.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            topTint.heightAnchor.constraint(equalTo: surface.heightAnchor, multiplier: 0.55)
        ])

        coinImage.contentMode = .scaleAspectFit
        unitLabel.text = "coins"
        [amountLabel, unitLabel, bonusLabel].forEach { $0.textAlignment = .center }

        let stack = UIStackView(arrangedSubviews: [coinImage, amountLabel, unitLabel, bonusLabel, priceButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.setCustomSpacing(8, after: coinImage)
        stack.setCustomSpacing(4, after: unitLabel)
        stack.setCustomSpacing(10, after: bonusLabel)
        amountLabel.adjustsFontSizeToFitWidth = true
        amountLabel.minimumScaleFactor = 0.7

        addSubview(card)
        card.pinEdges(to: self, insets: UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0))
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            coinImage.widthAnchor.constraint(equalToConstant: 32),
            coinImage.heightAnchor.constraint(equalToConstant: 32),
            priceButton.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.layer.shadowPath = UIBezierPath(roundedRect: card.bounds, cornerRadius: CoinPackCardView.cornerRadius).cgPath
    }

    func configure(with option: CoinsViewModel.PackOption) {
        packID = option.pack.id
        let coins = option.pack.coins ?? 0
        let bonus = option.pack.bonusCoins ?? 0
        amountLabel.text = coins.formatted()
        bonusLabel.text = bonus > 0 ? "+\(bonus.formatted()) bonus" : " "
        priceButton.configuration?.attributedTitle = AttributedString(option.displayPrice, attributes: AttributeContainer([
            .font: VibeFont.scaled(.bold, 13, style: .footnote)
        ]))
        priceButton.titleLabel?.adjustsFontSizeToFitWidth = true
        priceButton.titleLabel?.minimumScaleFactor = 0.7

        badge?.removeFromSuperview()
        badge = nil
        let highlight = option.isBestValue ? "BEST VALUE" : option.isPopular ? "POPULAR" : nil
        if let highlight {
            let badge = StoreBadgeView(text: highlight,
                                       colors: option.isBestValue ? [VibeTheme.gold, AppColor.BrightSun] : VibeTheme.brandGradient)
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.centerYAnchor.constraint(equalTo: card.topAnchor),
                badge.centerXAnchor.constraint(equalTo: card.centerXAnchor)
            ])
            self.badge = badge
        }
        let accent: UIColor? = highlight == nil ? nil : (option.isBestValue ? VibeTheme.gold : AppColor.Punch)
        surface.layer.borderColor = accent?.cgColor
        surface.layer.borderWidth = accent == nil ? 0 : 1.5
        card.layer.shadowColor = (accent ?? .black).cgColor
        card.layer.shadowOpacity = accent == nil ? 0.12 : 0.25

        accessibilityLabel = [highlight?.capitalized, "\(coins) coins", bonus > 0 ? "plus \(bonus) bonus" : nil, option.displayPrice]
            .compactMap { $0 }.joined(separator: ", ")
        accessibilityHint = "Buys this coin pack"
    }
}
