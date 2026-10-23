//
//  MomentsListViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

/// Moments tab (`GET moments?type=feed`), "My Moments" (`GET moments/me`) and another
/// user's moments (`GET users/:userId/moments`).
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
    /// Local like / comment / gift / delete, so a socket echo doesn't bump counts twice.
    private var recentLocalEdits: [String: Date] = [:]
    private let onlyCurrentUser: Bool
    /// Set for another user's moments (`GET users/:userId/moments`); mock people (numeric ids) still come from `MockMomentsStore`.
    private let authorID: String?
    /// Shown on that user's moments when the backend sends them without a creator.
    private let authorName: String?
    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    init(onlyCurrentUser: Bool = false, authorID: String? = nil, authorName: String? = nil,
         sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.onlyCurrentUser = onlyCurrentUser
        self.authorID = authorID
        self.authorName = authorName
        self.sessionManager = sessionManager
    }

    convenience init(authorID: String, authorName: String? = nil) {
        self.init(onlyCurrentUser: false, authorID: authorID, authorName: authorName)
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

    func loadFirstPage(momentId: String? = nil, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        currentPage = 0
        fetchPage(1, momentId: momentId, completion: completion)
    }

    func loadNextPage(completion: @escaping (Result<Void, MomentsError>) -> Void) {
        guard hasMore, !isLoading else { return }
        fetchPage(currentPage + 1, completion: completion)
    }

    private func fetchPage(_ page: Int, momentId: String? = nil, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        isLoading = true
        if let authorID, OtherUserProfileRouter.remoteID(for: authorID) == nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isLoading = false
                let data = MockMomentsStore.shared.feed(page: page, limit: self.pageSize, authorID: authorID).data
                self.apply(rows: data?.rows ?? [], page: page, hasMore: data?.hasMore ?? false, total: data?.count)
                completion(.success(()))
            }
            return
        }
        let request: Single<MomentFeedPage>
        if let authorID {
            let fallbackAuthor = MomentsAuthor(userId: authorID, userName: authorName, fullName: authorName,
                                               profilePicture: nil, verified: nil, location: nil)
            request = sessionManager.userMoments(userId: authorID, page: page, limit: pageSize, fallbackAuthor: fallbackAuthor)
        } else if onlyCurrentUser {
            request = sessionManager.myMoments(page: page, limit: pageSize)
        } else {
            request = sessionManager.momentsFeed(page: page, limit: pageSize, momentId: momentId)
        }
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
        // `users/:userId/moments` already applies block rules, and a stale local block would hide every row.
        let rows = authorID == nil ? rows.filter { !Self.isAuthorBlocked($0) } : rows
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
        totalCount = max(totalCount, vibes.count)
    }

    @discardableResult
    func updateVibe(id: String, _ change: (inout MomentsPost) -> Void) -> Int? {
        guard let index = index(of: id) else { return nil }
        change(&vibes[index])
        return index
    }

    func markLocalEdit(id: String) {
        recentLocalEdits[id] = Date()
    }

    private func hasRecentLocalEdit(_ id: String) -> Bool {
        guard let date = recentLocalEdits[id] else { return false }
        if Date().timeIntervalSince(date) > 3 {
            recentLocalEdits.removeValue(forKey: id)
            return false
        }
        return true
    }

    @discardableResult
    func removeVibe(id: String) -> Int? {
        guard let index = index(of: id) else { return nil }
        vibes.remove(at: index)
        totalCount = max(0, totalCount - 1)
        return index
    }

    // MARK: - Sockets

    enum SocketListChange {
        case counts(Int)
        case inserted(Int)
        case removed(Int)
        case none
    }

    /// Applies a live `moment:*` event to the in-memory feed.
    func applySocket(_ update: MomentSocketUpdate) -> SocketListChange {
        if update.kind == .deleted {
            return removeVibe(id: update.momentId).map { .removed($0) } ?? .none
        }

        if index(of: update.momentId) == nil {
            guard let moment = update.moment, shouldAccept(moment) else { return .none }
            prepend(apply(update, to: moment))
            return .inserted(0)
        }

        let row = updateVibe(id: update.momentId) { vibe in
            vibe = apply(update, to: vibe)
        }
        return row.map { .counts($0) } ?? .none
    }

    private func shouldAccept(_ vibe: MomentsPost) -> Bool {
        guard !Self.isAuthorBlocked(vibe) else { return false }
        if onlyCurrentUser { return isOwnVibe(vibe) }
        if let authorID { return Self.authorID(of: vibe) == authorID }
        return true
    }

    private func apply(_ update: MomentSocketUpdate, to vibe: MomentsPost) -> MomentsPost {
        var vibe = vibe
        let skipDelta = hasRecentLocalEdit(update.momentId)

        if let likes = update.likesCount {
            vibe.likesCount = likes
        } else if !skipDelta, update.kind == .likeUpdated, let liked = update.viewerHasLiked {
            let before = vibe.hasLiked ?? false
            if liked != before {
                vibe.likesCount = max((vibe.likesCount ?? 0) + (liked ? 1 : -1), 0)
            }
        }

        if let comments = update.commentsCount {
            vibe.commentsCount = comments
        } else if !skipDelta {
            switch update.kind {
            case .commentCreated:
                vibe.commentsCount = (vibe.commentsCount ?? 0) + 1
            case .commentDeleted:
                vibe.commentsCount = max((vibe.commentsCount ?? 0) - 1, 0)
            default:
                break
            }
        }

        if let gifts = update.giftsCount {
            vibe.giftCount = gifts
        } else if !skipDelta, update.kind == .giftSent {
            vibe.giftCount = (vibe.giftCount ?? 0) + 1
        }

        if let shares = update.sharesCount { vibe.shareCount = shares }
        if let liked = update.viewerHasLiked { vibe.hasLiked = liked }
        return vibe
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
        markLocalEdit(id: vibeId)
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
        markLocalEdit(id: vibeId)
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
