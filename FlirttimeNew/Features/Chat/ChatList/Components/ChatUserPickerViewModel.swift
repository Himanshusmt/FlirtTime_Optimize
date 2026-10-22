//
//  ChatUserPickerViewModel.swift
//  FlirttimeNew
//

import Foundation
import SwiftUI
import Swinject
import RxSwift

struct SelectableUser: Identifiable, Hashable {
    let id: String
    let name: String
    let username: String
    let avatarURL: String?
}

@MainActor
final class ChatUserPickerViewModel: ObservableObject {
    @Published var users: [SelectableUser] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let sessionManager: SessionManager = Container.sharedContainer.require(SessionManager.self)

    private var currentPage = 1
    private let browsePageSize = 30
    private let searchPageSize = 20
    private var hasMorePages = true
    private var isFetchingData = false
    private var currentSearchText = ""
    private var searchDebounceTask: Task<Void, Never>?

    private var pageSize: Int {
        currentSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? browsePageSize
            : searchPageSize
    }

    private var allLoadedUsers: [SelectableUser] = []
    private var allLoadedUserIds: Set<String> = []

    private var hasEverLoaded = false

    private static var sharedCache: [SelectableUser] = []
    private static var sharedCacheIds: Set<String> = []

    // MARK: - Public API

    func load(search: String?) {
        if !Self.sharedCache.isEmpty {
            allLoadedUsers = Self.sharedCache
            allLoadedUserIds = Self.sharedCacheIds
            users = Self.sharedCache
            hasEverLoaded = true
            isLoading = false
            currentPage = 1
            hasMorePages = true
            isFetchingData = false
            currentSearchText = search ?? ""
            fetchSilent()
        } else if allLoadedUsers.isEmpty {
            fetchInitial(search: search)
        }
    }

    func reload(search: String?) {
        if !Self.sharedCache.isEmpty {
            allLoadedUsers = Self.sharedCache
            allLoadedUserIds = Self.sharedCacheIds
            users = Self.sharedCache
            hasEverLoaded = true
            isLoading = false
            // Refresh in background
            currentPage = 1
            hasMorePages = true
            isFetchingData = false
            currentSearchText = search ?? ""
            fetchSilent()
        } else {
            hasEverLoaded = false
            allLoadedUsers.removeAll()
            allLoadedUserIds.removeAll()
            users.removeAll()
            currentPage = 1
            hasMorePages = true
            isFetchingData = false
            currentSearchText = search ?? ""
            fetchInitial(search: search)
        }
    }

    func search(text: String) {
        currentSearchText = text

        // Instant local filter for responsive UX
        if !text.isEmpty {
            let q = text.lowercased()
            users = allLoadedUsers.filter {
                $0.name.lowercased().contains(q) || $0.username.lowercased().contains(q)
            }
        } else {
            users = allLoadedUsers
        }

        // Debounce server fetch to refine results silently
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self.currentPage = 1
            self.hasMorePages = true
            self.isFetchingData = false
            self.fetchSilent()
        }
    }

    func loadMoreIfNeeded(currentItem: SelectableUser?) {
        guard let currentItem = currentItem else { return }
        let thresholdIndex = users.index(users.endIndex, offsetBy: -5)
        if users.firstIndex(where: { $0.id == currentItem.id }) == thresholdIndex {
            guard !isFetchingData, hasMorePages else { return }
            fetchSilent()
        }
    }

    // MARK: - Fetching

    private func fetchInitial(search: String?) {
        currentSearchText = search ?? ""
        isLoading = true
        isFetchingData = true

        Task { [weak self] in
            guard let self = self else { return }
            await self.performFetch()
        }
    }

    private func fetchSilent() {
        guard !isFetchingData, hasMorePages else { return }
        isFetchingData = true

        Task { [weak self] in
            guard let self = self else { return }
            await self.performFetch()
        }
    }

    private func performFetch() async {
        do {
            let response = try await getGroupCandidatesAsync(
                search: currentSearchText,
                page: currentPage,
                limit: pageSize
            )

            let mapped: [SelectableUser] = response.users.compactMap { user in
                guard let userId = user.userId ?? user.id else { return nil }
                return SelectableUser(
                    id: userId,
                    name: user.fullName ?? user.userName ?? "",
                    username: user.userName ?? "",
                    avatarURL: user.profilePictureDetails?.filePath ?? user.profilePicture
                )
            }

            // Merge into master store (deduplicated)
            mergeIntoAllLoaded(mapped)

            // Update visible list
            if currentSearchText.isEmpty {
                // No active search — show full master list up to loaded pages
                users = allLoadedUsers
            } else {
                // Active search — show server results merged with local data
                let q = currentSearchText.lowercased()
                users = allLoadedUsers.filter {
                    $0.name.lowercased().contains(q) || $0.username.lowercased().contains(q)
                }
            }

            // Prefer totalResults when present; otherwise page-size heuristic
            if response.totalResults > 0 {
                hasMorePages = allLoadedUsers.count < response.totalResults
                    && response.users.count >= pageSize
            } else {
                hasMorePages = response.users.count >= pageSize
            }
            currentPage += 1
            errorMessage = nil

        } catch {
            errorMessage = error.localizedDescription
        }

        isFetchingData = false
        if !hasEverLoaded {
            hasEverLoaded = true
            isLoading = false
        }
    }

    private func mergeIntoAllLoaded(_ newUsers: [SelectableUser]) {
        for user in newUsers {
            if allLoadedUserIds.insert(user.id).inserted {
                allLoadedUsers.append(user)
            }
            if Self.sharedCacheIds.insert(user.id).inserted {
                Self.sharedCache.append(user)
            }
        }
    }

    // MARK: - Network

    private func getGroupCandidatesAsync(search: String, page: Int, limit: Int) async throws -> PaginatedUsersResponse {
        try await withCheckedThrowingContinuation { continuation in
            sessionManager.getGroupCandidates(search: search, page: page, limit: limit)
                .subscribe(onSuccess: { response in
                    continuation.resume(returning: response)
                }, onFailure: { error in
                    continuation.resume(throwing: error)
                })
        }
    }
}

// MARK: - Forward Recipients

@MainActor
final class ForwardRecipientPickerViewModel: ObservableObject {
    @Published var users: [SelectableUser] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let sessionManager: SessionManager = Container.sharedContainer.require(SessionManager.self)
    private let pageSize = ChatConstants.Pagination.forwardConversationsPageSize

    private var currentPage = 1
    private var hasMorePages = true
    private var isFetchingData = false
    private var currentSearchText = ""
    private var searchDebounceTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var loadedIds: Set<String> = []

    func reload(search: String?) {
        currentSearchText = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        currentPage = 1
        hasMorePages = true
        loadedIds.removeAll()
        users.removeAll()
        fetch(reset: true, showLoading: true)
    }

    func search(text: String) {
        currentSearchText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(ChatConstants.Timing.searchDebounce * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self.currentPage = 1
            self.hasMorePages = true
            self.fetch(reset: true, showLoading: self.users.isEmpty)
        }
    }

    func loadMoreIfNeeded(currentItem: SelectableUser?) {
        guard let currentItem, !isFetchingData, hasMorePages else { return }
        guard let index = users.firstIndex(where: { $0.id == currentItem.id }) else { return }
        if index >= users.count - 5 {
            fetch(reset: false, showLoading: false)
        }
    }

    private func fetch(reset: Bool, showLoading: Bool) {
        guard hasMorePages || reset else { return }
        if isFetchingData && !reset { return }

        fetchTask?.cancel()
        isFetchingData = true
        if showLoading {
            isLoading = true
        }

        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.fetchPage(
                    search: self.currentSearchText,
                    page: reset ? 1 : self.currentPage,
                    limit: self.pageSize
                )
                guard !Task.isCancelled else { return }

                let mapped = response.recipients.compactMap { recipient -> SelectableUser? in
                    let id = recipient.id.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !id.isEmpty else { return nil }
                    return SelectableUser(
                        id: id,
                        name: recipient.name,
                        username: recipient.username,
                        avatarURL: recipient.avatarURL
                    )
                }

                if reset {
                    self.loadedIds.removeAll()
                    self.users.removeAll()
                    self.currentPage = 1
                }

                var appended: [SelectableUser] = []
                for user in mapped where self.loadedIds.insert(user.id).inserted {
                    appended.append(user)
                }
                self.users.append(contentsOf: appended)

                if let hasMore = response.hasMore {
                    self.hasMorePages = hasMore
                } else if let total = response.total {
                    self.hasMorePages = self.users.count < total
                } else {
                    self.hasMorePages = mapped.count >= self.pageSize
                }
                if reset {
                    self.currentPage = 2
                } else if !mapped.isEmpty {
                    self.currentPage += 1
                }
                self.errorMessage = nil
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }

            guard !Task.isCancelled else { return }
            self.isFetchingData = false
            self.isLoading = false
        }
    }

    private func fetchPage(search: String, page: Int, limit: Int) async throws -> ForwardRecipientsAPIData {
        try await withCheckedThrowingContinuation { continuation in
            sessionManager.getForwardRecipients(search: search, page: page, limit: limit)
                .subscribe(onSuccess: { response in
                    continuation.resume(returning: response)
                }, onFailure: { error in
                    continuation.resume(throwing: error)
                })
        }
    }
}
