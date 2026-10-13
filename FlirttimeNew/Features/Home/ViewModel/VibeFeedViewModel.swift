//
//  VibeFeedViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

/// Moments tab (`GET moments?type=feed`) and "My Moments" (`GET moments/me`).
final class VibeFeedViewModel {

    private(set) var vibes: [Vibe] = []
    private(set) var hasMore = false
    private(set) var isLoading = false

    private let pageSize = 20
    private var currentPage = 0
    /// Bumped on every like tap so only the latest response for a vibe is applied.
    private var likeGeneration: [String: Int] = [:]
    private let onlyCurrentUser: Bool
    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    init(onlyCurrentUser: Bool = false,
         sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.onlyCurrentUser = onlyCurrentUser
        self.sessionManager = sessionManager
    }

    var currentUserID: String? { UserDataManager.shared.appUser?.id }
    var currentUserAuthor: VibeAuthor { .currentUser }

    func isOwnVibe(_ vibe: Vibe) -> Bool {
        if onlyCurrentUser { return true }
        guard let currentUserID else { return false }
        return (vibe.author?.userId ?? vibe.userId) == currentUserID
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
        let request = onlyCurrentUser
            ? sessionManager.myMoments(page: page, limit: pageSize)
            : sessionManager.momentsFeed(page: page, limit: pageSize)
        request
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] response in
                guard let self else { return }
                self.isLoading = false
                self.apply(rows: response.vibes, page: page, hasMore: response.hasMore)
                completion(.success(()))
            }, onFailure: { [weak self] error in
                self?.isLoading = false
                completion(.failure(VibeError(message: parseError(error) ?? "Unable to load moments")))
            })
            .disposed(by: disposeBag)
    }

    private func apply(rows: [Vibe], page: Int, hasMore: Bool) {
        if page == 1 {
            vibes = rows
        } else {
            let existing = Set(vibes.map(\.id))
            vibes.append(contentsOf: rows.filter { !existing.contains($0.id) })
        }
        currentPage = page
        self.hasMore = hasMore
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

    // MARK: - Report

    static let reportReasons = ["Spam", "Nudity or sexual content", "Harassment or bullying",
                                "Hate speech", "Fake profile", "Something else"]

    private static func reportCode(for reason: String) -> String {
        switch reason {
        case "Spam": return "spam"
        case "Nudity or sexual content": return "inappropriate_content"
        case "Harassment or bullying": return "harassment"
        case "Hate speech": return "hate_speech"
        case "Fake profile": return "fake_profile"
        default: return "other"
        }
    }

    /// Reported vibes are hidden from the reporter's feed; `completion` receives the removed row.
    func reportVibe(vibeId: String, reason: String, completion: @escaping (Result<Int?, VibeError>) -> Void) {
        sessionManager.reportMoment(momentId: vibeId, reason: Self.reportCode(for: reason), description: reason)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                guard let self else { return }
                let index = self.index(of: vibeId)
                if let index { self.vibes.remove(at: index) }
                completion(.success(index))
            }, onFailure: { error in
                completion(.failure(VibeError(message: parseError(error) ?? "Unable to report moment")))
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Like

    /// Applies the like optimistically, then reconciles with the server. `completion` receives
    /// the row index to refresh once the response lands (nil if the vibe is gone).
    /// Optimistic: flips locally, then syncs with the server's `isLiked` / `likesCount`, or reverts on failure.
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

        sessionManager.likeMoment(momentId: vibeId, isLiked: liked)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] json in
                guard let self, self.likeGeneration[vibeId] == generation else { return }
                let data = json["data"] as? [String: Any]
                let row = self.updateVibe(id: vibeId) { vibe in
                    if let isLiked = (data?["isLiked"] ?? data?["liked"]) as? Bool {
                        vibe.hasLiked = isLiked
                    }
                    if let count = data?["likesCount"] as? Int {
                        vibe.likesCount = count
                    }
                }
                completion(row)
            }, onFailure: { [weak self] _ in
                guard let self, self.likeGeneration[vibeId] == generation else { return }
                let row = self.updateVibe(id: vibeId) {
                    $0.hasLiked = before.hasLiked
                    $0.likesCount = before.likesCount
                }
                completion(row)
            })
            .disposed(by: disposeBag)
    }
}
