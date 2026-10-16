//
//  CoinWallet.swift
//  FlirttimeNew
//
//  The signed-in user's coin balance, shared by the Discover header and the Coin Shop.
//  Always sourced from `GET /api/v1/wallet/balance` (or purchase-verify `currentBalance`).
//

import Foundation
import Combine
import RxSwift
import StoreKit
import Swinject

final class CoinWallet {

    static let shared = CoinWallet()

    @Published private(set) var balance: Int

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()
    private let balanceRefresh = SerialDisposable()
    private var observer: NSObjectProtocol?

    private init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
        balance = 0
        balanceRefresh.disposed(by: disposeBag)
        observer = NotificationCenter.default.addObserver(forName: StoreManager.entitlementsDidChange, object: nil, queue: .main) { [weak self] note in
            guard let transaction = note.object as? Transaction, transaction.productType == .consumable else { return }
            let signed = note.userInfo?[StoreManager.signedTransactionUserInfoKey] as? String
            self?.creditDeferred(transaction, signedTransaction: signed)
        }
        // Pull the real balance as soon as the wallet is created (app launch while logged in).
        refresh()
    }

    /// Fetches `GET /api/v1/wallet/balance` and publishes `data.coins` to Discover / Coin Shop.
    func refresh() {
        guard sessionManager.isLoggedIn else {
            update(0)
            return
        }
        balanceRefresh.disposable = sessionManager.walletBalance()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] response in
                guard let self else { return }
                guard response.isSuccessful else {
                    AppLogger.debug("[Coins] Wallet balance not successful: \(response.message ?? "")")
                    return
                }
                guard let coins = response.data?.coins else {
                    AppLogger.debug("[Coins] Wallet balance response missing coins: \(response.message ?? "")")
                    return
                }
                self.update(coins)
            }, onFailure: { error in
                AppLogger.debug("[Coins] Wallet balance failed: \(parseError(error) ?? error.localizedDescription)")
            })
    }

    func update(_ newBalance: Int) {
        let value = max(0, newBalance)
        if Thread.isMainThread {
            // Always assign so UI rebinds even when the value is unchanged after a remount.
            balance = value
        } else {
            DispatchQueue.main.async { self.balance = value }
        }
    }

    /// Coin packs approved after the purchase sheet closed (Ask to Buy, interrupted purchases).
    private func creditDeferred(_ transaction: Transaction, signedTransaction: String?) {
        guard let pack = CoinPackStore.shared.pack(forProductID: transaction.productID) else { return }
        guard let signedTransaction, !signedTransaction.isEmpty else {
            AppLogger.debug("[Coins] Deferred purchase for \(transaction.productID) has no signed transaction; skipping verify")
            return
        }
        let parameters = CoinsViewModel.purchaseParameters(pack: pack,
                                                           transaction: transaction,
                                                           signedTransaction: signedTransaction)
        sessionManager.verifyCoinPurchase(parameters: parameters)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] response in
                guard let self, response.isSuccessful else { return }
                if let balance = response.data?.walletBalance {
                    self.update(balance)
                }
                // Authoritative sync from wallet endpoint.
                self.refresh()
            }, onFailure: { error in
                AppLogger.debug("[Coins] Deferred verify failed: \(parseError(error) ?? error.localizedDescription)")
            })
            .disposed(by: disposeBag)
    }
}
