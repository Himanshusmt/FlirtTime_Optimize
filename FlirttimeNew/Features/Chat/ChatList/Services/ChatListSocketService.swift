//
//  ChatListSocketService.swift
//  FlirttimeNew
//
//  Created by Awais on 29/09/2025.
//

import Foundation
import Combine
import Swinject

// MARK: - Event Models

/// Emitted when another user starts or stops typing in a conversation.
struct TypingEvent {
    let conversationId: String
    let userId: String
    let senderName: String
    let isTyping: Bool
}

/// Emitted when message delivery/read status changes for one or more messages.
struct MessageStatusEvent {
    let conversationId: String
    let messageIds: [String]
    let status: String          // "delivered" | "seen" | etc.
    let deliveredTo: [String]
    let seenBy: String?
}

/// Emitted when a new message arrives from the socket (for chat list preview updates).
struct IncomingMessageEvent {
    let conversationId: String
    let message: ConversationMessage
    let rawData: [String: Any]
}

class ChatListSocketService: ObservableObject {
    static let shared = ChatListSocketService()

    // MARK: - Published State
    @Published var onlineUserIds: Set<String> = []

    // MARK: - Combine Publishers (typed, replacing ad-hoc closures)

    /// New or updated message received on any conversation.
    var messageReceived: AnyPublisher<IncomingMessageEvent, Never> {
        _messageReceivedSubject.eraseToAnyPublisher()
    }

    /// A user started or stopped typing in a conversation.
    var typingReceived: AnyPublisher<TypingEvent, Never> {
        _typingSubject.eraseToAnyPublisher()
    }

    /// Message delivery/read status updated for one or more messages.
    var messageStatusUpdated: AnyPublisher<MessageStatusEvent, Never> {
        _messageStatusSubject.eraseToAnyPublisher()
    }

    /// A conversation was deleted.
    var conversationDeleted: AnyPublisher<String, Never> {
        _conversationDeletedSubject.eraseToAnyPublisher()
    }

    /// A new conversation was created.
    var conversationCreated: AnyPublisher<ChatMessageRow, Never> {
        _conversationCreatedSubject.eraseToAnyPublisher()
    }

    /// NEW — `chat:inbox:refresh` soft signal (re-fetch inbox). FE: scheduleRefresh().
    var inboxRefreshNeeded: AnyPublisher<String?, Never> {
        _inboxRefreshSubject.eraseToAnyPublisher()
    }

    /// NEW — `chat:member:added` (conversationId, userIds).
    var memberAdded: AnyPublisher<(conversationId: String, userIds: [String]), Never> {
        _memberAddedSubject.eraseToAnyPublisher()
    }

    /// Conversation settings updated (conversationId, settings dict).
    var settingsUpdated: AnyPublisher<(String, [String: Any]), Never> {
        _settingsUpdatedSubject.eraseToAnyPublisher()
    }

    /// A user's online/offline status changed.
    var userStatusChanged: AnyPublisher<(userId: String, isOnline: Bool), Never> {
        _userStatusSubject.eraseToAnyPublisher()
    }

    // MARK: - Private Subjects

    private let _messageReceivedSubject  = PassthroughSubject<IncomingMessageEvent, Never>()
    private let _typingSubject           = PassthroughSubject<TypingEvent, Never>()
    private let _messageStatusSubject    = PassthroughSubject<MessageStatusEvent, Never>()
    private let _conversationDeletedSubject = PassthroughSubject<String, Never>()
    private let _conversationCreatedSubject = PassthroughSubject<ChatMessageRow, Never>()
    private let _inboxRefreshSubject     = PassthroughSubject<String?, Never>()
    private let _memberAddedSubject      = PassthroughSubject<(conversationId: String, userIds: [String]), Never>()
    private let _settingsUpdatedSubject  = PassthroughSubject<(String, [String: Any]), Never>()
    private let _userStatusSubject       = PassthroughSubject<(userId: String, isOnline: Bool), Never>()
    private let _userBlockUpdatedSubject = PassthroughSubject<(actorId: String, targetId: String, isBlocked: Bool), Never>()

    /// FE `user:blocked` / `user:unblocked` — `{ actorId, targetId, blocked }`
    var userBlockUpdated: AnyPublisher<(actorId: String, targetId: String, isBlocked: Bool), Never> {
        _userBlockUpdatedSubject.eraseToAnyPublisher()
    }

    // MARK: - Internal

    private let chatSocketManager = ChatSocketManager.shared
    private let outgoingAckPersistenceQueue = OutgoingAckPersistenceQueue.shared
    private var eventListenerIds: [UUID] = []
    private var areListenersConfigured = false
    private var isOutgoingAckQueueConfigured = false

    private init() {}

    func setupSocketListeners() {
        configureOutgoingAckQueueIfNeeded()

        guard !areListenersConfigured else { return }

        setupConversationSettingsListener()
        setupUserBlockListeners()
        setupNewMessageListener()
        setupInboxRefreshListener()
        setupGlobalOutgoingMessageAckListener()
        setupDeleteConversationListener()
        setupDeleteConversationPushListener()
        setupCreateConversationListener()
        setupMemberAddedListener()
        setupMemberRemovedListener()
        setupGroupUpdatedListener()
        setupConversationDeletedPushListener()
        setupUserStatusListener()
        setupGetOnlineUsersListener()
        setupTypingListener()

        setupGlobalMessageEditedListener()
        setupGlobalMessageDeletedListener()
        setupGlobalMessageStatusUpdateListener()
        setupDeliveredAndSeenListeners()
        setupGlobalReactionAckListener()
        setupConversationSystemMessageListener()

        areListenersConfigured = true
    }

    func invalidateSocketListeners() {
        removeAllListeners()
        areListenersConfigured = false
        isOutgoingAckQueueConfigured = false
        outgoingAckPersistenceQueue.clearAll()
    }

    func requestOnlineUsers() {
        // FE / socket console: emit `presence:online:list`
        chatSocketManager.emitMessage(SocketEvent.getOnlineUsers.rawValue, withData: [[:]])
        AppLogger.debug("[Presence] Emitted presence:online:list")
    }
    
    func emitSettingsUpdate(conversationId: String, settings: [String: Any]) {
        // FE console sample is flat: `{ conversationId, isMuted, … }` (not nested under `settings`).
        var payload: [String: Any] = ["conversationId": conversationId]
        for (key, value) in settings {
            payload[key] = value
        }
        chatSocketManager.emitMessage(SocketEvent.updateConversationSettings.rawValue, withData: [payload])
    }
    
    func emitDeleteConversation(conversationId: String, forEveryone: Bool = false) {
        let payload: [String: Any] = ["conversationId": conversationId, "forEveryone": forEveryone]
        chatSocketManager.emitMessage(SocketEvent.deleteConversation.rawValue, withData: [payload])
    }

    /// NEW — emit `chat:conversation:create` (c2s). Peers get fanout via inbox:refresh / member:added.
    func emitCreateConversation(
        type: String,
        participantIds: [String],
        title: String? = nil,
        avatarPath: String? = nil,
        requestId: String = UUID().uuidString
    ) {
        var payload: [String: Any] = [
            "requestId": requestId,
            "type": type,
            "participantIds": participantIds
        ]
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["title"] = title
        }
        if let avatarPath, !avatarPath.isEmpty {
            payload["avatarPath"] = avatarPath
        }
        AppLogger.debug("[CreateConversation] emit chat:conversation:create type=\(type) participants=\(participantIds.count) requestId=\(requestId)")
        chatSocketManager.emitMessage(SocketEvent.createConversation.rawValue, withData: [payload])
    }

    /// Waits for matching `chat:conversation:create:ack` (by requestId when present).
    func awaitCreateConversationAck(
        requestId: String,
        timeout: TimeInterval = 12
    ) async -> String? {
        await withCheckedContinuation { continuation in
            var settled = false
            var listenerId: UUID?
            let timeoutItem = DispatchWorkItem {
                guard !settled else { return }
                settled = true
                if let listenerId {
                    ChatSocketManager.shared.offEventById(listenerId)
                }
                AppLogger.debug("[CreateConversation] ack timeout requestId=\(requestId)")
                continuation.resume(returning: nil)
            }

            listenerId = chatSocketManager.listenToEvent(SocketEvent.createConversationAck.rawValue) { data in
                guard !settled else { return }
                guard let payload = data.first as? [String: Any] else { return }

                let ackRequestId = payload["requestId"] as? String
                if let ackRequestId, !ackRequestId.isEmpty, ackRequestId != requestId {
                    return
                }

                let success = payload["success"] as? Bool ?? true
                guard success else { return }

                let dataObj = payload["data"] as? [String: Any]
                let id = (dataObj?["id"] as? String)
                    ?? (payload["id"] as? String)
                    ?? (payload["conversationId"] as? String)
                    ?? ""
                guard !id.isEmpty else { return }

                settled = true
                timeoutItem.cancel()
                if let listenerId {
                    ChatSocketManager.shared.offEventById(listenerId)
                }
                AppLogger.debug("[CreateConversation] ack ok id=\(id) requestId=\(requestId)")
                continuation.resume(returning: id)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
        }
    }

    /// Local nudge after REST group create (creator device). Other users rely on server `chat:inbox:refresh`.
    @MainActor
    func notifyLocalInboxRefresh(reason: String) {
        _inboxRefreshSubject.send(reason)
    }
        
    private func setupConversationSettingsListener() {
        listen(SocketEvent.conversationSettingsUpdated.rawValue) { [weak self] data in
            guard let dataDict = data.first as? [String: Any],
                  let parsed = SocketAckParser.conversationSettings(from: dataDict) else { return }
            Task { @MainActor in
                self?._settingsUpdatedSubject.send((parsed.conversationId, parsed.settings))
            }
        }
    }

    /// FE `user:blocked` / `user:unblocked` — drives chat block overlay without waiting for sync/refresh.
    private func setupUserBlockListeners() {
        listen(SocketEvent.userBlocked.rawValue) { [weak self] data in
            self?.handleUserBlockEvent(data: data, defaultBlocked: true)
        }
        listen(SocketEvent.userUnblocked.rawValue) { [weak self] data in
            self?.handleUserBlockEvent(data: data, defaultBlocked: false)
        }
    }

    private func handleUserBlockEvent(data: [Any], defaultBlocked: Bool) {
        guard let payload = data.first as? [String: Any] else { return }
        let actorId = (payload["actorId"] as? String) ?? (payload["actor_id"] as? String) ?? ""
        let targetId = (payload["targetId"] as? String) ?? (payload["target_id"] as? String) ?? ""
        let isBlocked = SocketAckParser.boolValue(from: payload["blocked"]) ?? defaultBlocked
        guard !actorId.isEmpty, !targetId.isEmpty else { return }
        AppLogger.debug("[UserBlock] socket \(isBlocked ? "blocked" : "unblocked") actor=\(actorId) target=\(targetId)")
        Task { @MainActor in
            self._userBlockUpdatedSubject.send((actorId, targetId, isBlocked))

            // Mirror FE: update local block set + notify open chat detail without waiting for list VM.
            let myId = Container.sharedContainer.resolve(SessionManager.self)?.user?.userId ?? ""
            if actorId == myId {
                if isBlocked {
                    BlockedUsersManager.shared.blockUser(id: targetId)
                } else {
                    BlockedUsersManager.shared.unblockUser(id: targetId)
                }
                NotificationCenter.default.post(
                    name: .ChatBlockStatusChanged,
                    object: nil,
                    userInfo: ["peerUserId": targetId, "isBlocked": isBlocked]
                )
            } else if targetId == myId {
                NotificationCenter.default.post(
                    name: .ChatBlockStatusChanged,
                    object: nil,
                    userInfo: ["peerUserId": actorId, "isBlocked": isBlocked]
                )
            }
        }
    }
    
    private func setupNewMessageListener() {
        listen(SocketEvent.getMessage.rawValue) { [weak self] data in
            guard let self,
                  let raw = data.first as? [String: Any] else { return }
            let messageData = (raw["data"] as? [String: Any]) ?? raw
            guard let message = ConversationMessage.fromDictionary(messageData) else { return }
            let conversationId = message.conversationId
            guard !conversationId.isEmpty else { return }
            AppLogger.debug("[GlobalIngestion] get-message conversation=\(conversationId) id=\(message.id)")
            let event = IncomingMessageEvent(conversationId: conversationId, message: message, rawData: messageData)
            Task { @MainActor in
                self._messageReceivedSubject.send(event)
            }
            Task { [weak self] in await self?.ingestIncomingMessage(message) }
            Self.markDeliveredIfNeeded(message: message)
        }
    }

    /// FE auth-context: on message:new not from self → POST .../delivered + socket delivered
    private static func markDeliveredIfNeeded(message: ConversationMessage) {
        let myId = Container.sharedContainer.resolve(SessionManager.self)?.user?.userId ?? ""
        let senderId = message.senderId ?? message.sender?.id ?? ""
        guard !myId.isEmpty, senderId != myId else { return }
        let conversationId = message.conversationId
        guard !conversationId.isEmpty, !message.id.isEmpty else { return }

        // Console: client may emit chat:message:delivered so sender ticks update live
        ChatSocketManager.shared.emitMessage(
            SocketEvent.messageDelivered.rawValue,
            withData: [[
                "conversationId": conversationId,
                "messageId": message.id
            ]]
        )

        guard let sessionManager = Container.sharedContainer.resolve(SessionManager.self) else { return }
        _ = sessionManager.markConversationDelivered(conversationId: conversationId, messageId: message.id)
            .subscribe(onSuccess: { _ in
                AppLogger.debug("[Delivered] REST ack for \(message.id) in \(conversationId)")
            }, onFailure: { error in
                AppLogger.debug("[Delivered] REST failed: \(error.localizedDescription)")
            })
    }

    /// NEW API — `chat:inbox:refresh` (s2c).
    /// Soft signal to re-fetch inbox when a group is created / ordering changes.
    /// FE: `s.on(INBOX_REFRESH, scheduleRefresh)`.
    private func setupInboxRefreshListener() {
        listen(SocketEvent.messageUpdated.rawValue) { [weak self] data in
            guard let self else { return }
            let payload = data.first as? [String: Any] ?? [:]
            let reason = payload["reason"] as? String

            // Legacy shape (old get-latest-conversation-message) — still ingest if present.
            if let status = payload["status"] as? Bool, status == true,
               let messageData = payload["data"] as? [String: Any],
               let message = ConversationMessage.fromDictionary(messageData) {
                let conversationId = message.conversationId
                guard !conversationId.isEmpty else { return }
                AppLogger.debug("[InboxRefresh] legacy message payload conversation=\(conversationId)")
                let event = IncomingMessageEvent(conversationId: conversationId, message: message, rawData: messageData)
                Task { @MainActor in
                    self._messageReceivedSubject.send(event)
                }
                Task { [weak self] in await self?.ingestIncomingMessage(message) }
                return
            }

            // NEW shape: `{ reason: "message_new" | "conversation_created" | ... , conversationId? }`
            let conversationId = payload["conversationId"] as? String
                ?? (payload["data"] as? [String: Any])?["conversationId"] as? String
            AppLogger.debug("[InboxRefresh] chat:inbox:refresh reason=\(reason ?? "nil") conversationId=\(conversationId ?? "nil") — requesting inbox sync")
            Task { @MainActor in
                if let conversationId, !conversationId.isEmpty {
                    ChatSocketManager.shared.joinConversationRoom(conversationId)
                }
                self._inboxRefreshSubject.send(reason)
            }
        }
    }

    /// NEW — `chat:member:added` when user is added to a group (incl. on create fanout).
    private func setupMemberAddedListener() {
        listen(SocketEvent.memberAdded.rawValue) { [weak self] data in
            guard let payload = data.first as? [String: Any] else { return }
            let body = (payload["data"] as? [String: Any]) ?? payload
            guard let conversationId = body["conversationId"] as? String ?? body["id"] as? String,
                  !conversationId.isEmpty else { return }
            let userIds = (body["userIds"] as? [String])
                ?? (body["userId"] as? String).map { [$0] }
                ?? []
            AppLogger.debug("[MemberAdded] conversation=\(conversationId) users=\(userIds.count)")
            Task { @MainActor in
                // Join room immediately so peer receives subsequent messages (FE joins after list refresh).
                ChatSocketManager.shared.joinConversationRoom(conversationId)
                self?._memberAddedSubject.send((conversationId, userIds))
                // Also nudge inbox refresh so the new group appears without pull-to-refresh
                self?._inboxRefreshSubject.send("member_added")
            }
        }
    }

    /// NEW — `chat:member:removed`
    private func setupMemberRemovedListener() {
        listen(SocketEvent.memberRemoved.rawValue) { [weak self] data in
            guard let payload = data.first as? [String: Any] else { return }
            let body = (payload["data"] as? [String: Any]) ?? payload
            guard let conversationId = body["conversationId"] as? String, !conversationId.isEmpty else { return }
            AppLogger.debug("[MemberRemoved] conversation=\(conversationId)")
            Task { @MainActor in
                self?._inboxRefreshSubject.send("member_removed")
            }
        }
    }

    /// NEW — `chat:group:updated`
    private func setupGroupUpdatedListener() {
        listen(SocketEvent.groupUpdated.rawValue) { [weak self] data in
            guard let payload = data.first as? [String: Any] else { return }
            let body = (payload["data"] as? [String: Any]) ?? payload
            let conversationId = body["conversationId"] as? String ?? ""
            AppLogger.debug("[GroupUpdated] conversation=\(conversationId)")
            Task { @MainActor in
                self?._inboxRefreshSubject.send("group_updated")
            }
        }
    }

    /// NEW — `chat:conversation:deleted` (s2c fanout). Prefer over listening to c2s delete name.
    private func setupConversationDeletedPushListener() {
        listen(SocketEvent.conversationDeletedPush.rawValue) { [weak self] data in
            guard let payload = data.first as? [String: Any] else { return }
            let body = (payload["data"] as? [String: Any]) ?? payload
            guard let conversationId = body["conversationId"] as? String ?? body["id"] as? String,
                  !conversationId.isEmpty else { return }
            AppLogger.debug("[ConversationDeleted] push conversation=\(conversationId)")
            Task { @MainActor in
                self?._conversationDeletedSubject.send(conversationId)
                NotificationCenter.default.post(
                    name: .conversationRemovedByServer,
                    object: nil,
                    userInfo: ["conversationId": conversationId]
                )
            }
        }
    }

    private func setupTypingListener() {
        listen(SocketEvent.userTypingUpdate.rawValue) { [weak self] data in
            guard let raw = data.first as? [String: Any] else { return }
            let payload = raw["data"] as? [String: Any] ?? raw
            guard let conversationId = payload["conversationId"] as? String,
                  let userId = payload["userId"] as? String else { return }
            let senderName = payload["senderName"] as? String ?? payload["userName"] as? String ?? ""
            let isTyping = payload["isTyping"] as? Bool ?? true
            let event = TypingEvent(conversationId: conversationId, userId: userId, senderName: senderName, isTyping: isTyping)
            Task { @MainActor in self?._typingSubject.send(event) }
        }
    }

    private func ingestIncomingMessage(_ message: ConversationMessage) async {
        let conversationId = message.conversationId
        guard !conversationId.isEmpty, !message.id.isEmpty else { return }

        do {
            try await MessageRepository().saveMessages([message], conversationId: conversationId)
            AppLogger.debug("[GlobalIngestion] persisted id=\(message.id) conversation=\(conversationId)")
        } catch {
            AppLogger.debug("[GlobalIngestion] persist failed id=\(message.id): \(error)")
        }

        do {
            try await ConversationRepository().updateLastMessage(conversationId: conversationId, message: message)
        } catch {
            AppLogger.debug("[GlobalIngestion] lastMessage update failed conversation=\(conversationId): \(error)")
        }

        // Process system message side effects (icon_change, title_change, etc.)
        ingestSystemMessageSideEffects(message)

        await MainActor.run {
            ChatDataPreloader.shared.refreshPreload(conversationId: conversationId, newMessages: [message])
        }
    }

    /// Applies avatar/title changes from system messages so the chat list
    /// reflects them immediately without waiting for a full data refresh.
    private func ingestSystemMessageSideEffects(_ message: ConversationMessage) {
        guard let metadata = message.metadata,
              metadata["isSystem"]?.value as? Bool == true else { return }

        let action = metadata["action"]?.value as? String ?? ""
        let conversationId = message.conversationId

        switch action {
        case "icon_change":
            guard let newIcon = metadata["newIcon"]?.value as? String, !newIcon.isEmpty else { return }
            AppLogger.debug("[GlobalIngestion] icon_change conversation=\(conversationId)")
            // Reuse the existing .conversationIconUpdated notification — ChatListViewModel,
            // ChatDetailViewModel, and GroupDetailViewModel all observe it.
            NotificationCenter.default.post(
                name: .conversationIconUpdated,
                object: nil,
                userInfo: ["conversationId": conversationId, "iconURL": newIcon]
            )

        case "title_change":
            guard let newTitle = metadata["newTitle"]?.value as? String, !newTitle.isEmpty else { return }
            AppLogger.debug("[GlobalIngestion] title_change conversation=\(conversationId) title=\(newTitle)")

        default:
            break
        }
    }

    private func setupGlobalOutgoingMessageAckListener() {
        listen(SocketEvent.sendConversationMessageAck.rawValue) { [weak self] data in
            self?.handleOutgoingMessageAck(data: data)
        }
    }

    private func handleOutgoingMessageAck(data: [Any]) {
        guard let message = SocketAckParser.parseMessage(from: data) else {
            return
        }

        let key = outgoingAckPersistenceKey(for: message)
        outgoingAckPersistenceQueue.enqueue(message: message, key: key)
    }

    private func configureOutgoingAckQueueIfNeeded() {
        guard !isOutgoingAckQueueConfigured else { return }
        isOutgoingAckQueueConfigured = true

        outgoingAckPersistenceQueue.configure { [weak self] (message: ConversationMessage) in
            guard let self = self else { return false }
            return await self.persistOutgoingAckMessage(message)
        }
    }

    private func persistOutgoingAckMessage(_ message: ConversationMessage) async -> Bool {
        let conversationId = message.conversationId

        do {
            try await MessageRepository().saveMessages([message], conversationId: conversationId)
        } catch {
            AppLogger.debug("ChatListSocketService: failed to persist outgoing ack message \(message.id): \(error.localizedDescription)")
            return false
        }

        if !conversationId.isEmpty {
            do {
                try await ConversationRepository().updateLastMessage(conversationId: conversationId, message: message)
            } catch {
                AppLogger.debug("ChatListSocketService: failed to update last message for conversation \(conversationId): \(error.localizedDescription)")
                return false
            }

            await MainActor.run {
                ChatDataPreloader.shared.refreshPreload(conversationId: conversationId, newMessages: [message])

                NotificationCenter.default.post(
                    name: NSNotification.Name("ChatLastMessageUpdated"),
                    object: nil,
                    userInfo: ["conversationId": conversationId, "message": message]
                )
            }
        }

        if !message.clientTempId.isEmpty {
            PendingMessageStore.shared.remove(tempId: message.clientTempId)
        }

        return true
    }

    private func outgoingAckPersistenceKey(for message: ConversationMessage) -> String {
        if !message.id.isEmpty {
            return "messageId:\(message.id)"
        }
        if !message.clientTempId.isEmpty {
            return "tempId:\(message.clientTempId)"
        }
        return UUID().uuidString
    }

    private func setupCreateConversationListener() {
        // NEW: chat:conversation:create:ack (and legacy create push). OLD: create-conversation
        let handler: ([Any]) -> Void = { [weak self] data in
            guard let self, let payload = data.first as? [String: Any] else { return }

            // Ack sample: { requestId, success, data: { id } }
            let dataObj = payload["data"] as? [String: Any]
            let conversationDict = dataObj
                ?? (payload["conversation"] as? [String: Any])
                ?? payload

            // Prefer full row decode; otherwise fetch by id so list can upsert.
            if let jsonData = try? JSONSerialization.data(withJSONObject: conversationDict) {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let conversation = try? decoder.decode(ChatMessageRow.self, from: jsonData),
                   let id = conversation.id, !id.isEmpty,
                   conversation.type != nil || conversation.title != nil || conversation.participants != nil {
                    AppLogger.debug("ChatListSocketService: conversation create received for \(id)")
                    Task { @MainActor in
                        self._conversationCreatedSubject.send(conversation)
                    }
                    return
                }
            }

            let id = (conversationDict["id"] as? String)
                ?? (payload["conversationId"] as? String)
                ?? ""
            guard !id.isEmpty else { return }
            AppLogger.debug("ChatListSocketService: create ack id-only \(id) → inbox refresh")
            Task { @MainActor in
                self._inboxRefreshSubject.send("conversation_created")
            }
        }
        listen(SocketEvent.createConversationAck.rawValue, handler: handler)
        // Do not listen to c2s `chat:conversation:create` — peers are notified via
        // `chat:inbox:refresh` / `chat:member:added`, not by echoing the create emit.
    }

    private func setupDeleteConversationPushListener() {
        listen(SocketEvent.deleteConversation.rawValue) { [weak self] data in
            guard let payload = data.first as? [String: Any],
                  let conversationId = payload["id"] as? String ?? payload["conversationId"] as? String,
                  !conversationId.isEmpty else { return }
            AppLogger.debug("ChatListSocketService: delete-conversation push for \(conversationId)")
            Task { @MainActor in
                self?._conversationDeletedSubject.send(conversationId)
                NotificationCenter.default.post(
                    name: .conversationRemovedByServer,
                    object: nil,
                    userInfo: ["conversationId": conversationId]
                )
            }
        }
    }
    
    private func setupDeleteConversationListener() {
        listen(SocketEvent.deleteConversationAck.rawValue) { [weak self] data in
            guard let conversationId = self?.parseDeletedConversationId(from: data) else { return }
            Task { @MainActor in self?._conversationDeletedSubject.send(conversationId) }
        }
    }
    
    private func setupUserStatusListener() {
        listen(SocketEvent.broadcastUserStatus.rawValue) { [weak self] data in
            let payloads: [[String: Any]] = {
                if let dict = data.first as? [String: Any] {
                    if let nested = dict["data"] as? [String: Any] { return [nested] }
                    if let arr = dict["data"] as? [[String: Any]] { return arr }
                    return [dict]
                }
                if let arr = data.first as? [[String: Any]] { return arr }
                return []
            }()

            for dataDict in payloads {
                guard let userId = dataDict["userId"] as? String ?? dataDict["id"] as? String,
                      !userId.isEmpty else { continue }
                let isOnline: Bool = (dataDict["online"] as? Bool)
                    ?? (dataDict["isOnline"] as? Bool)
                    ?? ((dataDict["status"] as? String)?.lowercased() == "online")
                Task { @MainActor in
                    self?._userStatusSubject.send((userId: userId, isOnline: isOnline))
                    self?.updateOnlineStatus(userId: userId, isOnline: isOnline)
                }
            }
        }
    }
    
    @MainActor
    private func updateOnlineStatus(userId: String, isOnline: Bool) {
        if isOnline {
            onlineUserIds.insert(userId)
        } else {
            onlineUserIds.remove(userId)
        }
    }

    /// Shared entry for presence:update from chat detail / list listeners.
    @MainActor
    func applyPresence(userId: String, isOnline: Bool) {
        updateOnlineStatus(userId: userId, isOnline: isOnline)
        _userStatusSubject.send((userId: userId, isOnline: isOnline))
    }

    /// FE `subscribePresence(userIds)` for inbox peers — `presence:get` { userIds }.
    func subscribePresence(userIds: [String]) {
        let ids = Array(Set(userIds.filter { !$0.isEmpty }))
        guard !ids.isEmpty else { return }
        chatSocketManager.emitMessage(SocketEvent.presenceGet.rawValue, withData: [["userIds": ids]])
        AppLogger.debug("[Presence] ChatList presence:get count=\(ids.count)")
    }

    private func setupGetOnlineUsersListener() {
        let handler: ([Any]) -> Void = { [weak self] data in
            let ids = Self.parseOnlineUserIds(from: data)
            Task { @MainActor in
                // Replace the entire set — empty list means all users are offline
                self?.onlineUserIds = Set(ids)
                AppLogger.debug("[Presence] presence:online:list set \(ids.count) online users")
            }
        }
        // Server may reply on `:ack` or echo on the same event name
        listen(SocketEvent.getOnlineUsersAck.rawValue, handler: handler)
        listen(SocketEvent.getOnlineUsers.rawValue, handler: handler)
    }

    private static func parseOnlineUserIds(from data: [Any]) -> [String] {
        func idsFromArray(_ any: Any?) -> [String]? {
            if let arr = any as? [String] { return arr }
            if let arr = any as? [[String: Any]] {
                return arr.compactMap { $0["userId"] as? String ?? $0["id"] as? String ?? $0["_id"] as? String }
            }
            return nil
        }

        if let arr = data.first as? [String] { return arr }
        if let arr = data.first as? [[String: Any]] {
            return arr.compactMap { $0["userId"] as? String ?? $0["id"] as? String ?? $0["_id"] as? String }
        }

        guard let dict = data.first as? [String: Any] else { return [] }

        // Prefer nested `data` when present (common ack envelope)
        let payloads: [[String: Any]] = {
            if let nested = dict["data"] as? [String: Any] { return [nested, dict] }
            if let nestedArr = dict["data"] as? [[String: Any]] {
                return nestedArr + [dict]
            }
            return [dict]
        }()

        for payload in payloads {
            if let ids = idsFromArray(payload["onlineUsers"]) { return ids }
            if let ids = idsFromArray(payload["userIds"]) { return ids }
            if let ids = idsFromArray(payload["users"]) { return ids }
            if let ids = idsFromArray(payload["online"]) { return ids }
            if let ids = idsFromArray(payload["data"]) { return ids }
        }

        // `{ success, data: ["id", ...] }`
        if let ids = idsFromArray(dict["data"]) { return ids }

        return []
    }
    
    private func getConversationId(from messageData: [String: Any]) -> String? {
        return messageData["conversationId"] as? String ??
               messageData["chatUserId"] as? String
    }
    
    private func parseDeletedConversationId(from data: [Any]) -> String? {
        if let dataArray = data.first as? [Any], dataArray.count >= 2 {
            if let ackData = dataArray[1] as? [String: Any],
               let conversationId = ackData["conversationId"] as? String {
                return conversationId
            } else if let conversationId = dataArray[1] as? String {
                return conversationId
            }
        } else if let responseDict = data.first as? [String: Any],
                  let conversationId = responseDict["conversationId"] as? String {
            return conversationId
        } else if let conversationId = data.first as? String {
            return conversationId
        }
        
        return nil
    }
    
    private func listen(_ eventName: String, handler: @escaping ([Any]) -> Void) {
        let id = chatSocketManager.listenToEvent(eventName, completionHandler: handler)
        eventListenerIds.append(id)
    }

    private func removeAllListeners() {
        for id in eventListenerIds {
            chatSocketManager.offEventById(id)
        }
        eventListenerIds.removeAll()
    }

    // MARK: - Global Background Listeners

    private func setupGlobalMessageEditedListener() {
        listen(SocketEvent.messageEdited.rawValue) { data in
            guard let responseData = data.first as? [String: Any] else { return }
            let messageData: [String: Any]?
            if let nested = responseData["data"] as? [String: Any] { messageData = nested }
            else if responseData["id"] != nil { messageData = responseData }
            else { messageData = nil }
            guard let validData = messageData,
                  let message = ConversationMessage.fromDictionary(validData) else { return }
            Task { try? await MessageRepository().updateMessage(message) }
        }
    }

    private func setupGlobalReactionAckListener() {
        let handler: ([Any]) -> Void = { [weak self] data in
            self?.handleGlobalMessageReacted(data: data)
        }
        // Android CHAT_MESSAGE_REACTED + emitter ack
        listen(SocketEvent.messageReacted.rawValue, handler: handler)
        listen(SocketEvent.reactToMessageAck.rawValue, handler: handler)
    }

    /// Persist `chat:message:reacted` onto existing Core Data message (merge-only).
    private func handleGlobalMessageReacted(data: [Any]) {
        guard let responseData = data.first as? [String: Any] else { return }
        let isExplicitFailure: Bool = {
            if let success = responseData["success"] as? Bool { return success == false }
            if let status = responseData["status"] as? Bool { return status == false }
            if let status = responseData["status"] as? Int { return status == 0 }
            return false
        }()
        if isExplicitFailure { return }

        var reactionUpdate = ConversationMessage.reactionUpdate(from: responseData)
        if reactionUpdate?.reactions == nil,
           let delta = ConversationMessage.reactionDelta(from: responseData) {
            var dict: [String: Any] = ["id": delta.messageId]
            if let cid = delta.conversationId { dict["conversationId"] = cid }
            dict["metadata"] = [
                "_reactionDeltaEmoji": delta.emoji,
                "_reactionDeltaUserId": delta.userId
            ]
            reactionUpdate = ConversationMessage.fromDictionary(dict) ?? reactionUpdate
        }

        guard let reactionUpdate, !reactionUpdate.id.isEmpty else { return }

        Task {
            let repository = MessageRepository()
            guard var existing = try? await repository.getMessage(id: reactionUpdate.id) else { return }

            if reactionUpdate.reactions != nil || reactionUpdate.reactionsWrapper != nil {
                existing.withReactions(reactionUpdate.reactions)
            } else if let emoji = reactionUpdate.metadata?["_reactionDeltaEmoji"]?.value as? String,
                      let userId = reactionUpdate.metadata?["_reactionDeltaUserId"]?.value as? String,
                      !emoji.isEmpty, !userId.isEmpty {
                existing.withReactions(
                    ConversationMessage.applyingReactionDelta(
                        existing.reactions ?? [],
                        emoji: emoji,
                        userId: userId
                    )
                )
            } else {
                return
            }

            if let updatedAt = reactionUpdate.updatedAt, !updatedAt.isEmpty {
                existing.updatedAt = updatedAt
            }
            try? await repository.updateMessage(existing)

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .ChatMessageReacted,
                    object: nil,
                    userInfo: [
                        "messageId": existing.id,
                        "conversationId": existing.conversationId,
                        "message": existing
                    ]
                )
            }
        }
    }

    private func setupGlobalMessageDeletedListener() {
        listen(SocketEvent.messageDeleted.rawValue) { data in
            guard let responseData = data.first as? [String: Any] else { return }
            let validData = (responseData["data"] as? [String: Any]) ?? responseData

            // FE: `{ conversationId, messageId, scope, actorId }` — peers only care about everyone.
            let scope = (
                (validData["scope"] as? String)
                ?? (responseData["scope"] as? String)
                ?? "everyone"
            ).lowercased()
            guard scope == "everyone" else { return }

            let conversationId = validData["conversationId"] as? String
                ?? responseData["conversationId"] as? String
                ?? ""

            var deletedIds: [String] = []
            if let ids = validData["deletedIds"] as? [String] {
                deletedIds = ids.filter { !$0.isEmpty }
            } else if let ids = validData["deletedIds"] as? [Any] {
                deletedIds = ids.compactMap { $0 as? String }.filter { !$0.isEmpty }
            } else if let ids = validData["messageIds"] as? [String] {
                deletedIds = ids.filter { !$0.isEmpty }
            } else if let messageId = (validData["messageId"] as? String)
                ?? (validData["id"] as? String)
                ?? (responseData["messageId"] as? String),
                !messageId.isEmpty {
                deletedIds = [messageId]
            }

            guard !deletedIds.isEmpty else { return }

            let deletedContent = ChatStrings.chat_messageDeleted.localizedString()
            AppLogger.debug(
                "[MessageDeleted] global scope=everyone conversation=\(conversationId) ids=\(deletedIds.count)"
            )

            Task {
                let repository = MessageRepository()
                try? await repository.markMessagesDeletedForEveryone(
                    ids: deletedIds,
                    conversationId: conversationId.isEmpty ? nil : conversationId,
                    deletedContent: deletedContent
                )
            }

            // Update preload on main so reopen does not restore original bodies.
            Task { @MainActor in
                if !conversationId.isEmpty {
                    ChatDataPreloader.shared.markMessagesDeletedForEveryone(
                        conversationId: conversationId,
                        messageIds: deletedIds,
                        deletedContent: deletedContent
                    )
                }
            }

            if !conversationId.isEmpty {
                for deletedId in deletedIds {
                    NotificationCenter.default.post(
                        name: .ChatLastMessageDeleted,
                        object: nil,
                        userInfo: ["conversationId": conversationId, "messageId": deletedId]
                    )
                }
            }
        }
    }

    private func setupGlobalMessageStatusUpdateListener() {
        listen(SocketEvent.conversationMessageStatusUpdate.rawValue) { [weak self] data in
            guard let root = data.first as? [String: Any] else { return }
            let payload = (root["data"] as? [String: Any]) ?? root
            let statusString = (payload["status"] as? String)
                ?? (payload["receiptStatus"] as? String)
                ?? (root["status"] as? String)
                ?? ""
            guard !statusString.isEmpty else { return }

            var messageIds: [String] = []
            if let mid = payload["messageId"] as? String, !mid.isEmpty {
                messageIds = [mid]
            } else if let mid = root["messageId"] as? String, !mid.isEmpty {
                messageIds = [mid]
            } else if let ids = payload["messageIds"] as? [String] {
                messageIds = ids.filter { !$0.isEmpty }
            } else if let ids = root["messageIds"] as? [String] {
                messageIds = ids.filter { !$0.isEmpty }
            }
            guard !messageIds.isEmpty else { return }

            let conversationId = (payload["conversationId"] as? String)
                ?? (root["conversationId"] as? String)
                ?? ""
            let deliveredTo = payload["deliveredTo"] as? [String] ?? []
            let seenBy = (payload["seenBy"] as? String)
                ?? (payload["readerId"] as? String)

            // Emit typed publisher for any subscriber (chat list, chat detail, etc.)
            let statusEvent = MessageStatusEvent(
                conversationId: conversationId,
                messageIds: messageIds,
                status: statusString,
                deliveredTo: deliveredTo,
                seenBy: seenBy
            )
            Task { @MainActor in self?._messageStatusSubject.send(statusEvent) }

            // Also update CoreData for persistence
            let newStatus = MessageDeliveryStatus.from(statusString)
            guard newStatus != .unknown else { return }

            let repo = MessageRepository()
            Task {
                for messageId in messageIds {
                    guard let existing = try? await repo.getMessage(id: messageId) else { continue }

                    let currentStatus = MessageDeliveryStatus.from(
                        status: existing.status,
                        sentAt: existing.sentAt,
                        deliveredAt: existing.deliveredAt,
                        seenAt: existing.seenAt
                    )
                    guard newStatus > currentStatus else { continue }

                    let updated = existing.withStatus(newStatus)
                    try? await repo.saveMessages([updated], conversationId: existing.conversationId)

                    let convId = existing.conversationId ?? ""
                    if !convId.isEmpty {
                        await ConversationRepository().updateLastMessageStatusIfLatest(
                            conversationId: convId,
                            messageId: messageId,
                            status: updated.status ?? statusString
                        )
                        await MainActor.run {
                            if let cached = ChatDataPreloader.shared.getPreloadedMessages(for: convId) {
                                let refreshed = cached.map { $0.id == messageId ? updated : $0 }
                                ChatDataPreloader.shared.setPreloadedMessages(for: convId, messages: refreshed)
                            }
                        }
                    }
                }
            }
        }
    }

    /// FE: chat:message:delivered / chat:message:status → update ticks for own messages.
    /// Note: chat:message:seen is c2s-only per console; sender ticks come from status.
    private func setupDeliveredAndSeenListeners() {
        listen(SocketEvent.messageDelivered.rawValue) { [weak self] data in
            self?.handleReceiptEvent(data: data, status: "delivered")
        }
        listen(SocketEvent.conversationMessageStatusUpdate.rawValue) { [weak self] data in
            guard let root = data.first as? [String: Any] else { return }
            let payload = (root["data"] as? [String: Any]) ?? root
            let status = (payload["status"] as? String)
                ?? (payload["receiptStatus"] as? String)
                ?? ""
            guard !status.isEmpty else { return }
            self?.handleReceiptEvent(data: data, status: status)
        }
    }

    private func handleReceiptEvent(data: [Any], status: String) {
        guard let root = data.first as? [String: Any] else { return }
        let payload = (root["data"] as? [String: Any]) ?? root
        let conversationId = (payload["conversationId"] as? String)
            ?? (root["conversationId"] as? String)
            ?? ""
        guard !conversationId.isEmpty else { return }

        let myId = Container.sharedContainer.resolve(SessionManager.self)?.user?.userId ?? ""
        let actorId: String = {
            if status == "delivered" {
                return (payload["delivererId"] as? String) ?? ""
            }
            return (payload["readerId"] as? String)
                ?? (payload["seenBy"] as? String)
                ?? ""
        }()
        if !myId.isEmpty, !actorId.isEmpty, actorId == myId { return }

        var messageIds: [String] = []
        if let mid = payload["messageId"] as? String, !mid.isEmpty {
            messageIds = [mid]
        } else if let ids = payload["messageIds"] as? [String] {
            messageIds = ids.filter { !$0.isEmpty }
        }

        let statusEvent = MessageStatusEvent(
            conversationId: conversationId,
            messageIds: messageIds,
            status: status,
            deliveredTo: [],
            seenBy: status == "seen" ? (actorId.isEmpty ? nil : actorId) : nil
        )
        Task { @MainActor in self._messageStatusSubject.send(statusEvent) }

        // Persist when we have explicit message ids; otherwise Conversation thread handler updates UI
        guard !messageIds.isEmpty else {
            NotificationCenter.default.post(
                name: NSNotification.Name("ChatReceiptStatusUpdated"),
                object: nil,
                userInfo: [
                    "conversationId": conversationId,
                    "status": status,
                    "messageIds": messageIds
                ]
            )
            return
        }

        let newStatus = MessageDeliveryStatus.from(status)
        guard newStatus != .unknown else { return }
        let repo = MessageRepository()
        Task {
            for messageId in messageIds {
                guard let existing = try? await repo.getMessage(id: messageId) else { continue }
                let currentStatus = MessageDeliveryStatus.from(
                    status: existing.status,
                    sentAt: existing.sentAt,
                    deliveredAt: existing.deliveredAt,
                    seenAt: existing.seenAt
                )
                guard newStatus > currentStatus else { continue }
                let updated = existing.withStatus(newStatus)
                try? await repo.saveMessages([updated], conversationId: existing.conversationId)
            }
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("ChatReceiptStatusUpdated"),
                    object: nil,
                    userInfo: [
                        "conversationId": conversationId,
                        "status": status,
                        "messageIds": messageIds
                    ]
                )
            }
        }
    }

    private func setupConversationSystemMessageListener() {
        listen(SocketEvent.conversationSystemMessage.rawValue) { [weak self] data in
            // Server sends: data = [[{message:..., conversationId:...}]]
            let payload: [String: Any] = (data.first as? [Any])?.first as? [String: Any]
                ?? data.first as? [String: Any]
                ?? [:]
            guard !payload.isEmpty else { return }
            guard let self else { return }

            let conversationId = payload["conversationId"] as? String ?? ""
            guard !conversationId.isEmpty else { return }

            // The server sends the system message under the "message" key
            let messageData = (payload["message"] as? [String: Any]) ?? payload
            guard let message = ConversationMessage.fromDictionary(messageData) else { return }

            AppLogger.debug("[GlobalIngestion] conversation-system-message conversation=\(conversationId) action=\(message.metadata?["action"]?.value as? String ?? "unknown")")

            let event = IncomingMessageEvent(conversationId: conversationId, message: message, rawData: messageData)
            Task { @MainActor in
                self._messageReceivedSubject.send(event)
            }
            Task { [weak self] in await self?.ingestIncomingMessage(message) }
        }
    }

}

private extension ConversationMessage {
    var clientTempId: String {
        (metadata?["clientTempId"]?.value as? String)
            ?? ""
    }
}
