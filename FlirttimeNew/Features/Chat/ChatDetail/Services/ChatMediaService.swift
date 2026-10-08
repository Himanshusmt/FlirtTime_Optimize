//
//  ChatMediaService.swift
//  FlirttimeNew
//
//  Created by Awais on 25/09/25.
//

import Foundation
import Combine

protocol ChatMediaServiceProtocol {
    func refreshMediaURLs(for messages: [ConversationMessage], conversationId: String) -> AnyPublisher<[ConversationMessage], Error>
    func refreshMediaForMessage(_ messageId: String, conversationId: String) -> AnyPublisher<ConversationMessage?, Error>
    func hasMediaURLChanges(existing: ConversationMessage, fresh: ConversationMessage) -> Bool
    func clearMediaCaches()
}

class ChatMediaService: ChatMediaServiceProtocol {

    private let sessionManager: SessionManager
    private var cachedWavDataByMessageId: [String: Data] = [:]

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    func refreshMediaURLs(for messages: [ConversationMessage], conversationId: String) -> AnyPublisher<[ConversationMessage], Error> {
        let limit = max(20, min(100, messages.count + 10))

        return Future<[ConversationMessage], Error> { [weak self] promise in
            Task {
                do {
                    guard let self = self else {
                        promise(.failure(NSError(domain: "ChatMediaService", code: -1)))
                        return
                    }
                    let response = try await self.getConversationMessagesAsync(
                        conversationId: conversationId,
                        page: 1,
                        limit: limit
                    )
                    promise(.success(response.data.data.messages))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func refreshMediaForMessage(_ messageId: String, conversationId: String) -> AnyPublisher<ConversationMessage?, Error> {
        return Future<ConversationMessage?, Error> { [weak self] promise in
            Task {
                do {
                    guard let self = self else {
                        promise(.failure(NSError(domain: "ChatMediaService", code: -1)))
                        return
                    }
                    let response = try await self.getConversationMessagesAsync(
                        conversationId: conversationId,
                        page: 1,
                        limit: 50
                    )
                    let message = response.data.data.messages.first { $0.id == messageId }
                    promise(.success(message))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    private func getConversationMessagesAsync(conversationId: String, page: Int, limit: Int) async throws -> ConversationMessagesResponse {
        try await withCheckedThrowingContinuation { continuation in
            sessionManager.getConversationMessages(conversationId: conversationId, page: page, limit: limit)
                .subscribe(onSuccess: { response in
                    continuation.resume(returning: response)
                }, onFailure: { error in
                    continuation.resume(throwing: error)
                })
        }
    }

    func hasMediaURLChanges(existing: ConversationMessage, fresh: ConversationMessage) -> Bool {
        let existingMediaURLs = Set(existing.media?.compactMap { $0.url } ?? [])
        let freshMediaURLs = Set(fresh.media?.compactMap { $0.url } ?? [])

        if existingMediaURLs != freshMediaURLs {
            return true
        }

        if existing.content != fresh.content {
            return true
        }

        return false
    }

    func clearMediaCaches() {
        cachedWavDataByMessageId.removeAll()
    }
}
