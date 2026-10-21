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
        recipientIds: [String]?,
        metadata: [String: Any]?,
        completion: ((Result<ConversationMessage, Error>) -> Void)?
    ) -> Bool

    /// Legacy name — routes through REST (no socket emit).
    func emitMessage(conversationId: String, messageType: String, content: String, replyToId: String?, metadata: [String: Any]?, isMediaAttach: Bool, mediaPath: String?, filename: String?, filesize: String?) -> Bool
}

extension ChatMessageServiceProtocol {
    @discardableResult
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
    ) -> Bool {
        sendViaREST(
            conversationId: conversationId,
            type: type,
            body: body,
            mediaIds: mediaIds,
            location: location,
            poll: poll,
            clientMessageId: clientMessageId,
            replyToId: replyToId,
            recipientIds: nil,
            metadata: nil,
            completion: completion
        )
    }

    @discardableResult
    func sendViaREST(
        conversationId: String,
        type: String,
        body: String?,
        mediaIds: [String]?,
        location: [String: Any]?,
        poll: [String: Any]?,
        clientMessageId: String?,
        replyToId: String?,
        recipientIds: [String]?,
        completion: ((Result<ConversationMessage, Error>) -> Void)?
    ) -> Bool {
        sendViaREST(
            conversationId: conversationId,
            type: type,
            body: body,
            mediaIds: mediaIds,
            location: location,
            poll: poll,
            clientMessageId: clientMessageId,
            replyToId: replyToId,
            recipientIds: recipientIds,
            metadata: nil,
            completion: completion
        )
    }
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
    
    func loadMessagesBeforeAsync(conversationId: String, beforeDate: Date, page: Int = 1, limit: Int = 30) async throws -> ConversationMessagesResponse {
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

    func loadMessagesBefore(conversationId: String, beforeDate: Date, page: Int = 1, limit: Int = 30) -> AnyPublisher<ConversationMessagesResponse, Error> {
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

    /// POST `/api/v1/chats/{id}/messages` for an open thread, or
    /// POST `/api/v1/chat/messages` when sending by recipient.
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
        recipientIds: [String]? = nil,
        metadata: [String: Any]? = nil,
        completion: ((Result<ConversationMessage, Error>) -> Void)? = nil
    ) -> Bool {
        guard sessionManager.user?.userId != nil else {
            AppLogger.debug("[sendViaREST] User ID not available")
            return false
        }
        let peers = (recipientIds ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !conversationId.isEmpty || !peers.isEmpty else {
            AppLogger.debug("[sendViaREST] Empty conversationId and recipientIds")
            return false
        }

        let resolvedType = type.isEmpty ? "text" : type
        if conversationId.isEmpty {
            AppLogger.debug("[sendViaREST] ▶ POST /api/v1/chat/messages type=\(resolvedType) recipients=\(peers.count) clientMessageId=\(clientMessageId ?? "nil")")
        } else {
            AppLogger.debug("[sendViaREST] ▶ POST /api/v1/chats/\(conversationId)/messages type=\(resolvedType) replyToId=\(replyToId ?? "nil") clientMessageId=\(clientMessageId ?? "nil")")
        }

        if !conversationId.isEmpty {
            emitSendMessage(
                conversationId: conversationId,
                type: resolvedType,
                body: body,
                mediaIds: mediaIds,
                location: location,
                clientMessageId: clientMessageId,
                replyToId: replyToId,
                metadata: metadata
            )
        }

        let send: Single<ConversationMessage>
        if conversationId.isEmpty {
            send = sessionManager.sendDirectChatMessage(
                recipientIds: peers,
                type: resolvedType,
                content: body ?? mediaIds?.first,
                location: location,
                metadata: metadata,
                clientMessageId: clientMessageId
            )
        } else {
            send = sessionManager.sendChatMessage(
                conversationId: conversationId,
                body: body,
                type: resolvedType,
                mediaIds: mediaIds,
                location: location,
                poll: poll,
                postId: nil,
                clientMessageId: clientMessageId,
                replyToId: replyToId,
                metadata: metadata
            )
        }
        send
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

    /// FlirtTime — emit `chat:send_message` so the peer gets `chat:message_received` live.
    /// Image handler accepts `imageUrl`, `image`, or a `data:image/...;base64,` URI.
    private func emitSendMessage(
        conversationId: String,
        type: String,
        body: String?,
        mediaIds: [String]?,
        location: [String: Any]?,
        clientMessageId: String?,
        replyToId: String?,
        metadata: [String: Any]?
    ) {
        let payload = Self.chatSendMessagePayload(
            conversationId: conversationId,
            type: type,
            body: body,
            mediaIds: mediaIds,
            location: location,
            clientMessageId: clientMessageId,
            replyToId: replyToId,
            metadata: metadata
        )
        AppLogger.debug("[sendViaREST] emit chat:send_message conversationId=\(conversationId) type=\(type)")
        ChatSocketManager.shared.emitMessage(SocketEvent.sendConversationMessage.rawValue, withData: [payload])
    }

    static func emitImageSendMessage(
        conversationId: String,
        imageUrl: String?,
        image: String? = nil,
        fileData: Data? = nil,
        mimeType: String = "image/jpeg",
        content: String? = nil,
        clientMessageId: String? = nil,
        replyToId: String? = nil,
        thumbnailUrl: String? = nil
    ) {
        guard !conversationId.isEmpty else { return }
        var metadata: [String: Any] = ["source": "photo"]
        if let thumbnailUrl, !thumbnailUrl.isEmpty { metadata["thumbnailUrl"] = thumbnailUrl }
        if let imageUrl, !imageUrl.isEmpty { metadata["imageUrl"] = imageUrl }
        let payload = chatSendMessagePayload(
            conversationId: conversationId,
            type: "image",
            body: content,
            mediaIds: content.map { [$0] },
            location: nil,
            clientMessageId: clientMessageId,
            replyToId: replyToId,
            metadata: metadata,
            fileData: fileData,
            mimeType: mimeType,
            imageOverride: image,
            imageUrlOverride: imageUrl
        )
        AppLogger.debug("[SOCKET] emit chat:send_message image conversationId=\(conversationId)")
        ChatSocketManager.shared.emitMessage(SocketEvent.sendConversationMessage.rawValue, withData: [payload])
    }

    static func chatSendMessagePayload(
        conversationId: String,
        type: String,
        body: String?,
        mediaIds: [String]?,
        location: [String: Any]?,
        clientMessageId: String?,
        replyToId: String?,
        metadata: [String: Any]?,
        fileData: Data? = nil,
        mimeType: String = "image/jpeg",
        imageOverride: String? = nil,
        imageUrlOverride: String? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "conversationId": conversationId,
            "messageType": type,
            "type": type
        ]
        if let body, !body.isEmpty { payload["content"] = body }
        if let first = mediaIds?.first, !first.isEmpty, payload["content"] == nil {
            payload["content"] = first
        }

        var meta = metadata ?? [:]
        if type.lowercased() == "location", let location {
            if let lat = location["latitude"] ?? location["lat"] { meta["latitude"] = lat }
            if let lng = location["longitude"] ?? location["lng"] { meta["longitude"] = lng }
            if let name = location["name"] { meta["name"] = name }
            if let address = location["address"] { meta["address"] = address }
            if meta["name"] == nil, let address = location["address"] { meta["name"] = address }
        }

        if type.lowercased() == "image" {
            if meta["source"] == nil { meta["source"] = "photo" }
            let resolvedImageURL = resolvedImageSocketURL(
                override: imageUrlOverride,
                metadata: meta,
                content: payload["content"] as? String,
                fileData: fileData,
                mimeType: mimeType
            )
            if let resolvedImageURL {
                payload["imageUrl"] = resolvedImageURL
                payload["image"] = imageOverride ?? resolvedImageURL
                if payload["content"] == nil {
                    payload["content"] = resolvedImageURL
                }
            } else if let imageOverride, !imageOverride.isEmpty {
                payload["image"] = imageOverride
                payload["imageUrl"] = imageOverride
            }
        }

        if !meta.isEmpty { payload["metadata"] = meta }
        if let clientMessageId, !clientMessageId.isEmpty { payload["clientMessageId"] = clientMessageId }
        if let replyToId, !replyToId.isEmpty { payload["replyToId"] = replyToId }
        return payload
    }

    private static func resolvedImageSocketURL(
        override: String?,
        metadata: [String: Any],
        content: String?,
        fileData: Data?,
        mimeType: String
    ) -> String? {
        let candidates = [
            override,
            metadata["imageUrl"] as? String,
            metadata["mediaUrl"] as? String,
            metadata["publicUrl"] as? String,
            metadata["image"] as? String,
            content
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        if let http = candidates.first(where: { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") || $0.lowercased().hasPrefix("data:image") }) {
            return http
        }
        if let first = candidates.first { return first }
        guard let fileData, !fileData.isEmpty else { return nil }
        let mime = mimeType.isEmpty ? "image/jpeg" : mimeType
        return "data:\(mime);base64,\(fileData.base64EncodedString())"
    }
}
