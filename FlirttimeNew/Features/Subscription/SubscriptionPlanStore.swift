//
//  SubscriptionPlanStore.swift
//  FlirttimeNew
//
//  Premium plans from `subscriptions`, paired with their App Store products. Preloaded at launch
//  so the Premium screen opens with plans and prices ready.
//

import Foundation
import Combine
import RxSwift
import StoreKit
import Swinject

final class SubscriptionPlanStore {

    static let shared = SubscriptionPlanStore()

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Every active plan from the API in `sort_order`; `product` is nil when the App Store has no match.
    @Published private(set) var options: [PremiumViewModel.PlanOption] = []

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()
    private var entitlementObserver: NSObjectProtocol?

    private init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
        entitlementObserver = NotificationCenter.default.addObserver(
            forName: StoreManager.entitlementsDidChange,
            object: nil,
            queue: .main
        ) { note in
            guard let transaction = note.object as? Transaction,
                  transaction.productType == .autoRenewable else { return }
            guard let signed = note.userInfo?[StoreManager.signedTransactionUserInfoKey] as? String,
                  !signed.isEmpty else {
                AppLogger.debug("[Premium] Deferred subscription for \(transaction.productID) has no signed transaction; skipping verify")
                PremiumViewModel.refreshMembership()
                return
            }
            PremiumViewModel.verifyDeferred(transaction: transaction, signedTransaction: signed)
        }
    }

    /// Must be called on the main queue. Calls made while a load is in flight are ignored;
    /// observe `state` to know when it finishes.
    func preload() {
        guard state != .loading else { return }
        state = .loading
        sessionManager.subscriptionPlans()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] response in
                guard let self else { return }
                guard response.status == true else {
                    self.state = .failed(response.message ?? "Couldn't load plans right now")
                    return
                }
                let plans = (response.data ?? [])
                    .filter { $0.isActive != false }
                    .sorted { ($0.sortOrder ?? .max) < ($1.sortOrder ?? .max) }
                Task { @MainActor in
                    await self.attachProducts(to: plans)
                }
            }, onFailure: { [weak self] error in
                self?.state = .failed(parseError(error) ?? "Couldn't load plans right now")
            })
            .disposed(by: disposeBag)
    }

    /// Reloads only when nothing has been loaded yet or the last load failed.
    func preloadIfNeeded() {
        switch state {
        case .idle, .failed: preload()
        case .loading, .loaded: break
        }
    }

    @MainActor
    private func attachProducts(to plans: [SubscriptionPlanData]) async {
        let ids = plans.compactMap(\.appleProductID)
        let products = (try? await StoreManager.shared.products(for: ids)) ?? []
        options = plans.map { plan in
            PremiumViewModel.PlanOption(plan: plan, product: products.first { $0.id == plan.appleProductID })
        }
        state = options.isEmpty ? .failed("No plans available right now") : .loaded
    }
}

/// Cached `GET /api/v1/subscriptions/my` for Profile and Coin Shop membership cards.
final class SubscriptionMembershipStore {

    static let shared = SubscriptionMembershipStore()

    @Published private(set) var membership: MySubscriptionData?
    @Published private(set) var isLoading = false

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    private init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    /// Fetches the latest membership. Safe to call from `viewWillAppear`.
    func refresh() {
        isLoading = true
        sessionManager.mySubscription()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] membership in
                guard let self else { return }
                self.membership = membership
                self.isLoading = false
                if let membership {
                    UserDataManager.shared.applySubscriptionStatus(membership.isCurrentlyActive)
                }
            }, onFailure: { [weak self] error in
                AppLogger.debug("[Premium] my subscription failed: \(parseError(error) ?? error.localizedDescription)")
                self?.isLoading = false
            })
            .disposed(by: disposeBag)
    }
}
