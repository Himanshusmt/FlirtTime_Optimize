//
//  CoinWallet.swift
//  FlirttimeNew
//
//  The signed-in user's coin balance, shared by the Discover header and the Coin Shop.
//

import Foundation
import Combine
import StoreKit

final class CoinWallet {

    static let shared = CoinWallet()

    @Published private(set) var balance: Int

    private var observer: NSObjectProtocol?

    private init() {
        balance = MockStore.shared.coinBalance
        observer = NotificationCenter.default.addObserver(forName: StoreManager.entitlementsDidChange, object: nil, queue: .main) { [weak self] note in
            guard let transaction = note.object as? Transaction, transaction.productType == .consumable else { return }
            self?.creditDeferred(transaction)
        }
    }

    // TODO: replace with the wallet balance from the user-details response.
    func refresh() {
        update(MockStore.shared.coinBalance)
    }

    func update(_ newBalance: Int) {
        if Thread.isMainThread {
            balance = newBalance
        } else {
            DispatchQueue.main.async { self.balance = newBalance }
        }
    }

    /// Coin packs approved after the purchase sheet closed (Ask to Buy, interrupted purchases).
    private func creditDeferred(_ transaction: Transaction) {
        guard let packs = MockDataStore.shared.decode(CoinsModel.self, from: MockStore.shared.coinPackagesJSON())?.data,
              let pack = packs.first(where: { $0.storeProductID == transaction.productID }) else { return }
        let json = MockStore.shared.purchaseCoinsJSON(package: pack, transactionID: String(transaction.id))
        if let balance = MockDataStore.shared.decode(CoinPurchaseResponse.self, from: json)?.data?.balance {
            update(balance)
        }
    }
}
