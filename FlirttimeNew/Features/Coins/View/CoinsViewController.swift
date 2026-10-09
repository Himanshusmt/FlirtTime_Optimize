//
//  CoinsViewController.swift
//  FlirttimeNew
//
//  Coin Shop: wallet balance and consumable coin packs.
//

import UIKit
import Combine

final class CoinsViewController: BaseViewController {

    private let viewModel = CoinsViewModel()
    private var cancellables: Set<AnyCancellable> = []
    private var packCards: [CoinPackCardView] = []

    init() {
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

    private let balanceCard = CoinBalanceCard()

    private lazy var premiumCard: UIControl = {
        let card = CoinPremiumUpsellCard()
        card.addAction(UIAction { [weak self] _ in self?.openPremium(source: nil) }, for: .touchUpInside)
        return card
    }()

    private let gridStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        return stack
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
        premiumCard.isHidden = UserDataManager.shared.isUserSubscriptionDone == true
    }

    // MARK: - UI

    private func setUI() {
        let background = VibeGradientView(colors: [VibeTheme.blushGradient[0], AppColor.AppWhite],
                                          start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 0.4))
        view.addSubview(background)
        background.pinEdges(to: view)

        let back = StoreUI.circleButton(symbol: "chevron.left", label: "Back", onDark: false)
        back.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        let title = UILabel.vibeLabel(.bold, 20, style: .title3, color: AppColor.AppBlack)
        title.text = "Coin Shop"
        title.textAlignment = .center
        title.accessibilityTraits = .header
        let spacer = UIView()
        let header = UIStackView(arrangedSubviews: [back, title, spacer])
        header.alignment = .center

        let packsTitle = UILabel.vibeLabel(.bold, 18, style: .headline, color: AppColor.AppBlack)
        packsTitle.text = "Top up your coins"
        packsTitle.accessibilityTraits = .header

        let note = UILabel.vibeLabel(.regular, 12, style: .caption1, color: AppColor.Boulder, lines: 0)
        note.text = "Coins are added to your wallet right after purchase and never expire. Coin purchases are non-refundable."
        note.textAlignment = .center
        let privacy = StoreUI.linkButton("Privacy Policy") { [weak self] in self?.loadPrivacyPolicy() }

        let content = UIStackView(arrangedSubviews: [balanceCard, premiumCard, packsTitle, gridStack,
                                                     loadingView, errorLabel, retryButton, note, privacy])
        content.axis = .vertical
        content.spacing = 14
        content.setCustomSpacing(24, after: premiumCard)
        content.setCustomSpacing(24, after: gridStack)
        content.setCustomSpacing(4, after: note)

        [header, scrollView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            spacer.widthAnchor.constraint(equalTo: back.widthAnchor),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    // MARK: - Binding

    private func setUpBinding() {
        CoinWallet.shared.$balance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] balance in self?.balanceCard.setBalance(balance) }
            .store(in: &cancellables)

        viewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(state) }
            .store(in: &cancellables)

        viewModel.$options
            .receive(on: DispatchQueue.main)
            .sink { [weak self] options in self?.buildGrid(options) }
            .store(in: &cancellables)

        viewModel.$purchasingPackID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                self?.packCards.forEach { $0.isPurchasing = $0.packID == id && id != nil }
                self?.packCards.forEach { $0.isEnabled = id == nil }
            }
            .store(in: &cancellables)

        viewModel.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
    }

    private func render(_ state: CoinsViewModel.State) {
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
    }

    private func buildGrid(_ options: [CoinsViewModel.PackOption]) {
        gridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        packCards = options.map { option in
            let card = CoinPackCardView()
            card.configure(with: option)
            card.addAction(UIAction { [weak self] _ in self?.viewModel.purchase(option) }, for: .touchUpInside)
            return card
        }
        let perRow = 3
        for start in stride(from: 0, to: packCards.count, by: perRow) {
            let cards: [UIView] = Array(packCards[start..<min(start + perRow, packCards.count)])
            let row = UIStackView(arrangedSubviews: cards + (0..<(perRow - cards.count)).map { _ in UIView() })
            row.spacing = 10
            row.distribution = .fillEqually
            row.alignment = .fill
            gridStack.addArrangedSubview(row)
        }
    }

    private func handle(_ event: CoinsViewModel.PurchaseEvent) {
        switch event {
        case .purchased(let coins, let message):
            VibeHaptics.connected()
            balanceCard.celebrate()
            showNewAlertPopUp(Title: "+\(coins) coins 🎉", Msg: message, isSuccess: true) { _ in }
        case .pending:
            aCustomToastView.show(message: "Your purchase is waiting for approval. Coins will be added once it's confirmed.")
        case .failed(let message):
            VibeHaptics.failed()
            showNewAlertPopUp(Title: "Purchase failed", Msg: message, isSuccess: false) { _ in }
        }
    }
}
