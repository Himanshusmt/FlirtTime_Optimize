//
//  CoinPackStore.swift
//  FlirttimeNew
//
//  Coin packs from `coin-packages`, paired with their App Store products. Preloaded at launch
//  so the Coin Shop opens with prices ready. The shop lists only the packs the API returns;
//  each price is the matching App Store product's localized price.
//

import Foundation
import Combine
import RxSwift
import StoreKit
import Swinject

final class CoinPackStore {

    static let shared = CoinPackStore()

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Every active pack from the API in `sort_order`; `product` is nil when the App Store has no match.
    @Published private(set) var options: [CoinsViewModel.PackOption] = []

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    private init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    func pack(forProductID productID: String) -> CoinData? {
        options.first { $0.pack.storeProductID == productID }?.pack
    }

    /// Must be called on the main queue. Calls made while a load is in flight are ignored;
    /// observe `state` to know when it finishes.
    func preload() {
        guard state != .loading else { return }
        state = .loading
        sessionManager.coinPackages()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] response in
                guard let self else { return }
                guard response.status == true else {
                    self.state = .failed(response.message ?? "Couldn't load coin packs right now")
                    return
                }
                let packs = (response.data ?? [])
                    .filter { $0.isActive != false }
                    .sorted { ($0.sortOrder ?? .max) < ($1.sortOrder ?? .max) }
                Task { @MainActor in
                    await self.attachProducts(to: packs)
                }
            }, onFailure: { [weak self] error in
                self?.state = .failed(parseError(error) ?? "Couldn't load coin packs right now")
            })
            .disposed(by: disposeBag)
    }

    /// Looks up App Store products for the packs the API actually returned, so a shorter
    /// catalog (for example five packs) is what the shop shows.
    @MainActor
    private func attachProducts(to packs: [CoinData]) async {
        let ids = packs.compactMap(\.storeProductID)
        let products = (try? await StoreManager.shared.products(for: ids)) ?? []
        options = packs.map { pack in
            CoinsViewModel.PackOption(pack: pack, product: products.first { $0.id == pack.storeProductID })
        }
        state = options.isEmpty ? .failed("No coin packs available right now") : .loaded
    }
}
