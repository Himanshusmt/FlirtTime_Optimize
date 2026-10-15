//
//  NotificationViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 23/05/24.
//

import Combine
import Foundation
import RxSwift
import Swinject

/// Notifications screen: the server's Today / Yesterday / Earlier sections, read state and deletion.
final class NotificationViewModel {

    @Published private(set) var sections: [NotificationSection]?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    var hasUnread: Bool {
        sections?.contains { $0.items.contains { !$0.isRead } } ?? false
    }

    private let pageSize = 20
    private var nextCursor: String?
    private var hasMore = false
    /// Bumped on every first-page load so a slower, older response can't overwrite a newer one.
    private var generation = 0
    private var didAutoMarkRead = false

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    func load() {
        generation += 1
        nextCursor = nil
        fetch(cursor: nil, generation: generation)
    }

    func loadMore() {
        guard hasMore, !isLoading, let cursor = nextCursor else { return }
        fetch(cursor: cursor, generation: generation)
    }

    /// Marks read locally first, and reverts if the request fails.
    func markRead(id: String) {
        guard let item = item(id: id), !item.isRead else { return }
        setRead(true, ids: [id])
        sessionManager.markNotificationRead(id: id)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: {
                NotificationBadgeStore.shared.refresh()
            }, onFailure: { [weak self] _ in
                self?.setRead(false, ids: [id])
            })
            .disposed(by: disposeBag)
    }

    func markAllRead() {
        let unreadIds = (sections ?? []).flatMap(\.items).filter { !$0.isRead }.map(\.id)
        guard !unreadIds.isEmpty else { return }
        setRead(true, ids: Set(unreadIds))
        NotificationBadgeStore.shared.set(unread: 0)
        sessionManager.markAllNotificationsRead()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: {
                NotificationBadgeStore.shared.refresh()
            }, onFailure: { [weak self] error in
                self?.setRead(false, ids: Set(unreadIds))
                self?.errorMessage = parseError(error) ?? "Unable to mark notifications as read"
                NotificationBadgeStore.shared.refresh()
            })
            .disposed(by: disposeBag)
    }

    /// Removes the row locally first, and puts it back if the request fails.
    func delete(id: String) {
        guard var current = sections else { return }
        let snapshot = current
        for index in current.indices {
            current[index].items.removeAll { $0.id == id }
        }
        sections = current.filter { !$0.items.isEmpty }
        sessionManager.deleteNotification(id: id)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: {
                NotificationBadgeStore.shared.refresh()
            }, onFailure: { [weak self] error in
                self?.sections = snapshot
                self?.errorMessage = parseError(error) ?? "Unable to delete notification"
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Private

    private func fetch(cursor: String?, generation current: Int) {
        let isFirstPage = cursor == nil
        isLoading = true
        sessionManager.notifications(limit: pageSize, cursor: cursor)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] feed in
                guard let self, self.generation == current else { return }
                self.isLoading = false
                self.nextCursor = feed.nextCursor
                self.hasMore = feed.hasMore && feed.nextCursor != nil
                self.errorMessage = nil
                feed.sections.flatMap(\.items).forEach { ImageLoader.shared.prefetch(path: $0.image) }
                self.sections = isFirstPage ? feed.sections : Self.merge(self.sections ?? [], with: feed.sections)
                if isFirstPage {
                    self.autoMarkReadIfNeeded(feed)
                }
            }, onFailure: { [weak self] error in
                guard let self, self.generation == current else { return }
                self.isLoading = false
                self.errorMessage = parseError(error) ?? "Unable to load notifications"
            })
            .disposed(by: disposeBag)
    }

    /// Opening the screen marks everything read on the server, but rows keep their unread look until the next visit.
    private func autoMarkReadIfNeeded(_ feed: NotificationFeed) {
        guard !didAutoMarkRead, feed.sections.contains(where: { $0.items.contains { !$0.isRead } }) else { return }
        didAutoMarkRead = true
        NotificationBadgeStore.shared.set(unread: 0)
        sessionManager.markAllNotificationsRead()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: {
                NotificationBadgeStore.shared.set(unread: 0)
            }, onFailure: { _ in
                NotificationBadgeStore.shared.refresh()
            })
            .disposed(by: disposeBag)
    }

    private static func merge(_ existing: [NotificationSection], with page: [NotificationSection]) -> [NotificationSection] {
        var merged = existing
        let knownIds = Set(existing.flatMap(\.items).map(\.id))
        for section in page {
            let fresh = section.items.filter { !knownIds.contains($0.id) }
            guard !fresh.isEmpty else { continue }
            if let index = merged.firstIndex(where: { $0.title == section.title }) {
                merged[index].items += fresh
            } else {
                merged.append(NotificationSection(title: section.title, items: fresh))
            }
        }
        return merged
    }

    private func item(id: String) -> AppNotification? {
        sections?.lazy.flatMap(\.items).first { $0.id == id }
    }

    private func setRead(_ isRead: Bool, ids: Set<String>) {
        guard var current = sections else { return }
        for sectionIndex in current.indices {
            for row in current[sectionIndex].items.indices where ids.contains(current[sectionIndex].items[row].id) {
                current[sectionIndex].items[row].isRead = isRead
            }
        }
        sections = current
    }
}
