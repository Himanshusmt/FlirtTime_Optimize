//
//  MomentsCommentViewModel.swift
//  FlirttimeNew
//

import Foundation

// TODO: replace MockMomentsStore with GET / POST vibes/{id}/comments requests.
final class MomentsCommentViewModel {

    let vibeId: String
    let maxCommentLength = 500

    private(set) var comments: [MomentsComment] = []
    private(set) var isSending = false

    private let store = MockMomentsStore.shared

    init(vibeId: String) {
        self.vibeId = vibeId
    }

    var currentUserAuthor: MomentsAuthor { store.currentUserAuthor }

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    func loadComments(completion: @escaping (Result<Void, MomentsError>) -> Void) {
        respond { [weak self] in
            guard let self else { return }
            let response = self.store.comments(vibeId: self.vibeId)
            guard response.success == true else {
                completion(.failure(MomentsError(message: response.message ?? "Unable to load comments")))
                return
            }
            self.comments = response.data?.rows ?? []
            completion(.success(()))
        }
    }

    func addComment(_ text: String, completion: @escaping (Result<MomentsComment, MomentsError>) -> Void) {
        let body = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCommentLength))
        guard !body.isEmpty, !isSending else { return }
        isSending = true
        respond { [weak self] in
            guard let self else { return }
            self.isSending = false
            let response = self.store.addComment(vibeId: self.vibeId, body: body)
            guard response.success == true, let comment = response.data else {
                completion(.failure(MomentsError(message: response.message ?? "Unable to post comment")))
                return
            }
            self.comments.insert(comment, at: 0)
            completion(.success(comment))
        }
    }
}
