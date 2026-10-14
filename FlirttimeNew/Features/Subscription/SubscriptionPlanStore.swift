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

    private init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
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
