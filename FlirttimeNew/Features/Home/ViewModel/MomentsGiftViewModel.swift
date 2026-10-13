//
//  MomentsGiftViewModel.swift
//  FlirttimeNew
//

import Foundation

// TODO: replace MockMomentsStore with GET gifts/, POST vibes/{id}/gifts { giftIds } and
// GET vibes/{id}/gifts requests.
final class MomentsGiftViewModel {

    let vibeId: String

    private(set) var gifts: [MomentsGift] = []
    private(set) var coinBalance = 0
    private(set) var selectedGiftIds: [Int] = []
    private(set) var isSending = false

    private(set) var receivedGifts: [MomentsReceivedGift] = []
    private(set) var totalReceivedCoins = 0

    private let store = MockMomentsStore.shared

    init(vibeId: String) {
        self.vibeId = vibeId
    }

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    var selectedAmount: Int {
        gifts.filter { selectedGiftIds.contains($0.id) }.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    var canAffordSelection: Bool {
        selectedAmount <= coinBalance
    }

    func isSelected(_ gift: MomentsGift) -> Bool {
        selectedGiftIds.contains(gift.id)
    }

    func toggleSelection(_ gift: MomentsGift) {
        if let index = selectedGiftIds.firstIndex(of: gift.id) {
            selectedGiftIds.remove(at: index)
        } else {
            selectedGiftIds.append(gift.id)
        }
    }

    // MARK: - Send gifts

    func loadCatalog(completion: @escaping (Result<Void, MomentsError>) -> Void) {
        respond { [weak self] in
            guard let self else { return }
            let response = self.store.giftCatalog()
            guard response.success == true, let data = response.data else {
                completion(.failure(MomentsError(message: "Unable to load gifts")))
                return
            }
            self.gifts = data.gifts ?? []
            self.coinBalance = data.coinBalance ?? 0
            completion(.success(()))
        }
    }

    /// On success returns how many gifts were sent so the feed can bump the moment's gift count.
    func sendSelectedGifts(completion: @escaping (Result<Int, MomentsError>) -> Void) {
        guard !selectedGiftIds.isEmpty, !isSending else { return }
        guard canAffordSelection else {
            completion(.failure(MomentsError(message: "You don't have enough coins for these gifts")))
            return
        }
        isSending = true
        let giftIds = selectedGiftIds
        respond { [weak self] in
            guard let self else { return }
            self.isSending = false
            let response = self.store.sendGifts(vibeId: self.vibeId, giftIds: giftIds)
            if let balance = response.data?.coinBalance {
                self.coinBalance = balance
            }
            guard response.success == true else {
                completion(.failure(MomentsError(message: response.message ?? "Unable to send gift")))
                return
            }
            self.selectedGiftIds.removeAll()
            completion(.success(giftIds.count))
        }
    }

    // MARK: - Received gifts (own moment)

    func loadReceivedGifts(completion: @escaping (Result<Void, MomentsError>) -> Void) {
        respond { [weak self] in
            guard let self else { return }
            let response = self.store.receivedGifts(vibeId: self.vibeId)
            guard response.success == true else {
                completion(.failure(MomentsError(message: "Unable to load gifts")))
                return
            }
            self.receivedGifts = response.gifts ?? []
            self.totalReceivedCoins = response.totalCoins ?? 0
            completion(.success(()))
        }
    }
}
