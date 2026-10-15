//
//  MomentsListViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

/// Moments tab (`GET moments?type=feed`) and "My Moments" (`GET moments/me`).
final class MomentsListViewModel {

    private(set) var vibes: [MomentsPost] = []
    private(set) var hasMore = false
    private(set) var isLoading = false
    /// All moments in this feed across every page, not just the loaded ones.
    private(set) var totalCount = 0

    private let pageSize = 20
    private var currentPage = 0
    /// Bumped on every like tap so only the latest response for a moment is applied.
    private var likeGeneration: [String: Int] = [:]
    private let onlyCurrentUser: Bool
    /// Another user's moments come from `MockMomentsStore` until the API exposes them.
    private let authorID: String?
    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    init(onlyCurrentUser: Bool = false, authorID: String? = nil,
         sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.onlyCurrentUser = onlyCurrentUser
        self.authorID = authorID
        self.sessionManager = sessionManager
    }

    convenience init(authorID: String) {
        self.init(onlyCurrentUser: false, authorID: authorID)
    }

    var currentUserID: String? { UserDataManager.shared.appUser?.id }
    var currentUserAuthor: MomentsAuthor { .currentUser }

    private static func authorID(of vibe: MomentsPost) -> String? {
        vibe.author?.userId ?? vibe.userId
    }

    private static func isAuthorBlocked(_ vibe: MomentsPost) -> Bool {
        guard let id = authorID(of: vibe) else { return false }
        return BlockedUsersManager.shared.isBlocked(id: id)
    }

    func isOwnVibe(_ vibe: MomentsPost) -> Bool {
        if onlyCurrentUser { return true }
        guard let currentUserID else { return false }
        return Self.authorID(of: vibe) == currentUserID
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
        if let authorID {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isLoading = false
                let data = MockMomentsStore.shared.feed(page: page, limit: self.pageSize, authorID: authorID).data
                self.apply(rows: data?.rows ?? [], page: page, hasMore: data?.hasMore ?? false, total: data?.count)
                completion(.success(()))
            }
            return
        }
        let request = onlyCurrentUser
            ? sessionManager.myMoments(page: page, limit: pageSize)
            : sessionManager.momentsFeed(page: page, limit: pageSize)
        request
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] response in
                guard let self else { return }
                self.isLoading = false
                self.apply(rows: response.vibes, page: page, hasMore: response.hasMore, total: response.total)
                completion(.success(()))
            }, onFailure: { [weak self] error in
                self?.isLoading = false
                completion(.failure(MomentsError(message: parseError(error) ?? "Unable to load moments")))
            })
            .disposed(by: disposeBag)
    }

    private func apply(rows: [MomentsPost], page: Int, hasMore: Bool, total: Int?) {
        let rows = rows.filter { !Self.isAuthorBlocked($0) }
        if page == 1 {
            vibes = rows
        } else {
            let existing = Set(vibes.map(\.id))
            vibes.append(contentsOf: rows.filter { !existing.contains($0.id) })
        }
        currentPage = page
        self.hasMore = hasMore
        totalCount = max(total ?? 0, vibes.count)
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

    // MARK: - Report

    /// Moment reasons accepted by POST `moments/:id/report` (title, API code). They differ from the user report reasons.
    private static let reportReasonCodes: [(title: String, code: String)] = [
        ("Nudity or sexual content", "nudity"),
        ("Violence or graphic content", "violence"),
        ("Harassment or bullying", "harassment"),
        ("Inappropriate content", "inappropriate_content"),
        ("Spam or advertising", "spam"),
        ("Fake or misleading content", "fake_content"),
        ("Something else", "other")
    ]

    static let reportReasons = reportReasonCodes.map(\.title)

    private static func reportCode(for reason: String) -> String {
        reportReasonCodes.first { $0.title == reason }?.code ?? "other"
    }

    /// Reported vibes are hidden from the reporter's feed; `completion` receives the removed row.
    func reportVibe(vibeId: String, reason: String, completion: @escaping (Result<Int?, MomentsError>) -> Void) {
        sessionManager.reportMoment(momentId: vibeId, reason: Self.reportCode(for: reason), description: reason)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                guard let self else { return }
                let index = self.index(of: vibeId)
                if let index { self.vibes.remove(at: index) }
                completion(.success(index))
            }, onFailure: { error in
                completion(.failure(MomentsError(message: parseError(error) ?? "Unable to report moment")))
            })
            .disposed(by: disposeBag)
    }

    /// Deletes an own moment; `completion` receives the removed row.
    func deleteVibe(vibeId: String, completion: @escaping (Result<Int?, MomentsError>) -> Void) {
        sessionManager.deleteMoment(momentId: vibeId)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                guard let self else { return }
                let index = self.index(of: vibeId)
                if let index { self.vibes.remove(at: index) }
                completion(.success(index))
            }, onFailure: { error in
                completion(.failure(MomentsError(message: parseError(error) ?? "Unable to delete moment")))
            })
            .disposed(by: disposeBag)
    }

    /// Blocks the moment's author and drops all of their moments from the feed; returns the removed rows.
    func blockAuthor(of vibe: MomentsPost, completion: @escaping (Result<[Int], MomentsError>) -> Void) {
        guard let authorID = Self.authorID(of: vibe) else {
            completion(.failure(MomentsError(message: "This user can't be blocked right now")))
            return
        }
        sessionManager.blockUser(userId: authorID, reason: "Blocked from Moments")
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                guard let self else { return }
                BlockedUsersManager.shared.blockUser(id: authorID)
                let rows = self.vibes.indices.filter { Self.authorID(of: self.vibes[$0]) == authorID }
                self.vibes.removeAll { Self.authorID(of: $0) == authorID }
                completion(.success(rows))
            }, onFailure: { error in
                completion(.failure(MomentsError(message: parseError(error) ?? "Unable to block this user")))
            })
            .disposed(by: disposeBag)
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

    // MARK: - Share

    /// Records a completed share and returns the row to refresh.
    func recordShare(vibeId: String, completion: @escaping (Int?) -> Void) {
        completion(updateVibe(id: vibeId) { $0.shareCount = ($0.shareCount ?? 0) + 1 })
    }
}
