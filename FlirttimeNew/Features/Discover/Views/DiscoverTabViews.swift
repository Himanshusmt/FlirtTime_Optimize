//
//  DiscoverTabViews.swift
//  FlirttimeNew
//
//  Discover's People / Quick Moments / Interests switcher, the Quick Moments grid and the Interests page.
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

// MARK: - Moments page

/// Quick Moments from `GET quick-moments/tray`: the user's own stories first, then everyone else's.
final class DiscoverMomentsView: UIView {

    /// Called with the tapped user's tray entry and whether it's the signed-in user's own.
    var onOpenStories: ((QuickMomentTrayItem, Bool) -> Void)?

    private struct Item {
        let tray: QuickMomentTrayItem
        let isMine: Bool
    }

    private var items: [Item] = []
    private let emptyLabel = UILabel.vibeLabel(.regular, 15, color: AppColor.DoveGray, lines: 0)
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 4, left: 16, bottom: 24, right: 16)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsVerticalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        view.register(MomentCell.self, forCellWithReuseIdentifier: MomentCell.reuseID)
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(collectionView)
        collectionView.pinEdges(to: self)
        emptyLabel.text = "No Moments to show right now."
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(tray: QuickMomentTray?) {
        var items: [Item] = []
        if let me = tray?.me, me.hasActive {
            items.append(Item(tray: me, isMine: true))
        }
        items += (tray?.users ?? []).filter(\.hasActive).map { Item(tray: $0, isMine: false) }
        self.items = items
        emptyLabel.isHidden = !items.isEmpty
        collectionView.reloadData()
    }
}

extension DiscoverMomentsView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MomentCell.reuseID, for: indexPath) as! MomentCell
        let item = items[indexPath.item]
        cell.configure(tray: item.tray, isMine: item.isMine)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = floor((collectionView.bounds.width - 16 * 2 - 12) / 2)
        return CGSize(width: width, height: width * 1.4)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = items[indexPath.item]
        onOpenStories?(item.tray, item.isMine)
    }
}

private final class MomentCell: UICollectionViewCell {

    static let reuseID = "MomentCell"

    private let textBackground = MomentsGradientView(colors: MomentsTheme.storyBackground(0))
    private let textLabel = UILabel.vibeLabel(.bold, 17, style: .headline, color: .white, lines: 0)
    private let imageView = UIImageView()
    private let avatar = UIImageView()
    private let nameLabel = UILabel.vibeLabel(.bold, 14, style: .subheadline, color: .white)
    private let timeLabel = UILabel.vibeLabel(.regular, 11, style: .caption2, color: UIColor.white.withAlphaComponent(0.85))
    private let countLabel = UILabel.vibeLabel(.bold, 12, style: .caption1, color: .white)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 20
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.backgroundColor = AppColor.AthensGray
        contentView.addSubview(textBackground)
        textBackground.pinEdges(to: contentView)
        textLabel.textAlignment = .center
        textLabel.adjustsFontSizeToFitWidth = true
        textLabel.minimumScaleFactor = 0.6
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textLabel)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        imageView.pinEdges(to: contentView)

        countLabel.textAlignment = .center
        countLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        countLabel.layer.cornerRadius = 11
        countLabel.clipsToBounds = true
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(countLabel)
        NSLayoutConstraint.activate([
            textLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -16),
            textLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            textLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            textLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 36),
            countLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            countLabel.heightAnchor.constraint(equalToConstant: 22),
            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 22)
        ])
        let shade = MomentsGradientView(colors: [.clear, UIColor.black.withAlphaComponent(0.7)],
                                     start: CGPoint(x: 0.5, y: 0.55), end: CGPoint(x: 0.5, y: 1))
        contentView.addSubview(shade)
        shade.pinEdges(to: contentView)

        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 14
        avatar.layer.borderWidth = 2
        avatar.layer.borderColor = AppColor.Punch.cgColor
        let texts = UIStackView(arrangedSubviews: [nameLabel, timeLabel])
        texts.axis = .vertical
        let row = UIStackView(arrangedSubviews: [avatar, texts])
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 28),
            avatar.heightAnchor.constraint(equalToConstant: 28),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -10),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
        contentView.bringSubviewToFront(countLabel)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(tray: QuickMomentTrayItem, isMine: Bool) {
        let latest = tray.stories.first
        let photo = latest?.thumbnailPath ?? latest?.mediaPath ?? (latest == nil ? tray.previewUrl : nil)
        if let photo {
            imageView.isHidden = false
            imageView.loadImage(path: photo, placeholder: UIImage(named: "ProfileBlur"))
        } else {
            imageView.isHidden = true
            imageView.loadImage(with: nil)
        }
        let background = latest == nil ? tray.previewBackground : latest?.backgroundColor
        textBackground.setColors(QuickMomentColors.gradient(for: background))
        textLabel.text = latest?.text ?? tray.previewText
        textLabel.isHidden = photo != nil

        avatar.loadImage(path: tray.user?.photo, placeholder: UIImage(named: "ProfileBlur"))
        avatar.layer.borderColor = (isMine || tray.hasUnread ? AppColor.Punch : AppColor.SilverChalice).cgColor
        let name = isMine ? "My story" : (tray.user?.name ?? tray.user?.fullName ?? "Someone")
        nameLabel.text = name
        timeLabel.text = tray.timeText

        let count = max(tray.activeCount, tray.stories.count)
        countLabel.text = " \(count) "
        countLabel.isHidden = count < 2
        accessibilityLabel = [name, count > 1 ? "\(count) stories" : nil, tray.hasUnread ? "new" : nil, tray.timeText]
            .compactMap { $0 }.joined(separator: ", ")
    }

    override var isHighlighted: Bool {
        didSet { UIView.animate(withDuration: 0.15) { self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity } }
    }
}

// MARK: - Interests page

/// Tiles from GET `interests`; the people row comes from `discovery/people?interestId=` for the selected tile.
final class DiscoverInterestsView: UIView {

    var onSelectProfile: ((MomentsProfile) -> Void)?
    var onDiscoverInterest: ((MomentsInterest) -> Void)?
    /// A tile was selected (tapped, or the first one picked automatically); load its people.
    var onSelectInterest: ((InterestCatalogItem) -> Void)?

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
        guard let self, let interest = self.selected?.vibeInterest else { return }
        self.onDiscoverInterest?(interest)
    }
    private let peopleStatusLabel = UILabel.vibeLabel(.regular, 14, style: .subheadline, color: AppColor.DoveGray)

    private var catalog: [InterestCatalogItem] = []
    private var selected: InterestCatalogItem?
    /// People for `selected`; `nil` while loading.
    private var people: [MomentsProfile]?
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

        peopleStatusLabel.numberOfLines = 0
        peopleStatusLabel.isHidden = true
        [header(interestsTitle, seeAllInterestsButton), gridStack, header(peopleTitle, seeAllPeopleButton), peopleStatusLabel, peopleScroll]
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

    func configure(catalog: [InterestCatalogItem]) {
        self.catalog = catalog
        if selected == nil || !catalog.contains(where: { $0.id == selected?.id }) {
            select(catalog.first)
        } else {
            reload()
        }
    }

    func configure(people: [MomentsProfile]?, for interestId: String) {
        guard interestId == selected?.id else { return }
        self.people = people
        reloadPeople()
    }

    private func select(_ item: InterestCatalogItem?) {
        selected = item
        people = nil
        reload()
        if let item { onSelectInterest?(item) }
    }

    private func reload() {
        gridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let visible = showsAllInterests ? catalog : Array(catalog.prefix(6))
        seeAllInterestsButton.isHidden = catalog.count <= 6
        seeAllInterestsButton.configuration?.attributedTitle = AttributedString(showsAllInterests ? "Show Less" : "See All", attributes: AttributeContainer([
            .font: MomentsFont.scaled(.medium, 14, style: .subheadline)
        ]))
        stride(from: 0, to: visible.count, by: 3).forEach { start in
            let tiles = visible[start..<min(start + 3, visible.count)].map { tile(for: $0) }
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
            peopleStatusLabel.isHidden = true
            seeAllPeopleButton.isHidden = true
            return
        }
        peopleTitle.text = "People who love \(selected.name)"
        let loaded = self.people ?? []
        loaded.forEach { peopleRow.addArrangedSubview(personCard($0)) }
        peopleRow.superview?.isHidden = loaded.isEmpty
        seeAllPeopleButton.isHidden = loaded.isEmpty
        peopleStatusLabel.isHidden = !loaded.isEmpty
        peopleStatusLabel.text = self.people == nil ? "Loading..." : "No one with this interest yet"
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

    private func tile(for item: InterestCatalogItem) -> UIView {
        let interest = item.vibeInterest
        let color = interest.map(MomentsInterestCatalog.color(for:)) ?? AppColor.Punch
        let isSelected = item.id == selected?.id
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
        let icon: UIView
        if let emoji = item.icon, !emoji.isEmpty {
            let label = UILabel()
            label.text = emoji
            label.font = .systemFont(ofSize: 24)
            label.textAlignment = .center
            icon = label
        } else {
            let symbol = interest.map(MomentsInterestCatalog.symbol(for:)) ?? "sparkles"
            let image = UIImageView(image: UIImage(systemName: symbol,
                                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)))
            image.tintColor = color
            image.contentMode = .center
            icon = image
        }
        iconBackground.addSubview(icon)
        icon.pinEdges(to: iconBackground)

        let title = UILabel.vibeLabel(.bold, 14, style: .subheadline, color: AppColor.AppBlack)
        title.text = item.name
        title.textAlignment = .center
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.75
        let subtitle = UILabel.vibeLabel(.regular, 11, style: .caption2, color: AppColor.DoveGray)
        subtitle.text = item.category ?? " "

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
        button.accessibilityLabel = [item.name, item.category].compactMap { $0 }.joined(separator: ", ")
        button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        button.addAction(UIAction { [weak self] _ in
            guard let self, item.id != self.selected?.id else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            self.select(item)
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
