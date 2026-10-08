//
//  VibeFeedViewModel.swift
//  FlirttimeNew
//

import Foundation

// TODO: replace the MockVibeStore responses with GET vibes/?page=&limit=,
// POST / DELETE vibes/{id}/likes, DELETE vibes/{id} and POST vibes/{id}/report requests.
final class VibeFeedViewModel {

    private(set) var vibes: [Vibe] = []
    private(set) var hasMore = false
    private(set) var isLoading = false

    private let pageSize = 10
    private var currentPage = 0
    /// Bumped on every like tap so only the latest response for a vibe is applied.
    private var likeGeneration: [String: Int] = [:]
    private let store = MockVibeStore.shared

    var currentUserID: String { store.currentUserID }
    var currentUserAuthor: VibeAuthor { store.currentUserAuthor }

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    func isOwnVibe(_ vibe: Vibe) -> Bool {
        (vibe.author?.userId ?? vibe.userId) == currentUserID
    }

    func index(of vibeId: String) -> Int? {
        vibes.firstIndex { $0.id == vibeId }
    }

    // MARK: - Feed

    func loadFirstPage(completion: @escaping (Result<Void, VibeError>) -> Void) {
        currentPage = 0
        fetchPage(1, completion: completion)
    }

    func loadNextPage(completion: @escaping (Result<Void, VibeError>) -> Void) {
        guard hasMore, !isLoading else { return }
        fetchPage(currentPage + 1, completion: completion)
    }

    private func fetchPage(_ page: Int, completion: @escaping (Result<Void, VibeError>) -> Void) {
        isLoading = true
        respond { [weak self] in
            guard let self else { return }
            self.isLoading = false
            let response = self.store.feed(page: page, limit: self.pageSize)
            guard response.success == true, let data = response.data else {
                completion(.failure(VibeError(message: response.message ?? "Unable to load vibes")))
                return
            }
            let rows = data.rows ?? []
            if page == 1 {
                self.vibes = rows
            } else {
                let existing = Set(self.vibes.map(\.id))
                self.vibes.append(contentsOf: rows.filter { !existing.contains($0.id) })
            }
            self.currentPage = page
            self.hasMore = data.hasMore ?? false
            completion(.success(()))
        }
    }

    // MARK: - Local updates

    func prepend(_ vibe: Vibe) {
        vibes.removeAll { $0.id == vibe.id }
        vibes.insert(vibe, at: 0)
    }

    @discardableResult
    func updateVibe(id: String, _ change: (inout Vibe) -> Void) -> Int? {
        guard let index = index(of: id) else { return nil }
        change(&vibes[index])
        return index
    }

    // MARK: - Delete / Report

    static let reportReasons = ["Spam", "Nudity or sexual content", "Harassment or bullying",
                                "Hate speech", "Fake profile", "Something else"]

    /// Removes the vibe from the feed on success; `completion` receives the removed row.
    func deleteVibe(vibeId: String, completion: @escaping (Result<Int?, VibeError>) -> Void) {
        respond { [weak self] in
            guard let self else { return }
            let response = self.store.deleteVibe(vibeId: vibeId)
            self.finishRemoval(vibeId: vibeId, response: response, fallback: "Unable to delete vibe", completion: completion)
        }
    }

    /// Reported vibes are hidden from the reporter's feed.
    func reportVibe(vibeId: String, reason: String, completion: @escaping (Result<Int?, VibeError>) -> Void) {
        respond { [weak self] in
            guard let self else { return }
            let response = self.store.reportVibe(vibeId: vibeId, reason: reason)
            self.finishRemoval(vibeId: vibeId, response: response, fallback: "Unable to report vibe", completion: completion)
        }
    }

    private func finishRemoval(vibeId: String, response: VibeActionResponse, fallback: String,
                               completion: (Result<Int?, VibeError>) -> Void) {
        guard response.success == true else {
            completion(.failure(VibeError(message: response.message ?? fallback)))
            return
        }
        let index = self.index(of: vibeId)
        if let index { vibes.remove(at: index) }
        completion(.success(index))
    }

    // MARK: - Like

    /// Applies the like optimistically, then reconciles with the server. `completion` receives
    /// the row index to refresh once the response lands (nil if the vibe is gone).
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
}
