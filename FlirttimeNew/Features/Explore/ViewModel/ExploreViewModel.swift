//
//  ExploreViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 21/05/24.
//
import Combine
import Foundation
import RxSwift
import Swinject

/// Likes, You Liked, Matches and Compliments tabs (`GET interactions?type=`) and their badge counts.
final class ExploreViewModel {

    private(set) var items: [ExploreTab: [InteractionCard]] = [:]
    private(set) var errors: [ExploreTab: String] = [:]
    private(set) var lockedTabs: [ExploreTab: Bool] = [:]
    @Published private(set) var counts: InteractionCounts?
    /// Fires on the main queue when a tab's cards change or its request fails.
    let tabDidUpdate = PassthroughSubject<ExploreTab, Never>()

    private let pageSize = 20
    private var nextCursor: [ExploreTab: String] = [:]
    private var hasMore: [ExploreTab: Bool] = [:]
    private var loading: Set<ExploreTab> = []
    /// Bumped on every first-page load so a slower, older response can't overwrite a newer one.
    private var generation: [ExploreTab: Int] = [:]

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    func cards(for tab: ExploreTab) -> [InteractionCard] {
        items[tab] ?? []
    }

    func isLocked(_ tab: ExploreTab) -> Bool {
        lockedTabs[tab] ?? FreeTierLimitsStore.shared.isTabLocked(tab)
    }

    func load(_ tab: ExploreTab) {
        nextCursor[tab] = nil
        fetch(tab, cursor: nil)
    }

    func loadMore(_ tab: ExploreTab) {
        guard hasMore[tab] == true, !loading.contains(tab), let cursor = nextCursor[tab] else { return }
        fetch(tab, cursor: cursor)
    }

    func loadCounts() {
        sessionManager.interactionCounts()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] counts in
                self?.counts = counts
            })
            .disposed(by: disposeBag)
    }

    /// Marks a received compliment read locally first, and reverts if the request fails.
    func markRead(_ card: InteractionCard, in tab: ExploreTab) {
        guard let id = card.id, card.isRead != true else { return }
        setRead(true, id: id, in: tab)
        sessionManager.markInteractionRead(interactionId: id)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                self?.loadCounts()
            }, onFailure: { [weak self] _ in
                self?.setRead(false, id: id, in: tab)
            })
            .disposed(by: disposeBag)
    }

    /// Sends like / nope / super_like from a Likes tab profile.
    func act(_ action: String, on userId: String, completion: @escaping () -> Void) {
        sessionManager.discoveryAction(targetUserId: userId, action: action)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { _ in completion() }, onFailure: { _ in completion() })
            .disposed(by: disposeBag)
    }

    private func fetch(_ tab: ExploreTab, cursor: String?) {
        let isFirstPage = cursor == nil
        let current = (generation[tab] ?? 0) + (isFirstPage ? 1 : 0)
        generation[tab] = current
        loading.insert(tab)
        sessionManager.interactions(type: Self.apiType(for: tab), limit: pageSize, cursor: cursor)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] page in
                guard let self, self.generation[tab] == current else { return }
                self.loading.remove(tab)
                self.nextCursor[tab] = page.nextCursor
                self.hasMore[tab] = page.hasMore && page.nextCursor != nil
                self.errors[tab] = nil
                if let locked = page.isLocked {
                    self.lockedTabs[tab] = locked
                }
                if isFirstPage {
                    self.items[tab] = page.items
                } else {
                    let existing = Set(self.cards(for: tab).compactMap(\.id))
                    self.items[tab] = self.cards(for: tab) + page.items.filter { $0.id.map { !existing.contains($0) } ?? true }
                }
                self.tabDidUpdate.send(tab)
            }, onFailure: { [weak self] error in
                guard let self, self.generation[tab] == current else { return }
                self.loading.remove(tab)
                self.errors[tab] = parseError(error) ?? "Unable to load \(tab.title.lowercased())"
                self.tabDidUpdate.send(tab)
            })
            .disposed(by: disposeBag)
    }

    private func setRead(_ isRead: Bool, id: String, in tab: ExploreTab) {
        guard var list = items[tab], let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].isRead = isRead
        items[tab] = list
        tabDidUpdate.send(tab)
    }

    private static func apiType(for tab: ExploreTab) -> String {
        switch tab {
        case .likes: return "likes"
        case .youLiked: return "you_liked"
        case .matches: return "matches"
        case .compliments: return "compliments"
        }
    }
}
