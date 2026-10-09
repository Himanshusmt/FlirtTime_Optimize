//
//  CoinsViewModel.swift
//  FlirttimeNew
//

import Foundation
import Combine
import StoreKit

// TODO: replace the MockStore responses with the coin-packages and coin purchase requests.
final class CoinsViewModel {

    struct PackOption: Hashable {
        let pack: CoinData
        let product: Product?

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

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    func load() {
        state = .loading
        CoinWallet.shared.refresh()
        respond { [weak self] in
            guard let self else { return }
            guard let response = MockDataStore.shared.decode(CoinsModel.self, from: MockStore.shared.coinPackagesJSON()),
                  response.status == true else {
                self.state = .failed("Couldn't load coin packs right now")
                return
            }
            let packs = (response.data ?? [])
                .filter { $0.isActive != 0 }
                .sorted { ($0.sortOrder ?? .max) < ($1.sortOrder ?? .max) }
            Task { await self.attachProducts(to: packs) }
        }
    }

    @MainActor
    private func attachProducts(to packs: [CoinData]) async {
        let products = (try? await StoreManager.shared.products(for: packs.compactMap(\.storeProductID))) ?? []
        options = packs.map { pack in
            PackOption(pack: pack, product: products.first { $0.id == pack.storeProductID })
        }
        state = options.isEmpty ? .failed("No coin packs available right now") : .loaded
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
                case .purchased(let transaction):
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
}
