//
//  PremiumViewController.swift
//  FlirttimeNew
//
//  Flirttime Premium paywall backed by App Store auto-renewable subscriptions.
//

import UIKit
import Combine
import StoreKit

final class PremiumViewController: BaseViewController {

    /// Called after the membership is active on our server.
    var onPurchased: (() -> Void)?

    private let source: SubscriptionPopUpType?
    private let viewModel = PremiumViewModel()
    private var cancellables: Set<AnyCancellable> = []
    private var planTiles: [PremiumPlanTile] = []
    private var carouselTimer: Timer?

    private static let benefits: [PremiumBenefit] = [
        PremiumBenefit(symbol: "eye.fill", title: "See who likes you", detail: "Skip the guessing and match with your admirers instantly."),
        PremiumBenefit(symbol: "infinity", title: "Unlimited Vibes", detail: "No daily limits. Discover as many people as you like."),
        PremiumBenefit(symbol: "bubble.left.and.bubble.right.fill", title: "Chat before matching", detail: "Start the conversation with anyone you vibe with."),
        PremiumBenefit(symbol: "star.fill", title: "Weekly Super Vibes", detail: "Stand out and let them know they're special."),
        PremiumBenefit(symbol: "gift.fill", title: "Unlimited compliments", detail: "Make a great first impression every time."),
        PremiumBenefit(symbol: "bolt.heart.fill", title: "Priority in Discover", detail: "Get shown to more people, more often.")
    ]

    init(source: SubscriptionPopUpType? = nil) {
        self.source = source
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Views

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    private let carousel: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.clipsToBounds = false
        return scrollView
    }()

    private let carouselStack = UIStackView()

    private let pageControl: UIPageControl = {
        let control = UIPageControl()
        control.numberOfPages = benefits.count
        control.currentPageIndicatorTintColor = AppColor.Punch
        control.pageIndicatorTintColor = AppColor.SeaPink.withAlphaComponent(0.5)
        control.isUserInteractionEnabled = false
        return control
    }()

    private let tilesScroll: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.clipsToBounds = false
        return scrollView
    }()

    private let tilesStack: UIStackView = {
        let stack = UIStackView()
        stack.spacing = 12
        stack.alignment = .fill
        return stack
    }()

    private let memberBanner = PremiumMemberBanner()
    private let comparisonCard = PremiumComparisonCard()

    private let bonusChip: UILabel = {
        let label = UILabel.vibeLabel(.medium, 13, style: .footnote, color: AppColor.Cherrywood)
        label.backgroundColor = AppColor.Serenade
        label.layer.cornerRadius = 14
        label.clipsToBounds = true
        label.textAlignment = .center
        label.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return label
    }()

    private lazy var restoreButton: PremiumRestoreButton = {
        let button = PremiumRestoreButton()
        button.addAction(UIAction { [weak self] _ in self?.viewModel.restore() }, for: .touchUpInside)
        return button
    }()

    private lazy var shopCard: PremiumShopCard = {
        let card = PremiumShopCard()
        card.addAction(UIAction { [weak self] _ in self?.openCoinShop() }, for: .touchUpInside)
        return card
    }()

    private let loadingView: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = AppColor.Punch
        spinner.hidesWhenStopped = true
        return spinner
    }()

    private let errorLabel: UILabel = {
        let label = UILabel.vibeLabel(.regular, 15, color: AppColor.DoveGray, lines: 0)
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private lazy var retryButton: UIButton = {
        let button = StoreUI.linkButton("Try Again", color: AppColor.Punch) { [weak self] in self?.viewModel.load() }
        button.isHidden = true
        return button
    }()

    private lazy var continueButton: PremiumCTAButton = {
        let button = PremiumCTAButton()
        button.setTitle("Get Premium")
        button.addAction(UIAction { [weak self] _ in self?.continueTapped() }, for: .touchUpInside)
        return button
    }()

    private let renewalLabel: UILabel = {
        let label = UILabel.vibeLabel(.regular, 11, style: .caption2, color: AppColor.Boulder, lines: 0)
        label.textAlignment = .center
        return label
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        setUI()
        setUpBinding()
        viewModel.load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCarousel()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        carouselTimer?.invalidate()
    }

    // MARK: - UI

    private func setUI() {
        let background = VibeGradientView(colors: [VibeTheme.blushGradient[0], AppColor.AppWhite],
                                          start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 0.45))
        view.addSubview(background)
        background.pinEdges(to: view)

        let back = StoreUI.circleButton(symbol: navigationController?.viewControllers.first == self ? "xmark" : "chevron.left",
                                        label: "Back", onDark: false)
        back.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        let title = UILabel.vibeLabel(.bold, 20, style: .title3, color: AppColor.AppBlack)
        title.text = "Premium"
        title.textAlignment = .center
        title.accessibilityTraits = .header
        let topBar = UIView()
        [back, title, restoreButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            topBar.addSubview($0)
        }
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            back.topAnchor.constraint(equalTo: topBar.topAnchor),
            back.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            title.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            title.leadingAnchor.constraint(greaterThanOrEqualTo: back.trailingAnchor, constant: 8),
            title.trailingAnchor.constraint(lessThanOrEqualTo: restoreButton.leadingAnchor, constant: -8),
            restoreButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            restoreButton.centerYAnchor.constraint(equalTo: back.centerYAnchor)
        ])

        let footerStack = UIStackView(arrangedSubviews: [continueButton, renewalLabel, makeLegalLinks()])
        footerStack.axis = .vertical
        footerStack.spacing = 4
        footerStack.setCustomSpacing(10, after: continueButton)
        let footer = UIView()
        footer.backgroundColor = AppColor.AppWhite
        footer.layer.shadowColor = UIColor.black.cgColor
        footer.layer.shadowOpacity = 0.06
        footer.layer.shadowRadius = 12
        footer.layer.shadowOffset = CGSize(width: 0, height: -4)

        let hero = PremiumHeroView(title: headlineText(), subtitle: subtitleText)
        let content = UIStackView(arrangedSubviews: [hero, memberBanner, makeCarousel(), makePlansSection(),
                                                     loadingView, errorLabel, retryButton, comparisonCard, shopCard])
        content.axis = .vertical
        content.spacing = 18
        content.setCustomSpacing(22, after: hero)
        content.setCustomSpacing(24, after: comparisonCard)
        memberBanner.isHidden = true
        comparisonCard.isHidden = true

        [scrollView, topBar, footer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        [content, footerStack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        scrollView.addSubview(content)
        footer.addSubview(footerStack)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerStack.topAnchor.constraint(equalTo: footer.topAnchor, constant: 14),
            footerStack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 20),
            footerStack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -20),
            footerStack.bottomAnchor.constraint(equalTo: footer.safeAreaLayoutGuide.bottomAnchor, constant: -2)
        ])
        view.bringSubviewToFront(footer)
    }

    private func headlineText() -> NSAttributedString {
        let text: String
        switch source {
        case .chat: text = "Start the conversation first"
        case .compliment: text = "Make an unforgettable first impression"
        case .superLike: text = "Stand out with Super Vibes"
        case .unlimitedSwipes: text = "Keep the vibes coming"
        case nil: text = "Find your match faster"
        }
        return NSAttributedString(string: text, attributes: [.font: VibeFont.scaled(.bold, 26, style: .title1), .foregroundColor: UIColor.white])
    }

    private var subtitleText: String {
        switch source {
        case .chat: return "Message anyone you vibe with, no match needed."
        case .compliment: return "Send compliments that get you noticed."
        case .superLike: return "Let them know they're special before anyone else."
        case .unlimitedSwipes: return "No daily limits. Discover as many people as you like."
        case nil: return "More matches, more conversations, more you."
        }
    }

    private func makeCarousel() -> UIView {
        carouselStack.distribution = .fillEqually
        carouselStack.translatesAutoresizingMaskIntoConstraints = false
        carousel.addSubview(carouselStack)
        carousel.delegate = self
        for benefit in Self.benefits {
            let card = PremiumBenefitCard(benefit)
            carouselStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: carousel.frameLayoutGuide.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            carouselStack.topAnchor.constraint(equalTo: carousel.contentLayoutGuide.topAnchor),
            carouselStack.leadingAnchor.constraint(equalTo: carousel.contentLayoutGuide.leadingAnchor),
            carouselStack.trailingAnchor.constraint(equalTo: carousel.contentLayoutGuide.trailingAnchor),
            carouselStack.bottomAnchor.constraint(equalTo: carousel.contentLayoutGuide.bottomAnchor),
            carouselStack.heightAnchor.constraint(equalTo: carousel.frameLayoutGuide.heightAnchor),
            carousel.heightAnchor.constraint(equalToConstant: 112)
        ])
        let stack = UIStackView(arrangedSubviews: [carousel, pageControl])
        stack.axis = .vertical
        stack.spacing = 0
        return stack
    }

    private func makePlansSection() -> UIView {
        let title = UILabel.vibeLabel(.bold, 18, style: .headline, color: AppColor.AppBlack)
        title.text = "Choose your plan"
        title.accessibilityTraits = .header

        tilesStack.translatesAutoresizingMaskIntoConstraints = false
        tilesScroll.addSubview(tilesStack)
        NSLayoutConstraint.activate([
            tilesStack.topAnchor.constraint(equalTo: tilesScroll.contentLayoutGuide.topAnchor),
            tilesStack.leadingAnchor.constraint(equalTo: tilesScroll.contentLayoutGuide.leadingAnchor),
            tilesStack.trailingAnchor.constraint(equalTo: tilesScroll.contentLayoutGuide.trailingAnchor),
            tilesStack.bottomAnchor.constraint(equalTo: tilesScroll.contentLayoutGuide.bottomAnchor),
            tilesStack.heightAnchor.constraint(equalTo: tilesScroll.frameLayoutGuide.heightAnchor),
            tilesScroll.heightAnchor.constraint(equalToConstant: 184)
        ])
        let chipRow = UIStackView(arrangedSubviews: [bonusChip])
        chipRow.alignment = .center
        chipRow.axis = .vertical
        let stack = UIStackView(arrangedSubviews: [title, tilesScroll, chipRow])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(12, after: tilesScroll)
        return stack
    }

    private func makeLegalLinks() -> UIView {
        let privacy = StoreUI.linkButton("Privacy Policy", color: AppColor.Boulder) { [weak self] in self?.loadPrivacyPolicy() }
        let terms = StoreUI.linkButton("Terms of Use", color: AppColor.Boulder) { [weak self] in self?.openTerms() }
        let stack = UIStackView(arrangedSubviews: [UIView(), privacy, terms, UIView()])
        stack.spacing = 16
        stack.distribution = .equalCentering
        return stack
    }

    // MARK: - Carousel

    private var initialBenefitPage: Int {
        switch source {
        case .chat: return 2
        case .superLike: return 3
        case .compliment: return 4
        case .unlimitedSwipes: return 1
        case nil: return 0
        }
    }

    private func startCarousel() {
        guard carouselTimer?.isValid != true else { return }
        if pageControl.currentPage == 0 && initialBenefitPage > 0 && carousel.contentOffset.x == 0 {
            scrollCarousel(to: initialBenefitPage, animated: false)
        }
        guard !UIAccessibility.isReduceMotionEnabled, !UIAccessibility.isVoiceOverRunning else { return }
        carouselTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.scrollCarousel(to: (self.pageControl.currentPage + 1) % Self.benefits.count, animated: true)
        }
    }

    private func scrollCarousel(to page: Int, animated: Bool) {
        view.layoutIfNeeded()
        carousel.setContentOffset(CGPoint(x: CGFloat(page) * carousel.bounds.width, y: 0), animated: animated)
        pageControl.currentPage = page
    }

    // MARK: - Binding

    private func setUpBinding() {
        viewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(state) }
            .store(in: &cancellables)

        viewModel.$options
            .receive(on: DispatchQueue.main)
            .sink { [weak self] options in self?.buildTiles(options) }
            .store(in: &cancellables)

        Publishers.CombineLatest4(viewModel.$selectedIndex, viewModel.$isSubscribed, viewModel.$isPurchasing, viewModel.$isRestoring)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in self?.updateSelection() }
            .store(in: &cancellables)

        viewModel.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: StoreManager.entitlementsDidChange)
            .sink { [weak self] _ in self?.viewModel.refreshStatus() }
            .store(in: &cancellables)
    }

    private func render(_ state: PremiumViewModel.State) {
        switch state {
        case .loading:
            loadingView.startAnimating()
            errorLabel.isHidden = true
            retryButton.isHidden = true
        case .loaded:
            loadingView.stopAnimating()
            errorLabel.isHidden = true
            retryButton.isHidden = true
        case .failed(let message):
            loadingView.stopAnimating()
            errorLabel.text = message
            errorLabel.isHidden = false
            retryButton.isHidden = false
        }
        continueButton.isEnabled = state == .loaded
        continueButton.alpha = state == .loaded ? 1 : 0.6
    }

    private func buildTiles(_ options: [PremiumViewModel.PlanOption]) {
        tilesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        planTiles = options.enumerated().map { index, option in
            let tile = PremiumPlanTile()
            tile.configure(with: option, savings: viewModel.savingsPercent(for: option))
            tile.addAction(UIAction { [weak self] _ in
                guard let self, !self.viewModel.isPurchasing else { return }
                VibeHaptics.threshold()
                self.viewModel.selectedIndex = index
            }, for: .touchUpInside)
            tilesStack.addArrangedSubview(tile)
            return tile
        }
        updateSelection()
        view.layoutIfNeeded()
        if planTiles.indices.contains(viewModel.selectedIndex) {
            tilesScroll.scrollRectToVisible(planTiles[viewModel.selectedIndex].frame.insetBy(dx: -40, dy: 0), animated: false)
        }
    }

    private func updateSelection() {
        for (index, tile) in planTiles.enumerated() {
            tile.isSelected = index == viewModel.selectedIndex
        }
        let option = viewModel.selectedOption
        comparisonCard.isHidden = option == nil
        let bonus = option?.plan.bonusCoins ?? 0
        bonusChip.isHidden = bonus == 0
        bonusChip.text = "    🎁 Includes \(bonus.formatted()) bonus coins    "
        if let option {
            comparisonCard.configure(planTitle: option.title, features: option.plan.features ?? [], bonusCoins: bonus)
            renewalLabel.text = "\(option.displayPrice) every \(option.plan.renewalPeriod). Renews automatically until cancelled. "
                + "Cancel anytime in Settings at least 24 hours before renewal."
        }

        memberBanner.isHidden = !viewModel.isSubscribed
        if viewModel.isSubscribed {
            continueButton.setTitle("Manage Subscription")
        } else if let option {
            continueButton.setTitle("Get \(option.title) · \(option.displayPrice)")
        }
        let buying = viewModel.isPurchasing && !viewModel.isRestoring
        continueButton.configuration?.showsActivityIndicator = buying
        continueButton.isUserInteractionEnabled = !viewModel.isPurchasing
        continueButton.accessibilityHint = viewModel.isSubscribed ? "Opens your App Store subscriptions" : "Starts the App Store purchase"
        restoreButton.isLoading = viewModel.isRestoring
        restoreButton.isEnabled = !buying
    }

    // MARK: - Actions

    private func continueTapped() {
        guard viewModel.isSubscribed else {
            viewModel.purchaseSelected()
            return
        }
        guard let scene = view.window?.windowScene else { return }
        Task { @MainActor in
            try? await AppStore.showManageSubscriptions(in: scene)
            viewModel.refreshStatus()
        }
    }

    private func handle(_ event: PremiumViewModel.PurchaseEvent) {
        switch event {
        case .purchased(let message), .restored(let message):
            VibeHaptics.connected()
            showNewAlertPopUp(Title: "You're Premium 👑", Msg: message, isSuccess: true) { _ in }
            onPurchased?()
            close()
        case .pending:
            aCustomToastView.show(message: "Your purchase is waiting for approval. We'll unlock Premium as soon as it's confirmed.")
        case .failed(let message):
            VibeHaptics.failed()
            showNewAlertPopUp(Title: "Purchase failed", Msg: message, isSuccess: false) { _ in }
        }
    }

    private func close() {
        if let navigationController, navigationController.viewControllers.first != self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private func openTerms() {
        guard let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - UIScrollViewDelegate
extension PremiumViewController: UIScrollViewDelegate {

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === carousel else { return }
        carouselTimer?.invalidate()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === carousel, scrollView.bounds.width > 0 else { return }
        pageControl.currentPage = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
    }
}
