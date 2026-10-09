//
//  VibeFiltersViewController.swift
//  FlirttimeNew
//
//  "Filters" sheet for Discover and Explore.
//

import UIKit

final class VibeFiltersViewController: UIViewController {

    var onApply: ((FilterModel) -> Void)?
    /// When set, the apply button shows how many people match the current selection.
    var matchCount: ((FilterModel) -> Int)?

    private var filters: FilterModel
    private let haptics = UISelectionFeedbackGenerator()

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var showMeButtons: [FilterModel.ShowMe: UIButton] = [:]
    private let ageValueLabel = UILabel.vibeLabel(.bold, 17, style: .headline, color: AppColor.Punch)
    private let ageSlider = VibeRangeSlider(range: FilterModel.ageBounds)
    private let distanceValueLabel = UILabel.vibeLabel(.bold, 17, style: .headline, color: AppColor.Punch)
    private let distanceSlider = UISlider()
    private let intentChips = VibeChipsView()
    private let interestChips = VibeChipsView()
    private let interestsCountLabel = UILabel.vibeLabel(.medium, 13, style: .footnote, color: AppColor.DoveGray)
    private let verifiedSwitch = UISwitch()
    private let onlineSwitch = UISwitch()
    private let applyButton = UIButton(type: .custom)
    private let resetButton = UIButton(type: .system)

    private static let intentInterests: [VibeInterest] = FilterModel.datingIntents.enumerated().map {
        VibeInterest(id: $0.offset, title: $0.element.title, emoji: $0.element.emoji)
    }
    private static let allInterests = VibeInterestCatalog.all.values.sorted { $0.title < $1.title }

    init(filters: FilterModel) {
        self.filters = filters
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Presents the sheet with the large detent and a grabber.
    static func present(from presenter: UIViewController, filters: FilterModel,
                        matchCount: ((FilterModel) -> Int)? = nil,
                        onApply: @escaping (FilterModel) -> Void) {
        let sheet = VibeFiltersViewController(filters: filters)
        sheet.matchCount = matchCount
        sheet.onApply = onApply
        sheet.modalPresentationStyle = .pageSheet
        if let controller = sheet.sheetPresentationController {
            controller.detents = [.large()]
            controller.prefersGrabberVisible = true
            controller.preferredCornerRadius = 28
        }
        presenter.present(sheet, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        let background = VibeGradientView(colors: [VibeTheme.blushGradient[0], AppColor.AppWhite],
                                          start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 0.4))
        view.addSubview(background)
        background.pinEdges(to: view)

        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)

        let bottomBar = makeBottomBar()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        contentStack.addArrangedSubview(makeHeader())
        contentStack.setCustomSpacing(20, after: contentStack.arrangedSubviews[0])
        contentStack.addArrangedSubview(makeShowMeSection())
        contentStack.addArrangedSubview(makeAgeSection())
        contentStack.addArrangedSubview(makeDistanceSection())
        contentStack.addArrangedSubview(makeIntentSection())
        contentStack.addArrangedSubview(makeInterestsSection())
        contentStack.addArrangedSubview(makeToggleSection())

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 28),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -18),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        refresh(animated: false)
    }

    // MARK: - Sections

    private func makeHeader() -> UIView {
        let title = UILabel.vibeLabel(.bold, 28, style: .title1, color: AppColor.MineShaft)
        title.text = "Filters"
        title.accessibilityTraits = .header
        let subtitle = UILabel.vibeLabel(.regular, 15, style: .subheadline, color: AppColor.DoveGray, lines: 0)
        subtitle.text = "Tune who shows up so every swipe feels like your vibe."
        let texts = UIStackView(arrangedSubviews: [title, subtitle])
        texts.axis = .vertical
        texts.spacing = 4

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColor.AppWhite
        config.baseForegroundColor = AppColor.MineShaft
        config.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        let close = UIButton(configuration: config)
        close.accessibilityLabel = "Close"
        close.layer.shadowColor = UIColor.black.cgColor
        close.layer.shadowOpacity = 0.08
        close.layer.shadowRadius = 8
        close.layer.shadowOffset = CGSize(width: 0, height: 3)
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            close.widthAnchor.constraint(equalToConstant: 38),
            close.heightAnchor.constraint(equalToConstant: 38)
        ])

        let row = UIStackView(arrangedSubviews: [texts, close])
        row.alignment = .top
        row.spacing = 12
        return row
    }

    private func makeShowMeSection() -> UIView {
        let row = UIStackView()
        row.distribution = .fillEqually
        row.spacing = 8
        for option in FilterModel.ShowMe.allCases {
            let button = UIButton(type: .custom)
            button.accessibilityLabel = option.title
            button.addAction(UIAction { [weak self] _ in
                guard let self, self.filters.showMe != option else { return }
                self.filters.showMe = option
                self.changed()
            }, for: .touchUpInside)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
            showMeButtons[option] = button
            row.addArrangedSubview(button)
        }
        return card(symbol: "heart.fill", tint: AppColor.Punch, title: "Show me", content: row)
    }

    private func makeAgeSection() -> UIView {
        ageSlider.minimumGap = 2
        ageSlider.accessibilityValueText = { $0 == FilterModel.ageBounds.upperBound ? "\($0) or older" : "\($0) years" }
        ageSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.filters.ageRange = self.ageSlider.lower...self.ageSlider.upper
            self.changed(refreshControls: false)
        }, for: .valueChanged)
        let stack = UIStackView(arrangedSubviews: [ageSlider, scale("\(FilterModel.ageBounds.lowerBound)", "\(FilterModel.ageBounds.upperBound)+")])
        stack.axis = .vertical
        stack.spacing = 2
        return card(symbol: "birthday.cake.fill", tint: UIColor(red: 0.58, green: 0.36, blue: 0.93, alpha: 1),
                    title: "Age range", value: ageValueLabel, content: stack)
    }

    private func makeDistanceSection() -> UIView {
        distanceSlider.minimumValue = Float(FilterModel.distanceBounds.lowerBound)
        distanceSlider.maximumValue = Float(FilterModel.distanceBounds.upperBound)
        distanceSlider.minimumTrackTintColor = AppColor.Punch
        distanceSlider.maximumTrackTintColor = AppColor.Punch.withAlphaComponent(0.14)
        distanceSlider.setThumbImage(Self.thumbImage, for: .normal)
        distanceSlider.accessibilityLabel = "Maximum distance"
        distanceSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let value = Int(self.distanceSlider.value.rounded())
            let newLimit: Int? = value >= FilterModel.distanceBounds.upperBound ? nil : value
            guard newLimit != self.filters.maxDistanceKm else { return }
            self.filters.maxDistanceKm = newLimit
            self.changed(refreshControls: false)
        }, for: .valueChanged)
        let stack = UIStackView(arrangedSubviews: [distanceSlider, scale("\(FilterModel.distanceBounds.lowerBound) km", "Anywhere")])
        stack.axis = .vertical
        stack.spacing = 6
        return card(symbol: "location.fill", tint: UIColor(red: 0.25, green: 0.52, blue: 0.96, alpha: 1),
                    title: "Distance", value: distanceValueLabel, content: stack)
    }

    private func makeIntentSection() -> UIView {
        intentChips.style = .light
        intentChips.isSelectable = true
        intentChips.onTap = { [weak self] intent in
            guard let self else { return }
            var intents = self.filters.intents ?? []
            if let index = intents.firstIndex(of: intent.title) { intents.remove(at: index) } else { intents.append(intent.title) }
            self.filters.intents = intents
            self.changed()
        }
        return card(symbol: "sparkles", tint: VibeTheme.gold, title: "Looking for", content: intentChips)
    }

    private func makeInterestsSection() -> UIView {
        interestChips.style = .light
        interestChips.isSelectable = true
        interestChips.onTap = { [weak self] interest in
            guard let self else { return }
            var ids = self.filters.interests ?? []
            if let index = ids.firstIndex(of: interest.id) { ids.remove(at: index) } else { ids.append(interest.id) }
            self.filters.interests = ids
            self.changed()
        }
        let hint = UILabel.vibeLabel(.regular, 13, style: .footnote, color: AppColor.DoveGray, lines: 0)
        hint.text = "Show people who share at least one of these."
        let stack = UIStackView(arrangedSubviews: [hint, interestChips])
        stack.axis = .vertical
        stack.spacing = 10
        return card(symbol: "star.fill", tint: UIColor(red: 0.98, green: 0.55, blue: 0.16, alpha: 1),
                    title: "Interests", value: interestsCountLabel, content: stack)
    }

    private func makeToggleSection() -> UIView {
        let verified = toggleRow(symbol: "checkmark.seal.fill", tint: UIColor(red: 0.25, green: 0.52, blue: 0.96, alpha: 1),
                                 title: "Verified only", subtitle: "Photo-verified profiles", toggle: verifiedSwitch) { [weak self] isOn in
            self?.filters.verifiedOnly = isOn
            self?.changed(refreshControls: false)
        }
        let online = toggleRow(symbol: "circle.fill", tint: UIColor(red: 0.16, green: 0.75, blue: 0.40, alpha: 1),
                               title: "Online now", subtitle: "People active right now", toggle: onlineSwitch) { [weak self] isOn in
            self?.filters.onlineOnly = isOn
            self?.changed(refreshControls: false)
        }
        let divider = UIView()
        divider.backgroundColor = AppColor.AthensGray
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let stack = UIStackView(arrangedSubviews: [verified, divider, online])
        stack.axis = .vertical
        stack.spacing = 12
        return container(stack)
    }

    private func makeBottomBar() -> UIView {
        let bar = UIView()
        bar.backgroundColor = AppColor.AppWhite
        bar.layer.shadowColor = UIColor.black.cgColor
        bar.layer.shadowOpacity = 0.08
        bar.layer.shadowRadius = 12
        bar.layer.shadowOffset = CGSize(width: 0, height: -4)

        var resetConfig = UIButton.Configuration.plain()
        resetConfig.baseForegroundColor = AppColor.MineShaft
        resetConfig.attributedTitle = AttributedString("Reset", attributes: AttributeContainer([.font: VibeFont.scaled(.medium, 16)]))
        resetButton.configuration = resetConfig
        resetButton.addAction(UIAction { [weak self] _ in self?.reset() }, for: .touchUpInside)

        var applyConfig = UIButton.Configuration.filled()
        applyConfig.cornerStyle = .capsule
        applyConfig.baseBackgroundColor = AppColor.Punch
        applyConfig.baseForegroundColor = .white
        applyButton.configuration = applyConfig
        applyButton.layer.shadowColor = AppColor.Punch.cgColor
        applyButton.layer.shadowOpacity = 0.35
        applyButton.layer.shadowRadius = 10
        applyButton.layer.shadowOffset = CGSize(width: 0, height: 5)
        applyButton.configurationUpdateHandler = { button in
            UIView.animate(withDuration: 0.15) {
                button.transform = button.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
        applyButton.addAction(UIAction { [weak self] _ in self?.apply() }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [resetButton, applyButton])
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: bar.topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -18),
            row.bottomAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            resetButton.widthAnchor.constraint(equalToConstant: 96),
            applyButton.heightAnchor.constraint(equalToConstant: 54)
        ])
        return bar
    }

    // MARK: - Building blocks

    private func card(symbol: String, tint: UIColor, title: String, value: UILabel? = nil, content: UIView) -> UIView {
        let titleLabel = UILabel.vibeLabel(.bold, 17, style: .headline, color: AppColor.MineShaft)
        titleLabel.text = title
        titleLabel.accessibilityTraits = .header
        var headerViews: [UIView] = [iconTile(symbol: symbol, tint: tint), titleLabel, UIView()]
        if let value {
            value.textAlignment = .right
            headerViews.append(value)
        }
        let header = UIStackView(arrangedSubviews: headerViews)
        header.spacing = 10
        header.alignment = .center

        let stack = UIStackView(arrangedSubviews: [header, content])
        stack.axis = .vertical
        stack.spacing = 14
        return container(stack)
    }

    private func container(_ content: UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = AppColor.AppWhite
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.06
        card.layer.shadowRadius = 12
        card.layer.shadowOffset = CGSize(width: 0, height: 4)
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    private func iconTile(symbol: String, tint: UIColor) -> UIView {
        let tile = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)))
        tile.tintColor = tint
        tile.contentMode = .center
        tile.backgroundColor = tint.withAlphaComponent(0.12)
        tile.layer.cornerRadius = 10
        tile.isAccessibilityElement = false
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 32),
            tile.heightAnchor.constraint(equalToConstant: 32)
        ])
        return tile
    }

    private func toggleRow(symbol: String, tint: UIColor, title: String, subtitle: String,
                           toggle: UISwitch, onChange: @escaping (Bool) -> Void) -> UIView {
        let titleLabel = UILabel.vibeLabel(.medium, 16, color: AppColor.MineShaft)
        titleLabel.text = title
        let subtitleLabel = UILabel.vibeLabel(.regular, 13, style: .footnote, color: AppColor.DoveGray)
        subtitleLabel.text = subtitle
        let texts = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        texts.axis = .vertical
        texts.spacing = 2
        toggle.onTintColor = AppColor.Punch
        toggle.accessibilityLabel = title
        toggle.accessibilityHint = subtitle
        toggle.addAction(UIAction { [unowned toggle] _ in onChange(toggle.isOn) }, for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [iconTile(symbol: symbol, tint: tint), texts, toggle])
        row.spacing = 12
        row.alignment = .center
        return row
    }

    private func scale(_ low: String, _ high: String) -> UIView {
        let lowLabel = UILabel.vibeLabel(.regular, 12, style: .caption1, color: AppColor.DoveGray)
        lowLabel.text = low
        let highLabel = UILabel.vibeLabel(.regular, 12, style: .caption1, color: AppColor.DoveGray)
        highLabel.text = high
        let row = UIStackView(arrangedSubviews: [lowLabel, UIView(), highLabel])
        row.isAccessibilityElement = false
        row.accessibilityElementsHidden = true
        return row
    }

    private static let thumbImage: UIImage = {
        let size: CGFloat = 28, pad: CGFloat = 6
        return UIGraphicsImageRenderer(size: CGSize(width: size + pad * 2, height: size + pad * 2)).image { context in
            let rect = CGRect(x: pad, y: pad - 2, width: size, height: size)
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 3), blur: 6, color: AppColor.Punch.withAlphaComponent(0.3).cgColor)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect).fill()
            context.cgContext.setShadow(offset: .zero, blur: 0)
            AppColor.Punch.setStroke()
            let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 3
            ring.stroke()
        }
    }()

    // MARK: - State

    private func changed(refreshControls: Bool = true) {
        haptics.selectionChanged()
        refresh(animated: true, controls: refreshControls)
    }

    private func refresh(animated: Bool, controls: Bool = true) {
        if controls {
            for (option, button) in showMeButtons {
                styleShowMe(button, option: option, selected: filters.showMe == option)
            }
            ageSlider.setValues(lower: filters.ageRange.lowerBound, upper: filters.ageRange.upperBound)
            distanceSlider.setValue(Float(filters.maxDistanceKm ?? FilterModel.distanceBounds.upperBound), animated: animated)
            verifiedSwitch.setOn(filters.verifiedOnly, animated: animated)
            onlineSwitch.setOn(filters.onlineOnly, animated: animated)
            let intents = Set(filters.intents ?? [])
            intentChips.configure(Self.intentInterests,
                                  highlighted: Set(Self.intentInterests.filter { intents.contains($0.title) }.map(\.id)))
            interestChips.configure(Self.allInterests, highlighted: Set(filters.interests ?? []))
        }
        ageValueLabel.text = filters.ageText
        distanceValueLabel.text = filters.distanceText
        distanceSlider.accessibilityValue = filters.distanceText
        let interestCount = filters.interests?.count ?? 0
        interestsCountLabel.text = interestCount == 0 ? "Any" : "\(interestCount) selected"
        updateBottomBar()
    }

    private func styleShowMe(_ button: UIButton, option: FilterModel.ShowMe, selected: Bool) {
        var config = UIButton.Configuration.filled()
        config.background.cornerRadius = 16
        config.baseBackgroundColor = selected ? AppColor.Lavenderblush : AppColor.AthensGray.withAlphaComponent(0.6)
        config.background.strokeColor = selected ? AppColor.Punch : .clear
        config.background.strokeWidth = selected ? 2 : 0
        config.baseForegroundColor = selected ? AppColor.Punch : AppColor.MineShaft
        config.titleAlignment = .center
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 2, bottom: 10, trailing: 2)
        config.attributedTitle = AttributedString(option.emoji, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 26)]))
        config.attributedSubtitle = AttributedString(option.title, attributes: AttributeContainer([
            .font: VibeFont.scaled(selected ? .bold : .medium, 12, style: .caption1)
        ]))
        config.titlePadding = 4
        button.configuration = config
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }

    private func updateBottomBar() {
        let active = filters.activeCount
        resetButton.isEnabled = active > 0
        resetButton.alpha = active > 0 ? 1 : 0.4

        let title: String
        var enabled = true
        if let matchCount {
            let count = matchCount(filters)
            switch count {
            case 0:
                title = "No matches – widen filters"
                enabled = false
            case 1: title = "Show 1 match"
            default: title = "Show \(count) matches"
            }
        } else {
            title = active > 0 ? "Apply \(active) filter\(active == 1 ? "" : "s")" : "Apply filters"
        }
        applyButton.configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: VibeFont.scaled(.bold, 17, style: .headline)
        ]))
        applyButton.configuration?.baseBackgroundColor = enabled ? AppColor.Punch : AppColor.Boulder.withAlphaComponent(0.5)
        applyButton.layer.shadowOpacity = enabled ? 0.35 : 0
        applyButton.isEnabled = enabled
    }

    private func reset() {
        filters = .standard
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        refresh(animated: true)
        UIAccessibility.post(notification: .announcement, argument: "Filters reset")
    }

    private func apply() {
        let filters = self.filters
        dismiss(animated: true) { [onApply] in onApply?(filters) }
    }
}
