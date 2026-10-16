//
//  StoreComponents.swift
//  FlirttimeNew
//
//  Pieces shared by the Premium and Coin Shop screens.
//

import UIKit

enum StoreUI {

    static func circleButton(symbol: String, label: String, onDark: Bool) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = onDark ? UIColor.white.withAlphaComponent(0.18) : AppColor.AppWhite
        config.baseForegroundColor = onDark ? .white : AppColor.MineShaft
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))
        let button = UIButton(configuration: config)
        if !onDark {
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.08
            button.layer.shadowRadius = 8
            button.layer.shadowOffset = CGSize(width: 0, height: 3)
        }
        button.accessibilityLabel = label
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
        return button
    }

    static func linkButton(_ title: String, color: UIColor = AppColor.DoveGray, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = color
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: MomentsFont.scaled(.medium, 13, style: .footnote),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]))
        let button = UIButton(configuration: config)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}

/// Small capsule tag such as "MOST POPULAR" or "+100 coins".
final class StoreBadgeView: UIView {

    private let label = UILabel.vibeLabel(.bold, 11, style: .caption2, color: .white)
    private var gradient: MomentsGradientView?

    var text: String? {
        get { label.text }
        set { label.text = newValue }
    }

    init(text: String, colors: [UIColor] = MomentsTheme.brandGradient, textColor: UIColor = .white) {
        super.init(frame: .zero)
        if colors.count > 1 {
            let gradient = MomentsGradientView(colors: colors, start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5))
            addSubview(gradient)
            gradient.pinEdges(to: self)
            self.gradient = gradient
        } else {
            backgroundColor = colors.first
        }
        clipsToBounds = true
        label.text = text
        label.textColor = textColor
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        ])
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

// MARK: - Active membership card (accordion)

/// Compact Premium row with chevron:
/// ▼ expands plan details · Benefits expands perks · ▲ collapses everything.
final class SubscriptionMembershipCard: UIView {

    var onManage: (() -> Void)?

    private var isExpanded = false
    private var benefitsExpanded = false
    private var collapsedSubtitle = "Tap the arrow to view plan details"

    private let crownView: UIImageView = {
        let image = UIImageView(image: UIImage(systemName: "crown.fill",
                                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)))
        image.tintColor = MomentsTheme.gold
        image.contentMode = .center
        image.backgroundColor = AppColor.AppWhite
        image.layer.cornerRadius = 22
        return image
    }()

    private let welcomeLabel: UILabel = {
        let label = UILabel.vibeLabel(.bold, 15, style: .subheadline, color: AppColor.Punch)
        label.text = "You're a Premium user"
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel.vibeLabel(.regular, 12, style: .caption1, color: AppColor.DoveGray)
        label.text = "Tap the arrow to view plan details"
        return label
    }()

    private let statusChip = MembershipStatusChip()

    private lazy var chevronButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = AppColor.Punch
        config.image = UIImage(systemName: "chevron.down",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in self?.toggleExpanded() }, for: .touchUpInside)
        button.accessibilityLabel = "Show plan details"
        return button
    }()

    private let headerView = UIView()
    private let detailsPanel = UIView()
    private let planLabel = UILabel.vibeLabel(.bold, 16, style: .headline, color: AppColor.AppBlack)
    private let priceLabel = UILabel.vibeLabel(.regular, 13, style: .footnote, color: AppColor.DoveGray)
    private let autoRenewLabel = UILabel.vibeLabel(.medium, 12, style: .caption1, color: AppColor.DoveGray)
    private let daysBanner = UIView()
    private let daysTitleLabel = UILabel.vibeLabel(.bold, 18, style: .headline, color: AppColor.Punch)
    private let daysSubtitleLabel = UILabel.vibeLabel(.regular, 12, style: .caption1, color: AppColor.DoveGray)
    private let startedBox = MembershipDateBox()
    private let expiresBox = MembershipDateBox()

    private lazy var benefitsButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.cornerStyle = .capsule
        config.baseForegroundColor = AppColor.Punch
        config.background.strokeColor = AppColor.Punch
        config.background.strokeWidth = 1.5
        config.background.backgroundColor = .clear
        config.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12)
        config.attributedTitle = AttributedString("Benefits", attributes: AttributeContainer([
            .font: MomentsFont.scaled(.bold, 14)
        ]))
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in self?.toggleBenefits() }, for: .touchUpInside)
        return button
    }()

    private lazy var manageButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColor.Punch
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12)
        config.attributedTitle = AttributedString("Manage", attributes: AttributeContainer([
            .font: MomentsFont.scaled(.bold, 14)
        ]))
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in self?.onManage?() }, for: .touchUpInside)
        return button
    }()

    private let benefitsPanel = UIView()
    private let benefitsTitleLabel = UILabel.vibeLabel(.bold, 13, style: .footnote, color: AppColor.AppBlack)
    private let benefitsStack = UIStackView()
    private var rootStack: UIStackView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ membership: MySubscriptionData) {
        statusChip.configure(text: membership.displayStatus, isActive: membership.isCurrentlyActive)

        planLabel.text = membership.displayPlanName

        if let days = membership.daysRemainingTitle {
            collapsedSubtitle = "\(membership.displayPlanName) · \(days)"
        } else if let price = membership.priceLine {
            collapsedSubtitle = "\(membership.displayPlanName) · \(price)"
        } else {
            collapsedSubtitle = "\(membership.displayStatus) · \(membership.autoRenewalLine)"
        }
        subtitleLabel.text = isExpanded
            ? "Everything is unlocked — enjoy Flirttime Premium."
            : collapsedSubtitle

        if let price = membership.priceLine {
            priceLabel.text = price
            priceLabel.isHidden = false
        } else {
            priceLabel.isHidden = true
        }

        autoRenewLabel.text = membership.autoRenewalLine
        autoRenewLabel.isHidden = false

        if let daysTitle = membership.daysRemainingTitle {
            daysTitleLabel.text = daysTitle
            daysSubtitleLabel.text = membership.daysRemainingSubtitle
            daysBanner.isHidden = false
        } else {
            daysTitleLabel.text = membership.displayStatus
            daysSubtitleLabel.text = membership.renewalSummary
            daysBanner.isHidden = false
        }

        startedBox.configure(title: "Started", value: membership.formattedPurchaseDate ?? "—")
        let endTitle = membership.autoRenew == true ? "Renews" : "Expires"
        expiresBox.configure(title: endTitle, value: membership.formattedExpiry ?? "—")

        let apiBenefits = membership.benefitTexts
        let planFeatures = SubscriptionPlanStore.shared.options
            .first { $0.plan.appleProductID == membership.productId }?
            .plan.features?
            .compactMap(\.text)
            .filter { !$0.isEmpty }
        if let apiBenefits, !apiBenefits.isEmpty {
            setBenefits(apiBenefits)
        } else if let planFeatures, !planFeatures.isEmpty {
            setBenefits(planFeatures)
        } else {
            setBenefits(Self.defaultBenefits)
        }

        setExpanded(false, animated: false)
        setBenefitsExpanded(false, animated: false)

        accessibilityLabel = "You're a Premium user. \(membership.displayStatus). \(membership.autoRenewalLine)."
    }

    private func setUI() {
        // Same soft blush surface as the Profile “No Moments yet” placeholder.
        backgroundColor = AppColor.Lavenderblush
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = 0
        layer.shadowOpacity = 0

        NSLayoutConstraint.activate([
            crownView.widthAnchor.constraint(equalToConstant: 44),
            crownView.heightAnchor.constraint(equalToConstant: 44),
            chevronButton.widthAnchor.constraint(equalToConstant: 36),
            chevronButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        let text = UIStackView(arrangedSubviews: [welcomeLabel, subtitleLabel])
        text.axis = .vertical
        text.spacing = 2

        let headerRow = UIStackView(arrangedSubviews: [crownView, text, statusChip, chevronButton])
        headerRow.alignment = .center
        headerRow.spacing = 10

        headerView.addSubview(headerRow)
        headerRow.pinEdges(to: headerView)

        // Details (plan / days / dates / actions)
        let planBlock = UIStackView(arrangedSubviews: [planLabel, priceLabel, autoRenewLabel])
        planBlock.axis = .vertical
        planBlock.spacing = 2

        daysBanner.backgroundColor = AppColor.AppWhite
        daysBanner.layer.cornerRadius = 14
        daysBanner.layer.cornerCurve = .continuous
        let daysText = UIStackView(arrangedSubviews: [daysTitleLabel, daysSubtitleLabel])
        daysText.axis = .vertical
        daysText.spacing = 2
        daysBanner.addSubview(daysText)
        daysText.pinEdges(to: daysBanner, insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))

        let datesRow = UIStackView(arrangedSubviews: [startedBox, expiresBox])
        datesRow.spacing = 8
        datesRow.distribution = .fillEqually

        let actions = UIStackView(arrangedSubviews: [benefitsButton, manageButton])
        actions.spacing = 10
        actions.distribution = .fillEqually

        benefitsTitleLabel.text = "What you get"
        benefitsStack.axis = .vertical
        benefitsStack.spacing = 8
        let benefitsContent = UIStackView(arrangedSubviews: [benefitsTitleLabel, benefitsStack])
        benefitsContent.axis = .vertical
        benefitsContent.spacing = 8
        benefitsPanel.addSubview(benefitsContent)
        benefitsContent.pinEdges(to: benefitsPanel, insets: UIEdgeInsets(top: 4, left: 0, bottom: 0, right: 0))
        benefitsPanel.isHidden = true

        let detailsStack = UIStackView(arrangedSubviews: [planBlock, daysBanner, datesRow, actions, benefitsPanel])
        detailsStack.axis = .vertical
        detailsStack.spacing = 12
        detailsPanel.addSubview(detailsStack)
        detailsStack.pinEdges(to: detailsPanel, insets: UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0))
        detailsPanel.isHidden = true

        rootStack = UIStackView(arrangedSubviews: [headerView, detailsPanel])
        rootStack.axis = .vertical
        rootStack.spacing = 0
        addSubview(rootStack)
        rootStack.pinEdges(to: self, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
    }

    private func toggleExpanded() {
        MomentsHaptics.threshold()
        setExpanded(!isExpanded, animated: true)
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        isExpanded = expanded
        if !expanded {
            setBenefitsExpanded(false, animated: false)
        }

        chevronButton.configuration?.image = UIImage(
            systemName: expanded ? "chevron.up" : "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        )
        chevronButton.accessibilityLabel = expanded ? "Hide plan details" : "Show plan details"
        subtitleLabel.text = expanded
            ? "Everything is unlocked — enjoy Flirttime Premium."
            : collapsedSubtitle

        let updates = {
            self.detailsPanel.isHidden = !expanded
            self.detailsPanel.alpha = expanded ? 1 : 0
            self.superview?.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseInOut, animations: updates)
        } else {
            updates()
        }
    }

    private func toggleBenefits() {
        guard isExpanded else { return }
        MomentsHaptics.threshold()
        setBenefitsExpanded(!benefitsExpanded, animated: true)
    }

    private func setBenefitsExpanded(_ expanded: Bool, animated: Bool) {
        benefitsExpanded = expanded
        let title = expanded ? "Hide benefits" : "Benefits"
        benefitsButton.configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: MomentsFont.scaled(.bold, 14)
        ]))
        benefitsButton.configuration?.background.backgroundColor = expanded ? AppColor.AppWhite : .clear

        let updates = {
            self.benefitsPanel.isHidden = !expanded
            self.benefitsPanel.alpha = expanded ? 1 : 0
            self.superview?.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: updates)
        } else {
            updates()
        }
    }

    private func setBenefits(_ items: [String]) {
        benefitsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items {
            let row = UIStackView()
            row.spacing = 8
            row.alignment = .top
            let bullet = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
            bullet.tintColor = AppColor.Punch
            bullet.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            bullet.setContentHuggingPriority(.required, for: .horizontal)
            let label = UILabel.vibeLabel(.regular, 13, style: .footnote, color: AppColor.DoveGray, lines: 0)
            label.text = item
            row.addArrangedSubview(bullet)
            row.addArrangedSubview(label)
            benefitsStack.addArrangedSubview(row)
        }
    }

    private static let defaultBenefits = [
        "Unlimited Likes",
        "See who likes you",
        "Free chats & compliments",
        "Match without ads",
        "Priority in Discover",
        "Weekly Super Likes"
    ]
}

/// Capsule status pill (“Active” / inactive).
private final class MembershipStatusChip: UIView {

    private let label = UILabel.vibeLabel(.bold, 11, style: .caption2, color: AppColor.OceanGreen)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        label.textAlignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(label)
        label.pinEdges(to: self, insets: UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10))
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        configure(text: "Active", isActive: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func configure(text: String, isActive: Bool) {
        label.text = text
        let tint = isActive ? AppColor.OceanGreen : AppColor.DoveGray
        label.textColor = tint
        backgroundColor = tint.withAlphaComponent(0.14)
    }
}

private final class MembershipDateBox: UIView {

    private let titleLabel = UILabel.vibeLabel(.medium, 11, style: .caption2, color: AppColor.DoveGray)
    private let valueLabel = UILabel.vibeLabel(.bold, 12, style: .caption1, color: AppColor.AppBlack, lines: 2)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AppColor.AppWhite
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 3
        addSubview(stack)
        stack.pinEdges(to: self, insets: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, value: String) {
        titleLabel.text = title
        valueLabel.text = value
    }
}
