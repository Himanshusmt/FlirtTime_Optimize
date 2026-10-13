//
//  DiscoverTabViews.swift
//  FlirttimeNew
//
//  Discover's People / Quick Moments / Interests switcher and the Interests page.
//

import UIKit

// MARK: - Pill tabs

final class MomentsPillTabsView: UIControl {

    private(set) var selectedIndex = 0
    private var buttons: [UIButton] = []

    init(titles: [String]) {
        super.init(frame: .zero)
        let stack = UIStackView()
        stack.spacing = 8
        stack.distribution = .fillProportionally
        for (index, title) in titles.enumerated() {
            var config = UIButton.Configuration.filled()
            config.cornerStyle = .capsule
            config.titleLineBreakMode = .byTruncatingTail
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: MomentsFont.scaled(.medium, 15, style: .subheadline)]))
            let button = UIButton(configuration: config)
            button.addAction(UIAction { [weak self] _ in self?.select(index, sendsActions: true) }, for: .touchUpInside)
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        addSubview(stack)
        stack.pinEdges(to: self)
        accessibilityTraits = .tabBar
        select(0, sendsActions: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(_ index: Int, sendsActions: Bool) {
        selectedIndex = index
        for (i, button) in buttons.enumerated() {
            let isSelected = i == index
            button.configuration?.baseBackgroundColor = isSelected ? AppColor.Punch : AppColor.AthensGray
            button.configuration?.baseForegroundColor = isSelected ? .white : AppColor.MineShaft
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
            button.layer.shadowColor = AppColor.Punch.cgColor
            button.layer.shadowOpacity = isSelected ? 0.3 : 0
            button.layer.shadowRadius = 8
            button.layer.shadowOffset = CGSize(width: 0, height: 4)
        }
        if sendsActions {
            UISelectionFeedbackGenerator().selectionChanged()
            sendActions(for: .valueChanged)
        }
    }
}

// MARK: - Interests page

final class DiscoverInterestsView: UIView {

    var onSelectProfile: ((MomentsProfile) -> Void)?
    var onDiscoverInterest: ((MomentsInterest) -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let gridStack = UIStackView()
    private let peopleTitle = UILabel.vibeLabel(.bold, 18, style: .headline, color: AppColor.AppBlack)
    private let peopleRow = UIStackView()
    private lazy var seeAllInterestsButton = seeAllButton { [weak self] in
        guard let self else { return }
        self.showsAllInterests.toggle()
        self.reload()
    }
    private lazy var seeAllPeopleButton = seeAllButton { [weak self] in
        guard let self, let selected = self.selected else { return }
        self.onDiscoverInterest?(selected)
    }

    private var profiles: [MomentsProfile] = []
    private var counts: [(interest: MomentsInterest, count: Int)] = []
    private var selected: MomentsInterest?
    private var showsAllInterests = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)
        scrollView.pinEdges(to: self)

        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        gridStack.axis = .vertical
        gridStack.spacing = 12

        let interestsTitle = UILabel.vibeLabel(.bold, 18, style: .headline, color: AppColor.AppBlack)
        interestsTitle.text = "Discover by Interests"
        interestsTitle.accessibilityTraits = .header
        peopleTitle.accessibilityTraits = .header

        let peopleScroll = UIScrollView()
        peopleScroll.showsHorizontalScrollIndicator = false
        peopleScroll.clipsToBounds = false
        peopleRow.spacing = 12
        peopleRow.translatesAutoresizingMaskIntoConstraints = false
        peopleScroll.addSubview(peopleRow)

        [header(interestsTitle, seeAllInterestsButton), gridStack, header(peopleTitle, seeAllPeopleButton), peopleScroll]
            .forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(26, after: gridStack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
            peopleRow.topAnchor.constraint(equalTo: peopleScroll.contentLayoutGuide.topAnchor),
            peopleRow.leadingAnchor.constraint(equalTo: peopleScroll.contentLayoutGuide.leadingAnchor),
            peopleRow.trailingAnchor.constraint(equalTo: peopleScroll.contentLayoutGuide.trailingAnchor),
            peopleRow.bottomAnchor.constraint(equalTo: peopleScroll.contentLayoutGuide.bottomAnchor),
            peopleRow.heightAnchor.constraint(equalTo: peopleScroll.frameLayoutGuide.heightAnchor),
            peopleScroll.heightAnchor.constraint(equalToConstant: 196)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with profiles: [MomentsProfile]) {
        self.profiles = profiles
        var tally: [MomentsInterest: Int] = [:]
        profiles.forEach { $0.interests.forEach { tally[$0, default: 0] += 1 } }
        counts = tally.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.interest.title < $1.interest.title }
        if selected == nil || !counts.contains(where: { $0.interest == selected }) {
            selected = counts.first?.interest
        }
        reload()
    }

    private func reload() {
        gridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let visible = showsAllInterests ? counts : Array(counts.prefix(6))
        seeAllInterestsButton.isHidden = counts.count <= 6
        seeAllInterestsButton.configuration?.attributedTitle = AttributedString(showsAllInterests ? "Show Less" : "See All", attributes: AttributeContainer([
            .font: MomentsFont.scaled(.medium, 14, style: .subheadline)
        ]))
        stride(from: 0, to: visible.count, by: 3).forEach { start in
            let tiles = visible[start..<min(start + 3, visible.count)].map { tile(for: $0.interest, count: $0.count) }
            let row = UIStackView(arrangedSubviews: tiles)
            row.spacing = 12
            row.distribution = .fillEqually
            while row.arrangedSubviews.count < 3 { row.addArrangedSubview(UIView()) }
            gridStack.addArrangedSubview(row)
        }
        reloadPeople()
    }

    private func reloadPeople() {
        peopleRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let selected else {
            peopleTitle.text = "People near you"
            return
        }
        peopleTitle.text = "People who love \(selected.title)"
        profiles.filter { $0.interests.contains(selected) }.forEach { peopleRow.addArrangedSubview(personCard($0)) }
    }

    private func header(_ title: UILabel, _ button: UIButton) -> UIView {
        let row = UIStackView(arrangedSubviews: [title, button])
        row.alignment = .center
        button.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func seeAllButton(_ action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = AppColor.Punch
        config.contentInsets = .zero
        config.attributedTitle = AttributedString("See All", attributes: AttributeContainer([.font: MomentsFont.scaled(.medium, 14, style: .subheadline)]))
        let button = UIButton(configuration: config)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func tile(for interest: MomentsInterest, count: Int) -> UIView {
        let color = MomentsInterestCatalog.color(for: interest)
        let isSelected = interest == selected
        let button = UIButton(type: .custom)
        button.backgroundColor = isSelected ? color.withAlphaComponent(0.16) : AppColor.AppWhite
        button.layer.cornerRadius = 18
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = isSelected ? 1.5 : 0
        button.layer.borderColor = color.cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.06
        button.layer.shadowRadius = 8
        button.layer.shadowOffset = CGSize(width: 0, height: 3)

        let iconBackground = UIView()
        iconBackground.backgroundColor = color.withAlphaComponent(0.14)
        iconBackground.layer.cornerRadius = 14
        let icon = UIImageView(image: UIImage(systemName: MomentsInterestCatalog.symbol(for: interest),
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)))
        icon.tintColor = color
        icon.contentMode = .center
        iconBackground.addSubview(icon)
        icon.pinEdges(to: iconBackground)

        let title = UILabel.vibeLabel(.bold, 14, style: .subheadline, color: AppColor.AppBlack)
        title.text = interest.title
        title.textAlignment = .center
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.75
        let subtitle = UILabel.vibeLabel(.regular, 11, style: .caption2, color: AppColor.DoveGray)
        subtitle.text = count == 1 ? "1 person" : "\(count) people"

        let stack = UIStackView(arrangedSubviews: [iconBackground, title, subtitle])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.setCustomSpacing(10, after: iconBackground)
        stack.isUserInteractionEnabled = false
        button.addSubview(stack)
        stack.pinEdges(to: button, insets: UIEdgeInsets(top: 14, left: 6, bottom: 12, right: 6))
        NSLayoutConstraint.activate([
            iconBackground.widthAnchor.constraint(equalToConstant: 48),
            iconBackground.heightAnchor.constraint(equalToConstant: 48)
        ])
        button.accessibilityLabel = "\(interest.title), \(subtitle.text ?? "")"
        button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            self.selected = interest
            self.reload()
        }, for: .touchUpInside)
        return button
    }

    private func personCard(_ profile: MomentsProfile) -> UIView {
        let button = UIButton(type: .custom)
        let image = UIImageView()
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.layer.cornerRadius = 18
        image.layer.cornerCurve = .continuous
        image.backgroundColor = AppColor.AthensGray
        image.loadImage(path: profile.photos.first, placeholder: UIImage(named: "ProfileBlur"))

        let name = UILabel.vibeLabel(.bold, 14, style: .subheadline, color: AppColor.AppBlack)
        name.text = profile.nameAndAge
        let nameRow = UIStackView(arrangedSubviews: [name])
        nameRow.spacing = 4
        if profile.isVerified {
            let seal = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
            seal.tintColor = AppColor.DodgerBlue
            seal.contentMode = .scaleAspectFit
            seal.widthAnchor.constraint(equalToConstant: 14).isActive = true
            nameRow.addArrangedSubview(seal)
        }
        name.setContentHuggingPriority(.required, for: .horizontal)
        nameRow.addArrangedSubview(UIView())
        let distance = UILabel.vibeLabel(.regular, 12, style: .caption1, color: AppColor.DoveGray)
        distance.text = profile.distanceText ?? profile.city ?? " "

        let stack = UIStackView(arrangedSubviews: [image, nameRow, distance])
        stack.axis = .vertical
        stack.spacing = 2
        stack.setCustomSpacing(8, after: image)
        stack.isUserInteractionEnabled = false
        button.addSubview(stack)
        stack.pinEdges(to: button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 124),
            image.heightAnchor.constraint(equalToConstant: 150)
        ])
        button.accessibilityLabel = profile.accessibilitySummary
        button.addAction(UIAction { [weak self] _ in self?.onSelectProfile?(profile) }, for: .touchUpInside)
        return button
    }
}
