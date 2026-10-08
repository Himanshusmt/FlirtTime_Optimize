//
//  ChatSocketService.swift
//  FlirttimeNew
//
//  Created by Awais on 25/09/25.
//

import Foundation
import Combine
import SocketIO
import Swinject

// MARK: - Message Status Update

struct MessageStatusUpdatePayload {
    let conversationId: String
    let messageIds: [String]
    let status: String
    let deliveredTo: [String]
    let seenBy: String?
}

// MARK: - Pin Message Update

struct PinMessageUpdate {
    let messageId: String
    let conversationId: String
    let isPinned: Bool
    let unpinnedMessageIds: [String]
}

// MARK: - Typing Payload

struct TypingPayload {
    let conversationId: String
    let userId: String
    let senderName: String
    let isTyping: Bool
}

protocol ChatSocketServiceProtocol {
    var messageReceived: AnyPublisher<ConversationMessage, Never> { get }
    var messageAcknowledged: AnyPublisher<ConversationMessage, Never> { get }
    /// Reaction ack / `chat:message:reacted` — merge onto existing message only (never insert).
    var messageReactionUpdated: AnyPublisher<ConversationMessage, Never> { get }
    var messageEdited: AnyPublisher<ConversationMessage, Never> { get }
    var messageTranslation: AnyPublisher<ConversationMessage, Never> { get }
    var messageDeleted: AnyPublisher<ConversationMessage, Never> { get }
    var pinMessageUpdate: AnyPublisher<PinMessageUpdate, Never> { get }
    var forwardMessageAck: AnyPublisher<[String: Any], Never> { get }
    var conversationSettingsUpdated: AnyPublisher<[String: Any], Never> { get }
    var conversationDeleted: AnyPublisher<String, Never> { get }
    // Channel
    var channelMessageReceived: AnyPublisher<ConversationMessage, Never> { get }
    var sendChannelMessageAck: AnyPublisher<[String: Any], Never> { get }
    var channelMessageDeleted: AnyPublisher<ConversationMessage, Never> { get }
    var channelMessageEdited: AnyPublisher<ConversationMessage, Never> { get }

    // Call-related publishers
    var incomingCall: AnyPublisher<[String: Any], Never> { get }
    var joinCall: AnyPublisher<[String: Any], Never> { get }
    var leaveCallAck: AnyPublisher<Void, Never> { get }
    var endCallAck: AnyPublisher<Void, Never> { get }
    var remoteCallEnded: AnyPublisher<[String: Any], Never> { get }
    var createMeetingAck: AnyPublisher<Void, Never> { get }

    // Message status publishers
    var messageStatusUpdate: AnyPublisher<MessageStatusUpdatePayload, Never> { get }

    func startListening()
    func stopListening()
    func emitUserStatus(status: String, conversationId: String, userId: String)
    func listenToEvent(_ event: String, callback: @escaping ([Any]) -> Void)
    func emitMessage(_ event: String, withData data: [String: Any])
    func emitMarkMessagesSeen(conversationId: String)
    func emitMarkMessagesSeen(conversationId: String, messageId: String?)
    func emitMessageDelivered(conversationId: String, messageId: String)
    func emitJoinConversation(_ conversationId: String)
    func emitLeaveConversation(_ conversationId: String)
    func emitJoinChannel(_ channelId: String)
    func emitLeaveChannel(_ channelId: String)
    /// FE / console `channel:message:seen` — mark channel read (and older).
    func emitMarkChannelMessagesSeen(channelId: String, messageId: String?)
    /// FE `subscribePresence` — emit `presence:get` { userIds }
    func emitSubscribePresence(userIds: [String])

    var conversationStatus: AnyPublisher<String, Never> { get }

    func emitGetConversationStatus(conversationId: String)

    /// Set the other user in the current 1-to-1 conversation so broadcast events are filtered.
    func setOtherUserId(_ id: String?)

    /// Peer last-seen / online privacy from user/conversation API — applied to presence:update.
    func setPresencePrivacy(
        lastSeenVisibility: String?,
        onlineVisibility: String?,
        viewerIsContact: Bool
    )

    /// Update only the contact relationship used for `my_contacts` privacy.
    func updateViewerIsContact(_ isContact: Bool)

    // Typing indicator
    var typingReceived: AnyPublisher<TypingPayload, Never> { get }
    func emitTyping(conversationId: String, userId: String)
    func emitStopTyping(conversationId: String, userId: String)

    /// Console `chat:message:pin` — `{ conversationId, messageId, pinned, pinDuration? }`
    func pinMessage(messageId: String, conversationId: String, isPinned: Bool, pinDuration: String?)
}

class ChatSocketService: ChatSocketServiceProtocol {

    // MARK: - Published Properties
    private let messageReceivedSubject = PassthroughSubject<ConversationMessage, Never>()
    private let messageAcknowledgedSubject = PassthroughSubject<ConversationMessage, Never>()
    private let messageReactionUpdatedSubject = PassthroughSubject<ConversationMessage, Never>()
    private let messageEditedSubject = PassthroughSubject<ConversationMessage, Never>()
    private let messageTranslationSubject = PassthroughSubject<ConversationMessage, Never>()
    private let messageDeletedSubject = PassthroughSubject<ConversationMessage, Never>()
    private let pinMessageUpdateSubject = PassthroughSubject<PinMessageUpdate, Never>()
    private let forwardMessageAckSubject = PassthroughSubject<[String: Any], Never>()
    private let conversationSettingsSubject = PassthroughSubject<[String: Any], Never>()
    private let conversationDeletedSubject = PassthroughSubject<String, Never>()
    // Channel subjects
    private let channelMessageReceivedSubject = PassthroughSubject<ConversationMessage, Never>()
    private let sendChannelMessageAckSubject = PassthroughSubject<[String: Any], Never>()
    private let channelMessageDeletedSubject = PassthroughSubject<ConversationMessage, Never>()
    private let channelMessageEditedSubject = PassthroughSubject<ConversationMessage, Never>()
    
    // Call-related subjects
    private let incomingCallSubject = PassthroughSubject<[String: Any], Never>()
    private let joinCallSubject = PassthroughSubject<[String: Any], Never>()
    private let leaveCallAckSubject = PassthroughSubject<Void, Never>()
    private let endCallAckSubject = PassthroughSubject<Void, Never>()
    private let remoteCallEndedSubject = PassthroughSubject<[String: Any], Never>()
    private let createMeetingAckSubject = PassthroughSubject<Void, Never>()

    // Message status subjects
    private let messageStatusUpdateSubject = PassthroughSubject<MessageStatusUpdatePayload, Never>()

    // Conversation presence subject
    private let conversationStatusSubject = PassthroughSubject<String, Never>()

    // Typing indicator subject
    private let typingReceivedSubject = PassthroughSubject<TypingPayload, Never>()

    private var isListening = false

    var otherUserId: String?

    /// Peer privacy from conversation / user-by-id API (defaults = show everyone).
    private var peerLastSeenVisibility: String? = "everyone"
    private var peerOnlineVisibility: String? = "everyone"
    private var peerViewerIsContact: Bool = true

    var messageReceived: AnyPublisher<ConversationMessage, Never> {
        messageReceivedSubject.eraseToAnyPublisher()
    }

    var messageAcknowledged: AnyPublisher<ConversationMessage, Never> {
        messageAcknowledgedSubject.eraseToAnyPublisher()
    }

    var messageReactionUpdated: AnyPublisher<ConversationMessage, Never> {
        messageReactionUpdatedSubject.eraseToAnyPublisher()
    }

    var messageEdited: AnyPublisher<ConversationMessage, Never> {
        messageEditedSubject.eraseToAnyPublisher()
    }

    var messageTranslation: AnyPublisher<ConversationMessage, Never> {
        messageTranslationSubject.eraseToAnyPublisher()
    }

    var messageDeleted: AnyPublisher<ConversationMessage, Never> {
        messageDeletedSubject.eraseToAnyPublisher()
    }

    var pinMessageUpdate: AnyPublisher<PinMessageUpdate, Never> {
        pinMessageUpdateSubject.eraseToAnyPublisher()
    }

    var forwardMessageAck: AnyPublisher<[String: Any], Never> {
        forwardMessageAckSubject.eraseToAnyPublisher()
    }

    var conversationSettingsUpdated: AnyPublisher<[String: Any], Never> {
        conversationSettingsSubject.eraseToAnyPublisher()
    }

    var conversationDeleted: AnyPublisher<String, Never> {
        conversationDeletedSubject.eraseToAnyPublisher()
    }
    var channelMessageReceived: AnyPublisher<ConversationMessage, Never> {
        channelMessageReceivedSubject.eraseToAnyPublisher()
    }
    var sendChannelMessageAck: AnyPublisher<[String: Any], Never> {
        sendChannelMessageAckSubject.eraseToAnyPublisher()
    }
    var channelMessageDeleted: AnyPublisher<ConversationMessage, Never> {
        channelMessageDeletedSubject.eraseToAnyPublisher()
    }
    var channelMessageEdited: AnyPublisher<ConversationMessage, Never> {
        channelMessageEditedSubject.eraseToAnyPublisher()
    }
    
    var incomingCall: AnyPublisher<[String: Any], Never> {
        incomingCallSubject.eraseToAnyPublisher()
    }
    
    var joinCall: AnyPublisher<[String: Any], Never> {
        joinCallSubject.eraseToAnyPublisher()
    }
    
    var leaveCallAck: AnyPublisher<Void, Never> {
        leaveCallAckSubject.eraseToAnyPublisher()
    }
    
    var endCallAck: AnyPublisher<Void, Never> {
        endCallAckSubject.eraseToAnyPublisher()
    }
    
    var createMeetingAck: AnyPublisher<Void, Never> {
        createMeetingAckSubject.eraseToAnyPublisher()
    }
    
    var remoteCallEnded: AnyPublisher<[String: Any], Never> {
        remoteCallEndedSubject.eraseToAnyPublisher()
    }

    var messageStatusUpdate: AnyPublisher<MessageStatusUpdatePayload, Never> {
        messageStatusUpdateSubject.eraseToAnyPublisher()
    }

    var conversationStatus: AnyPublisher<String, Never> {
        conversationStatusSubject.eraseToAnyPublisher()
    }

    var typingReceived: AnyPublisher<TypingPayload, Never> {
        typingReceivedSubject.eraseToAnyPublisher()
    }

    private let userListViewModel: ChatUserListViewModel
    private let socketManager = ChatSocketManager.shared
    private var statusTimer: Timer?
    private var listenerIds: [UUID] = []

    /// All event names registered by setupSocketListeners().
    /// Used to bulk-remove stale handlers before re-registering.
    private let allEventNames: [String] = [
        SocketEvent.getMessage.rawValue,
        SocketEvent.messageUpdated.rawValue,
        SocketEvent.sendConversationMessageAck.rawValue,
        SocketEvent.updateConversationMessageAck.rawValue,
        SocketEvent.messageEdited.rawValue,
        SocketEvent.conversationSettingsUpdated.rawValue,
        SocketEvent.deleteConversation.rawValue,
        SocketEvent.deleteConversationAck.rawValue,
        SocketEvent.incomingChannelMessage.rawValue,
        SocketEvent.sendMessageToChannelAck.rawValue,
        SocketEvent.adminDeleteChannelMessageAck.rawValue,
        SocketEvent.channelMessageDeleted.rawValue,
        SocketEvent.adminEditChannelMessageAck.rawValue,
        SocketEvent.channelMessageEdited.rawValue,
        SocketEvent.incomingCall.rawValue, SocketEvent.joinCall.rawValue, SocketEvent.leaveCallAck.rawValue, SocketEvent.endCallAck.rawValue,
        SocketEvent.remoteCallEnded.rawValue, SocketEvent.createMeetingAck.rawValue, SocketEvent.acceptCall.rawValue, SocketEvent.rejectCall.rawValue,
        SocketEvent.votePollAck.rawValue, SocketEvent.reactToMessageAck.rawValue, SocketEvent.messageReacted.rawValue, SocketEvent.translateMessageAck.rawValue,
        SocketEvent.forwardMessageAck.rawValue, SocketEvent.deleteConversationMessageAck.rawValue,
        SocketEvent.messageDeleted.rawValue,
        SocketEvent.pinMessageAck.rawValue, SocketEvent.messagePinUpdated.rawValue,
        SocketEvent.messagePinExpired.rawValue,
        SocketEvent.markConversationMessagesSeenAck.rawValue,
        SocketEvent.conversationMessageStatusUpdate.rawValue,
        SocketEvent.messageDelivered.rawValue,
        SocketEvent.seenMessages.rawValue,
        SocketEvent.getConversationStatusAck.rawValue,
        SocketEvent.broadcastUserStatus.rawValue,
        SocketEvent.userTypingUpdate.rawValue,
        SocketEvent.conversationSystemMessage.rawValue,
    ]

    init(userListViewModel: ChatUserListViewModel) {
        self.userListViewModel = userListViewModel
    }

    deinit {
        stopListening()
    }

    func setOtherUserId(_ id: String?) {
        otherUserId = id
        if id == nil {
            peerLastSeenVisibility = "everyone"
            peerOnlineVisibility = "everyone"
            peerViewerIsContact = true
        }
    }

    func setPresencePrivacy(
        lastSeenVisibility: String?,
        onlineVisibility: String?,
        viewerIsContact: Bool
    ) {
        if let lastSeenVisibility {
            peerLastSeenVisibility = lastSeenVisibility
        }
        if let onlineVisibility {
            peerOnlineVisibility = onlineVisibility
        }
        peerViewerIsContact = viewerIsContact
    }

    func updateViewerIsContact(_ isContact: Bool) {
        peerViewerIsContact = isContact
    }

    func startListening() {
        // Remove only our own previous listeners by ID, not all listeners
        // for the event (ChatListSocketService also listens on some of these).
        for id in listenerIds {
            socketManager.offEventById(id)
        }
        listenerIds.removeAll()

        isListening = true
        setupSocketListeners()
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false
        statusTimer?.invalidate()
        statusTimer = nil
        for id in listenerIds {
            socketManager.offEventById(id)
        }
        listenerIds.removeAll()
    }

    func emitUserStatus(status: String, conversationId: String, userId: String) {
        let statusData: [String: Any] = [
            "status": status,
            "conversation_id": conversationId,
            "user_id": userId,
            "user": userId
        ]

        socketManager.emitMessage(SocketEvent.emitUserStatus.rawValue, withData: [statusData])
    }
    
    // MARK: - Call-related socket methods
    func listenToEvent(_ event: String, callback: @escaping ([Any]) -> Void) {
        socketManager.listenToEvent(event, completionHandler: callback)
    }
    
    func emitMessage(_ event: String, withData data: [String: Any]) {
        socketManager.emitMessage(event, withData: [data])
    }

    private func listen(_ eventName: String, handler: @escaping ([Any]) -> Void) {
        let id = socketManager.listenToEvent(eventName, completionHandler: handler)
        listenerIds.append(id)
    }

    private func setupSocketListeners() {
        listen(SocketEvent.getMessage.rawValue) { [weak self] data in
            self?.handleNewMessage(data: data)
        }

        listen(SocketEvent.messageUpdated.rawValue) { [weak self] data in
            self?.handleLatestConversationMessage(data: data)
        }

        listen(SocketEvent.sendConversationMessageAck.rawValue) { [weak self] data in
            self?.handleMessageAcknowledgment(data: data)
        }

        listen(SocketEvent.updateConversationMessageAck.rawValue) { [weak self] data in
            self?.handleMessageEditAcknowledgment(data: data)
        }

        // Real-time message edited event (broadcast to other participants)
        listen(SocketEvent.messageEdited.rawValue) { [weak self] data in
            self?.handleMessageEditedRealTime(data: data)
        }

        listen(SocketEvent.conversationSettingsUpdated.rawValue) { [weak self] data in
            self?.handleConversationSettingsUpdate(data: data)
        }

        listen(SocketEvent.deleteConversationAck.rawValue) { [weak self] data in
            self?.handleConversationDeletion(data: data)
        }

        // Channel events — FE `CHANNEL_MESSAGE_NEW`: payload is the message object
        // (also tolerate `{ message }` / `{ data }` wrappers used by some acks).
        listen(SocketEvent.incomingChannelMessage.rawValue) { [weak self] data in
            guard let message = Self.parseChannelMessagePayload(data) else {
                AppLogger.debug("ChatSocketService: Failed to parse channel:message:new")
                return
            }
            DispatchQueue.main.async { self?.channelMessageReceivedSubject.send(message) }
        }
        listen(SocketEvent.sendMessageToChannelAck.rawValue) { [weak self] data in
            guard let ack = data.first as? [String: Any] else { return }
            DispatchQueue.main.async { self?.sendChannelMessageAckSubject.send(ack) }
        }

        // Channel admin — delete
        listen(SocketEvent.adminDeleteChannelMessageAck.rawValue) { [weak self] data in
            self?.handleAdminDeleteChannelMessageAck(data: data)
        }
        listen(SocketEvent.channelMessageDeleted.rawValue) { [weak self] data in
            self?.handleChannelMessageDeletedBroadcast(data: data)
        }

        // Channel admin — edit
        listen(SocketEvent.adminEditChannelMessageAck.rawValue) { [weak self] data in
            self?.handleAdminEditChannelMessageAck(data: data)
        }
        listen(SocketEvent.channelMessageEdited.rawValue) { [weak self] data in
            self?.handleChannelMessageEditedBroadcast(data: data)
        }

        // Call-related socket listeners
        listen(SocketEvent.incomingCall.rawValue) { [weak self] data in
            self?.handleIncomingCall(data: data)
        }
        listen(SocketEvent.joinCall.rawValue) { [weak self] data in
            self?.handleJoinCall(data: data)
        }
        listen(SocketEvent.leaveCallAck.rawValue) { [weak self] data in
            self?.handleLeaveCallAck(data: data)
        }
        listen(SocketEvent.endCallAck.rawValue) { [weak self] data in
            self?.handleEndCallAck(data: data)
        }
        listen(SocketEvent.remoteCallEnded.rawValue) { [weak self] data in
            self?.handleRemoteCallEnded(data: data)
        }
        listen(SocketEvent.createMeetingAck.rawValue) { [weak self] data in
            self?.handleCreateMeetingAck(data: data)
        }
        listen(SocketEvent.acceptCall.rawValue) { [weak self] data in
            // Handle accept-call signal
        }
        listen(SocketEvent.rejectCall.rawValue) { [weak self] data in
            // Handle reject-call signal
        }

        // Vote poll acknowledgement
        listen(SocketEvent.votePollAck.rawValue) { [weak self] data in
            self?.handleVotePollAck(data: data)
        }

        // React ack (emitter) + realtime fanout (Android CHAT_MESSAGE_REACTED)
        listen(SocketEvent.reactToMessageAck.rawValue) { [weak self] data in
            self?.handleReactToMessageAck(data: data)
        }
        listen(SocketEvent.messageReacted.rawValue) { [weak self] data in
            self?.handleMessageReacted(data: data)
        }

        // Translation acknowledgement
        listen(SocketEvent.translateMessageAck.rawValue) { [weak self] data in
            self?.handleTranslateMessageAck(data: data)
        }

        // Forward message acknowledgement
        listen(SocketEvent.forwardMessageAck.rawValue) { [weak self] data in
            self?.handleForwardMessageAck(data: data)
        }

        // Delete message acknowledgement
        listen(SocketEvent.deleteConversationMessageAck.rawValue) { [weak self] data in
            self?.handleMessageDeletedAck(data: data)
        }

        // Real-time message deleted event (broadcast to other participants)
        listen(SocketEvent.messageDeleted.rawValue) { [weak self] data in
            self?.handleMessageDeletedRealTime(data: data)
        }

        // Pin message events (console: ack / updated / expired)
        listen(SocketEvent.pinMessageAck.rawValue) { [weak self] data in
            self?.handlePinEvent(data: data)
        }
        listen(SocketEvent.messagePinUpdated.rawValue) { [weak self] data in
            self?.handlePinEvent(data: data)
        }
        listen(SocketEvent.messagePinExpired.rawValue) { [weak self] data in
            self?.handlePinExpiredEvent(data: data)
        }

        // MARK: - Message Status Events
        // Console contract (https://socket.onevibe.walit.in/console):
        // - chat:message:seen       = c2s only (client marks read)
        // - chat:message:seen:ack   = s2c ack to reader
        // - chat:message:status     = s2c fanout to sender { messageId, status: "seen"|"delivered" }
        // - chat:message:delivered  = both (client may emit; server pushes delivered to sender)

        listen(SocketEvent.markConversationMessagesSeenAck.rawValue) { [weak self] data in
            self?.handleSeenAck(data: data)
        }

        listen(SocketEvent.conversationMessageStatusUpdate.rawValue) { [weak self] data in
            self?.handleConversationMessageStatusUpdate(data: data)
        }

        listen(SocketEvent.messageDelivered.rawValue) { [weak self] data in
            self?.handleReceiptSocketEvent(data: data, status: "delivered")
        }

        // Do NOT treat chat:message:seen as inbound tick fanout — catalog marks it c2s only.
        // Sender blue ticks come from chat:message:status. Keeping a defensive listener
        // only when the payload looks like a server push (has status / readerId).
        listen(SocketEvent.seenMessages.rawValue) { [weak self] data in
            self?.handleInboundSeenFanoutIfPresent(data: data)
        }

        listen(SocketEvent.getConversationStatusAck.rawValue) { [weak self] data in
            self?.handleGetConversationStatusAck(data: data)
        }

        listen(SocketEvent.broadcastUserStatus.rawValue) { [weak self] data in
            self?.handleBroadcastUserStatus(data: data)
        }

        // Typing indicator
        listen(SocketEvent.userTypingUpdate.rawValue) { [weak self] data in
            self?.handleTypingAck(data: data)
        }

        // System messages (screenshot taken, etc.)
        listen(SocketEvent.conversationSystemMessage.rawValue) { [weak self] data in
            self?.handleConversationSystemMessage(data: data)
        }
    }

    // MARK: - Conversation Status Emit

    func emitGetConversationStatus(conversationId: String) {
        guard !conversationId.isEmpty else { return }
        let payload: [String: Any] = ["conversationId": conversationId]
        socketManager.emitMessage(SocketEvent.getConversationStatus.rawValue, withData: [payload])
    }

    /// FE `subscribePresence(userIds)` — `presence:get` { userIds }
    func emitSubscribePresence(userIds: [String]) {
        let ids = userIds.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        socketManager.emitMessage(SocketEvent.presenceGet.rawValue, withData: [["userIds": ids]])
        AppLogger.debug("[Presence] Emitted presence:get userIds=\(ids)")
    }

    // MARK: - Typing Indicator

    func emitTyping(conversationId: String, userId: String) {
        guard !conversationId.isEmpty, !userId.isEmpty else { return }
        let payload: [String: Any] = [
            "conversationId": conversationId,
            "userId": userId,
            "isTyping": true
        ]
        socketManager.emitMessage(SocketEvent.userTyping.rawValue, withData: [payload])
    }

    func emitStopTyping(conversationId: String, userId: String) {
        guard !conversationId.isEmpty, !userId.isEmpty else { return }
        let payload: [String: Any] = [
            "conversationId": conversationId,
            "userId": userId,
            "isTyping": false
        ]
        socketManager.emitMessage(SocketEvent.userTyping.rawValue, withData: [payload])
    }

    private func handleTypingAck(data: [Any]) {
        guard let raw = data.first as? [String: Any] else { return }
        // Support both direct payload and nested `data` key
        let payload = raw["data"] as? [String: Any] ?? raw
        guard let conversationId = payload["conversationId"] as? String,
              let userId = payload["userId"] as? String else { return }

        let senderName = payload["senderName"] as? String
            ?? payload["userName"] as? String
            ?? ""
        let isTyping = payload["isTyping"] as? Bool ?? true

        DispatchQueue.main.async { [weak self] in
            self?.typingReceivedSubject.send(
                TypingPayload(conversationId: conversationId, userId: userId, senderName: senderName, isTyping: isTyping)
            )
        }
    }

    // MARK: - Conversation Status Ack Handler

    private func handleGetConversationStatusAck(data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            AppLogger.debug("ChatSocketService: Failed to parse get-conversation-status-ack")
            return
        }

        // Ignore empty OLD privacy payloads so they don't clear presence:update text
        let statusText = parseConversationStatusText(from: payload)
        guard !statusText.isEmpty else { return }
        DispatchQueue.main.async {
            self.conversationStatusSubject.send(statusText)
        }
    }

    private func handleBroadcastUserStatus(data: [Any]) {
        // FE PresenceSnapshot: { userId, online, lastSeenAt, status? }
        // Also accept OLD: { userId, isOnline/status, lastOnline }
        let payloads: [[String: Any]] = {
            if let dict = data.first as? [String: Any] {
                if let nested = dict["data"] as? [String: Any] { return [nested] }
                if let arr = dict["data"] as? [[String: Any]] { return arr }
                if let snapshots = dict["snapshots"] as? [[String: Any]] { return snapshots }
                if let users = dict["users"] as? [[String: Any]] { return users }
                return [dict]
            }
            if let arr = data.first as? [[String: Any]] { return arr }
            // Socket.IO may deliver a bare array as the full `data` args
            if let arr = data as? [[String: Any]] { return arr }
            return []
        }()

        for dataDict in payloads {
            guard let userId = dataDict["userId"] as? String ?? dataDict["id"] as? String,
                  !userId.isEmpty else { continue }

            // Explicit null status ⇒ privacy hide (NEW FE)
            let statusHidden: Bool = {
                if dataDict["status"] is NSNull { return true }
                if let s = dataDict["status"] as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return t.isEmpty || t == "null"
                }
                return false
            }()

            let statusString = dataDict["status"] as? String
            let isOnline: Bool = (dataDict["online"] as? Bool)
                ?? (dataDict["isOnline"] as? Bool)
                ?? ((statusString)?.lowercased() == "online")

            let lastSeen = Self.stringValue(
                dataDict["lastSeenAt"]
                    ?? dataDict["lastOnline"]
                    ?? dataDict["last_online"]
                    ?? dataDict["lastSeen"]
            )

            // Prefer per-event visibility when server includes it; else stored peer privacy.
            let lastSeenVis = (dataDict["lastSeenVisibility"] as? String) ?? peerLastSeenVisibility
            let onlineVis = (dataDict["onlineVisibility"] as? String) ?? peerOnlineVisibility

            Task { @MainActor in
                var onlineVisEnum = PresencePrivacy.normalize(onlineVis)
                if onlineVisEnum == .sameAsLastSeen {
                    onlineVisEnum = PresencePrivacy.normalize(lastSeenVis)
                }
                let canShowOnlineDot = !statusHidden
                    && PresencePrivacy.allows(onlineVisEnum, viewerIsContact: self.peerViewerIsContact)

                // Keep list presence in sync even when this isn't the open peer
                if canShowOnlineDot {
                    ChatListSocketService.shared.applyPresence(userId: userId, isOnline: isOnline)
                } else {
                    ChatListSocketService.shared.applyPresence(userId: userId, isOnline: false)
                }

                guard let targetId = self.otherUserId, userId == targetId else { return }

                let statusText: String
                if statusHidden {
                    statusText = ""
                } else {
                    statusText = PresencePrivacy.subtitle(
                        isOnline: isOnline,
                        lastSeenAt: lastSeen,
                        status: statusString,
                        lastSeenVisibility: lastSeenVis,
                        onlineVisibility: onlineVis,
                        viewerIsContact: self.peerViewerIsContact
                    )
                }
                self.conversationStatusSubject.send(statusText)
            }
        }
    }

    /// FE `channel:message:new` delivers the message object directly.
    /// Also accept `{ message }` / `{ data }` wrappers for compatibility.
    static func parseChannelMessagePayload(_ data: [Any]) -> ConversationMessage? {
        guard let payload = data.first as? [String: Any] else { return nil }
        let messageDict = (payload["message"] as? [String: Any])
            ?? (payload["data"] as? [String: Any])
            ?? payload
        guard messageDict["id"] != nil else { return nil }
        return ConversationMessage.fromDictionary(messageDict)
    }

    private static func stringValue(_ raw: Any?) -> String? {
        guard let raw else { return nil }
        if let s = raw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || t.lowercased() == "null" ? nil : t
        }
        if let n = raw as? NSNumber {
            // Seconds vs ms heuristic
            let v = n.doubleValue
            let seconds = v > 1_000_000_000_000 ? v / 1000.0 : v
            let date = Date(timeIntervalSince1970: seconds)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return iso.string(from: date)
        }
        return nil
    }

    /// Rules (applied in order via `PresencePrivacy`):
    ///  - `lastSeenVisibility = nobody` && `onlineVisibility = same_as_last_seen` → hide
    ///  - `lastSeenVisibility = nobody` && `onlineVisibility = everyone`           → online only / offline label
    ///  - `lastSeenVisibility = my_contacts`  && viewer not a contact              → hide
    ///  - `lastSeenVisibility = everyone` (or unknown)                             → show normally
    private func parseConversationStatusText(from payload: [String: Any]) -> String {
        guard let data = payload["data"] as? [String: Any] else { return "" }

        let rawStatus = data["status"] as? String
        // Explicit null status ⇒ hide
        if data["status"] is NSNull { return "" }
        if let rawStatus {
            let t = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t.isEmpty || t == "null" { return "" }
        }

        let lastSeenVis = (data["lastSeenVisibility"] as? String) ?? peerLastSeenVisibility
        let onlineVis = (data["onlineVisibility"] as? String) ?? peerOnlineVisibility
        let lastOnline = (data["lastOnline"] as? String)
            ?? (data["lastSeenAt"] as? String)
            ?? (data["lastSeen"] as? String)
        let isOnline = (data["isOnline"] as? Bool)
            ?? (data["online"] as? Bool)
            ?? (rawStatus?.lowercased() == "online")

        return PresencePrivacy.subtitle(
            isOnline: isOnline,
            lastSeenAt: lastOnline,
            status: rawStatus,
            lastSeenVisibility: lastSeenVis,
            onlineVisibility: onlineVis,
            viewerIsContact: peerViewerIsContact
        )
    }

    // MARK: - Mark Seen Emit

    func emitJoinConversation(_ conversationId: String) {
        guard !conversationId.isEmpty else { return }
        socketManager.joinConversationRoom(conversationId)
        socketManager.setConversationViewing(conversationId: conversationId, active: true)
    }

    func emitLeaveConversation(_ conversationId: String) {
        guard !conversationId.isEmpty else { return }
        // FE: viewing inactive; keep socket room if inbox still lists this chat
        socketManager.setConversationViewing(conversationId: conversationId, active: false)
        if !ChatSocketManager.shared.isInboxConversation(conversationId) {
            socketManager.leaveConversationRoom(conversationId)
        }
    }

    func emitJoinChannel(_ channelId: String) {
        guard !channelId.isEmpty else { return }
        socketManager.joinChannelRoom(channelId)
        socketManager.setChannelViewing(channelId: channelId, active: true)
    }

    func emitLeaveChannel(_ channelId: String) {
        guard !channelId.isEmpty else { return }
        // FE: viewing inactive; keep socket room if channel inbox still lists this channel
        socketManager.setChannelViewing(channelId: channelId, active: false)
        if !ChatSocketManager.shared.isInboxChannel(channelId) {
            socketManager.leaveChannelRoom(channelId)
        }
    }

    func emitMarkMessagesSeen(conversationId: String) {
        emitMarkMessagesSeen(conversationId: conversationId, messageId: nil)
    }

    /// Console `chat:message:seen` sample: `{ requestId, conversationId, messageId }`
    /// `messageId` is required by the server for sender `chat:message:status` fanout.
    func emitMarkMessagesSeen(conversationId: String, messageId: String?) {
        guard !conversationId.isEmpty else { return }
        guard let messageId, !messageId.isEmpty else {
            AppLogger.debug(
                "[MarkSeen] Skipped chat:message:seen — messageId required by console contract conversationId=\(conversationId)"
            )
            return
        }
        let payload: [String: Any] = [
            "requestId": UUID().uuidString,
            "conversationId": conversationId,
            "messageId": messageId
        ]
        socketManager.emitMessage(SocketEvent.markConversationMessagesSeen.rawValue, withData: [payload])
        AppLogger.debug(
            "[MarkSeen] Emitted chat:message:seen conversationId=\(conversationId) messageId=\(messageId.prefix(8))"
        )
    }

    /// Console `chat:message:delivered` sample: `{ conversationId, messageId }`
    func emitMessageDelivered(conversationId: String, messageId: String) {
        guard !conversationId.isEmpty, !messageId.isEmpty else { return }
        let payload: [String: Any] = [
            "conversationId": conversationId,
            "messageId": messageId
        ]
        socketManager.emitMessage(SocketEvent.messageDelivered.rawValue, withData: [payload])
        AppLogger.debug(
            "[Delivered] Emitted chat:message:delivered conversationId=\(conversationId) messageId=\(messageId.prefix(8))"
        )
    }

    func emitMarkChannelMessagesSeen(channelId: String, messageId: String?) {
        guard !channelId.isEmpty else { return }
        var payload: [String: Any] = [
            "requestId": UUID().uuidString,
            "channelId": channelId
        ]
        if let messageId, !messageId.isEmpty {
            payload["messageId"] = messageId
        }
        socketManager.emitMessage(SocketEvent.channelMessageSeen.rawValue, withData: [payload])
        AppLogger.debug("[ChannelSeen] Emitted channel:message:seen channelId=\(channelId) messageId=\(messageId ?? "nil")")
    }

    // MARK: - Message Status Update Handler

    private func unwrapSocketPayload(_ data: [Any]) -> [String: Any]? {
        guard let root = data.first as? [String: Any] else { return nil }
        if let nested = root["data"] as? [String: Any] {
            // Prefer nested fields but keep top-level conversationId/status if missing inside data
            var merged = nested
            for key in ["conversationId", "messageId", "messageIds", "status", "seenBy", "readerId", "delivererId", "userId"] {
                if merged[key] == nil, let value = root[key] {
                    merged[key] = value
                }
            }
            return merged
        }
        return root
    }

    private func extractMessageIds(from payload: [String: Any]) -> [String] {
        if let mid = payload["messageId"] as? String, !mid.isEmpty {
            return [mid]
        }
        if let mid = payload["id"] as? String, !mid.isEmpty {
            return [mid]
        }
        if let message = payload["message"] as? [String: Any] {
            if let mid = message["messageId"] as? String, !mid.isEmpty { return [mid] }
            if let mid = message["id"] as? String, !mid.isEmpty { return [mid] }
        }
        if let ids = payload["messageIds"] as? [String] {
            return ids.filter { !$0.isEmpty }
        }
        if let ids = payload["ids"] as? [String] {
            return ids.filter { !$0.isEmpty }
        }
        return []
    }

    private func handleConversationMessageStatusUpdate(data: [Any]) {
        guard let payload = unwrapSocketPayload(data) else {
            AppLogger.debug("ChatSocketService: Failed to parse chat:message:status payload: \(data)")
            return
        }
        let conversationId = payload["conversationId"] as? String
            ?? (payload["message"] as? [String: Any])?["conversationId"] as? String
            ?? ""
        guard !conversationId.isEmpty else {
            AppLogger.debug("ChatSocketService: chat:message:status missing conversationId: \(payload)")
            return
        }

        // Console sample: { conversationId, messageId, status: "seen" }
        let status = (payload["status"] as? String)
            ?? (payload["receiptStatus"] as? String)
            ?? (payload["message"] as? [String: Any])?["status"] as? String
            ?? (payload["message"] as? [String: Any])?["receiptStatus"] as? String
            ?? ""
        guard !status.isEmpty else {
            AppLogger.debug("ChatSocketService: chat:message:status missing status field: \(payload)")
            return
        }

        let messageIds = extractMessageIds(from: payload)
        let deliveredTo = payload["deliveredTo"] as? [String] ?? []
        let seenBy = (payload["seenBy"] as? String)
            ?? (payload["readerId"] as? String)

        let update = MessageStatusUpdatePayload(
            conversationId: conversationId,
            messageIds: messageIds,
            status: status,
            deliveredTo: deliveredTo,
            seenBy: seenBy
        )

        AppLogger.debug(
            "[StatusUpdate] chat:message:status conversationId=\(conversationId) status=\(status) messageIds=\(messageIds)"
        )

        DispatchQueue.main.async {
            self.messageStatusUpdateSubject.send(update)
        }
    }

    /// Console `chat:message:seen:ack` — reader confirmation. If `data` carries status rows, apply them.
    private func handleSeenAck(data: [Any]) {
        guard let root = data.first as? [String: Any] else { return }

        let success = (root["success"] as? Bool)
            ?? ((root["status"] as? Bool).map { $0 })
            ?? ((root["status"] as? Int).map { $0 == 1 })
            ?? true
        guard success else {
            AppLogger.debug("[SeenAck] failed: \(root)")
            return
        }

        let payload = (root["data"] as? [String: Any]) ?? root
        let conversationId = payload["conversationId"] as? String
            ?? root["conversationId"] as? String
            ?? ""
        let count = payload["count"] as? Int ?? 0
        AppLogger.debug("[SeenAck] success conversationId=\(conversationId) count=\(count)")

        // Some servers put the sender-facing status snapshot into ack data.
        let status = (payload["status"] as? String) ?? ""
        let messageIds = extractMessageIds(from: payload)
        let rows = payload["rows"] as? [[String: Any]]
            ?? (payload["messages"] as? [[String: Any]])
            ?? []

        if !conversationId.isEmpty, (!messageIds.isEmpty && !status.isEmpty) || !rows.isEmpty {
            if !rows.isEmpty {
                for row in rows {
                    let rowStatus = (row["status"] as? String) ?? status
                    guard !rowStatus.isEmpty else { continue }
                    let ids = extractMessageIds(from: row)
                    guard !ids.isEmpty else { continue }
                    let update = MessageStatusUpdatePayload(
                        conversationId: (row["conversationId"] as? String) ?? conversationId,
                        messageIds: ids,
                        status: rowStatus,
                        deliveredTo: [],
                        seenBy: row["readerId"] as? String ?? row["seenBy"] as? String
                    )
                    DispatchQueue.main.async {
                        self.messageStatusUpdateSubject.send(update)
                    }
                }
            } else {
                let update = MessageStatusUpdatePayload(
                    conversationId: conversationId,
                    messageIds: messageIds,
                    status: status.isEmpty ? "seen" : status,
                    deliveredTo: [],
                    seenBy: payload["readerId"] as? String ?? payload["seenBy"] as? String
                )
                DispatchQueue.main.async {
                    self.messageStatusUpdateSubject.send(update)
                }
            }
        }
    }

    /// Defensive: only accept inbound `chat:message:seen` when it looks like a server push
    /// (has status/readerId). Ignore plain c2s echoes `{ requestId, conversationId, messageId }`.
    private func handleInboundSeenFanoutIfPresent(data: [Any]) {
        guard let payload = unwrapSocketPayload(data) else { return }
        let hasServerFanoutShape =
            (payload["status"] as? String) != nil
            || (payload["receiptStatus"] as? String) != nil
            || (payload["readerId"] as? String) != nil
            || (payload["seenBy"] as? String) != nil
            || payload["data"] is [String: Any]
        guard hasServerFanoutShape else {
            // Likely our own c2s emit shape or unsupported echo — sender ticks use chat:message:status
            AppLogger.debug("[Seen] Ignored non-fanout chat:message:seen payload keys=\(Array(payload.keys))")
            return
        }
        handleReceiptSocketEvent(data: data, status: "seen")
    }

    /// FE / console `chat:message:delivered` (and defensive seen fanout) → MessageStatusUpdatePayload
    private func handleReceiptSocketEvent(data: [Any], status: String) {
        guard let payload = unwrapSocketPayload(data),
              let conversationId = payload["conversationId"] as? String,
              !conversationId.isEmpty else { return }

        let myId = Container.sharedContainer.resolve(SessionManager.self)?.user?.userId ?? ""
        // Only drop *own action echoes* using explicit actor fields.
        let actorId: String = {
            if status == "delivered" {
                return (payload["delivererId"] as? String) ?? ""
            }
            return (payload["readerId"] as? String)
                ?? (payload["seenBy"] as? String)
                ?? ""
        }()
        if !myId.isEmpty, !actorId.isEmpty, actorId == myId { return }

        let messageIds = extractMessageIds(from: payload)
        // Prefer explicit status in payload when present (server fanout)
        let resolvedStatus = (payload["status"] as? String)
            ?? (payload["receiptStatus"] as? String)
            ?? status

        let update = MessageStatusUpdatePayload(
            conversationId: conversationId,
            messageIds: messageIds,
            status: resolvedStatus,
            deliveredTo: [],
            seenBy: (resolvedStatus == "seen" || resolvedStatus == "read")
                ? (actorId.isEmpty ? nil : actorId)
                : nil
        )
        AppLogger.debug(
            "[Receipt] \(resolvedStatus) conversationId=\(conversationId) messageIds=\(messageIds) actor=\(actorId.prefix(8))"
        )
        DispatchQueue.main.async {
            self.messageStatusUpdateSubject.send(update)
        }
    }

    private func handleNewMessage(data: [Any]) {
        guard let raw = data.first as? [String: Any] else {
            AppLogger.debug("Failed to parse socket message data")
            return
        }
        // NEW chat:message:new may be flat or wrapped in { data: {...} }
        let messageData = (raw["data"] as? [String: Any]) ?? raw
        guard let message = ConversationMessage.fromDictionary(messageData) else {
            AppLogger.debug("Failed to parse socket message data")
            return
        }

        DispatchQueue.main.async {
            self.messageReceivedSubject.send(message)
        }
    }

    private func handleConversationSystemMessage(data: [Any]) {
        // Server sends: data = [[{message:..., conversationId:...}]]
        let payload: [String: Any] = (data.first as? [Any])?.first as? [String: Any]
            ?? data.first as? [String: Any]
            ?? [:]
        guard !payload.isEmpty else {
            AppLogger.debug("ChatSocketService: conversation-system-message — failed to parse payload")
            return
        }

        let messageData = (payload["message"] as? [String: Any]) ?? payload
        guard let message = ConversationMessage.fromDictionary(messageData) else {
            AppLogger.debug("ChatSocketService: Failed to parse conversation-system-message")
            return
        }

        AppLogger.debug("ChatSocketService: conversation-system-message received conversation=\(message.conversationId)")
        DispatchQueue.main.async {
            self.messageReceivedSubject.send(message)
        }
    }

    private func handleMessageAcknowledgment(data: [Any]) {
        guard let message = SocketAckParser.parseMessage(from: data) else {
            AppLogger.debug("ChatSocketService: Failed to parse message acknowledgment data: \(data)")
            return
        }

        DispatchQueue.main.async {
            self.messageAcknowledgedSubject.send(message)
        }
    }

    private func handleMessageEditAcknowledgment(data: [Any]) {
        guard let message = SocketAckParser.parseMessage(from: data) else {
            AppLogger.debug("ChatSocketService: Failed to parse message edit acknowledgment data")
            return
        }

        DispatchQueue.main.async {
            self.messageEditedSubject.send(message)
        }
    }

    /// Handle real-time message-edited event broadcast from server when someone else edits a message
    private func handleMessageEditedRealTime(data: [Any]) {
        AppLogger.debug("ChatSocketService: Received real-time message-edited event: \(data)")

        guard let responseData = data.first as? [String: Any] else {
            AppLogger.debug("ChatSocketService: Failed to parse message-edited data: \(data)")
            return
        }

        // The actual message data might be nested inside "data" field or directly in the response
        var messageData: [String: Any]?

        if let nestedData = responseData["data"] as? [String: Any] {
            messageData = nestedData
        } else if responseData["id"] != nil {
            messageData = responseData
        }

        guard let validMessageData = messageData,
              let message = ConversationMessage.fromDictionary(validMessageData) else {
            AppLogger.debug("ChatSocketService: Failed to parse message from message-edited event: \(responseData)")
            return
        }

        AppLogger.debug("ChatSocketService: Forwarding edited message to subscribers: \(message.id)")
        DispatchQueue.main.async {
            self.messageEditedSubject.send(message)
        }
    }

    private func handleLatestConversationMessage(data: [Any]) {
        guard let payload = data.first as? [String: Any] else {
            AppLogger.debug("ChatSocketService: Failed to parse latest conversation message payload: \(data)")
            return
        }

        var messageData: [String: Any]?
        if let status = payload["status"] as? Bool, status == true,
           let nestedData = payload["data"] as? [String: Any] {
            messageData = nestedData
        } else if payload["id"] != nil {
            messageData = payload
        }

        guard let validData = messageData,
              let message = ConversationMessage.fromDictionary(validData) else {
            AppLogger.debug("ChatSocketService: Failed to parse latest conversation message payload: \(data)")
            return
        }

        DispatchQueue.main.async {
            self.messageReceivedSubject.send(message)
        }
    }

    private func handleConversationSettingsUpdate(data: [Any]) {
        guard let settingsData = data.first as? [String: Any] else {
            AppLogger.debug("Failed to parse conversation settings data")
            return
        }

        DispatchQueue.main.async {
            self.conversationSettingsSubject.send(settingsData)
        }
    }

    private func handleConversationDeletion(data: [Any]) {
        guard let deletionData = data.first as? [String: Any],
              let conversationId = deletionData["conversation_id"] as? String else {
            AppLogger.debug("Failed to parse conversation deletion data")
            return
        }

        DispatchQueue.main.async {
            self.conversationDeletedSubject.send(conversationId)
        }
    }

    // MARK: - User Status Management
    func startUserStatusEmitting(status: String, conversationId: String, userId: String) {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.emitUserStatus(status: status, conversationId: conversationId, userId: userId)
        }
    }

    func stopUserStatusEmitting() {
        statusTimer?.invalidate()
        statusTimer = nil
    }
    
    // MARK: - Call-related event handlers
    private func handleIncomingCall(data: [Any]) {
        guard let callData = data.first as? [String: Any] else {
            AppLogger.debug("Failed to parse incoming call data")
            return
        }
        // Defense: ignore Agora-shaped payloads if event names ever collide again.
        if Self.isAgoraCallPayload(callData) {
            AppLogger.debug("ChatSocketService: ignoring Agora payload on Dyte incoming-call path")
            return
        }

        DispatchQueue.main.async {
            self.incomingCallSubject.send(callData)
        }
    }

    private func handleJoinCall(data: [Any]) {
        guard let callData = data.first as? [String: Any] else {
            AppLogger.debug("Failed to parse join-call data")
            return
        }
        if Self.isAgoraCallPayload(callData) {
            AppLogger.debug("ChatSocketService: ignoring Agora payload on Dyte join-call path")
            return
        }

        DispatchQueue.main.async {
            self.joinCallSubject.send(callData)
        }
    }

    private func handleLeaveCallAck(data: [Any]) {
        DispatchQueue.main.async {
            self.leaveCallAckSubject.send(())
        }
    }

    private func handleEndCallAck(data: [Any]) {
        if let callData = data.first as? [String: Any], Self.isAgoraCallPayload(callData) {
            return
        }
        DispatchQueue.main.async {
            self.endCallAckSubject.send(())
        }
    }

    private func handleRemoteCallEnded(data: [Any]) {
        guard let callData = data.first as? [String: Any] else { return }
        if Self.isAgoraCallPayload(callData) { return }
        DispatchQueue.main.async {
            self.remoteCallEndedSubject.send(callData)
        }
    }

    private func handleCreateMeetingAck(data: [Any]) {
        guard let ackData = data.first as? [String: Any],
              let message = ackData["message"] as? String,
              message == "The meeting was created" else {
            AppLogger.debug("Failed to parse create-meeting-ack data")
            return
        }

        DispatchQueue.main.async {
            self.createMeetingAckSubject.send(())
        }
    }

    /// Agora `call:*` payloads — must not drive Dyte CallManager.
    private static func isAgoraCallPayload(_ dict: [String: Any]) -> Bool {
        if dict["channelName"] != nil { return true }
        if dict["callId"] != nil { return true }
        if dict["token"] != nil, dict["call"] != nil { return true }
        if let call = dict["call"] as? [String: Any], call["channelName"] != nil || call["id"] != nil {
            return true
        }
        if let type = dict["type"] as? String {
            let t = type.lowercased()
            if t == "audio" || t == "video" || t == "agora_call" { return true }
        }
        return false
    }

    private func handleVotePollAck(data: [Any]) {
        guard let ackResponse = data.first as? [String: Any],
              let status = ackResponse["status"],
              (status as? Bool == true || status as? Int == 1),
              let messageData = ackResponse["data"] as? [String: Any] else {
            AppLogger.debug("ChatSocketService: Failed to parse vote-poll-ack data: \(data)")
            return
        }

        guard let message = ConversationMessage.fromDictionary(messageData) else {
            AppLogger.debug("ChatSocketService: Failed to decode ConversationMessage from vote-poll-ack data: \(messageData)")
            return
        }

        let dedupKey = (messageId: message.id, updatedAt: message.updatedAt ?? "")
        if let last = lastVotePollAckDedupKey,
           last.messageId == dedupKey.messageId,
           last.updatedAt == dedupKey.updatedAt {
            AppLogger.debug("ChatSocketService: Dropping duplicate vote-poll-ack for \(message.id)")
            return
        }
        lastVotePollAckDedupKey = dedupKey

        DispatchQueue.main.async {
            self.messageAcknowledgedSubject.send(message)
        }
    }

    private var lastReactionAckDedupKey: (messageId: String, updatedAt: String)?
    private var lastVotePollAckDedupKey: (messageId: String, updatedAt: String)?

    private func handleReactToMessageAck(data: [Any]) {
        publishReactionSocketPayload(data, source: "react:ack")
    }

    /// Android `CHAT_MESSAGE_REACTED` = `chat:message:reacted`
    private func handleMessageReacted(data: [Any]) {
        publishReactionSocketPayload(data, source: "message:reacted")
    }

    private func publishReactionSocketPayload(_ data: [Any], source: String) {
        guard let ackResponse = data.first as? [String: Any] else {
            AppLogger.debug("ChatSocketService[\(source)]: Failed to parse react payload: \(data)")
            return
        }

        let isExplicitFailure: Bool = {
            if let success = ackResponse["success"] as? Bool { return success == false }
            if let status = ackResponse["status"] as? Bool { return status == false }
            if let status = ackResponse["status"] as? Int { return status == 0 }
            if let status = ackResponse["status"] as? String {
                return ["false", "0", "error", "failed"].contains(status.lowercased())
            }
            return false
        }()
        if isExplicitFailure {
            AppLogger.debug("ChatSocketService[\(source)]: react event reported failure: \(ackResponse)")
            return
        }

        // Prefer full reactions list; fall back to emoji+userId delta.
        var message = ConversationMessage.reactionUpdate(from: ackResponse)
        if (message?.reactions == nil),
           let delta = ConversationMessage.reactionDelta(from: ackResponse) {
            var dict: [String: Any] = ["id": delta.messageId]
            if let cid = delta.conversationId { dict["conversationId"] = cid }
            dict["metadata"] = [
                "_reactionDeltaEmoji": delta.emoji,
                "_reactionDeltaUserId": delta.userId
            ]
            message = ConversationMessage.fromDictionary(dict) ?? message
        }

        guard let message, !message.id.isEmpty else {
            AppLogger.debug("ChatSocketService[\(source)]: Failed to decode reaction update from: \(ackResponse)")
            return
        }

        let dedupKey = (
            messageId: message.id,
            updatedAt: message.updatedAt
                ?? "\(message.reactions?.count ?? -1)-\(message.metadata?["_reactionDeltaEmoji"]?.value as? String ?? "")-\(message.metadata?["_reactionDeltaUserId"]?.value as? String ?? "")"
        )
        if let last = lastReactionAckDedupKey,
           last.messageId == dedupKey.messageId,
           last.updatedAt == dedupKey.updatedAt {
            AppLogger.debug("ChatSocketService[\(source)]: Dropping duplicate react event for \(message.id)")
            return
        }
        lastReactionAckDedupKey = dedupKey

        AppLogger.debug("ChatSocketService[\(source)]: reaction update messageId=\(message.id.prefix(8)) reactions=\(message.reactions?.count ?? -1)")

        DispatchQueue.main.async {
            self.messageReactionUpdatedSubject.send(message)
        }
    }

    private func handleTranslateMessageAck(data: [Any]) {
        guard let ackResponse = data.first as? [String: Any],
              let status = ackResponse["status"],
              (status as? Bool == true || status as? Int == 1),
              let messageData = ackResponse["data"] as? [String: Any],
              let message = ConversationMessage.fromDictionary(messageData) else {
            AppLogger.debug("ChatSocketService: Failed to parse translation acknowledgment data")
            return
        }

        DispatchQueue.main.async {
            self.messageTranslationSubject.send(message)
        }
    }

    private func handleForwardMessageAck(data: [Any]) {
        guard let ackResponse = data.first as? [String: Any] else {
            AppLogger.debug("ChatSocketService: Failed to parse forward-message-ack data: \(data)")
            return
        }

        DispatchQueue.main.async {
            self.forwardMessageAckSubject.send(ackResponse)
        }
    }

    private func handleMessageDeletedAck(data: [Any]) {
        guard let ackResponse = data.first as? [String: Any] else {
            AppLogger.debug("ChatSocketService: Failed to parse delete-conversation-message-ack data: \(data)")
            return
        }

        // Check status
        var statusOk = false
        if let status = ackResponse["status"] {
            statusOk = (status as? Bool == true) || (status as? Int == 1)
        }

        guard statusOk else {
            let errorMsg = ackResponse["message"] as? String ?? "Unknown error"
            AppLogger.debug("ChatSocketService: Delete message failed: \(errorMsg)")
            return
        }

        let successMsg = ackResponse["message"] as? String ?? ChatStrings.chat_messageDeleted.localizedString()
        AppLogger.debug("ChatSocketService: \(successMsg)")

        let payload = (ackResponse["data"] as? [String: Any]) ?? ackResponse
        let conversationId = extractConversationId(from: payload) ?? extractConversationId(from: ackResponse)

        let deletedIds = extractDeletedMessageIds(from: payload)
        if !deletedIds.isEmpty {
            AppLogger.debug("ChatSocketService: Forwarding batch deleted messages from ack: count=\(deletedIds.count)")
            for deletedId in deletedIds {
                forwardDeletedMessage(id: deletedId, conversationId: conversationId)
            }
            return
        }

        if let messageData = ackResponse["data"] as? [String: Any] {
            let messageId = nonEmptyString(messageData["messageId"])
                ?? nonEmptyString(messageData["id"])
            guard let messageId else { return }

            let isForEveryone: Bool
            if let val = messageData["isDeletedEveryone"] as? Bool {
                isForEveryone = val
            } else if let val = messageData["isDeletedEveryone"] as? Int {
                isForEveryone = val == 1
            } else if let val = messageData["isDeletedEveryone"] as? String {
                isForEveryone = val == "1" || val.lowercased() == "true"
            } else if let scope = messageData["scope"] as? String {
                isForEveryone = scope.lowercased() == "everyone"
            } else if let forEveryone = messageData["forEveryone"] as? Bool {
                isForEveryone = forEveryone
            } else {
                isForEveryone = false
            }

            guard isForEveryone else {
                return
            }

            let conversationId = extractConversationId(from: messageData) ?? conversationId
            AppLogger.debug("ChatSocketService: Forwarding deleted message to subscribers: \(messageId)")
            forwardDeletedMessage(id: messageId, conversationId: conversationId)
        }
    }

    /// Handle real-time `chat:message:deleted` broadcast (FE shape:
    /// `{ conversationId, messageId, scope, actorId }`).
    private func handleMessageDeletedRealTime(data: [Any]) {
        guard let responseData = data.first as? [String: Any] else {
            AppLogger.debug("ChatSocketService: Failed to parse message-deleted data: \(data)")
            return
        }

        AppLogger.debug("ChatSocketService: Received real-time message-deleted event: \(responseData)")

        let validMessageData = (responseData["data"] as? [String: Any]) ?? responseData

        // FE only removes the bubble for the peer when scope is everyone.
        let scope = (
            (validMessageData["scope"] as? String)
            ?? (responseData["scope"] as? String)
            ?? "everyone"
        ).lowercased()
        guard scope == "everyone" else {
            AppLogger.debug("ChatSocketService: Ignoring message-deleted scope=\(scope)")
            return
        }

        let conversationId = extractConversationId(from: validMessageData) ?? extractConversationId(from: responseData)

        let deletedIds = extractDeletedMessageIds(from: validMessageData)
        if !deletedIds.isEmpty {
            AppLogger.debug("ChatSocketService: Forwarding batch deleted messages from real-time event: count=\(deletedIds.count)")
            for deletedId in deletedIds {
                forwardDeletedMessage(id: deletedId, conversationId: conversationId)
            }
            return
        }

        // Prefer `messageId` (FE) over `id`. Never decode the sparse FE payload via
        // fromDictionary without remapping — missing `id` used to become a random UUID.
        guard let messageId = nonEmptyString(validMessageData["messageId"])
                ?? nonEmptyString(validMessageData["id"])
                ?? nonEmptyString(responseData["messageId"])
                ?? nonEmptyString(responseData["id"]) else {
            AppLogger.debug("ChatSocketService: No messageId found in message-deleted event")
            return
        }

        AppLogger.debug("ChatSocketService: Forwarding real-time deleted message: \(messageId)")
        forwardDeletedMessage(id: messageId, conversationId: conversationId)
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func extractConversationId(from payload: [String: Any]) -> String? {
        if let conversationId = payload["conversationId"] as? String, !conversationId.isEmpty {
            return conversationId
        }
        if let conversationId = payload["conversation_id"] as? String, !conversationId.isEmpty {
            return conversationId
        }
        return nil
    }

    private func extractDeletedMessageIds(from payload: [String: Any]) -> [String] {
        if let ids = payload["deletedIds"] as? [String] {
            return ids.filter { !$0.isEmpty }
        }

        if let anyIds = payload["deletedIds"] as? [Any] {
            return anyIds.compactMap { $0 as? String }.filter { !$0.isEmpty }
        }

        if let ids = payload["messageIds"] as? [String] {
            return ids.filter { !$0.isEmpty }
        }

        return []
    }

    private func forwardDeletedMessage(id messageId: String, conversationId: String?) {
        let partialMessage = ConversationMessage(
            id: messageId,
            conversationId: conversationId ?? "",
            content: ChatStrings.chat_messageDeleted.localizedString(),
            status: "deleted",
            metadata: ["isDeletedEveryone": AnyCodable(true)],
            isDeleted: true
        )

        // Persist even when chat detail is not open (peer on inbox / another screen).
        Task {
            try? await MessageRepository().markMessagesDeletedForEveryone(
                ids: [messageId],
                conversationId: conversationId,
                deletedContent: ChatStrings.chat_messageDeleted.localizedString()
            )
        }
        if let conversationId, !conversationId.isEmpty {
            Task { @MainActor in
                ChatDataPreloader.shared.markMessagesDeletedForEveryone(
                    conversationId: conversationId,
                    messageIds: [messageId]
                )
            }
        }

        DispatchQueue.main.async {
            self.messageDeletedSubject.send(partialMessage)
        }
    }

    // MARK: - Pin Message Handler
    /// Console shapes:
    /// - `chat:message:pin:updated` → `{ conversationId, messageId, pinned }`
    /// - `chat:message:pin:ack` → `{ success: true, data: { ... } }` (may use `status` legacy)
    private func handlePinEvent(data: [Any]) {
        guard let root = data.first as? [String: Any] else {
            AppLogger.debug("ChatSocketService: pin event missing payload: \(data)")
            return
        }

        let isExplicitFailure: Bool = {
            if let success = root["success"] as? Bool { return success == false }
            if let status = root["status"] as? Bool { return status == false }
            if let status = root["status"] as? Int { return status == 0 }
            if let status = root["status"] as? String {
                return ["false", "0", "error", "failed"].contains(status.lowercased())
            }
            return false
        }()
        if isExplicitFailure {
            AppLogger.debug("ChatSocketService: pin event reported failure: \(root)")
            return
        }

        let payload = (root["data"] as? [String: Any]) ?? root
        let messageId = (payload["messageId"] as? String)
            ?? (payload["id"] as? String)
            ?? (root["messageId"] as? String)
            ?? ""
        let conversationId = (payload["conversationId"] as? String)
            ?? (root["conversationId"] as? String)
            ?? ""
        // Console uses `pinned`; legacy clients used `isPinned`
        let isPinned = (payload["pinned"] as? Bool)
            ?? (payload["isPinned"] as? Bool)
            ?? (root["pinned"] as? Bool)
            ?? (root["isPinned"] as? Bool)
            ?? false
        let unpinnedMessageIds = (payload["unpinnedMessageIds"] as? [String])
            ?? (root["unpinnedMessageIds"] as? [String])
            ?? []
        guard !messageId.isEmpty else {
            AppLogger.debug("ChatSocketService: pin event missing messageId: \(root)")
            return
        }
        let update = PinMessageUpdate(
            messageId: messageId,
            conversationId: conversationId,
            isPinned: isPinned,
            unpinnedMessageIds: unpinnedMessageIds
        )
        AppLogger.debug(
            "ChatSocketService: pin update messageId=\(messageId.prefix(8)) pinned=\(isPinned) conv=\(conversationId.prefix(8))"
        )
        DispatchQueue.main.async {
            self.pinMessageUpdateSubject.send(update)
        }
    }

    /// Console `chat:message:pin:expired` → `{ conversationId, messageId }`
    private func handlePinExpiredEvent(data: [Any]) {
        guard let root = data.first as? [String: Any] else { return }
        let payload = (root["data"] as? [String: Any]) ?? root
        let messageId = (payload["messageId"] as? String) ?? (payload["id"] as? String) ?? ""
        let conversationId = (payload["conversationId"] as? String) ?? ""
        guard !messageId.isEmpty else { return }
        let update = PinMessageUpdate(
            messageId: messageId,
            conversationId: conversationId,
            isPinned: false,
            unpinnedMessageIds: []
        )
        DispatchQueue.main.async {
            self.pinMessageUpdateSubject.send(update)
        }
    }

    // MARK: - Pin Message Emit
    /// Console `chat:message:pin` sample: `{ conversationId, messageId, pinned }`
    func pinMessage(messageId: String, conversationId: String, isPinned: Bool, pinDuration: String?) {
        var payload: [String: Any] = [
            "messageId": messageId,
            "conversationId": conversationId,
            "pinned": isPinned
        ]
        if let pinDuration, !pinDuration.isEmpty {
            payload["pinDuration"] = pinDuration
        }
        socketManager.emitMessage(SocketEvent.pinMessage.rawValue, withData: [payload])
    }
}


extension ChatSocketService {
    /// Caller: create a meeting for this conversation
    func createMeeting(conversationId: String) {
        let payload: [String: Any] = ["conversationId": conversationId]
        emitMessage(SocketEvent.createMeeting.rawValue, withData: payload)
    }

    /// Callee: accept incoming call with the payload received from SocketEvent.incomingCall.rawValue
    func acceptCall(_ incomingData: [String: Any]) {
        emitMessage(SocketEvent.acceptCall.rawValue, withData: incomingData)
    }

    /// Callee: decline incoming call with the payload received from SocketEvent.incomingCall.rawValue
    func declineCall(_ incomingData: [String: Any]) {
        emitMessage(SocketEvent.declineCall.rawValue, withData: incomingData)
    }

    /// Any participant: leave the call for self
    func leaveCall(meetingId: String) {
        let payload: [String: Any] = ["meetingId": meetingId]
        emitMessage(SocketEvent.endCall.rawValue, withData: payload)
    }

    /// Any participant: end the call for everyone (when only 2 left)
    func endCall(meetingId: String) {
        let payload: [String: Any] = ["meetingId": meetingId]
        emitMessage(SocketEvent.endCall.rawValue, withData: payload)
    }

    /// Forward a message to multiple conversations (socket fallback — REST is primary).
    /// Web parity: `{ messageIds, targetConversationIds }`
    func forwardMessage(messageIds: [String], receiverIds: [String]) {
        let payload: [String: Any] = [
            "messageIds": messageIds,
            "targetConversationIds": receiverIds,
            "conversationIds": receiverIds
        ]
        emitMessage(SocketEvent.forwardMessage.rawValue, withData: payload)
    }
    func sendChannelMessage(channelId: String, messageType: String = "text", content: String) {
        let payload: [String: Any] = [
            "requestId": UUID().uuidString,
            "channelId": channelId,
            "body": content,
            "type": messageType
        ]
        emitMessage(SocketEvent.sendMessageToChannel.rawValue, withData: payload)
    }

    // MARK: - Channel Admin Delete Handlers

    private func handleAdminDeleteChannelMessageAck(data: [Any]) {
        guard let ack = data.first as? [String: Any] else {
            AppLogger.debug("ChatSocketService: Failed to parse admin-delete-channel-message-ack")
            return
        }
        let statusOk: Bool
        if let b = ack["status"] as? Bool { statusOk = b }
        else if let i = ack["status"] as? Int { statusOk = i == 1 }
        else { statusOk = false }

        guard statusOk else {
            let msg = ack["message"] as? String ?? "Unknown error"
            AppLogger.debug("ChatSocketService: admin-delete-channel-message-ack failed: \(msg)")
            return
        }

        let dataDict = ack["data"] as? [String: Any] ?? ack
        let channelId = dataDict["channelId"] as? String ?? ""

        // Server returns messageId as an array (matching the request format)
        let messageIds: [String]
        if let ids = dataDict["messageId"] as? [String] {
            messageIds = ids
        } else if let singleId = dataDict["messageId"] as? String, !singleId.isEmpty {
            messageIds = [singleId]
        } else {
            AppLogger.debug("ChatSocketService: admin-delete-channel-message-ack missing messageId")
            return
        }

        for messageId in messageIds {
            let partial = ConversationMessage(id: messageId, channelId: channelId, isDeleted: true)
            AppLogger.debug("ChatSocketService: Channel message deleted (admin ack): \(messageId)")
            DispatchQueue.main.async { self.channelMessageDeletedSubject.send(partial) }
        }
    }

    private func handleChannelMessageDeletedBroadcast(data: [Any]) {
        guard let response = data.first as? [String: Any] else {
            AppLogger.debug("ChatSocketService: Failed to parse channel-message-deleted broadcast")
            return
        }
        let payload = response["data"] as? [String: Any] ?? response
        let channelId = payload["channelId"] as? String ?? ""

        // Server can send either messageIds (array) or messageId (single string)
        let messageIds: [String]
        if let ids = payload["messageIds"] as? [String] {
            messageIds = ids
        } else if let singleId = payload["messageId"] as? String ?? payload["id"] as? String, !singleId.isEmpty {
            messageIds = [singleId]
        } else {
            AppLogger.debug("ChatSocketService: channel-message-deleted missing messageId(s)")
            return
        }

        for messageId in messageIds {
            let partial = ConversationMessage(id: messageId, channelId: channelId, isDeleted: true)
            AppLogger.debug("ChatSocketService: Channel message deleted (broadcast): \(messageId)")
            DispatchQueue.main.async { self.channelMessageDeletedSubject.send(partial) }
        }
    }

    // MARK: - Channel Admin Edit Handlers

    private func handleAdminEditChannelMessageAck(data: [Any]) {
        guard let ack = data.first as? [String: Any] else {
            AppLogger.debug("ChatSocketService: Failed to parse admin-edit-channel-message-ack")
            return
        }
        let statusOk: Bool
        if let b = ack["status"] as? Bool { statusOk = b }
        else if let i = ack["status"] as? Int { statusOk = i == 1 }
        else { statusOk = false }

        guard statusOk,
              let messageData = ack["data"] as? [String: Any],
              let message = ConversationMessage.fromDictionary(messageData) else {
            AppLogger.debug("ChatSocketService: admin-edit-channel-message-ack failed or missing data")
            return
        }
        AppLogger.debug("ChatSocketService: Channel message edited (admin ack): \(message.id)")
        DispatchQueue.main.async { self.channelMessageEditedSubject.send(message) }
    }

    private func handleChannelMessageEditedBroadcast(data: [Any]) {
        guard let response = data.first as? [String: Any] else {
            AppLogger.debug("ChatSocketService: Failed to parse channel-message-edited broadcast")
            return
        }
        let payload = response["data"] as? [String: Any] ?? response

        if let message = ConversationMessage.fromDictionary(payload) {
            AppLogger.debug("ChatSocketService: Channel message edited (broadcast): \(message.id)")
            DispatchQueue.main.async { self.channelMessageEditedSubject.send(message) }
            return
        }

        guard let messageId = payload["messageId"] as? String ?? payload["id"] as? String,
              !messageId.isEmpty else {
            AppLogger.debug("ChatSocketService: channel-message-edited missing messageId")
            return
        }
        let content = payload["content"] as? String
        let editedAt = payload["editedAt"] as? String
        let channelId = payload["channelId"] as? String ?? ""
        let partial = ConversationMessage(
            id: messageId,
            channelId: channelId,
            content: content,
            isEdited: true
        )
        AppLogger.debug("ChatSocketService: Channel message edited (partial broadcast): \(messageId)")
        DispatchQueue.main.async { self.channelMessageEditedSubject.send(partial) }
    }
}

