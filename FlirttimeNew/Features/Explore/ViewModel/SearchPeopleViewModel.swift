//
//  SearchPeopleViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

/// Search People screen: `GET users/search` by name or city, paged.
final class SearchPeopleViewModel {

    @Published private(set) var people: [UserSearchResult] = []
    /// The query `people` belong to; empty until a search comes back.
    @Published private(set) var query = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let pageSize = 20
    private let debounceInterval: TimeInterval = 0.35
    private var nextPage = 1
    private var hasMore = false
    private var pendingSearch: DispatchWorkItem?
    private var searchRequest: Disposable?

    private let sessionManager: AppSessionManager

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    deinit {
        pendingSearch?.cancel()
        searchRequest?.dispose()
    }

    /// Searches for `text` once typing pauses; an empty text clears the results.
    func search(_ text: String) {
        pendingSearch?.cancel()
        searchRequest?.dispose()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hasMore = false
            errorMessage = nil
            isLoading = false
            query = ""
            people = []
            return
        }
        isLoading = true
        let work = DispatchWorkItem { [weak self] in self?.fetch(trimmed, page: 1) }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    func loadMoreIfNeeded() {
        guard hasMore, !isLoading, !query.isEmpty else { return }
        fetch(query, page: nextPage)
    }

    // MARK: - Private

    private func fetch(_ text: String, page: Int) {
        searchRequest?.dispose()
        isLoading = true
        searchRequest = sessionManager.searchUsers(query: text, page: page, limit: pageSize)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] result in
                guard let self else { return }
                let existing = page == 1 ? [] : self.people
                let knownIDs = Set(existing.compactMap(\.userId))
                let found = result.users.filter { user in
                    guard let userId = user.userId, !userId.isEmpty else { return false }
                    return !knownIDs.contains(userId)
                }
                self.nextPage = (result.page ?? page) + 1
                self.hasMore = result.hasMore ?? (result.users.count >= self.pageSize)
                self.errorMessage = nil
                self.isLoading = false
                self.query = text
                self.people = existing + found
            }, onFailure: { [weak self] error in
                guard let self else { return }
                self.hasMore = false
                self.errorMessage = parseError(error) ?? "Couldn't search right now"
                self.isLoading = false
                if page == 1 {
                    self.query = text
                    self.people = []
                }
            })
    }
}
