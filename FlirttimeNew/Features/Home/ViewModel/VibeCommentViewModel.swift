//
//  VibeCommentViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

final class VibeCommentViewModel {

    let vibeId: String
    let maxCommentLength = 500
    private static let pageSize = 50

    /// Newest first.
    private(set) var comments: [VibeComment] = []
    /// All comments on the moment, including ones not loaded yet.
    private(set) var totalCount = 0
    private(set) var isSending = false
    private var deletingIds = Set<String>()

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    init(vibeId: String,
         sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.vibeId = vibeId
        self.sessionManager = sessionManager
    }

    var currentUserAuthor: VibeAuthor { .currentUser }

    func loadComments(completion: @escaping (Result<Void, VibeError>) -> Void) {
        sessionManager.momentComments(momentId: vibeId, page: 1, limit: Self.pageSize)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] data in
                guard let self else { return }
                self.comments = (data.comments ?? [])
                    .compactMap { $0.vibeComment(momentId: self.vibeId) }
                    .sorted { (VibeDate.date(from: $0.createdAt) ?? .distantPast) > (VibeDate.date(from: $1.createdAt) ?? .distantPast) }
                self.totalCount = max(data.totalComments ?? 0, self.comments.count)
                completion(.success(()))
            }, onFailure: { error in
                completion(.failure(VibeError(message: parseError(error) ?? "Unable to load comments")))
            })
            .disposed(by: disposeBag)
    }

    func canDelete(at index: Int) -> Bool {
        comments.indices.contains(index) && comments[index].isMine == true && !deletingIds.contains(comments[index].id)
    }

    /// On success removes the comment and returns its former row.
    func deleteComment(id: String, completion: @escaping (Result<Int, VibeError>) -> Void) {
        guard !deletingIds.contains(id) else { return }
        deletingIds.insert(id)
        sessionManager.deleteMomentComment(momentId: vibeId, commentId: id)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                guard let self else { return }
                self.deletingIds.remove(id)
                guard let index = self.comments.firstIndex(where: { $0.id == id }) else { return }
                self.comments.remove(at: index)
                self.totalCount = max(0, self.totalCount - 1)
                completion(.success(index))
            }, onFailure: { [weak self] error in
                self?.deletingIds.remove(id)
                completion(.failure(VibeError(message: parseError(error) ?? "Unable to delete comment")))
            })
            .disposed(by: disposeBag)
    }

    func addComment(_ text: String, completion: @escaping (Result<VibeComment, VibeError>) -> Void) {
        let body = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCommentLength))
        guard !body.isEmpty, !isSending else { return }
        isSending = true
        sessionManager.commentOnMoment(momentId: vibeId, comment: body)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] json in
                guard let self else { return }
                self.isSending = false
                let data = json["data"] as? [String: Any]
                let comment = VibeComment(id: (data?["commentId"] ?? data?["id"]) as? String ?? UUID().uuidString,
                                          vibeId: self.vibeId,
                                          body: body,
                                          createdAt: (data?["createdAt"] as? String) ?? VibeDate.string(from: Date()),
                                          author: self.currentUserAuthor,
                                          isMine: true)
                self.comments.insert(comment, at: 0)
                self.totalCount += 1
                completion(.success(comment))
            }, onFailure: { [weak self] error in
                self?.isSending = false
                completion(.failure(VibeError(message: parseError(error) ?? "Unable to send reply")))
            })
            .disposed(by: disposeBag)
    }
}
