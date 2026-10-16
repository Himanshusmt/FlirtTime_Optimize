//
//  PremiumViewModel.swift
//  FlirttimeNew
//

import Foundation
import Combine
import RxSwift
import StoreKit
import Swinject

final class PremiumViewModel {

    struct PlanOption: Hashable {
        let plan: SubscriptionPlanData
        let product: Product?

        var id: Int { plan.id ?? 0 }
        var title: String { plan.name ?? plan.durationTitle }

        /// The App Store's localized price when available, otherwise the server price.
        var displayPrice: String {
            if let product { return product.displayPrice }
            return PremiumViewModel.format(Decimal(string: plan.price ?? "") ?? 0, currency: plan.currency)
        }

        var weeklyAmount: Double {
            let total = product?.price ?? Decimal(string: plan.price ?? "") ?? 0
            return NSDecimalNumber(decimal: total).doubleValue / plan.weeks
        }

        var pricePerWeek: String? {
            guard (plan.durationDays ?? 0) > 7 else { return nil }
            let currency = product?.priceFormatStyle.currencyCode ?? plan.currency ?? "INR"
            let formatted = Decimal(weeklyAmount.rounded()).formatted(.currency(code: currency).precision(.fractionLength(0)))
            return "\(formatted)/wk"
        }

        /// ("6", "months") for the plan tile.
        var durationParts: (count: String, unit: String) {
            let parts = plan.durationTitle.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return (plan.durationTitle, "") }
            return (parts[0], parts[1].lowercased())
        }

        static func == (lhs: PlanOption, rhs: PlanOption) -> Bool { lhs.plan == rhs.plan && lhs.product?.id == rhs.product?.id }
        func hash(into hasher: inout Hasher) { hasher.combine(plan) }
    }

    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum PurchaseEvent {
        case purchased(String)
        case restored(String)
        case pending
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var options: [PlanOption] = []
    @Published var selectedIndex = 0
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var isSubscribed = UserDataManager.shared.isUserSubscriptionDone == true
    let events = PassthroughSubject<PurchaseEvent, Never>()

    private let planStore = SubscriptionPlanStore.shared
    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
        planStore.$options
            .sink { [weak self] options in
                guard let self else { return }
                self.options = options
                self.selectedIndex = options.firstIndex { $0.plan.isPopular == true } ?? 0
            }
            .store(in: &cancellables)
        planStore.$state
            .map { state -> State in
                switch state {
                case .idle, .loading: return .loading
                case .loaded: return .loaded
                case .failed(let message): return .failed(message)
                }
            }
            .assign(to: &$state)
    }

    var selectedOption: PlanOption? {
        options.indices.contains(selectedIndex) ? options[selectedIndex] : nil
    }

    /// Saving per week against the shortest plan; `nil` below 5%.
    func savingsPercent(for option: PlanOption) -> Int? {
        guard let base = options.min(by: { ($0.plan.durationDays ?? 0) < ($1.plan.durationDays ?? 0) }),
              base != option, base.weeklyAmount > 0 else { return nil }
        let percent = Int(((1 - option.weeklyAmount / base.weeklyAmount) * 100).rounded())
        return percent >= 5 ? percent : nil
    }

    // MARK: - Loading

    /// Uses the plans preloaded at launch; refetches only if that load failed or hasn't run.
    func load() {
        planStore.preloadIfNeeded()
        refreshStatus()
    }

    // MARK: - Purchase

    func purchaseSelected() {
        guard !isPurchasing, let option = selectedOption else { return }
        guard let product = option.product else {
            events.send(.failed(StoreError.productUnavailable.localizedDescription))
            return
        }
        isPurchasing = true
        Task { @MainActor in
            do {
                switch try await StoreManager.shared.purchase(product) {
                case .purchased(let transaction, let signedTransaction):
                    let parameters = Self.purchaseParameters(transaction: transaction,
                                                             signedTransaction: signedTransaction)
                    Self.log(parameters, plan: option.plan)
                    verifyAndActivate(parameters: parameters, restored: false)
                case .pending:
                    isPurchasing = false
                    events.send(.pending)
                case .cancelled:
                    isPurchasing = false
                }
            } catch {
                isPurchasing = false
                events.send(.failed(error.localizedDescription))
            }
        }
    }

    func restore() {
        guard !isPurchasing else { return }
        isPurchasing = true
        isRestoring = true
        Task { @MainActor in
            do {
                guard let restored = try await StoreManager.shared.restorePurchases() else {
                    resetProgress()
                    events.send(.failed("We couldn't find an active subscription for this Apple ID."))
                    return
                }
                let parameters = Self.purchaseParameters(transaction: restored.transaction,
                                                         signedTransaction: restored.signedTransaction)
                let plan = options.first { $0.plan.appleProductID == restored.transaction.productID }?.plan
                Self.log(parameters, plan: plan)
                verifyAndActivate(parameters: parameters, restored: true)
            } catch {
                resetProgress()
                events.send(.failed(error.localizedDescription))
            }
        }
    }

    private func resetProgress() {
        isPurchasing = false
        isRestoring = false
    }

    /// Sends the App Store JWS to the backend, which verifies with Apple and activates Premium once per transaction.
    private func verifyAndActivate(parameters: [String: Any], restored: Bool) {
        sessionManager.verifySubscriptionPurchase(parameters: parameters)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] response in
                guard let self else { return }
                self.resetProgress()
                guard response.isSuccessful else {
                    self.events.send(.failed("Your purchase went through but we couldn't activate it yet. Tap Restore Purchases to try again."))
                    return
                }
                self.setSubscribed(response.data?.isActive ?? true)
                if let balance = response.data?.walletBalance {
                    CoinWallet.shared.update(balance)
                } else {
                    CoinWallet.shared.refresh()
                }
                // Refresh profile + membership card so Premium details stay in sync with the server.
                self.sessionManager.myProfile().subscribe().disposed(by: self.disposeBag)
                SubscriptionMembershipStore.shared.refresh()
                let message = response.message.isEmpty
                    ? (restored ? "Your Premium membership has been restored." : "Welcome to Flirttime Premium!")
                    : response.message
                self.events.send(restored ? .restored(message) : .purchased(message))
            }, onFailure: { [weak self] error in
                guard let self else { return }
                self.resetProgress()
                // App Store already charged; StoreKit keeps the entitlement so Restore can retry.
                let message = parseError(error)
                    ?? "Your purchase went through but we couldn't activate it yet. Tap Restore Purchases to try again."
                self.events.send(.failed(message))
            })
            .disposed(by: disposeBag)
    }

    /// Body for `POST /api/v1/subscriptions/purchase/verify`. The server verifies
    /// `signedTransactionInfo` with Apple, then activates Premium once per `transactionId`.
    static func purchaseParameters(transaction: Transaction, signedTransaction: String) -> [String: Any] {
        [
            "platform": "ios",
            "productId": transaction.productID,
            "transactionId": String(transaction.id),
            "signedTransactionInfo": signedTransaction
        ]
    }

    private static func log(_ parameters: [String: Any], plan: SubscriptionPlanData?) {
        let body = (try? JSONSerialization.data(withJSONObject: parameters, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\(parameters)"
        AppLogger.debug("""

        ===== SUBSCRIPTION PURCHASE =====
        Plan: \(plan?.name ?? "-") (id \(plan?.id ?? 0))
        Backend request body:
        \(body)
        =================================
        """)
    }

    // MARK: - Status

    func refreshStatus() {
        PremiumViewModel.refreshMembership { [weak self] isActive in
            self?.isSubscribed = isActive
        }
    }

    private func setSubscribed(_ value: Bool) {
        UserDataManager.shared.isUserSubscriptionDone = value
        isSubscribed = value
    }

    /// Membership UI uses the server `isSubscribed` flag synced from profile / me.
    static func refreshMembership(completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.main.async {
            let isActive = UserDataManager.shared.isUserSubscriptionDone == true
            completion?(isActive)
        }
    }

    /// Verifies a deferred subscription (Ask to Buy / renewal) that arrived outside the purchase sheet.
    static func verifyDeferred(transaction: Transaction, signedTransaction: String) {
        let parameters = purchaseParameters(transaction: transaction, signedTransaction: signedTransaction)
        log(parameters, plan: SubscriptionPlanStore.shared.options
            .first { $0.plan.appleProductID == transaction.productID }?.plan)
        let sessionManager = Container.appContainer.resolve(AppSessionManager.self)!
        sessionManager.verifySubscriptionPurchase(parameters: parameters)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { response in
                guard response.isSuccessful else { return }
                UserDataManager.shared.isUserSubscriptionDone = response.data?.isActive ?? true
                if let balance = response.data?.walletBalance {
                    CoinWallet.shared.update(balance)
                }
            }, onFailure: { error in
                AppLogger.debug("[Premium] Deferred verify failed: \(parseError(error) ?? error.localizedDescription)")
            })
            .disposed(by: deferredDisposeBag)
    }

    private static let deferredDisposeBag = DisposeBag()

    static func format(_ amount: Decimal, currency: String?) -> String {
        amount.formatted(.currency(code: currency ?? "INR").precision(.fractionLength(0...2)))
    }
}
