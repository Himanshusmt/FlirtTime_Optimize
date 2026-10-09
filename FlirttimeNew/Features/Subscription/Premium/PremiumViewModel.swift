//
//  PremiumViewModel.swift
//  FlirttimeNew
//

import Foundation
import Combine
import StoreKit

// TODO: replace the MockStore responses with the subscriptions / subscription/create / subscription/check requests.
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

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    // MARK: - Loading

    func load() {
        state = .loading
        respond { [weak self] in
            guard let self else { return }
            guard let response = MockDataStore.shared.decode(SubscriptionModel.self, from: MockStore.shared.subscriptionPlansJSON()),
                  response.status == true else {
                self.state = .failed("Couldn't load plans right now")
                return
            }
            let plans = (response.data ?? [])
                .filter { $0.isActive != false }
                .sorted { ($0.sortOrder ?? .max) < ($1.sortOrder ?? .max) }
            Task { await self.attachProducts(to: plans) }
        }
        refreshStatus()
    }

    @MainActor
    private func attachProducts(to plans: [SubscriptionPlanData]) async {
        let ids = plans.compactMap(\.appleProductID)
        let products = (try? await StoreManager.shared.products(for: ids)) ?? []
        options = plans.map { plan in
            PlanOption(plan: plan, product: products.first { $0.id == plan.appleProductID })
        }
        selectedIndex = options.firstIndex { $0.plan.isPopular == true } ?? 0
        state = options.isEmpty ? .failed("No plans available right now") : .loaded
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
                case .purchased(let transaction):
                    sendSubscription(for: option, transaction: transaction, restored: false)
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
                guard let transaction = try await StoreManager.shared.restorePurchases() else {
                    resetProgress()
                    events.send(.failed("We couldn't find an active subscription for this Apple ID."))
                    return
                }
                guard let option = options.first(where: { $0.plan.appleProductID == transaction.productID }) else {
                    resetProgress()
                    setSubscribed(true)
                    events.send(.restored("Your Premium membership has been restored."))
                    return
                }
                sendSubscription(for: option, transaction: transaction, restored: true)
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

    /// Records the App Store transaction on our server, which grants the membership and bonus coins.
    private func sendSubscription(for option: PlanOption, transaction: Transaction, restored: Bool) {
        let start = transaction.purchaseDate
        let end = transaction.expirationDate
            ?? Calendar.current.date(byAdding: .day, value: option.plan.durationDays ?? 30, to: start) ?? start
        let subscription = Subscription(
            title: option.title,
            description: "amount paid for \(option.plan.durationTitle)",
            productID: transaction.productID,
            transactionID: String(transaction.originalID),
            paidAmount: NSDecimalNumber(decimal: option.product?.price ?? Decimal(string: option.plan.price ?? "") ?? 0).doubleValue,
            currency: option.product?.priceFormatStyle.currencyCode ?? option.plan.currency ?? "",
            startDate: MockStore.dayFormatter.string(from: start),
            endDate: MockStore.dayFormatter.string(from: end),
            paymentGateway: "applepay")

        respond { [weak self] in
            guard let self else { return }
            self.resetProgress()
            let json = MockStore.shared.createSubscriptionJSON(subscription.parameters, plan: option.plan)
            guard let response = MockDataStore.shared.decode(SubscriptionResponse.self, from: json), response.status else {
                // The App Store charge succeeded; StoreKit keeps the entitlement so the next refresh recovers it.
                self.events.send(.failed("Your purchase went through but we couldn't activate it yet. Tap Restore Purchases to try again."))
                return
            }
            self.setSubscribed(true)
            CoinWallet.shared.refresh()
            self.events.send(restored ? .restored(response.message) : .purchased(response.message))
        }
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

    /// Membership is active when the server says so (any platform) or StoreKit holds a live entitlement.
    static func refreshMembership(completion: ((Bool) -> Void)? = nil) {
        Task { @MainActor in
            let storeKitActive = await StoreManager.shared.hasActiveSubscription()
            let check = MockDataStore.shared.decode(CheckSubscriptionResponse.self, from: MockStore.shared.checkSubscriptionJSON())
            let isActive = storeKitActive || check?.data?.isActive == true
            UserDataManager.shared.isUserSubscriptionDone = isActive
            completion?(isActive)
        }
    }

    static func format(_ amount: Decimal, currency: String?) -> String {
        amount.formatted(.currency(code: currency ?? "INR").precision(.fractionLength(0...2)))
    }
}
