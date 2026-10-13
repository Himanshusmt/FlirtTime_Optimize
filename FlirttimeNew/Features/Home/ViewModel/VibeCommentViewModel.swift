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
                                          author: self.currentUserAuthor)
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
