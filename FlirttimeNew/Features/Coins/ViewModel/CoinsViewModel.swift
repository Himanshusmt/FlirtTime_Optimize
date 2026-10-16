//
//  CoinsViewModel.swift
//  FlirttimeNew
//

import Foundation
import Combine
import RxSwift
import StoreKit
import Swinject

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
    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
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

    /// Uses the packs preloaded at launch; refetches only if that load failed or hasn't run.
    func load() {
        refreshBalance()
        if packStore.options.isEmpty {
            packStore.preload()
        }
    }

    /// Re-fetches wallet coins from the backend (Discover / Coin Shop appearance).
    func refreshBalance() {
        CoinWallet.shared.refresh()
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
                    let parameters = Self.purchaseParameters(pack: option.pack,
                                                             transaction: transaction,
                                                             signedTransaction: signedTransaction)
                    Self.log(parameters, pack: option.pack)
                    verifyAndCredit(pack: option.pack, parameters: parameters)
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

    /// Sends the App Store receipt to the backend, which verifies with Apple and credits once per transaction.
    private func verifyAndCredit(pack: CoinData, parameters: [String: Any]) {
        sessionManager.verifyCoinPurchase(parameters: parameters)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] response in
                guard let self else { return }
                self.purchasingPackID = nil
                guard response.isSuccessful else {
                    // Still pull wallet in case the credit landed but the envelope looked unsuccessful.
                    CoinWallet.shared.refresh()
                    self.events.send(.failed("Your purchase went through but the coins haven't arrived yet. They'll be added shortly."))
                    return
                }
                if let balance = response.data?.walletBalance {
                    CoinWallet.shared.update(balance)
                }
                // Always re-sync from wallet/balance so Discover + Coin Shop match the server.
                CoinWallet.shared.refresh()
                let coins = response.data?.coinsCredited ?? pack.totalCoins
                let message = response.message?.isEmpty == false
                    ? (response.message ?? "")
                    : "\(coins) coins added to your wallet"
                self.events.send(.purchased(coins: coins, message: message))
            }, onFailure: { [weak self] error in
                guard let self else { return }
                self.purchasingPackID = nil
                // App Store already charged; wallet refresh may still pick up a server-side credit.
                CoinWallet.shared.refresh()
                let message = parseError(error)
                    ?? "Your purchase went through but the coins haven't arrived yet. They'll be added shortly."
                self.events.send(.failed(message))
            })
            .disposed(by: disposeBag)
    }

    /// Body for `POST /api/v1/coins/purchase/verify`. The server verifies
    /// `signedTransactionInfo` with Apple, then credits `packageId` once per `transactionId`.
    static func purchaseParameters(pack: CoinData,
                                   transaction: Transaction,
                                   signedTransaction: String) -> [String: Any] {
        [
            "platform": "ios",
            "packageId": pack.id ?? 0,
            "productId": transaction.productID,
            "transactionId": String(transaction.id),
            "signedTransactionInfo": signedTransaction
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
