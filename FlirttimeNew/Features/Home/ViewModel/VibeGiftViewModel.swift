//
//  VibeGiftViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

final class VibeGiftViewModel {

    let vibeId: String
    private static let receivedPageSize = 20

    private(set) var gifts: [VibeGift] = []
    private(set) var coinBalance = 0
    /// Moment creator's name for the sheet title, when the API sends it.
    private(set) var recipientName: String?
    private(set) var selectedGiftIds: [Int] = []
    private(set) var isSending = false

    private(set) var receivedGifts: [VibeReceivedGift] = []
    private(set) var totalReceivedGifts = 0
    private(set) var totalReceivedCoins = 0
    private(set) var isLoadingReceived = false
    private var receivedPage = 0
    private var receivedTotalPages = 1

    var hasMoreReceivedGifts: Bool { receivedPage < receivedTotalPages }

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    init(vibeId: String,
         sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.vibeId = vibeId
        self.sessionManager = sessionManager
    }

    var selectedAmount: Int {
        gifts.filter { selectedGiftIds.contains($0.id) }.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    var canAffordSelection: Bool {
        selectedAmount <= coinBalance
    }

    func isSelected(_ gift: VibeGift) -> Bool {
        selectedGiftIds.contains(gift.id)
    }

    func toggleSelection(_ gift: VibeGift) {
        if let index = selectedGiftIds.firstIndex(of: gift.id) {
            selectedGiftIds.remove(at: index)
        } else {
            selectedGiftIds.append(gift.id)
        }
    }

    // MARK: - Send gifts

    func loadCatalog(completion: @escaping (Result<Void, VibeError>) -> Void) {
        sessionManager.momentGiftCatalog(momentId: vibeId)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] data in
                guard let self else { return }
                self.gifts = data.gifts.map(\.vibeGift)
                self.recipientName = data.recipientName
                if let balance = data.coinBalance {
                    self.coinBalance = balance
                    CoinWallet.shared.update(balance)
                }
                completion(self.gifts.isEmpty ? .failure(VibeError(message: "No gifts available right now")) : .success(()))
            }, onFailure: { error in
                completion(.failure(VibeError(message: parseError(error) ?? "Unable to load gifts")))
            })
            .disposed(by: disposeBag)
    }

    /// Sends each selected gift as its own request, in order; stops at the first failure.
    /// On success returns how many gifts were sent so the feed can bump the moment's gift count.
    func sendSelectedGifts(completion: @escaping (Result<Int, VibeError>) -> Void) {
        guard !selectedGiftIds.isEmpty, !isSending else { return }
        guard canAffordSelection else {
            completion(.failure(VibeError(message: "You don't have enough coins for these gifts")))
            return
        }
        let selected = gifts.filter { selectedGiftIds.contains($0.id) && $0.code != nil }
        guard !selected.isEmpty else { return }
        isSending = true

        var sentCount = 0
        var spent = 0
        var lastBalance: Int?
        let requests = selected.map { gift in
            sessionManager.sendMomentGift(momentId: vibeId, giftCode: gift.code ?? "")
                .asObservable()
                .do(onNext: { data in
                    sentCount += 1
                    spent += gift.amount ?? 0
                    if let balance = data?.coinBalance { lastBalance = balance }
                })
        }
        let startBalance = coinBalance

        Observable.concat(requests)
            .observe(on: MainScheduler.instance)
            .subscribe(onError: { [weak self] error in
                guard let self else { return }
                self.finishSending(sent: sentCount, balance: lastBalance ?? startBalance - spent)
                let message = parseError(error) ?? "Unable to send gift"
                completion(.failure(VibeError(message: sentCount > 0 ? "\(sentCount) sent. \(message)" : message)))
            }, onCompleted: { [weak self] in
                guard let self else { return }
                self.finishSending(sent: sentCount, balance: lastBalance ?? startBalance - spent)
                self.selectedGiftIds.removeAll()
                completion(.success(sentCount))
            })
            .disposed(by: disposeBag)
    }

    private func finishSending(sent: Int, balance: Int) {
        isSending = false
        guard sent > 0 else { return }
        coinBalance = max(0, balance)
        CoinWallet.shared.update(coinBalance)
    }

    // MARK: - Received gifts (own moment)

    func loadReceivedGifts(completion: @escaping (Result<Void, VibeError>) -> Void) {
        receivedPage = 0
        receivedTotalPages = 1
        fetchReceived(page: 1, completion: completion)
    }

    func loadMoreReceivedGifts(completion: @escaping (Result<Void, VibeError>) -> Void) {
        guard hasMoreReceivedGifts, !isLoadingReceived else { return }
        fetchReceived(page: receivedPage + 1, completion: completion)
    }

    private func fetchReceived(page: Int, completion: @escaping (Result<Void, VibeError>) -> Void) {
        isLoadingReceived = true
        sessionManager.momentReceivedGifts(momentId: vibeId, page: page, limit: Self.receivedPageSize)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] data in
                guard let self else { return }
                self.isLoadingReceived = false
                let items = data.gifts.map(\.vibeReceivedGift)
                self.receivedGifts = page == 1 ? items : self.receivedGifts + items
                self.receivedPage = page
                self.receivedTotalPages = data.totalPages ?? (items.count < Self.receivedPageSize ? page : page + 1)
                self.totalReceivedGifts = data.total ?? self.receivedGifts.count
                self.totalReceivedCoins = data.totalCoins ?? self.receivedGifts.reduce(0) { $0 + ($1.coinsUsed ?? 0) }
                completion(.success(()))
            }, onFailure: { [weak self] error in
                self?.isLoadingReceived = false
                completion(.failure(VibeError(message: parseError(error) ?? "Unable to load gifts")))
            })
            .disposed(by: disposeBag)
    }
}
