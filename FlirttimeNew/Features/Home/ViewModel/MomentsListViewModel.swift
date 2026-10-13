//
//  MomentsListViewModel.swift
//  FlirttimeNew
//

import Foundation

// TODO: replace the MockMomentsStore responses with GET vibes/?page=&limit=,
// POST / DELETE vibes/{id}/likes, DELETE vibes/{id} and POST vibes/{id}/report requests.
final class MomentsListViewModel {

    private(set) var vibes: [MomentsPost] = []
    private(set) var hasMore = false
    private(set) var isLoading = false
    /// All moments in this feed across every page, not just the loaded ones.
    private(set) var totalCount = 0

    private let pageSize = 10
    private var currentPage = 0
    /// Bumped on every like tap so only the latest response for a moment is applied.
    private var likeGeneration: [String: Int] = [:]
    private let store = MockMomentsStore.shared
    /// Limits the feed to one author's moments; `nil` is the everyone feed.
    private let authorID: String?

    init(onlyCurrentUser: Bool = false) {
        self.authorID = onlyCurrentUser ? MockMomentsStore.shared.currentUserID : nil
    }

    init(authorID: String) {
        self.authorID = authorID
    }

    var currentUserID: String { store.currentUserID }
    var currentUserAuthor: MomentsAuthor { store.currentUserAuthor }

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    private static func authorID(of vibe: MomentsPost) -> String? {
        vibe.author?.userId ?? vibe.userId
    }

    private static func isAuthorBlocked(_ vibe: MomentsPost) -> Bool {
        guard let id = authorID(of: vibe) else { return false }
        return BlockedUsersManager.shared.isBlocked(id: id)
    }

    func isOwnVibe(_ vibe: MomentsPost) -> Bool {
        Self.authorID(of: vibe) == currentUserID
    }

    func index(of vibeId: String) -> Int? {
        vibes.firstIndex { $0.id == vibeId }
    }

    // MARK: - Feed

    func loadFirstPage(completion: @escaping (Result<Void, MomentsError>) -> Void) {
        currentPage = 0
        fetchPage(1, completion: completion)
    }

    func loadNextPage(completion: @escaping (Result<Void, MomentsError>) -> Void) {
        guard hasMore, !isLoading else { return }
        fetchPage(currentPage + 1, completion: completion)
    }

    private func fetchPage(_ page: Int, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        isLoading = true
        respond { [weak self] in
            guard let self else { return }
            self.isLoading = false
            let response = self.store.feed(page: page, limit: self.pageSize,
                                           authorID: self.authorID)
            guard response.success == true, let data = response.data else {
                completion(.failure(MomentsError(message: response.message ?? "Unable to load moments")))
                return
            }
            let rows = (data.rows ?? []).filter { !Self.isAuthorBlocked($0) }
            if page == 1 {
                self.vibes = rows
            } else {
                let existing = Set(self.vibes.map(\.id))
                self.vibes.append(contentsOf: rows.filter { !existing.contains($0.id) })
            }
            self.currentPage = page
            self.hasMore = data.hasMore ?? false
            self.totalCount = max(data.count ?? 0, self.vibes.count)
            completion(.success(()))
        }
    }

    // MARK: - Local updates

    func prepend(_ vibe: MomentsPost) {
        vibes.removeAll { $0.id == vibe.id }
        vibes.insert(vibe, at: 0)
    }

    @discardableResult
    func updateVibe(id: String, _ change: (inout MomentsPost) -> Void) -> Int? {
        guard let index = index(of: id) else { return nil }
        change(&vibes[index])
        return index
    }

    // MARK: - Delete / Report

    static let reportReasons = ["Spam", "Nudity or sexual content", "Harassment or bullying",
                                "Hate speech", "Fake profile", "Something else"]

    /// Removes the moment from the feed on success; `completion` receives the removed row.
    func deleteVibe(vibeId: String, completion: @escaping (Result<Int?, MomentsError>) -> Void) {
        respond { [weak self] in
            guard let self else { return }
            let response = self.store.deleteVibe(vibeId: vibeId)
            self.finishRemoval(vibeId: vibeId, response: response, fallback: "Unable to delete moment", completion: completion)
        }
    }

    /// Reported moments are hidden from the reporter's feed.
    func reportVibe(vibeId: String, reason: String, completion: @escaping (Result<Int?, MomentsError>) -> Void) {
        respond { [weak self] in
            guard let self else { return }
            let response = self.store.reportVibe(vibeId: vibeId, reason: reason)
            self.finishRemoval(vibeId: vibeId, response: response, fallback: "Unable to report moment", completion: completion)
        }
    }

    /// Blocks the moment's author and drops all of their moments from the feed; returns the removed rows.
    func blockAuthor(of vibe: MomentsPost) -> [Int] {
        guard let authorID = Self.authorID(of: vibe) else { return [] }
        BlockedUsersManager.shared.blockUser(id: authorID)
        let rows = vibes.indices.filter { Self.authorID(of: vibes[$0]) == authorID }
        vibes.removeAll { Self.authorID(of: $0) == authorID }
        return rows
    }

    private func finishRemoval(vibeId: String, response: MomentsActionResponse, fallback: String,
                               completion: (Result<Int?, MomentsError>) -> Void) {
        guard response.success == true else {
            completion(.failure(MomentsError(message: response.message ?? fallback)))
            return
        }
        let index = self.index(of: vibeId)
        if let index { vibes.remove(at: index) }
        completion(.success(index))
    }

    // MARK: - Like

    /// Applies the like optimistically, then reconciles with the server. `completion` receives
    /// the row index to refresh once the response lands (nil if the moment is gone).
    func toggleLike(vibeId: String, completion: @escaping (Int?) -> Void) {
        guard let index = index(of: vibeId) else { return }
        let before = vibes[index]
        let liked = !(before.hasLiked ?? false)
        updateVibe(id: vibeId) {
            $0.hasLiked = liked
            $0.likesCount = liked ? ($0.likesCount ?? 0) + 1 : max(($0.likesCount ?? 0) - 1, 0)
        }

        let generation = (likeGeneration[vibeId] ?? 0) + 1
        likeGeneration[vibeId] = generation
        respond { [weak self] in
            guard let self else { return }
            let response = self.store.setLike(vibeId: vibeId, liked: liked)
            guard self.likeGeneration[vibeId] == generation else { return }
            let row = self.updateVibe(id: vibeId) {
                if response.success == true, let data = response.data {
                    $0.hasLiked = data.hasLiked
                    $0.likesCount = data.likesCount
                } else {
                    $0.hasLiked = before.hasLiked
                    $0.likesCount = before.likesCount
                }
            }
            completion(row)
        }
    }

    // MARK: - Share

    /// Records a completed share and returns the row to refresh.
    func recordShare(vibeId: String, completion: @escaping (Int?) -> Void) {
        respond { [weak self] in
            guard let self else { return }
            guard let count = self.store.recordShare(vibeId: vibeId) else {
                completion(nil)
                return
            }
            let row = self.updateVibe(id: vibeId) { $0.shareCount = count }
            completion(row)
        }
    }
}
