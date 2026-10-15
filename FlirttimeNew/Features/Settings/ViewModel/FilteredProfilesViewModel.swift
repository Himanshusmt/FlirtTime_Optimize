//
//  FilteredProfilesViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

/// Blocked & reported screen: `GET users/blocked`, `GET users/reports` and unblock.
final class FilteredProfilesViewModel {

    @Published private(set) var blocked: [FilteredProfile] = []
    @Published private(set) var reported: [FilteredProfile] = []
    @Published private(set) var blockedTotal: Int?
    @Published private(set) var reportedTotal: Int?
    @Published private(set) var errorMessage: String?
    /// Lists whose first page has come back (or failed).
    @Published private(set) var loadedKinds: Set<FilteredProfileKind> = []

    private let pageSize = 20
    private var nextPage: [FilteredProfileKind: Int] = [:]
    private var hasMore: [FilteredProfileKind: Bool] = [:]
    private var loading: Set<FilteredProfileKind> = []
    /// Bumped on every first-page load so a slower, older response can't overwrite a newer one.
    private var generation: [FilteredProfileKind: Int] = [:]

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    func load() {
        fetch(.blocked, page: 1)
        fetch(.reported, page: 1)
    }

    func loadMore(_ kind: FilteredProfileKind) {
        guard hasMore[kind] == true, !loading.contains(kind), let page = nextPage[kind] else { return }
        fetch(kind, page: page)
    }

    func profiles(for kind: FilteredProfileKind) -> [FilteredProfile] {
        kind == .blocked ? blocked : reported
    }

    func count(for kind: FilteredProfileKind) -> Int {
        let total = kind == .blocked ? blockedTotal : reportedTotal
        return total ?? profiles(for: kind).count
    }

    /// Removes the row locally first, and puts it back if the request fails.
    func unblock(_ profile: FilteredProfile, completion: @escaping (Bool) -> Void) {
        guard let userId = profile.userId, let index = blocked.firstIndex(where: { $0.id == profile.id }) else { return }
        let previousTotal = blockedTotal
        blockedTotal = previousTotal.map { max(0, $0 - 1) }
        blocked.remove(at: index)
        sessionManager.unblockUser(userId: userId)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: {
                BlockedUsersManager.shared.unblockUser(id: userId)
                completion(true)
            }, onFailure: { [weak self] error in
                guard let self else { return }
                self.blockedTotal = previousTotal
                self.blocked.insert(profile, at: min(index, self.blocked.count))
                self.errorMessage = parseError(error) ?? "Unable to unblock \(profile.name)"
                completion(false)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Private

    private func fetch(_ kind: FilteredProfileKind, page: Int) {
        let isFirstPage = page == 1
        let current = (generation[kind] ?? 0) + (isFirstPage ? 1 : 0)
        generation[kind] = current
        loading.insert(kind)

        let request: Single<([FilteredProfile], ListPagination?)>
        switch kind {
        case .blocked:
            request = sessionManager.blockedUsers(page: page, limit: pageSize)
                .map { ($0.blockedUsers.map(\.profile), $0.pagination) }
        case .reported:
            request = sessionManager.myReports(page: page, limit: pageSize)
                .map { ($0.reports.map(\.profile), $0.pagination) }
        }

        request
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] items, pagination in
                guard let self, self.generation[kind] == current else { return }
                self.loading.remove(kind)
                self.nextPage[kind] = (pagination?.page ?? page) + 1
                self.hasMore[kind] = pagination?.hasMore ?? false
                self.errorMessage = nil
                let existing = isFirstPage ? [] : self.profiles(for: kind)
                let knownIds = Set(existing.map(\.id))
                let merged = existing + items.filter { !knownIds.contains($0.id) }
                switch kind {
                case .blocked:
                    self.blockedTotal = pagination?.total
                    self.blocked = merged
                case .reported:
                    self.reportedTotal = pagination?.total
                    self.reported = merged
                }
                self.loadedKinds.insert(kind)
            }, onFailure: { [weak self] error in
                guard let self, self.generation[kind] == current else { return }
                self.loading.remove(kind)
                self.loadedKinds.insert(kind)
                self.errorMessage = parseError(error) ?? "Unable to load this list"
            })
            .disposed(by: disposeBag)
    }
}
