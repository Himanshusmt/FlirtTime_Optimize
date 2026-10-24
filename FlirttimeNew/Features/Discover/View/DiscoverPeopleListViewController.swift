//
//  DiscoverPeopleListViewController.swift
//  FlirttimeNew
//
//  Discover tab: People (swipe cards) and Interest-based discovery. Quick Moments opens
//  QuickMomentsListViewController.
//

import UIKit
import Combine

final class DiscoverPeopleListViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.dashboard
    }

    private enum Page: Int, CaseIterable {
        case people, moments, interests
        var title: String {
            switch self {
            case .people: return "People"
            case .moments: return "Quick Moments"
            case .interests: return "Interests"
            }
        }
    }

    private let viewModel = DiscoverViewModel()
    private var cancellables: Set<AnyCancellable> = []

    /// Set before restoring a card so it animates back in from the side it left through.
    private var pendingReturnAction: MomentsAction?
    /// Set when an action comes from the Connect flow (with optional reasons).
    private var pendingConnectReasons: [ConnectReason]?
    /// Set when the user likes a specific part of the current profile.
    private var pendingReaction: MomentsReaction?
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

    private lazy var notificationButton: UIButton = {
        let button = headerButton(image: UIImage(named: "Notification"), label: "Notifications") { [weak self] in
            self?.notificationTapped()
        }
        button.bindNotificationBadge(inset: 9)
        return button
    }()

    private lazy var filterButton = headerButton(
        image: UIImage(systemName: "slider.horizontal.3", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))?
            .withTintColor(AppColor.Punch, renderingMode: .alwaysOriginal),
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

    private lazy var tabs: MomentsPillTabsView = {
        let tabs = MomentsPillTabsView(titles: Page.allCases.map(\.title))
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
    private let interestsView = DiscoverInterestsView()
    private var currentPage: Page = .people
    private weak var quickMomentsList: QuickMomentsListViewController?

    private lazy var cardStack: MomentsCardStackView = {
        let stack = MomentsCardStackView()
        stack.delegate = self
        stack.cardDelegate = self
        stack.onAccessibilityViewProfile = { [weak self] in
            guard let profile = self?.viewModel.currentProfile else { return }
            self?.openProfile(profile)
        }
        return stack
    }()

    private lazy var actionBar: UIStackView = {
        let superLike = MomentsProfileActionButton.make(kind: .superLike, size: 72) { [weak self] in
            self?.superLikeTapped()
        }
        let notInterested = actionButton(title: "Not interested", symbol: "xmark", size: 58, background: AppColor.AppWhite, tint: AppColor.MineShaft,
                                         hint: "Same as swiping left") { [weak self] in self?.cardStack.perform(.notMyVibe) }
        let superLikeColumn = labeledAction(title: "Super like", color: AppColor.Punch, hint: "Send a Super Like", button: superLike)
        let like = actionButton(title: "Like", symbol: "heart.fill", size: 58, background: AppColor.Lavenderblush, tint: AppColor.Punch,
                                hint: "Same as swiping right") { [weak self] in self?.cardStack.perform(.interested) }
        let stack = UIStackView(arrangedSubviews: [notInterested, superLikeColumn, like])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 36
        // Equal side columns keep Super Like on the screen's vertical center line.
        NSLayoutConstraint.activate([
            notInterested.widthAnchor.constraint(equalTo: like.widthAnchor)
        ])
        return stack
    }()

    private let loadingView: UIStackView = {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = AppColor.Punch
        spinner.startAnimating()
        let label = UILabel.vibeLabel(.regular, 16, color: AppColor.DoveGray)
        label.text = "Finding your matches…"
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
        FreeTierLimitsStore.shared.refresh()
        NotificationBadgeStore.shared.refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        VoiceIntroPlayer.shared.stop()
    }

    // MARK: - UI

    private func setUI() {
        let background = MomentsGradientView(colors: [MomentsTheme.blushGradient[0], AppColor.AppWhite],
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

        [header, tabs, peopleView, interestsView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        [filterChip, cardStack, actionBar, loadingView, emptyView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            peopleView.addSubview($0)
        }
        cardStackTopConstraint = cardStack.topAnchor.constraint(equalTo: peopleView.topAnchor, constant: 4)
        let bottomInset = -(DiscoverPeopleListViewController.centerTabButtonOverlap + 4)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5),
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
        NSLayoutConstraint.activate([
            interestsView.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 12),
            interestsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            interestsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            interestsView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: bottomInset + 20)
        ])

        interestsView.onSelectProfile = { [weak self] profile in self?.openProfile(profile) }
        interestsView.onSelectInterest = { [weak self] item in self?.viewModel.loadPeople(for: item) }
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
            let gradient = MomentsGradientView(colors: MomentsTheme.brandGradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 1))
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

    private func labeledAction(title: String, color: UIColor, hint: String, button: UIButton) -> UIView {
        button.accessibilityHint = hint
        let label = UILabel.vibeLabel(.medium, 12, style: .caption1, color: color)
        label.text = title
        label.isAccessibilityElement = false
        let stack = UIStackView(arrangedSubviews: [button, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        return stack
    }

    private func show(_ page: Page) {
        if page == .moments {
            tabs.select(currentPage.rawValue, sendsActions: false)
            openQuickMomentsList()
            return
        }
        currentPage = page
        if tabs.selectedIndex != page.rawValue {
            tabs.select(page.rawValue, sendsActions: false)
        }
        peopleView.isHidden = page != .people
        interestsView.isHidden = page != .interests
        if page == .interests { viewModel.loadInterestCatalog() }
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    private func openQuickMomentsList() {
        let listVC = QuickMomentsListViewController(tray: viewModel.quickMomentTray)
        listVC.hidesBottomBarWhenPushed = true
        listVC.onAdd = { [weak self] in self?.openAddQuickMoment() }
        listVC.onOpenStories = { [weak self] item, isMine in self?.openQuickMoments(of: item, isMine: isMine) }
        listVC.onRefresh = { [weak self, weak listVC] in
            self?.viewModel.loadQuickMomentTray { [weak listVC] in
                listVC?.endRefreshing()
            }
        }
        quickMomentsList = listVC
        navigationController?.pushViewController(listVC, animated: true)
        viewModel.loadQuickMomentTray()
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

        viewModel.$quickMomentTray
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tray in self?.quickMomentsList?.configure(tray: tray) }
            .store(in: &cancellables)

        viewModel.$interestCatalog
            .receive(on: DispatchQueue.main)
            .sink { [weak self] catalog in self?.interestsView.configure(catalog: catalog) }
            .store(in: &cancellables)

        viewModel.$interestPeople
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] result in self?.interestsView.configure(people: result.profiles, for: result.interestId) }
            .store(in: &cancellables)

        CoinWallet.shared.$balance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] balance in self?.updateCoinBalance(balance) }
            .store(in: &cancellables)
    }

    private func updateCoinBalance(_ balance: Int) {
        coinShopButton.setBalance(balance)
    }

    private func deckChanged(_ deck: [MomentsProfile]) {
        let returning = pendingReturnAction
        pendingReturnAction = nil
        cardStack.sync(current: deck.first, next: deck.dropFirst().first, returningFrom: returning)
        if let current = deck.first, current.id != lastImpressionID {
            lastImpressionID = current.id
            MomentsAnalytics.track(.discoverProfileImpression, profileID: current.id)
        }
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
            emptyTitleLabel.text = "✨ You've explored all available profiles"
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

    private func updateFilterChip(_ interest: MomentsInterest?) {
        filterChip.isHidden = interest == nil
        cardStackTopConstraint.constant = interest == nil ? 4 : 42
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25) {
            self.view.layoutIfNeeded()
        }
        guard let interest else { return }
        filterChip.configuration?.attributedTitle = AttributedString("Showing \(interest.chipTitle)", attributes: AttributeContainer([
            .font: MomentsFont.scaled(.medium, 13, style: .footnote)
        ]))
        filterChip.accessibilityLabel = "Showing people into \(interest.title)"
    }

    // MARK: - Actions

    private func superLikeTapped() {
        guard cardStackShouldBeginInteraction(cardStack) else { return }
        _ = cardStack.perform(.superVibe)
    }

    private func send(_ action: MomentsAction, for profile: MomentsProfile, reasons: [ConnectReason],
                      reaction: MomentsReaction? = nil, fromConnectFlow: Bool) {
        let started = viewModel.perform(action, on: profile, reasons: reasons, reaction: reaction,
                                        viaConnectSheet: fromConnectFlow) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let outcome):
                self.handle(outcome, fromConnectFlow: fromConnectFlow)
            case .failure(.network):
                MomentsHaptics.failed()
                self.showActionFailure(action, profile: profile, reasons: reasons, reaction: reaction, fromConnectFlow: fromConnectFlow)
            case .failure(.serverBusy):
                MomentsHaptics.failed()
                self.showActionFailure(action, profile: profile, reasons: reasons, reaction: reaction,
                                       fromConnectFlow: fromConnectFlow, serverBusy: true)
            case .failure(.membershipRequired), .failure(.insufficientCoins):
                self.restore(profile, from: action)
                self.showQuotaPopup(.insufficientCoins)
            case .failure(.likeLimitReached):
                self.restore(profile, from: action)
                self.showQuotaPopup(.likeLimitReached)
            }
        }
        if !started {
            cardStack.sync(current: viewModel.currentProfile, next: viewModel.nextProfile, returningFrom: action)
        }
    }

    private func handle(_ outcome: MomentsActionOutcome, fromConnectFlow: Bool) {
        if outcome.isMatch {
            MomentsHaptics.connected()
            presentConnection(.matched(outcome.profile), reaction: outcome.reaction)
        } else if fromConnectFlow {
            presentConnection(.sent(outcome.profile), reaction: outcome.reaction)
        } else if let reaction = outcome.reaction {
            aCustomToastView.show(message: "💗 You liked \(reaction.subject(for: outcome.profile.displayName))")
        } else if outcome.action == .interested {
            aCustomToastView.show(message: "💗 Like sent to \(outcome.profile.displayName)")
        } else if outcome.action == .superVibe {
            aCustomToastView.show(message: "✨ Super Like sent to \(outcome.profile.displayName)")
        }
    }

    /// Never reports success for a failed action; the user either retries or keeps the profile for later.
    private func showActionFailure(_ action: MomentsAction, profile: MomentsProfile, reasons: [ConnectReason],
                                   reaction: MomentsReaction?, fromConnectFlow: Bool, serverBusy: Bool = false) {
        let alert = UIAlertController(
            title: serverBusy ? "Server is busy" : "Couldn't update right now",
            message: serverBusy
                ? "Please try again in a moment. Your \(action.displayName) for \(profile.displayName) wasn't sent."
                : "Your \(action.displayName) for \(profile.displayName) wasn't sent.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            self?.send(action, for: profile, reasons: reasons, reaction: reaction, fromConnectFlow: fromConnectFlow)
        })
        alert.addAction(UIAlertAction(title: "Continue Later", style: .cancel) { [weak self] _ in
            self?.restore(profile, from: action)
        })
        present(alert, animated: true)
    }

    private func restore(_ profile: MomentsProfile, from action: MomentsAction) {
        pendingReturnAction = action
        viewModel.restore(profile)
    }

    private func presentConnection(_ mode: MomentsConnectionViewController.Mode, reaction: MomentsReaction?) {
        let connectionVC = MomentsConnectionViewController(mode: mode, reaction: reaction)
        connectionVC.onStartConversation = { [weak self] profile in
            MomentsAnalytics.track(.conversationStarted, profileID: profile.id)
            self?.openChat(with: profile)
        }
        present(connectionVC, animated: true)
    }

    private func openChat(with profile: MomentsProfile) {
        guard let userID = profile.remoteUserId, !userID.isEmpty else {
            aCustomToastView.show(message: "Unable to start chat")
            return
        }
        if !FreeTierLimitsStore.shared.canStartChat(isMatched: true) {
            showSubscriptionPopUp(subscriptionPopUpType: .chat)
            return
        }
        let avatarURL = profile.photos.first.flatMap { path -> String? in
            guard !path.isEmpty else { return nil }
            return path.hasPrefix("http") ? path : ApiName.imgBaseURL + path
        }
        ChatProfileRouter.openChat(userID: userID,
                                   name: profile.displayName,
                                   avatarPath: avatarURL,
                                   isVerified: profile.isVerified,
                                   from: self)
    }

    private func openProfile(_ profile: MomentsProfile) {
        MomentsAnalytics.track(.vibeCardOpened, profileID: profile.id)
        let profileVC = CardDetailViewController(profile: profile)
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
        profileVC.onSafetyAction = { [weak self] profile, action in
            self?.applySafety(action, to: profile) {
                self?.popProfile {}
            }
        }
        navigationController?.pushViewController(profileVC, animated: true)
    }

    /// The top card animates away; anyone else (opened from Interests) is sent directly.
    private func apply(_ action: MomentsAction, to profile: MomentsProfile, reasons: [ConnectReason]?, reaction: MomentsReaction?) {
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

    /// Sends a report or block; `onSuccess` runs only once the API accepts it. On failure the user stays put.
    private func applySafety(_ action: MomentsSafetyAction, to profile: MomentsProfile, onSuccess: @escaping () -> Void) {
        setLoading(true)
        viewModel.apply(action, to: profile) { [weak self] result in
            guard let self else { return }
            self.setLoading(false)
            switch result {
            case .success:
                onSuccess()
                if case .block = action {
                    self.aCustomToastView.show(message: "\(profile.displayName) has been blocked")
                } else {
                    self.aCustomToastView.show(message: "Thanks for reporting. We'll review this profile.")
                }
            case .failure(let error):
                self.aCustomToastView.show(message: parseError(error) ?? "Something went wrong. Please try again.")
            }
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

    private func openAddQuickMoment() {
        let presenter = quickMomentsList ?? self
        let composer = AddQuickMomentViewController()
        composer.onShare = { [weak self, weak presenter] text, background, image in
            guard let self else { return }
            presenter?.setLoading(true)
            self.viewModel.createQuickMoment(text: text, background: background, image: image) { [weak self, weak presenter] result in
                presenter?.setLoading(false)
                guard let self else { return }
                let toast = presenter?.aCustomToastView ?? self.aCustomToastView
                switch result {
                case .success:
                    toast.show(message: "Quick moment shared")
                case .failure(let error):
                    toast.show(message: error.message)
                }
            }
        }
        presenter.present(composer, animated: true)
    }

    private func openQuickMoments(of item: QuickMomentTrayItem, isMine: Bool) {
        viewModel.quickMoments(of: item, isMine: isMine) { [weak self] stories in
            guard let self else { return }
            if isMine {
                self.presentQuickMoments(stories, of: item, isMine: true)
                return
            }
            guard !stories.isEmpty else {
                self.aCustomToastView.show(message: "These moments have expired")
                self.viewModel.loadQuickMomentTray()
                return
            }
            self.presentQuickMoments(stories, of: item, isMine: false)
        }
    }

    /// `stories` arrive newest first; they play oldest first, starting at the first unseen one.
    private func presentQuickMoments(_ stories: [QuickMoment], of item: QuickMomentTrayItem, isMine: Bool) {
        guard !stories.isEmpty else { return }
        let (pages, start) = QuickMomentViewerPage.sequence(tray: viewModel.quickMomentTray, selected: item, isMine: isMine)
        let pager = QuickMomentsPagerViewController(pages: pages, startIndex: start, initialStories: stories)
        pager.onLoadStories = { [weak self] page, done in
            self?.viewModel.quickMoments(of: page.item, isMine: page.isMine, completion: done)
        }
        pager.onBindViewer = { [weak self] viewer, stories, page in
            self?.bindQuickMomentViewer(viewer, stories: stories, isMine: page.isMine)
        }
        pager.onDismiss = { [weak self] in self?.viewModel.loadQuickMomentTray() }
        (navigationController ?? self).present(pager, animated: true)
    }

    private func bindQuickMomentViewer(_ viewer: QuickMomentViewController, stories: [QuickMoment], isMine: Bool) {
        if !isMine {
            MomentsAnalytics.track(.vibeMomentOpened, profileID: viewer.analyticsProfileID)
        }

        if isMine {
            viewer.onShowActivity = { index, presenter in
                guard stories.indices.contains(index) else { return }
                let activity = QuickMomentActivityViewController(moment: stories[index])
                activity.modalPresentationStyle = .pageSheet
                if let sheet = activity.sheetPresentationController {
                    sheet.detents = [.medium(), .large()]
                    sheet.prefersGrabberVisible = true
                }
                presenter.present(activity, animated: true)
            }
            viewer.onDelete = { [weak self] index in
                guard stories.indices.contains(index) else { return }
                self?.viewModel.deleteQuickMoment(id: stories[index].id) { message in
                    self?.aCustomToastView.show(message: message ?? "Quick moment deleted")
                }
            }
            return
        }

        var seen = Set<String>()
        viewer.onMomentShown = { [weak self] index in
            guard stories.indices.contains(index), !stories[index].hasViewed,
                  seen.insert(stories[index].id).inserted else { return }
            self?.viewModel.markQuickMomentViewed(id: stories[index].id)
        }
        viewer.onReact = { [weak self] index, emoji in
            guard stories.indices.contains(index) else { return }
            self?.viewModel.reactToQuickMoment(id: stories[index].id, emoji: emoji) { message in
                self?.aCustomToastView.show(message: message)
            }
        }
        viewer.onReply = { [weak self] index, message in
            guard stories.indices.contains(index) else { return }
            self?.viewModel.replyToQuickMoment(id: stories[index].id, message: message) { error in
                self?.aCustomToastView.show(message: error)
            }
        }
        viewer.onReport = { [weak self] profile, reason in
            self?.applySafety(.report(reason), to: profile) {}
        }
        viewer.onViewProfile = { [weak self] profile in
            self?.dismiss(animated: true) { self?.openProfile(profile) }
        }
    }

    private func discover(_ interest: MomentsInterest) {
        if viewModel.interestFilter == interest { return }
        if viewModel.filter(by: interest) {
            aCustomToastView.show(message: "Showing people into \(interest.title)")
        } else {
            aCustomToastView.show(message: "No one else into \(interest.title) right now")
        }
    }

    private func notificationTapped() {
        let aNotificationViewController: NotificationViewController = NotificationViewController.instantiateFromStoryboard()
        navigationController?.pushViewController(aNotificationViewController, animated: true)
    }

    private func openFilters() {
        viewModel.loadFilterOptions()
        MomentsFiltersViewController.present(
            from: tabBarController ?? self,
            filters: viewModel.preferences,
            options: viewModel.filterOptions,
            matchCount: { [weak self] filters, completion in
                guard let self else { return completion(nil) }
                self.viewModel.matchCount(for: filters, completion: completion)
            },
            onReset: { [weak self] completion in
                guard let self else { return completion(nil) }
                self.viewModel.resetFilters { defaults in
                    if defaults == nil {
                        self.aCustomToastView.show(message: "Couldn't reset your filters. Please try again.")
                    }
                    completion(defaults)
                }
            },
            onApply: { [weak self] filters in
                guard let self else { return }
                self.aActivityIndicator.show()
                self.viewModel.apply(filters) { [weak self] error in
                    guard let self else { return }
                    self.aActivityIndicator.hide()
                    if let error { self.aCustomToastView.show(message: error) }
                }
            })
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

// MARK: - MomentsCardStackViewDelegate
extension DiscoverPeopleListViewController: MomentsCardStackViewDelegate {

    func cardStackShouldBeginInteraction(_ stack: MomentsCardStackView) -> Bool {
        !viewModel.actionInProgress && presentedViewController == nil
    }

    func cardStack(_ stack: MomentsCardStackView, shouldCommit action: MomentsAction, for profile: MomentsProfile) -> Bool {
        guard let blocked = FreeTierLimitsStore.shared.blockReason(for: action) else { return true }
        showQuotaPopup(blocked)
        return false
    }

    private func showQuotaPopup(_ error: MomentsActionError) {
        switch error {
        case .likeLimitReached:
            showSubscriptionPopUp(subscriptionPopUpType: .unlimitedSwipes)
        case .insufficientCoins, .membershipRequired:
            showSubscriptionPopUp(subscriptionPopUpType: .superLike)
        default:
            break
        }
    }

    func cardStack(_ stack: MomentsCardStackView, didBeginDragging profile: MomentsProfile) {
        MomentsAnalytics.track(.gestureStarted, profileID: profile.id)
    }

    func cardStack(_ stack: MomentsCardStackView, didCancelDragging profile: MomentsProfile) {
        MomentsAnalytics.track(.gestureCancelled, profileID: profile.id)
    }

    func cardStack(_ stack: MomentsCardStackView, didCommit action: MomentsAction, for profile: MomentsProfile) {
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

// MARK: - MomentsCardViewDelegate
extension DiscoverPeopleListViewController: MomentsCardViewDelegate {

    func vibeCardDidTapProfile(_ card: MomentsCardView) {
        openProfile(card.profile)
    }

    func vibeCardDidTapVerification(_ card: MomentsCardView) {
        MomentsVerificationInfo.present(for: card.profile, from: self)
    }

    func vibeCard(_ card: MomentsCardView, didTapInterest interest: MomentsInterest) {
        discover(interest)
    }

    /// A photo like is an Interested with context; the heart burst plays before the card leaves.
    func vibeCard(_ card: MomentsCardView, didReact reaction: MomentsReaction) {
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
