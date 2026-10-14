//
//  CoinsViewModel.swift
//  FlirttimeNew
//

import Foundation
import Combine
import StoreKit

// TODO: replace the MockStore response with the coin purchase request.
final class CoinsViewModel {

    struct PackOption: Hashable {
        let pack: CoinData
        let product: Product?

        /// Localized App Store price. The server amount is only used when that product is missing.
        var displayPrice: String {
            if let product { return product.displayPrice }
            return PremiumViewModel.format(Decimal(string: pack.price ?? "") ?? 0, currency: pack.currency)
        }

        var isPopular: Bool { pack.tag == "popular" }
        var isBestValue: Bool { pack.tag == "best_value" }

        static func == (lhs: PackOption, rhs: PackOption) -> Bool { lhs.pack == rhs.pack && lhs.product?.id == rhs.product?.id }
        func hash(into hasher: inout Hasher) { hasher.combine(pack) }
    }

    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum PurchaseEvent {
        case purchased(coins: Int, message: String)
        case pending
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var options: [PackOption] = []
    /// The pack currently being bought, so only its card shows progress.
    @Published private(set) var purchasingPackID: Int?
    let events = PassthroughSubject<PurchaseEvent, Never>()

    private let packStore = CoinPackStore.shared

    init() {
        packStore.$options.assign(to: &$options)
        packStore.$state
            .map { state -> State in
                switch state {
                case .idle, .loading: return .loading
                case .loaded: return .loaded
                case .failed(let message): return .failed(message)
                }
            }
            .assign(to: &$state)
    }

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    /// Uses the packs preloaded at launch; refetches only if that load failed or hasn't run.
    func load() {
        CoinWallet.shared.refresh()
        if packStore.options.isEmpty {
            packStore.preload()
        }
    }

    func purchase(_ option: PackOption) {
        guard purchasingPackID == nil else { return }
        guard let product = option.product else {
            events.send(.failed(StoreError.productUnavailable.localizedDescription))
            return
        }
        purchasingPackID = option.pack.id
        Task { @MainActor in
            do {
                switch try await StoreManager.shared.purchase(product) {
                case .purchased(let transaction, let signedTransaction):
                    let parameters = Self.purchaseParameters(pack: option.pack, product: product,
                                                             transaction: transaction, signedTransaction: signedTransaction)
                    Self.log(parameters, pack: option.pack)
                    credit(option.pack, transactionID: String(transaction.id))
                case .pending:
                    purchasingPackID = nil
                    events.send(.pending)
                case .cancelled:
                    purchasingPackID = nil
                }
            } catch {
                purchasingPackID = nil
                events.send(.failed(error.localizedDescription))
            }
        }
    }

    private func credit(_ pack: CoinData, transactionID: String) {
        respond { [weak self] in
            guard let self else { return }
            self.purchasingPackID = nil
            let json = MockStore.shared.purchaseCoinsJSON(package: pack, transactionID: transactionID)
            guard let response = MockDataStore.shared.decode(CoinPurchaseResponse.self, from: json), response.status else {
                self.events.send(.failed("Your purchase went through but the coins haven't arrived yet. They'll be added shortly."))
                return
            }
            if let balance = response.data?.balance {
                CoinWallet.shared.update(balance)
            }
            self.events.send(.purchased(coins: pack.totalCoins, message: response.message))
        }
    }

    /// Body for the backend's coin purchase verification. The server should verify
    /// `signed_transaction` with Apple, then credit `package_id` once per `transaction_id`.
    static func purchaseParameters(pack: CoinData, product: Product,
                                   transaction: Transaction, signedTransaction: String) -> [String: Any] {
        [
            "platform": "ios",
            "package_id": pack.id ?? 0,
            "product_id": transaction.productID,
            "transaction_id": String(transaction.id),
            "original_transaction_id": String(transaction.originalID),
            "purchase_date": ISO8601DateFormatter().string(from: transaction.purchaseDate),
            "price": NSDecimalNumber(decimal: product.price).stringValue,
            "currency": product.priceFormatStyle.currencyCode,
            "environment": transaction.environment.rawValue,
            "signed_transaction": signedTransaction
        ]
    }

    private static func log(_ parameters: [String: Any], pack: CoinData) {
        let body = (try? JSONSerialization.data(withJSONObject: parameters, options: [.prettyPrinted, .sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\(parameters)"
        AppLogger.debug("""

        ===== COIN PURCHASE =====
        Package: \(pack.name ?? "-") (id \(pack.id ?? 0))
        Coins: \(pack.coins ?? 0) + \(pack.bonusCoins ?? 0) bonus = \(pack.totalCoins)
        Backend request body:
        \(body)
        =========================
        """)
    }
}
