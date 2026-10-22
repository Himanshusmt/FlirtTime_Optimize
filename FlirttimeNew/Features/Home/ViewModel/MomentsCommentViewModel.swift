//
//  MomentsCommentViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

/// A top-level comment and the replies under it; one table section each.
struct MomentsCommentThread {
    var comment: MomentsComment
    /// Oldest first.
    var replies: [MomentsComment]
    var isExpanded: Bool

    /// Replies on the server, which can be more than the ones loaded.
    var replyCount: Int { max(comment.repliesCount ?? 0, replies.count) }
}

final class MomentsCommentViewModel {

    let vibeId: String
    let maxCommentLength = 500
    private static let pageSize = 50
    private static let repliesPageSize = 100

    /// Newest thread first.
    private(set) var threads: [MomentsCommentThread] = []
    /// All comments on the moment, including ones not loaded yet.
    private(set) var totalCount = 0
    private(set) var isSending = false
    private(set) var isLoadingPage = false
    private(set) var hasMore = false

    /// Every loaded comment and reply, flat; `threads` is rebuilt from it.
    private var allComments: [MomentsComment] = []
    private var expandedIds = Set<String>()
    private var deletingIds = Set<String>()
    private var likeRequestsInFlight = Set<String>()
    private var loadingRepliesIds = Set<String>()
    private var currentPage = 0

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    init(vibeId: String,
         sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.vibeId = vibeId
        self.sessionManager = sessionManager
    }

    var currentUserAuthor: MomentsAuthor { .currentUser }

    var isEmpty: Bool { threads.isEmpty }

    // MARK: - Table data

    func numberOfRows(in section: Int) -> Int {
        guard threads.indices.contains(section) else { return 0 }
        let thread = threads[section]
        return 1 + (thread.isExpanded ? thread.replies.count : 0)
    }

    func comment(at indexPath: IndexPath) -> MomentsComment? {
        guard threads.indices.contains(indexPath.section) else { return nil }
        let thread = threads[indexPath.section]
        if indexPath.row == 0 { return thread.comment }
        let index = indexPath.row - 1
        return thread.isExpanded && thread.replies.indices.contains(index) ? thread.replies[index] : nil
    }

    func indexPath(forCommentId id: String) -> IndexPath? {
        for (section, thread) in threads.enumerated() {
            if thread.comment.id == id { return IndexPath(row: 0, section: section) }
            if thread.isExpanded, let row = thread.replies.firstIndex(where: { $0.id == id }) {
                return IndexPath(row: row + 1, section: section)
            }
        }
        return nil
    }

    func canDelete(_ comment: MomentsComment) -> Bool {
        comment.isMine == true && !deletingIds.contains(comment.id)
    }

    /// Resolves `@username` to a profile seed: thread authors first, then `users/search`.
    func resolveMentionedUser(username: String,
                              completion: @escaping (Result<OtherUserProfileRouter.Seed, MomentsError>) -> Void) {
        let handle = Self.normalizedHandle(username)
        guard !handle.isEmpty else {
            completion(.failure(MomentsError(message: "User not found")))
            return
        }
        if let author = mentionedAuthor(handle: handle),
           let userId = author.userId?.trimmingCharacters(in: .whitespacesAndNewlines), !userId.isEmpty {
            completion(.success(Self.seed(from: author)))
            return
        }
        sessionManager.searchUsers(query: handle, page: 1, limit: 20)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { page in
                let match = page.users.first { user in
                    (user.username ?? "").caseInsensitiveCompare(handle) == .orderedSame
                }
                guard let match, let userId = match.userId?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !userId.isEmpty else {
                    completion(.failure(MomentsError(message: "User not found")))
                    return
                }
                completion(.success(OtherUserProfileRouter.Seed(
                    userID: userId,
                    name: match.displayName,
                    avatar: match.profilePhoto,
                    location: match.city,
                    age: match.age,
                    isVerified: match.isVerified ?? false,
                    isOnline: match.isOnline ?? false
                )))
            }, onFailure: { error in
                completion(.failure(MomentsError(message: parseError(error) ?? "Unable to open profile")))
            })
            .disposed(by: disposeBag)
    }

    private func mentionedAuthor(handle: String) -> MomentsAuthor? {
        let authors = allComments.compactMap(\.author) + [currentUserAuthor]
        return authors.first { author in
            let userName = (author.userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !userName.isEmpty, userName.caseInsensitiveCompare(handle) == .orderedSame {
                return true
            }
            let stripped = author.displayName.replacingOccurrences(of: " ", with: "")
            return !stripped.isEmpty && stripped.caseInsensitiveCompare(handle) == .orderedSame
        }
    }

    private static func seed(from author: MomentsAuthor) -> OtherUserProfileRouter.Seed {
        OtherUserProfileRouter.Seed(
            userID: author.userId,
            name: author.displayName,
            avatar: author.profilePicture,
            location: author.location,
            isVerified: author.verified ?? false
        )
    }

    private static func normalizedHandle(_ username: String) -> String {
        username.trimmingCharacters(in: CharacterSet(charactersIn: "@").union(.whitespacesAndNewlines))
    }

    func isLoadingReplies(section: Int) -> Bool {
        threads.indices.contains(section) && loadingRepliesIds.contains(threads[section].comment.id)
    }

    // MARK: - Load

    func loadComments(completion: @escaping (Result<Void, MomentsError>) -> Void) {
        loadPage(1, completion: completion)
    }

    /// Loads the next page; does nothing while a page is loading or when everything is loaded.
    func loadMoreIfNeeded(completion: @escaping (Result<Void, MomentsError>) -> Void) {
        guard hasMore, !isLoadingPage else { return }
        loadPage(currentPage + 1, completion: completion)
    }

    private func loadPage(_ page: Int, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        isLoadingPage = true
        sessionManager.momentComments(momentId: vibeId, page: page, limit: Self.pageSize)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] data in
                guard let self else { return }
                self.isLoadingPage = false
                let received = data.comments ?? []
                let loaded = received.flatMap { $0.flattened(momentId: self.vibeId) }
                if page == 1 { self.allComments = [] }
                self.merge(loaded)
                self.currentPage = page
                if let current = data.page, let totalPages = data.totalPages {
                    self.hasMore = current < totalPages
                } else {
                    self.hasMore = received.count >= Self.pageSize
                }
                self.rebuildThreads()
                self.totalCount = max(data.totalComments ?? 0, self.allComments.count)
                completion(.success(()))
            }, onFailure: { [weak self] error in
                self?.isLoadingPage = false
                completion(.failure(MomentsError(message: parseError(error) ?? "Unable to load comments")))
            })
            .disposed(by: disposeBag)
    }

    /// Shows or hides a thread's replies, fetching them first when the server has more than are loaded.
    func toggleReplies(section: Int, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        guard threads.indices.contains(section) else { return }
        let thread = threads[section]
        let rootId = thread.comment.id
        guard thread.replyCount > 0, !loadingRepliesIds.contains(rootId) else { return }

        if thread.isExpanded {
            expandedIds.remove(rootId)
            rebuildThreads()
            completion(.success(()))
            return
        }
        guard thread.replies.count < thread.replyCount else {
            expandedIds.insert(rootId)
            rebuildThreads()
            completion(.success(()))
            return
        }

        loadingRepliesIds.insert(rootId)
        sessionManager.momentCommentReplies(momentId: vibeId, commentId: rootId, page: 1, limit: Self.repliesPageSize)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] data in
                guard let self else { return }
                self.loadingRepliesIds.remove(rootId)
                self.merge(data.replies.flatMap { $0.replies(inThread: rootId, momentId: self.vibeId) })
                self.expandedIds.insert(rootId)
                self.rebuildThreads()
                completion(.success(()))
            }, onFailure: { [weak self] error in
                guard let self else { return }
                self.loadingRepliesIds.remove(rootId)
                // Still show whatever replies are already loaded.
                if !thread.replies.isEmpty { self.expandedIds.insert(rootId) }
                self.rebuildThreads()
                completion(.failure(MomentsError(message: parseError(error) ?? "Unable to load replies")))
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Add

    /// Replies go under `replyTo`'s top-level comment. On success returns where the new comment is shown.
    func addComment(_ text: String,
                    replyTo: MomentsComment? = nil,
                    completion: @escaping (Result<(indexPath: IndexPath, isNewThread: Bool), MomentsError>) -> Void) {
        let body = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCommentLength))
        guard !body.isEmpty, !isSending else { return }
        let parentId = replyTo.map { rootId(of: $0) }
        let request: Single<[String: Any]>
        if let replyTo, let parentId {
            // Answering a reply (not the top-level comment) also names that reply.
            request = sessionManager.replyToMomentComment(momentId: vibeId, commentId: parentId, reply: body,
                                                          parentReplyId: replyTo.id == parentId ? nil : replyTo.id)
        } else {
            request = sessionManager.commentOnMoment(momentId: vibeId, comment: body)
        }
        isSending = true
        request
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] json in
                guard let self else { return }
                self.isSending = false
                let data = json["data"] as? [String: Any]
                let created = (data?["reply"] as? [String: Any]) ?? (data?["comment"] as? [String: Any]) ?? data
                // On a reply `commentId` is the parent comment, so the reply's own id comes first.
                let id = parentId == nil
                    ? MomentsCommentViewModel.string(created?["commentId"]) ?? MomentsCommentViewModel.string(created?["id"])
                    : MomentsCommentViewModel.string(created?["replyId"]) ?? MomentsCommentViewModel.string(created?["id"])
                let comment = MomentsComment(id: id ?? UUID().uuidString,
                                             vibeId: self.vibeId,
                                             body: body,
                                             createdAt: (created?["createdAt"] as? String) ?? MomentsDate.string(from: Date()),
                                             author: self.currentUserAuthor,
                                             isMine: true,
                                             parentId: parentId,
                                             likesCount: 0,
                                             isLiked: false,
                                             repliesCount: 0)
                self.allComments.append(comment)
                if let parentId {
                    self.adjustReplyCount(rootId: parentId, by: 1)
                    self.expandedIds.insert(parentId)
                }
                self.totalCount += 1
                self.rebuildThreads()
                guard let indexPath = self.indexPath(forCommentId: comment.id) else { return }
                completion(.success((indexPath, indexPath.row == 0)))
            }, onFailure: { [weak self] error in
                self?.isSending = false
                let fallback = parentId == nil ? "Unable to send comment" : "Unable to send reply"
                completion(.failure(MomentsError(message: parseError(error) ?? fallback)))
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Like

    /// Flips the like right away; `completion` runs once the server agrees or the change is rolled back.
    func toggleLike(commentId: String, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        guard let index = allComments.firstIndex(where: { $0.id == commentId }) else { return }
        let liked = !(allComments[index].isLiked ?? false)
        setLike(liked, at: index)
        rebuildThreads()
        syncLike(commentId: commentId, completion: completion)
    }

    /// Sends the latest like state; taps made while a request is in flight are sent when it returns.
    private func syncLike(commentId: String, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        guard !likeRequestsInFlight.contains(commentId),
              let wanted = allComments.first(where: { $0.id == commentId })?.isLiked else { return }
        likeRequestsInFlight.insert(commentId)
        sessionManager.likeMomentComment(momentId: vibeId, commentId: commentId, isLiked: wanted)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] json in
                guard let self else { return }
                self.likeRequestsInFlight.remove(commentId)
                guard let index = self.allComments.firstIndex(where: { $0.id == commentId }) else { return }
                if self.allComments[index].isLiked != wanted {
                    self.syncLike(commentId: commentId, completion: completion)
                    return
                }
                let data = json["data"] as? [String: Any]
                if let isLiked = data?["isLiked"] as? Bool {
                    self.allComments[index].isLiked = isLiked
                }
                if let count = MomentsCommentViewModel.int(data?["likesCount"] ?? data?["likeCount"]) {
                    self.allComments[index].likesCount = max(0, count)
                }
                self.rebuildThreads()
                completion(.success(()))
            }, onFailure: { [weak self] error in
                guard let self else { return }
                self.likeRequestsInFlight.remove(commentId)
                if let index = self.allComments.firstIndex(where: { $0.id == commentId }),
                   self.allComments[index].isLiked == wanted {
                    self.setLike(!wanted, at: index)
                    self.rebuildThreads()
                }
                completion(.failure(MomentsError(message: parseError(error) ?? "Unable to update like")))
            })
            .disposed(by: disposeBag)
    }

    private func setLike(_ liked: Bool, at index: Int) {
        guard (allComments[index].isLiked ?? false) != liked else { return }
        allComments[index].isLiked = liked
        allComments[index].likesCount = max(0, (allComments[index].likesCount ?? 0) + (liked ? 1 : -1))
    }

    // MARK: - Delete

    /// On success returns the section the comment was in and whether its whole thread was removed.
    func deleteComment(id: String, completion: @escaping (Result<(section: Int, removedThread: Bool), MomentsError>) -> Void) {
        guard !deletingIds.contains(id) else { return }
        deletingIds.insert(id)
        sessionManager.deleteMomentComment(momentId: vibeId, commentId: id)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                guard let self else { return }
                self.deletingIds.remove(id)
                guard let section = self.threads.firstIndex(where: { thread in
                    thread.comment.id == id || thread.replies.contains { $0.id == id }
                }) else { return }
                let removedThread = self.threads[section].comment.id == id
                var removed = 1
                if removedThread {
                    let replyIds = Set(self.threads[section].replies.map(\.id))
                    removed += replyIds.count
                    self.allComments.removeAll { $0.id == id || replyIds.contains($0.id) }
                    self.expandedIds.remove(id)
                } else {
                    self.allComments.removeAll { $0.id == id }
                    self.adjustReplyCount(rootId: self.threads[section].comment.id, by: -1)
                }
                self.totalCount = max(0, self.totalCount - removed)
                self.rebuildThreads()
                completion(.success((section, removedThread)))
            }, onFailure: { [weak self] error in
                self?.deletingIds.remove(id)
                completion(.failure(MomentsError(message: parseError(error) ?? "Unable to delete comment")))
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Threads

    private func merge(_ comments: [MomentsComment]) {
        var indexById = Dictionary(allComments.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        for comment in comments {
            if let index = indexById[comment.id] {
                allComments[index] = comment
            } else {
                indexById[comment.id] = allComments.count
                allComments.append(comment)
            }
        }
    }

    /// The top-level comment a comment belongs to. Replies to replies stay in the same thread.
    private func rootId(of comment: MomentsComment) -> String {
        var current = comment
        var visited: Set<String> = [comment.id]
        while let parentId = current.parentId, !parentId.isEmpty,
              let parent = allComments.first(where: { $0.id == parentId }),
              !visited.contains(parent.id) {
            visited.insert(parent.id)
            current = parent
        }
        // A reply whose parent isn't loaded keeps the parent's id so it still lands in that thread once it loads.
        return current.parentId.flatMap { $0.isEmpty ? nil : $0 } ?? current.id
    }

    private func adjustReplyCount(rootId: String, by delta: Int) {
        guard let index = allComments.firstIndex(where: { $0.id == rootId }),
              let count = allComments[index].repliesCount else { return }
        allComments[index].repliesCount = max(0, count + delta)
    }

    private func rebuildThreads() {
        let rootIds = Set(allComments.filter { ($0.parentId ?? "").isEmpty }.map(\.id))
        var roots: [MomentsComment] = []
        var repliesByRoot: [String: [MomentsComment]] = [:]
        for comment in allComments {
            let root = rootId(of: comment)
            if root == comment.id {
                roots.append(comment)
            } else if rootIds.contains(root) {
                repliesByRoot[root, default: []].append(comment)
            } else {
                // Parent not loaded (or deleted): show the reply on its own rather than hide it.
                roots.append(comment)
            }
        }
        let byDate: (MomentsComment) -> Date = { MomentsDate.date(from: $0.createdAt) ?? .distantPast }
        threads = roots
            .sorted { byDate($0) > byDate($1) }
            .map { root in
                MomentsCommentThread(comment: root,
                                     replies: (repliesByRoot[root.id] ?? []).sorted { byDate($0) < byDate($1) },
                                     isExpanded: expandedIds.contains(root.id))
            }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string.isEmpty ? nil : string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }
}
