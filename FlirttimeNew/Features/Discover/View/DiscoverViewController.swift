//
//  DiscoverViewController.swift
//  FlirttimeNew
//
//  Home tab: Vibe Discovery. People (swipe cards), Moments and Interest-based discovery.
//

import UIKit
import Combine

final class DiscoverViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.dashboard
    }

    private enum Page: Int, CaseIterable {
        case people, moments, interests
        var title: String {
            switch self {
            case .people: return "People"
            case .moments: return "Moments"
            case .interests: return "Interests"
            }
        }
    }

    private let viewModel = DiscoverViewModel()
    private var cancellables: Set<AnyCancellable> = []

    /// Set before restoring a card so it animates back in from the side it left through.
    private var pendingReturnAction: VibeAction?
    /// Set when an action comes from the Connect flow (with optional reasons).
    private var pendingConnectReasons: [ConnectReason]?
    /// Set when the user likes a specific part of the current profile.
    private var pendingReaction: VibeReaction?
    private var lastImpressionID: Int?

    /// The tab bar's centre button rises above the bar.
    private static let centerTabButtonOverlap: CGFloat = 44

    private var cardStackTopConstraint = NSLayoutConstraint()

    // MARK: - Views

    private let logoImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "FlirtTimeTitle"))
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Flirt Time"
        imageView.accessibilityTraits = .header
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 100),
            imageView.heightAnchor.constraint(equalToConstant: 24)
        ])
        return imageView
    }()

    private lazy var coinShopButton: CoinBalancePill = {
        let pill = CoinBalancePill()
        pill.addAction(UIAction { [weak self] _ in self?.openCoinShop() }, for: .touchUpInside)
        return pill
    }()

    private lazy var notificationButton = headerButton(image: UIImage(named: "Notification"), label: "Notifications") { [weak self] in
        self?.notificationTapped()
    }

    private lazy var filterButton = headerButton(
        image: UIImage(systemName: "slider.horizontal.3", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)),
        label: "Filters") { [weak self] in
            self?.openFilters()
        }

    private let filterBadge: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.bold, size: 11)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = AppColor.Punch
        label.layer.cornerRadius = 9
        label.layer.borderWidth = 2
        label.layer.borderColor = UIColor.white.cgColor
        label.clipsToBounds = true
        label.isHidden = true
        label.isUserInteractionEnabled = false
        return label
    }()

    private lazy var tabs: VibePillTabsView = {
        let tabs = VibePillTabsView(titles: Page.allCases.map(\.title))
        tabs.addAction(UIAction { [weak self, unowned tabs] _ in
            self?.show(Page(rawValue: tabs.selectedIndex) ?? .people)
        }, for: .valueChanged)
        return tabs
    }()

    private lazy var filterChip: UIButton = {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColor.Lavenderblush
        config.baseForegroundColor = AppColor.Punch
        config.image = UIImage(systemName: "xmark.circle.fill")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 10)
        let button = UIButton(configuration: config)
        button.isHidden = true
        button.accessibilityHint = "Clears the interest filter"
        button.addAction(UIAction { [weak self] _ in self?.viewModel.clearFilter() }, for: .touchUpInside)
        return button
    }()

    private let peopleView = UIView()
    private let momentsView = DiscoverMomentsView()
    private let interestsView = DiscoverInterestsView()

    private lazy var cardStack: VibeCardStackView = {
        let stack = VibeCardStackView()
        stack.delegate = self
        stack.cardDelegate = self
        stack.onAccessibilityViewProfile = { [weak self] in
            guard let profile = self?.viewModel.currentProfile else { return }
            self?.openProfile(profile)
        }
        return stack
    }()

    private lazy var actionBar: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [
            actionButton(title: "Not my vibe", symbol: "xmark", size: 58, background: AppColor.AppWhite, tint: AppColor.MineShaft,
                         hint: "Same as swiping left") { [weak self] in self?.cardStack.perform(.notMyVibe) },
            actionButton(title: "Connect", symbol: "star.fill", size: 72, background: AppColor.Punch, tint: .white,
                         hint: "Send a Vibe with a reason") { [weak self] in self?.connectTapped() },
            actionButton(title: "Like", symbol: "heart.fill", size: 58, background: AppColor.Lavenderblush, tint: AppColor.Punch,
                         hint: "Same as swiping right") { [weak self] in self?.cardStack.perform(.interested) }
        ])
        stack.axis = .horizontal
        stack.alignment = .bottom
        stack.spacing = 36
        return stack
    }()

    private let loadingView: UIStackView = {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = AppColor.Punch
        spinner.startAnimating()
        let label = UILabel.vibeLabel(.regular, 16, color: AppColor.DoveGray)
        label.text = "Finding your vibes…"
        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.isHidden = true
        return stack
    }()

    private let emptyTitleLabel = UILabel.vibeLabel(.bold, 20, style: .title3, color: AppColor.MineShaft, lines: 0)
    private let emptyMessageLabel = UILabel.vibeLabel(.regular, 15, color: AppColor.DoveGray, lines: 0)
    private lazy var emptyButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColor.Punch
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 28, bottom: 12, trailing: 28)
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in self?.emptyButtonTapped() }, for: .touchUpInside)
        return button
    }()

    private lazy var emptyView: UIStackView = {
        let image = UIImageView(image: UIImage(named: "NoCards"))
        image.contentMode = .scaleAspectFit
        image.heightAnchor.constraint(equalToConstant: 140).isActive = true
        emptyTitleLabel.textAlignment = .center
        emptyMessageLabel.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [image, emptyTitleLabel, emptyMessageLabel, emptyButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.setCustomSpacing(24, after: emptyMessageLabel)
        stack.isHidden = true
        return stack
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        setUI()
        setUpBinding()
        viewModel.loadRecommendations()    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: false)
        CoinWallet.shared.refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        VoiceIntroPlayer.shared.stop()
    }

    // MARK: - UI

    private func setUI() {
        let background = VibeGradientView(colors: [VibeTheme.blushGradient[0], AppColor.AppWhite],
                                          start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 0.5))
        view.addSubview(background)
        background.pinEdges(to: view)

        let header = UIStackView(arrangedSubviews: [logoImageView, UIView(), coinShopButton, notificationButton, filterButton])
        header.spacing = 10
        header.alignment = .center
        filterBadge.translatesAutoresizingMaskIntoConstraints = false
        filterButton.addSubview(filterBadge)
        NSLayoutConstraint.activate([
            filterBadge.topAnchor.constraint(equalTo: filterButton.topAnchor, constant: -4),
            filterBadge.trailingAnchor.constraint(equalTo: filterButton.trailingAnchor, constant: 4),
            filterBadge.heightAnchor.constraint(equalToConstant: 18),
            filterBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18)
        ])

        [header, tabs, peopleView, momentsView, interestsView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        [filterChip, cardStack, actionBar, loadingView, emptyView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            peopleView.addSubview($0)
        }
        cardStackTopConstraint = cardStack.topAnchor.constraint(equalTo: peopleView.topAnchor, constant: 4)
        let bottomInset = -(DiscoverViewController.centerTabButtonOverlap + 4)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tabs.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tabs.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            peopleView.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 12),
            peopleView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            peopleView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            peopleView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: bottomInset),

            filterChip.topAnchor.constraint(equalTo: peopleView.topAnchor),
            filterChip.leadingAnchor.constraint(equalTo: peopleView.leadingAnchor, constant: 20),

            cardStackTopConstraint,
            cardStack.leadingAnchor.constraint(equalTo: peopleView.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: peopleView.trailingAnchor, constant: -16),
            cardStack.bottomAnchor.constraint(equalTo: actionBar.topAnchor, constant: -14),

            actionBar.centerXAnchor.constraint(equalTo: peopleView.centerXAnchor),
            actionBar.bottomAnchor.constraint(equalTo: peopleView.bottomAnchor),

            loadingView.centerXAnchor.constraint(equalTo: cardStack.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: cardStack.centerYAnchor),

            emptyView.centerYAnchor.constraint(equalTo: cardStack.centerYAnchor),
            emptyView.leadingAnchor.constraint(equalTo: peopleView.leadingAnchor, constant: 32),
            emptyView.trailingAnchor.constraint(equalTo: peopleView.trailingAnchor, constant: -32)
        ])
        for page in [momentsView, interestsView] {
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 12),
                page.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                page.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: bottomInset + 20)
            ])
        }

        momentsView.onOpenMoment = { [weak self] profile, index in self?.openMoments(of: profile, at: index) }
        interestsView.onSelectProfile = { [weak self] profile in self?.openProfile(profile) }
        interestsView.onDiscoverInterest = { [weak self] interest in
            self?.show(.people)
            self?.discover(interest)
        }
        show(.people)
    }

    private func headerButton(image: UIImage?, label: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColor.AppWhite
        config.baseForegroundColor = AppColor.MineShaft
        config.image = image
        let button = UIButton(configuration: config)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.08
        button.layer.shadowRadius = 8
        button.layer.shadowOffset = CGSize(width: 0, height: 3)
        button.accessibilityLabel = label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 42),
            button.heightAnchor.constraint(equalToConstant: 42)
        ])
        return button
    }

    private func actionButton(title: String, symbol: String, size: CGFloat, background: UIColor, tint: UIColor,
                              hint: String, action: @escaping () -> Void) -> UIView {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = background
        config.baseForegroundColor = tint
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.36, weight: .bold))
        let isPrimary = background == AppColor.Punch
        if isPrimary {
            let gradient = VibeGradientView(colors: VibeTheme.brandGradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 1))
            gradient.layer.cornerRadius = size / 2
            gradient.clipsToBounds = true
            config.background.customView = gradient
        } else {
            config.background.strokeColor = AppColor.AthensGray
            config.background.strokeWidth = 1
        }
        let button = UIButton(configuration: config)
        button.layer.shadowColor = (isPrimary ? AppColor.Punch : UIColor.black).cgColor
        button.layer.shadowOpacity = isPrimary ? 0.4 : 0.1
        button.layer.shadowRadius = isPrimary ? 12 : 8
        button.layer.shadowOffset = CGSize(width: 0, height: 5)
        button.configurationUpdateHandler = { button in
            UIView.animate(withDuration: 0.15) {
                button.transform = button.isHighlighted ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
            }
        }
        button.accessibilityLabel = title
        button.accessibilityHint = hint
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)

        let label = UILabel.vibeLabel(.medium, 12, style: .caption1, color: isPrimary ? AppColor.Punch : AppColor.DoveGray)
        label.text = title
        label.isAccessibilityElement = false
        let stack = UIStackView(arrangedSubviews: [button, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size)
        ])
        return stack
    }

    private func show(_ page: Page) {
        if tabs.selectedIndex != page.rawValue {
            tabs.select(page.rawValue, sendsActions: false)
        }
        peopleView.isHidden = page != .people
        momentsView.isHidden = page != .moments
        interestsView.isHidden = page != .interests
        switch page {
        case .people: break
        case .moments: momentsView.configure(with: viewModel.everyone)
        case .interests: interestsView.configure(with: viewModel.everyone)
        }
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    // MARK: - Binding

    private func setUpBinding() {
        viewModel.$deck
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deck in self?.deckChanged(deck) }
            .store(in: &cancellables)

        viewModel.$loadState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStateViews() }
            .store(in: &cancellables)

        viewModel.$interestFilter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interest in self?.updateFilterChip(interest) }
            .store(in: &cancellables)

        viewModel.$preferences
            .receive(on: DispatchQueue.main)
            .sink { [weak self] filters in self?.updateFilterBadge(filters.activeCount) }
            .store(in: &cancellables)

        CoinWallet.shared.$balance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] balance in self?.updateCoinBalance(balance) }
            .store(in: &cancellables)
    }

    private func updateCoinBalance(_ balance: Int) {
        coinShopButton.setBalance(balance)
    }

    private func deckChanged(_ deck: [VibeProfile]) {
        let returning = pendingReturnAction
        pendingReturnAction = nil
        cardStack.sync(current: deck.first, next: deck.dropFirst().first, returningFrom: returning)
        if let current = deck.first, current.id != lastImpressionID {
            lastImpressionID = current.id
            VibeAnalytics.track(.discoverProfileImpression, profileID: current.id)
        }
        if !momentsView.isHidden { momentsView.configure(with: viewModel.everyone) }
        if !interestsView.isHidden { interestsView.configure(with: viewModel.everyone) }
        updateStateViews()
    }

    private func updateStateViews() {
        let hasCards = viewModel.currentProfile != nil
        switch viewModel.loadState {
        case .idle, .loading:
            loadingView.isHidden = hasCards
            emptyView.isHidden = true
        case .loaded where viewModel.isEmptyBecauseOfFilters:
            loadingView.isHidden = true
            emptyView.isHidden = hasCards
            emptyTitleLabel.text = "No one matches your filters"
            emptyMessageLabel.text = "Try widening your age range, distance or interests."
            emptyButton.configuration?.attributedTitle = AttributedString("Adjust Filters", attributes: AttributeContainer([.font: UIFont.fredoka(.medium, size: 16)]))
        case .loaded:
            loadingView.isHidden = true
            emptyView.isHidden = hasCards
            emptyTitleLabel.text = "✨ You've explored all available Vibes"
            emptyMessageLabel.text = "Check back later for new people."
            emptyButton.configuration?.attributedTitle = AttributedString("Explore Again", attributes: AttributeContainer([.font: UIFont.fredoka(.medium, size: 16)]))
        case .failed(let message):
            loadingView.isHidden = true
            emptyView.isHidden = hasCards
            emptyTitleLabel.text = message
            emptyMessageLabel.text = "Check your connection and try again."
            emptyButton.configuration?.attributedTitle = AttributedString("Try Again", attributes: AttributeContainer([.font: UIFont.fredoka(.medium, size: 16)]))
        }
        actionBar.isHidden = !hasCards
    }

    private func updateFilterChip(_ interest: VibeInterest?) {
        filterChip.isHidden = interest == nil
        cardStackTopConstraint.constant = interest == nil ? 4 : 42
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25) {
            self.view.layoutIfNeeded()
        }
        guard let interest else { return }
        filterChip.configuration?.attributedTitle = AttributedString("Showing \(interest.chipTitle)", attributes: AttributeContainer([
            .font: VibeFont.scaled(.medium, 13, style: .footnote)
        ]))
        filterChip.accessibilityLabel = "Showing people into \(interest.title)"
    }

    // MARK: - Actions

    private func connectTapped() {
        guard let profile = viewModel.currentProfile, cardStackShouldBeginInteraction(cardStack) else { return }
        presentConnectBecause(for: profile) { [weak self] reasons in
            guard let self, self.viewModel.currentProfile?.id == profile.id else { return }
            self.pendingConnectReasons = reasons
            if !self.cardStack.perform(.interested) {
                self.pendingConnectReasons = nil
            }
        }
    }

    private func presentConnectBecause(for profile: VibeProfile, onSend: @escaping ([ConnectReason]) -> Void) {
        let connectVC = ConnectBecauseViewController(profile: profile)
        connectVC.onSend = { [weak self] reasons in
            self?.dismiss(animated: true) { onSend(reasons) }
        }
        presentSheet(connectVC, detents: [.medium(), .large()])
    }

    private func send(_ action: VibeAction, for profile: VibeProfile, reasons: [ConnectReason],
                      reaction: VibeReaction? = nil, fromConnectFlow: Bool) {
        let started = viewModel.perform(action, on: profile, reasons: reasons, reaction: reaction) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let outcome):
                self.handle(outcome, fromConnectFlow: fromConnectFlow)
            case .failure(.network):
                VibeHaptics.failed()
                self.showActionFailure(action, profile: profile, reasons: reasons, reaction: reaction, fromConnectFlow: fromConnectFlow)
            case .failure(.membershipRequired):
                self.restore(profile, from: action)
                self.showSubscriptionPopUp(subscriptionPopUpType: .superLike)
            }
        }
        if !started {
            cardStack.sync(current: viewModel.currentProfile, next: viewModel.nextProfile, returningFrom: action)
        }
    }

    private func handle(_ outcome: VibeActionOutcome, fromConnectFlow: Bool) {
        if outcome.isMatch {
            VibeHaptics.connected()
            presentConnection(.matched(outcome.profile), reaction: outcome.reaction)
        } else if fromConnectFlow {
            presentConnection(.sent(outcome.profile), reaction: outcome.reaction)
        } else if let reaction = outcome.reaction {
            aCustomToastView.show(message: "💗 You liked \(reaction.subject(for: outcome.profile.displayName))")
        } else if outcome.action == .interested {
            aCustomToastView.show(message: "💗 Vibe sent to \(outcome.profile.displayName)")
        } else if outcome.action == .superVibe {
            aCustomToastView.show(message: "✨ Super Vibe sent to \(outcome.profile.displayName)")
        }
    }

    /// Never reports success for a failed action; the user either retries or keeps the profile for later.
    private func showActionFailure(_ action: VibeAction, profile: VibeProfile, reasons: [ConnectReason],
                                   reaction: VibeReaction?, fromConnectFlow: Bool) {
        let alert = UIAlertController(title: "Couldn't update right now",
                                      message: "Your \(action.displayName) for \(profile.displayName) wasn't sent.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            self?.send(action, for: profile, reasons: reasons, reaction: reaction, fromConnectFlow: fromConnectFlow)
        })
        alert.addAction(UIAlertAction(title: "Continue Later", style: .cancel) { [weak self] _ in
            self?.restore(profile, from: action)
        })
        present(alert, animated: true)
    }

    private func restore(_ profile: VibeProfile, from action: VibeAction) {
        pendingReturnAction = action
        viewModel.restore(profile)
    }

    private func presentConnection(_ mode: VibeConnectionViewController.Mode, reaction: VibeReaction?) {
        let connectionVC = VibeConnectionViewController(mode: mode, reaction: reaction)
        connectionVC.onStartConversation = { [weak self] profile in
            VibeAnalytics.track(.conversationStarted, profileID: profile.id)
            self?.openChat(with: profile)
        }
        present(connectionVC, animated: true)
    }

    private func openChat(with profile: VibeProfile) {
        // TODO: push ChatViewController for `profile` once chat is ported.
        tabBarController?.selectedIndex = 3
        showComingSoon("Chat")
    }

    private func openProfile(_ profile: VibeProfile) {
        VibeAnalytics.track(.vibeCardOpened, profileID: profile.id)
        let profileVC = VibeProfileViewController(profile: profile)
        profileVC.hidesBottomBarWhenPushed = true
        profileVC.onAction = { [weak self] action, reasons, reaction in
            self?.popProfile {
                self?.apply(action, to: profile, reasons: reasons, reaction: reaction)
            }
        }
        profileVC.onInterestTapped = { [weak self] interest in
            self?.popProfile {
                self?.show(.people)
                self?.discover(interest)
            }
        }
        profileVC.onHide = { [weak self] profile, blocked in
            self?.popProfile {
                guard let self else { return }
                self.viewModel.hide(profile, block: blocked)
                self.aCustomToastView.show(message: blocked ? "\(profile.displayName) has been blocked"
                                                            : "Thanks for reporting. We'll review this profile.")
            }
        }
        navigationController?.pushViewController(profileVC, animated: true)
    }

    /// The top card animates away; anyone else (opened from Interests) is sent directly.
    private func apply(_ action: VibeAction, to profile: VibeProfile, reasons: [ConnectReason]?, reaction: VibeReaction?) {
        guard viewModel.currentProfile?.id == profile.id, !peopleView.isHidden else {
            send(action, for: profile, reasons: reasons ?? [], reaction: reaction, fromConnectFlow: reasons != nil)
            return
        }
        pendingConnectReasons = reasons
        pendingReaction = reaction
        if !cardStack.perform(action) {
            pendingConnectReasons = nil
            pendingReaction = nil
        }
    }

    private func popProfile(then completion: @escaping () -> Void) {
        navigationController?.popViewController(animated: true)
        if let coordinator = navigationController?.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in completion() }
        } else {
            completion()
        }
    }

    private func openMoments(of profile: VibeProfile, at index: Int) {
        VibeAnalytics.track(.vibeMomentOpened, profileID: profile.id)
        let momentsVC = VibeMomentsViewController(profile: profile, startIndex: index)
        momentsVC.onReport = { [weak self] profile in
            self?.viewModel.hide(profile, block: false)
            self?.aCustomToastView.show(message: "Thanks for reporting. We'll review this profile.")
        }
        momentsVC.onViewProfile = { [weak self] profile in
            self?.dismiss(animated: true) { self?.openProfile(profile) }
        }
        present(momentsVC, animated: true)
    }

    private func discover(_ interest: VibeInterest) {
        if viewModel.interestFilter == interest { return }
        if viewModel.filter(by: interest) {
            aCustomToastView.show(message: "Showing people into \(interest.title)")
        } else {
            aCustomToastView.show(message: "No one else into \(interest.title) right now")
        }
    }

    private func presentSheet(_ viewController: UIViewController, detents: [UISheetPresentationController.Detent]) {
        viewController.modalPresentationStyle = .pageSheet
        if let sheet = viewController.sheetPresentationController {
            sheet.detents = detents
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(viewController, animated: true)
    }

    private func notificationTapped() {
        let aNotificationViewController: NotificationViewController = NotificationViewController.instantiateFromStoryboard()
        navigationController?.pushViewController(aNotificationViewController, animated: true)
    }

    private func openFilters() {
        VibeFiltersViewController.present(from: tabBarController ?? self, filters: viewModel.preferences,
                                          matchCount: { [weak self] in self?.viewModel.matchCount(for: $0) ?? 0 },
                                          onApply: { [weak self] in self?.viewModel.apply($0) })
    }

    private func updateFilterBadge(_ count: Int) {
        filterBadge.isHidden = count == 0
        filterBadge.text = "\(count)"
        filterButton.accessibilityValue = count == 0 ? nil : "\(count) active"
    }

    private func emptyButtonTapped() {
        if case .failed = viewModel.loadState {
            viewModel.loadRecommendations()
        } else if viewModel.isEmptyBecauseOfFilters {
            openFilters()
        } else {
            viewModel.exploreAgain()
        }
    }
}

// MARK: - VibeCardStackViewDelegate
extension DiscoverViewController: VibeCardStackViewDelegate {

    func cardStackShouldBeginInteraction(_ stack: VibeCardStackView) -> Bool {
        !viewModel.actionInProgress && presentedViewController == nil
    }

    func cardStack(_ stack: VibeCardStackView, didBeginDragging profile: VibeProfile) {
        VibeAnalytics.track(.gestureStarted, profileID: profile.id)
    }

    func cardStack(_ stack: VibeCardStackView, didCancelDragging profile: VibeProfile) {
        VibeAnalytics.track(.gestureCancelled, profileID: profile.id)
    }

    func cardStack(_ stack: VibeCardStackView, didCommit action: VibeAction, for profile: VibeProfile) {
        if VoiceIntroPlayer.shared.playingProfileID == profile.id {
            VoiceIntroPlayer.shared.stop()
        }
        let reasons = pendingConnectReasons
        let reaction = action.sendsConnection ? pendingReaction : nil
        pendingConnectReasons = nil
        pendingReaction = nil
        send(action, for: profile, reasons: reasons ?? [], reaction: reaction, fromConnectFlow: reasons != nil)
    }
}

// MARK: - VibeCardViewDelegate
extension DiscoverViewController: VibeCardViewDelegate {

    func vibeCardDidTapProfile(_ card: VibeCardView) {
        openProfile(card.profile)
    }

    func vibeCardDidTapVerification(_ card: VibeCardView) {
        VibeVerificationInfo.present(for: card.profile, from: self)
    }

    func vibeCard(_ card: VibeCardView, didTapInterest interest: VibeInterest) {
        discover(interest)
    }

    /// A photo like is an Interested with context; the heart burst plays before the card leaves.
    func vibeCard(_ card: VibeCardView, didReact reaction: VibeReaction) {
        guard pendingReaction == nil, cardStackShouldBeginInteraction(cardStack) else { return }
        pendingReaction = reaction
        let delay = UIAccessibility.isReduceMotionEnabled ? 0.1 : 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard self.viewModel.currentProfile?.id == card.profile.id, self.cardStack.perform(.interested) else {
                self.pendingReaction = nil
                return
            }
        }
    }
}
