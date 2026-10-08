//
//  ChatMessageService.swift
//  FlirttimeNew
//
//  Created by Awais on 25/09/25.
//

import Foundation
import Combine
import RxSwift

protocol ChatMessageServiceProtocol {
    // Async/await methods (primary API)
    func sendTextMessageAsync(_ text: String, conversationId: String, replyToId: String?) async throws -> Bool
    func sendMediaMessageAsync(mediaPath: String, messageType: String, conversationId: String, filename: String?, filesize: String?, clientTempId: String, metadata: [String: Any]?) async throws -> Bool
    func deleteMessageAsync(messageId: String) async throws
    func deleteMessageAsync(messageId: String, scope: String) async throws
    func deleteMessagesAsync(messageIds: [String], scope: String) async throws
    func loadMessagesAsync(conversationId: String, page: Int, limit: Int) async throws -> ConversationMessagesResponse
    func loadChannelMessagesAsync(channelId: String, page: Int, limit: Int) async throws -> ConversationMessagesResponse
    func loadChannelMessagesBeforeAsync(channelId: String, beforeDate: Date, page: Int, limit: Int) async throws -> ConversationMessagesResponse
    func loadMessagesAfterAsync(conversationId: String, afterDate: Date, limit: Int) async throws -> ConversationMessagesResponse
    func loadMessagesBeforeAsync(conversationId: String, beforeDate: Date, page: Int, limit: Int) async throws -> ConversationMessagesResponse

    // Combine publishers (for backward compatibility)
    func sendTextMessage(_ text: String, conversationId: String, replyToId: String?) -> AnyPublisher<Bool, Error>
    func sendMediaMessage(mediaPath: String, messageType: String, conversationId: String, filename: String?, filesize: String?, clientTempId: String, metadata: [String: Any]?) -> AnyPublisher<Bool, Error>
    func deleteMessage(messageId: String) -> AnyPublisher<Void, Error>
    func deleteMessage(messageId: String, scope: String) -> AnyPublisher<Void, Error>
    func deleteMessages(messageIds: [String], scope: String) -> AnyPublisher<Void, Error>
    func loadMessages(conversationId: String, page: Int, limit: Int) -> AnyPublisher<ConversationMessagesResponse, Error>
    func loadChannelMessages(channelId: String, page: Int, limit: Int) -> AnyPublisher<ConversationMessagesResponse, Error>
    func loadChannelMessagesBefore(channelId: String, beforeDate: Date, page: Int, limit: Int) -> AnyPublisher<ConversationMessagesResponse, Error>
    func loadChannelMessagesAfter(channelId: String, afterDate: Date, limit: Int) -> AnyPublisher<ConversationMessagesResponse, Error>
    func loadMessagesAfter(conversationId: String, afterDate: Date, limit: Int) -> AnyPublisher<ConversationMessagesResponse, Error>
    func loadMessagesBefore(conversationId: String, beforeDate: Date, page: Int, limit: Int) -> AnyPublisher<ConversationMessagesResponse, Error>

    /// REST send (FE `sendChatMessage`). Returns true if the request was started.
    func sendViaREST(
        conversationId: String,
        type: String,
        body: String?,
        mediaIds: [String]?,
        location: [String: Any]?,
        poll: [String: Any]?,
        clientMessageId: String?,
        replyToId: String?,
        completion: ((Result<ConversationMessage, Error>) -> Void)?
    ) -> Bool

    /// Legacy name — routes through REST (no socket emit).
    func emitMessage(conversationId: String, messageType: String, content: String, replyToId: String?, metadata: [String: Any]?, isMediaAttach: Bool, mediaPath: String?, filename: String?, filesize: String?) -> Bool
}

class ChatMessageService: ChatMessageServiceProtocol {
    private let sessionManager: SessionManager
    private let userListViewModel: ChatUserListViewModel
    private let disposeBag = DisposeBag()

    init(sessionManager: SessionManager, userListViewModel: ChatUserListViewModel) {
        self.sessionManager = sessionManager
        self.userListViewModel = userListViewModel
    }

    // MARK: - Async/Await Methods (Primary)

    func sendTextMessageAsync(_ text: String, conversationId: String, replyToId: String?) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            let started = sendViaREST(
                conversationId: conversationId,
                type: "text",
                body: text,
                mediaIds: nil,
                location: nil,
                poll: nil,
                clientMessageId: nil,
                replyToId: replyToId
            ) { result in
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            if !started {
                continuation.resume(returning: false)
            }
        }
    }

    func sendMediaMessageAsync(mediaPath: String, messageType: String, conversationId: String, filename: String?, filesize: String?, clientTempId: String, metadata: [String: Any]? = nil) async throws -> Bool {
        let replyToId = metadata?["reply_to_id"] as? String
        var mediaIds: [String]?
        if let mediaId = metadata?["mediaId"] as? String, !mediaId.isEmpty {
            mediaIds = [mediaId]
        } else if let ids = metadata?["mediaIds"] as? [String], !ids.isEmpty {
            mediaIds = ids
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            let started = sendViaREST(
                conversationId: conversationId,
                type: messageType,
                body: nil,
                mediaIds: mediaIds,
                location: nil,
                poll: nil,
                clientMessageId: clientTempId,
                replyToId: replyToId
            ) { result in
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            if !started {
                continuation.resume(returning: false)
            }
        }
    }
    
    func deleteMessageAsync(messageId: String) async throws {
        try await deleteMessagesAsync(messageIds: [messageId], scope: "me")
    }

    func deleteMessageAsync(messageId: String, scope: String) async throws {
        try await deleteMessagesAsync(messageIds: [messageId], scope: scope)
    }

    /// POST `chat/messages/delete` — `{ messageIds, scope: "me"|"everyone" }`
    func deleteMessagesAsync(messageIds: [String], scope: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionManager.deleteChatMessages(messageIds: messageIds, scope: scope)
                .subscribe(onSuccess: {
                    continuation.resume()
                }, onFailure: { error in
                    continuation.resume(throwing: error)
                })
                .disposed(by: disposeBag)
        }
    }
    
    func loadMessagesAsync(conversationId: String, page: Int, limit: Int) async throws -> ConversationMessagesResponse {
        try await withCheckedThrowingContinuation { continuation in
            sessionManager.getConversationMessages(conversationId: conversationId, page: page, limit: limit)
                .subscribe(onSuccess: { response in
                    continuation.resume(returning: response)
                }, onFailure: { error in
                    continuation.resume(throwing: error)
                })
        }
    }
    
    func loadChannelMessagesAsync(channelId: String, page: Int, limit: Int) async throws -> ConversationMessagesResponse {
        try await withCheckedThrowingContinuation { continuation in
            sessionManager.getChannelMessages(channelId: channelId, page: page, limit: limit)
                .subscribe(onSuccess: { response in
                    continuation.resume(returning: response)
                }, onFailure: { error in
                    continuation.resume(throwing: error)
                })
        }
    }

    func loadChannelMessagesBeforeAsync(channelId: String, beforeDate: Date, page: Int = 1, limit: Int = 20) async throws -> ConversationMessagesResponse {
        try await withCheckedThrowingContinuation { continuation in
            sessionManager.getChannelMessagesBefore(channelId: channelId, beforeDate: beforeDate, page: page, limit: limit)
                .subscribe(onSuccess: { response in
                    continuation.resume(returning: response)
                }, onFailure: { error in
                    continuation.resume(throwing: error)
                })
        }
    }
    
    func loadMessagesAfterAsync(conversationId: String, afterDate: Date, limit: Int = 100) async throws -> ConversationMessagesResponse {
        try await withCheckedThrowingContinuation { continuation in
            sessionManager.getConversationMessagesAfter(conversationId: conversationId, afterDate: afterDate, limit: limit)
                .subscribe(onSuccess: { response in
                    print(response,"--->>")
                    continuation.resume(returning: response)
                }, onFailure: { error in
                    continuation.resume(throwing: error)
                })
        }
    }
    
    func loadMessagesBeforeAsync(conversationId: String, beforeDate: Date, page: Int = 1, limit: Int = 20) async throws -> ConversationMessagesResponse {
        try await withCheckedThrowingContinuation { continuation in
            sessionManager.getConversationMessagesBefore(conversationId: conversationId, beforeDate: beforeDate, page: page, limit: limit)
                .subscribe(onSuccess: { response in
                    continuation.resume(returning: response)
                }, onFailure: { error in
                    continuation.resume(throwing: error)
                })
        }
    }

    // MARK: - Combine Publisher Methods (Backward Compatibility)

    func sendTextMessage(_ text: String, conversationId: String, replyToId: String?) -> AnyPublisher<Bool, Error> {
        Future<Bool, Error> { promise in
            let started = self.sendViaREST(
                conversationId: conversationId,
                type: "text",
                body: text,
                mediaIds: nil,
                location: nil,
                poll: nil,
                clientMessageId: nil,
                replyToId: replyToId
            ) { result in
                switch result {
                case .success:
                    promise(.success(true))
                case .failure(let error):
                    promise(.failure(error))
                }
            }
            if !started {
                promise(.success(false))
            }
        }
        .eraseToAnyPublisher()
    }

    func sendMediaMessage(mediaPath: String, messageType: String, conversationId: String, filename: String?, filesize: String?, clientTempId: String, metadata: [String: Any]? = nil) -> AnyPublisher<Bool, Error> {
        Future<Bool, Error> { promise in
            let replyToId = metadata?["reply_to_id"] as? String
            var mediaIds: [String]?
            if let mediaId = metadata?["mediaId"] as? String, !mediaId.isEmpty {
                mediaIds = [mediaId]
            } else if let ids = metadata?["mediaIds"] as? [String], !ids.isEmpty {
                mediaIds = ids
            }

            let started = self.sendViaREST(
                conversationId: conversationId,
                type: messageType,
                body: nil,
                mediaIds: mediaIds,
                location: nil,
                poll: nil,
                clientMessageId: clientTempId,
                replyToId: replyToId
            ) { result in
                switch result {
                case .success(let message):
                    // Notify detail VMs that may be waiting on ack-style replacement
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ChatRESTMessageSent"),
                        object: nil,
                        userInfo: ["tempId": clientTempId, "message": message]
                    )
                    promise(.success(true))
                case .failure(let error):
                    promise(.failure(error))
                }
            }
            if !started {
                promise(.success(false))
            }
        }
        .eraseToAnyPublisher()
    }

    func deleteMessage(messageId: String) -> AnyPublisher<Void, Error> {
        deleteMessages(messageIds: [messageId], scope: "me")
    }

    func deleteMessage(messageId: String, scope: String) -> AnyPublisher<Void, Error> {
        deleteMessages(messageIds: [messageId], scope: scope)
    }

    /// POST `chat/messages/delete` — `{ messageIds, scope: "me"|"everyone" }`
    func deleteMessages(messageIds: [String], scope: String) -> AnyPublisher<Void, Error> {
        Future<Void, Error> { promise in
            Task {
                do {
                    try await self.deleteMessagesAsync(messageIds: messageIds, scope: scope)
                    promise(.success(()))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func loadMessages(conversationId: String, page: Int, limit: Int) -> AnyPublisher<ConversationMessagesResponse, Error> {
        Future<ConversationMessagesResponse, Error> { promise in
            Task {
                do {
                    let response = try await self.loadMessagesAsync(conversationId: conversationId, page: page, limit: limit)
                    promise(.success(response))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func loadChannelMessages(channelId: String, page: Int, limit: Int) -> AnyPublisher<ConversationMessagesResponse, Error> {
        Future<ConversationMessagesResponse, Error> { promise in
            Task {
                do {
                    let response = try await self.loadChannelMessagesAsync(channelId: channelId, page: page, limit: limit)
                    promise(.success(response))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func loadChannelMessagesBefore(channelId: String, beforeDate: Date, page: Int = 1, limit: Int = 20) -> AnyPublisher<ConversationMessagesResponse, Error> {
        Future<ConversationMessagesResponse, Error> { promise in
            Task {
                do {
                    let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ConversationMessagesResponse, Error>) in
                        self.sessionManager.getChannelMessagesBefore(channelId: channelId, beforeDate: beforeDate, page: page, limit: limit)
                            .subscribe(onSuccess: { continuation.resume(returning: $0) }, onFailure: { continuation.resume(throwing: $0) })
                    }
                    promise(.success(response))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func loadChannelMessagesAfter(channelId: String, afterDate: Date, limit: Int = 100) -> AnyPublisher<ConversationMessagesResponse, Error> {
        Future<ConversationMessagesResponse, Error> { promise in
            Task {
                do {
                    let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ConversationMessagesResponse, Error>) in
                        self.sessionManager.getChannelMessagesAfter(channelId: channelId, afterDate: afterDate, limit: limit)
                            .subscribe(onSuccess: { continuation.resume(returning: $0) }, onFailure: { continuation.resume(throwing: $0) })
                    }
                    promise(.success(response))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func loadMessagesAfter(conversationId: String, afterDate: Date, limit: Int = 100) -> AnyPublisher<ConversationMessagesResponse, Error> {
        Future<ConversationMessagesResponse, Error> { promise in
            Task {
                do {
                    let response = try await self.loadMessagesAfterAsync(conversationId: conversationId, afterDate: afterDate, limit: limit)
                    promise(.success(response))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func loadMessagesBefore(conversationId: String, beforeDate: Date, page: Int = 1, limit: Int = 20) -> AnyPublisher<ConversationMessagesResponse, Error> {
        Future<ConversationMessagesResponse, Error> { promise in
            Task {
                do {
                    let response = try await self.loadMessagesBeforeAsync(conversationId: conversationId, beforeDate: beforeDate, page: page, limit: limit)
                    promise(.success(response))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    // MARK: - REST Send (FE sendChatMessage)

    /// POST `/api/v1/chat/messages` — primary send path matching onevibe_frontend-main.
    @discardableResult
    func sendViaREST(
        conversationId: String,
        type: String,
        body: String? = nil,
        mediaIds: [String]? = nil,
        location: [String: Any]? = nil,
        poll: [String: Any]? = nil,
        clientMessageId: String? = nil,
        replyToId: String? = nil,
        completion: ((Result<ConversationMessage, Error>) -> Void)? = nil
    ) -> Bool {
        guard sessionManager.user?.userId != nil else {
            AppLogger.debug("[sendViaREST] User ID not available")
            return false
        }
        guard !conversationId.isEmpty else {
            AppLogger.debug("[sendViaREST] Empty conversationId")
            return false
        }

        let resolvedType = type.isEmpty ? "text" : type
        AppLogger.debug("[sendViaREST] ▶ POST chat/messages conversationId=\(conversationId) type=\(resolvedType) replyToId=\(replyToId ?? "nil") clientMessageId=\(clientMessageId ?? "nil")")

        sessionManager.sendChatMessage(
            conversationId: conversationId,
            body: body,
            type: resolvedType,
            mediaIds: mediaIds,
            location: location,
            poll: poll,
            postId: nil,
            clientMessageId: clientMessageId,
            replyToId: replyToId
        )
        .subscribe(onSuccess: { message in
            var msg = message
            // Ensure optimistic match key survives round-trip
            if let clientMessageId, !clientMessageId.isEmpty {
                var meta = msg.metadata ?? [:]
                if meta["clientTempId"] == nil {
                    meta["clientTempId"] = AnyCodable(clientMessageId)
                    msg.metadata = meta
                }
            }
            let statusLower = (msg.status ?? "").lowercased()
            if statusLower.isEmpty || statusLower == "sending" || statusLower == "pending" {
                msg.status = "sent"
            }
            AppLogger.debug("[sendViaREST] ✅ id=\(msg.id) temp=\(clientMessageId ?? "") replyPreview=\(msg.replyToId?.id ?? "nil")")
            DispatchQueue.main.async {
                completion?(.success(msg))
            }
        }, onFailure: { error in
            AppLogger.debug("[sendViaREST] ❌ \(error.localizedDescription)")
            DispatchQueue.main.async {
                completion?(.failure(error))
            }
        })
        .disposed(by: disposeBag)

        return true
    }

    /// Routes through REST — kept for call-site compatibility.
    @discardableResult
    func emitMessage(conversationId: String, messageType: String, content: String, replyToId: String?, metadata: [String: Any]?, isMediaAttach: Bool = false, mediaPath: String? = nil, filename: String? = nil, filesize: String? = nil) -> Bool {
        let clientMsgId = (metadata?["clientTempId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var mediaIds: [String]?
        if isMediaAttach {
            if let mediaId = metadata?["mediaId"] as? String, !mediaId.isEmpty {
                mediaIds = [mediaId]
            } else if let ids = metadata?["mediaIds"] as? [String], !ids.isEmpty {
                mediaIds = ids
            }
        }

        let location = metadata?["location"] as? [String: Any]
        let poll = metadata?["poll"] as? [String: Any]

        return sendViaREST(
            conversationId: conversationId,
            type: messageType.isEmpty ? "text" : messageType,
            body: content.isEmpty ? nil : content,
            mediaIds: mediaIds,
            location: location,
            poll: poll,
            clientMessageId: clientMsgId,
            replyToId: replyToId,
            completion: nil
        )
    }
}
