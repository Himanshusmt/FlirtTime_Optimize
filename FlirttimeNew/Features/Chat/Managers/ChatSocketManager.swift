//
//  ChatSocketManager.swift
//  FlirttimeNew
//
//  Created by Devesh Pareek on 19/03/24.
//

import Foundation
import SocketIO
import KeychainAccess
import Network
import UIKit
import Swinject

/// Parses NEW (`success`) and OLD (`status`) Socket.IO ack envelopes.
enum SocketAckParser {
    static func isSuccess(_ payload: [String: Any]) -> Bool {
        for key in ["success", "status"] {
            if let b = payload[key] as? Bool { return b }
            if let i = payload[key] as? Int { return i == 1 }
            if let n = payload[key] as? NSNumber { return n.boolValue }
        }
        return false
    }

    /// Prefer nested `data`; otherwise treat the payload itself as the message.
    static func messagePayload(from ack: [String: Any]) -> [String: Any]? {
        if let data = ack["data"] as? [String: Any] { return data }
        if ack["id"] != nil { return ack }
        return nil
    }

    static func parseMessage(from data: [Any]) -> ConversationMessage? {
        guard let ack = data.first as? [String: Any],
              isSuccess(ack),
              let messageData = messagePayload(from: ack) else { return nil }
        return ConversationMessage.fromDictionary(messageData)
    }

    /// Socket / JSON often encode booleans as `NSNumber` — `as? Bool` alone fails.
    static func boolValue(from value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let i = value as? Int { return i != 0 }
        if let s = value as? String {
            switch s.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    /// FE `chat:conversation:settings:updated` sample is flat
    /// `{ conversationId, isMuted }` — also accept nested `{ settings: { … } }`.
    static func conversationSettings(from payload: [String: Any]) -> (conversationId: String, settings: [String: Any])? {
        let conversationId = (payload["conversationId"] as? String)
            ?? (payload["conversation_id"] as? String)
            ?? ""
        guard !conversationId.isEmpty else { return nil }

        var settings: [String: Any] = [:]
        if let nested = payload["settings"] as? [String: Any] {
            settings = nested
        }
        for key in ["isMuted", "isPinned", "isArchived", "isBlocked", "isLocked", "labelText", "labelColor", "disappearingMessages"] {
            if let value = payload[key], settings[key] == nil {
                settings[key] = value
            }
        }
        guard !settings.isEmpty else { return nil }
        return (conversationId, settings)
    }
}

/// Socket.IO events — https://socket.onevibe.walit.in/console (`/console/events.json`)
/// NEW names use `namespace:action` (e.g. `chat:message:send`). OLD kebab-case noted in comments.
enum SocketEvent: String, CaseIterable {
    case socketAck = "socket_ack" // legacy client ack helper

    // MARK: Chat messages
    case sendConversationMessage = "chat:message:send" // NEW — OLD: send-conversation-message / send-new-message
    case sendConversationMessageAck = "chat:message:send:ack" // NEW — OLD: send-conversation-message-ack / new-message-ack
    case getMessage = "chat:message:new" // NEW listener — OLD: get-message
    case translateMessage = "chat:message:translate" // NEW — OLD: translate-message
    case translateMessageAck = "chat:message:translate:ack" // NEW — OLD: translate-message-ack
    case editMessage = "chat:message:edit" // NEW — OLD: edit-message / update-conversation-message
    case editMessageAck = "chat:message:edit:ack" // NEW — OLD: edit-message-ack / update-conversation-message-ack
    case messageEdited = "chat:message:edited" // NEW — OLD: message-edited
    case deleteMessage = "chat:message:delete" // NEW — OLD: delete-message / delete-conversation-message
    case deleteMessageAck = "chat:message:delete:ack" // NEW — OLD: delete-message-ack / delete-conversation-message-ack
    case messageDeleted = "chat:message:deleted" // NEW — OLD: message-deleted
    case forwardMessage = "chat:message:forward" // NEW — OLD: forward-message
    case forwardMessageAck = "chat:message:forward:ack" // NEW — OLD: forward-message-ack
    case reactToMessage = "chat:message:react" // NEW — OLD: react-to-message
    case reactToMessageAck = "chat:message:react:ack" // NEW — OLD: react-to-message-ack
    /// Android `CHAT_MESSAGE_REACTED` — realtime reaction fanout to conversation members
    case messageReacted = "chat:message:reacted"
    case messageDelivered = "chat:message:delivered" // NEW
    case chatListing = "chat:message:list" // NEW — OLD: chat-listing
    case chatListingResp = "chat:message:list:ack" // NEW — OLD: chat-listing-resp
    case seenMessages = "chat:message:seen" // NEW — OLD: seen-messages / mark-conversation-messages-seen
    case seenMessagesAck = "chat:message:seen:ack" // NEW — OLD: mark-conversation-messages-seen-ack
    case conversationMessageStatusUpdate = "chat:message:status" // NEW — OLD: conversation-message-status-update

    // Aliases kept so existing call sites compile (same NEW event names)
    static var sendNewMessage: SocketEvent { .sendConversationMessage }
    static var newMessageAck: SocketEvent { .sendConversationMessageAck }
    static var updateConversationMessage: SocketEvent { .editMessage }
    static var updateConversationMessageAck: SocketEvent { .editMessageAck }
    static var deleteConversationMessage: SocketEvent { .deleteMessage }
    static var deleteConversationMessageAck: SocketEvent { .deleteMessageAck }
    static var markConversationMessagesSeen: SocketEvent { .seenMessages }
    static var markConversationMessagesSeenAck: SocketEvent { .seenMessagesAck }

    case userList = "get-user-list" // OLD — not in NEW socket catalog
    case userListResp = "user-list" // OLD — not in NEW socket catalog
    case recentChatUser = "recent-chat-user" // OLD — not in NEW socket catalog

    // MARK: Conversation
    case joinConversation = "chat:conversation:join" // NEW — sample: conversation UUID string
    case leaveConversation = "chat:conversation:leave" // NEW
    case conversationViewing = "chat:conversation:viewing" // NEW — { conversationId, active } (FE)
    case updateConversationSettings = "chat:conversation:settings:update" // NEW — OLD: update-conversation-settings
    case conversationSettingsUpdated = "chat:conversation:settings:updated" // NEW — OLD: conversation-settings-updated
    /// FE / socket console — block edge created (rooms: user:{actor}, user:{target})
    case userBlocked = "user:blocked"
    /// FE / socket console — block edge removed
    case userUnblocked = "user:unblocked"
    case deleteConversation = "chat:conversation:delete" // NEW — OLD: delete-conversation
    case deleteConversationAck = "chat:conversation:delete:ack" // NEW — OLD: delete-conversation-ack
    case createConversation = "chat:conversation:create" // NEW — OLD: create-conversation
    case createConversationAck = "chat:conversation:create:ack" // NEW
    case listConversations = "chat:conversation:list" // NEW — c2s inbox via socket
    case listConversationsAck = "chat:conversation:list:ack" // NEW
    case getConversation = "chat:conversation:get" // NEW — c2s one conversation
    case getConversationAck = "chat:conversation:get:ack" // NEW
    case getConversationStatus = "chat:conversation:status:get" // NEW — OLD: get-conversation-status
    case getConversationStatusAck = "chat:conversation:status:get:ack" // NEW — OLD: get-conversation-status-ack
    case messageUpdated = "chat:inbox:refresh" // NEW — soft signal to re-fetch inbox (FE INBOX_REFRESH)
    case getGlobalUnreadCount = "chat:unread:get" // NEW — OLD: get-global-unread-count
    case getGlobalUnreadCountAck = "chat:unread:get:ack" // NEW
    case conversationScreenshot = "chat:screenshot" // NEW — OLD: conversation-screenshot
    case conversationSystemMessage = "chat:system:message" // NEW — OLD: conversation-system-message
    case conversationDeletedPush = "chat:conversation:deleted" // NEW — s2c remove from UI
    case conversationSettingsUpdateAck = "chat:conversation:settings:update:ack" // NEW
    case memberAdd = "chat:member:add" // NEW — c2s add members
    case memberAddAck = "chat:member:add:ack" // NEW
    case memberAdded = "chat:member:added" // NEW — s2c fanout when members added / group created
    case memberRemove = "chat:member:remove" // NEW
    case memberRemoveAck = "chat:member:remove:ack" // NEW
    case memberRemoved = "chat:member:removed" // NEW
    case memberLeave = "chat:member:leave" // NEW
    case memberLeaveAck = "chat:member:leave:ack" // NEW
    case memberRoleUpdated = "chat:member:role:updated" // NEW — s2c
    case groupUpdate = "chat:group:update" // NEW
    case groupUpdateAck = "chat:group:update:ack" // NEW
    case groupUpdated = "chat:group:updated" // NEW — s2c group metadata changed

    // MARK: Pin
    case pinMessage = "chat:message:pin" // NEW — OLD: pin-message
    case pinMessageAck = "chat:message:pin:ack" // NEW — OLD: pin-message-ack
    case getPinnedMessages = "chat:message:pin:list" // NEW — OLD: get-pinned-messages
    case getPinnedMessagesAck = "chat:message:pin:list:ack" // NEW — OLD: get-pinned-messages-ack
    case messagePinUpdated = "chat:message:pin:updated" // NEW — OLD: message-pin-updated
    case messagePinExpired = "chat:message:pin:expired" // NEW — s2c

    // MARK: Poll
    case votePoll = "chat:poll:vote" // NEW — OLD: vote-poll
    case votePollAck = "chat:poll:vote:ack" // NEW — OLD: vote-poll-ack

    // MARK: Presence / typing / heartbeat
    case emitUserStatus = "presence:set" // NEW — OLD: user-status
    case broadcastUserStatus = "presence:update" // NEW listener — OLD: broadcast-user-status / user-status-resp
    case presenceGet = "presence:get" // NEW — FE subscribePresence({ userIds })
    case getOnlineUsers = "presence:online:list" // NEW — OLD: get-online-users
    case getOnlineUsersAck = "presence:online:list:ack" // NEW — OLD: get-online-users-ack
    case userTyping = "presence:typing" // NEW emit — OLD: user-typing
    case userTypingUpdate = "presence:typing:update" // NEW listener (was same as emit on OLD user-typing)
    case heartbeat = "system:heartbeat" // NEW — OLD: heartbeat
    case heartbeatAck = "system:heartbeat:ack" // NEW — OLD: heartbeat-ack
    static var listenUserStatus: SocketEvent { .broadcastUserStatus }

    case error = "error" // NEW — OLD: exception
    case disconnected = "disconnected"

    // MARK: Live Location (OLD — not in NEW socket catalog)
    case startLiveLocation = "start-live-location" // OLD
    case startLiveLocationAck = "start-live-location-ack" // OLD
    case updateLiveLocation = "update-live-location" // OLD
    case liveLocationUpdated = "live-location-update" // OLD
    case stopLiveLocation = "stop-live-location" // OLD
    case stopLiveLocationAck = "stop-live-location-ack" // OLD
    case liveLocationStopped = "live-location-stopped" // OLD

    // MARK: Channel
    case sendMessageToChannel = "channel:message:send" // NEW — OLD: send-message-to-channel
    case sendMessageToChannelAck = "channel:message:send:ack" // NEW — OLD: send-message-to-channel-ack
    case incomingChannelMessage = "channel:message:new" // NEW — OLD: incoming-channel-message
    case adminDeleteChannelMessage = "channel:message:admin:delete" // NEW — OLD: admin-delete-channel-message
    case adminDeleteChannelMessageAck = "channel:message:admin:delete:ack" // NEW — OLD: admin-delete-channel-message-ack
    case channelMessageDeleted = "channel:message:deleted" // NEW — OLD: channel-message-deleted
    case adminEditChannelMessage = "channel:message:admin:edit" // NEW — OLD: admin-edit-channel-message
    case adminEditChannelMessageAck = "channel:message:admin:edit:ack" // NEW — OLD: admin-edit-channel-message-ack
    case channelMessageEdited = "channel:message:edited" // NEW — OLD: channel-message-edited
    case getChannelsList = "channel:list" // NEW — OLD: get-channels-list
    case getChannelsListAck = "channel:list:ack" // NEW — OLD: get-channels-list-ack
    case getFollowedChannelsList = "channel:followed:list" // NEW
    case getFollowedChannelsListAck = "channel:followed:list:ack" // NEW
    case createChannel = "channel:create" // NEW — OLD: create-channel; sample: name, description, isPublic, participantIds, adminIds
    case createChannelAck = "channel:create:ack" // NEW
    case channelUpdated = "channel:updated" // NEW — OLD: channel-updated
    case channelEdit = "channel:edit" // NEW
    case channelEditAck = "channel:edit:ack" // NEW
    case channelFollowersUpdated = "channel:followers:updated" // NEW — receive-only fanout
    case followOrUnfollowChannel = "channel:follow" // NEW — OLD: follow-or-unfollow-channel
    case followChannelAck = "channel:follow:ack" // NEW — OLD: follow-or-unfollow-channel-ack
    case channelLeave = "channel:leave" // NEW unfollow/leave OR room leave (FE)
    case channelJoin = "channel:join" // NEW — join channel socket room (FE joinChannelRoom)
    /// FE / console — focused/blurred channel thread `{ channelId, active }` (Redis; suppresses unread +1 while active)
    case channelViewing = "channel:viewing"
    /// FE / console — mark channel read (and older). Server also pushes to the actor’s devices with unreadCount 0.
    case channelMessageSeen = "channel:message:seen"
    case channelMessageSeenAck = "channel:message:seen:ack"
    /// FE / console — mark channel unread. Server pushes to the actor’s devices with server unreadCount.
    case channelMessageUnread = "channel:message:unread"
    case channelMessageUnreadAck = "channel:message:unread:ack"
    case deleteChannel = "channel:delete" // NEW — OLD: delete-channel
    case deleteChannelAck = "channel:delete:ack" // NEW — OLD: delete-channel-ack

    // MARK: Calls — legacy Dyte (OLD event names; must stay separate from Agora call:*)
    case createMeeting = "create-meeting"
    case createMeetingAck = "create-meeting-ack"
    case incomingCall = "incoming-call"
    case acceptCall = "accept-call"
    case declineCall = "decline-call"
    case rejectCall = "reject-call"
    case joinCall = "join-call"
    case leaveCall = "leave-call"
    case leaveCallAck = "leave-call-ack"
    case endCall = "end-call"
    case endCallAck = "end-call-ack"
    case remoteCallEnded = "remote-call-ended"

    // MARK: Calls — Agora NEW (known-event catalog; runtime uses AgoraCallSocketEvents)
    case agoraCallCreate = "call:create"
    case agoraCallCreateAck = "call:create:ack"
    case agoraCallIncoming = "call:incoming"
    case agoraCallAccept = "call:accept"
    case agoraCallJoin = "call:join"
    case agoraCallDecline = "call:decline"
    case agoraCallDeclined = "call:declined"
    case agoraCallBusy = "call:busy"
    case agoraCallRejected = "call:rejected"
    case agoraCallCancelled = "call:cancelled"
    case agoraCallRinging = "call:ringing"
    case agoraCallLeave = "call:leave"
    case agoraCallLeaveAck = "call:leave:ack"
    case agoraCallEnd = "call:end"
    case agoraCallEndAck = "call:end:ack"
    case agoraCallParticipantJoined = "call:participant:joined"
    case agoraCallParticipantLeft = "call:participant:left"

    // MARK: Social — feed / vibe / profile / follow
    case profileJoin = "profile:join"
    case profileLeave = "profile:leave"
    case feedPostJoin = "feed:post:join"
    case feedPostLeave = "feed:post:leave"
    case vibeJoin = "vibe:join"
    case vibeLeave = "vibe:leave"
    case feedPostCreated = "feed:post:created"
    case feedPostDeleted = "feed:post:deleted"
    case feedPostUpdated = "feed:post:updated"
    case vibeCreated = "vibe:created"
    case vibeDeleted = "vibe:deleted"
    case vibeUpdated = "vibe:updated"
    case feedCommentCreated = "feed:comment:created"
    case feedCommentDeleted = "feed:comment:deleted"
    case feedCommentUpdated = "feed:comment:updated"
    case vibeCommentCreated = "vibe:comment:created"
    case vibeCommentDeleted = "vibe:comment:deleted"
    case vibeCommentUpdated = "vibe:comment:updated"
    case followChanged = "follow:changed"
}

class ChatSocketManager {
    static let shared = ChatSocketManager()

    private var socket: SocketIOClient?
    private var manager: SocketManager
    private let keychain: Keychain
    private var isConnected: Bool = false
    private var isConnecting: Bool = false

    private var retryCount: Int = 0
    private let maxRetries: Int = 3

    private typealias SocketListenerCallback = ([Any]) -> Void
    private struct ListenerRegistration {
        let eventName: String
        let callback: SocketListenerCallback
    }

    private var registeredListeners: [UUID: ListenerRegistration] = [:]
    private var registeredListenerSocketIds: [UUID: UUID] = [:]

    private let pathMonitor = NWPathMonitor()
    private var lastPathStatus: NWPath.Status = .requiresConnection

    // Heartbeat
    private var heartbeatTimer: Timer?
    private var isHeartbeatActive = false
    /// UAE/KZ: shorter ping so a dead India socket is detected before the next incoming call.
    private var heartbeatInterval: TimeInterval {
        CallInternationalDiagnostics.prefersForcedTCPCloudProxy ? 15.0 : 25.0
    }

    /// Emits queued while socket was disconnected — flushed on connect.
    private var pendingEmits: [(event: String, data: [SocketData])] = []
    private let pendingEmitsLock = NSLock()

    /// Rooms to re-join after reconnect (FE joins inbox + open chat).
    private var trackedConversationIds = Set<String>()
    private var trackedChannelIds = Set<String>()
    /// Retain-count social rooms so Home sync + comment sheet can share a room safely.
    private var profileRoomRetainCounts: [String: Int] = [:]
    private var postRoomRetainCounts: [String: Int] = [:]
    private var vibeRoomRetainCounts: [String: Int] = [:]
    /// IDs currently owned by `syncPostRooms` / `syncVibeRooms` (one retain each).
    private var syncedPostIds = Set<String>()
    private var syncedVibeIds = Set<String>()
    private var activeViewingConversationId: String?
    private var activeViewingChannelId: String?
    /// Last inbox IDs from chat list — detail leave re-joins if still listed.
    private var lastInboxConversationIds = Set<String>()
    private var lastInboxChannelIds = Set<String>()

    private init() {
        keychain = Keychain()
        let url = URL(string: ChatConfig.socketURL) ?? URL(fileURLWithPath: "")
        print("[Socket] Initialising. Base URL: \(url.absoluteString)")
        manager = SocketManager(socketURL: url, config: [.log(false)])
        socket = manager.defaultSocket
        startNetworkMonitoring()
        setupAppLifecycleObservers()
    }

    private var lastSocketURL: String = ""

    private func buildManager(token: String) -> SocketManager {
        let url = URL(string: ChatConfig.socketURL) ?? URL(fileURLWithPath: "")
        // Prefer WebSocket with Engine.IO polling fallback.
        // Historical `forcePolling(true)` (Apache on walit.in) hurts high-latency UAE/KZ paths
        // and blocks upgrade to WS on production.onevibe.ai (nginx).
        return SocketManager(socketURL: url, config: [
            .log(false),
            .forcePolling(false),
            .forceWebsockets(false),
            .path(ChatConfig.socketPath),
            .compress,
            .reconnects(true),
            .reconnectWait(1),
            .reconnectAttempts(-1),
            .connectParams(["token": token]),
            .extraHeaders(["Authorization": "Bearer \(token)", "token": token]),
            .version(.three)
        ])
    }

    private func setupSocketEvents() {
        // Catch-all: log every incoming socket event, including ones we don't handle
        socket?.onAny { event in
            // Engine.IO transport keepalive — ignore noise
            if event.event == "ping" || event.event == "pong" { return }

            let knownEvents = Set(SocketEvent.allCases.map { $0.rawValue })
            let eventName = event.event
            let isKnown = knownEvents.contains(eventName)
            let tag = isKnown ? "HANDLED" : "UNHANDLED"

            // Use String description only — Socket.IO items can contain
            // non-JSON-serializable Swift types that crash NSJSONSerialization.
            if let items = event.items, !items.isEmpty {
                print("[SOCKET ALL] [\(tag)] Event: \(eventName) | Data: \(items)")
            } else {
                print("[SOCKET ALL] [\(tag)] Event: \(eventName) | (no data)")
            }

            if !isKnown {
                print("[SOCKET ALL] ⚠️ UNHANDLED event '\(eventName)' — consider adding a listener for this")
            }
        }

        socket?.on(clientEvent: .statusChange) { data, _ in
            DispatchQueue.main.async {
                print("[Socket] Status changed: \(data)")
            }
        }

        socket?.on(clientEvent: .connect) { [weak self] data, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                // Ignore stale connect callbacks if the engine already dropped.
                guard self.socket?.status == .connected else {
                    print("[Socket] Ignoring connect callback — status is \(self.socket?.status.description ?? "nil")")
                    return
                }
                print("[Socket] Connected. SID: \(self.socket?.sid ?? "unknown")")
                self.isConnected = true
                self.isConnecting = false
                self.retryCount = 0
                CallInternationalDiagnostics.log(
                    "socketConnected sid=\(self.socket?.sid ?? "?") \(CallInternationalDiagnostics.networkPathSummary)"
                )
                self.startHeartbeat()
                self.flushPendingEmits()
                self.rejoinTrackedRooms()
                // Refresh online strip for ChatList after reconnect
                ChatListSocketService.shared.requestOnlineUsers()
                NotificationCenter.default.post(name: .chatSocketDidConnect, object: nil)
            }
        }

        socket?.on(clientEvent: .disconnect) { [weak self] data, _ in
            DispatchQueue.main.async {
                let reason = data.first as? String ?? "unknown"
                print("[Socket] Disconnected. Reason: \(reason)")
                CallInternationalDiagnostics.log("socketDisconnected reason=\(reason)")
                self?.stopHeartbeat()
                self?.isConnected = false
                self?.isConnecting = false
                NotificationCenter.default.post(name: .chatSocketDidDisconnect, object: nil)
            }
        }

        socket?.on(clientEvent: .error) { [weak self] data, _ in
            DispatchQueue.main.async {
                print("[Socket] Client error: \(data)")
                self?.isConnecting = false
            }
        }

        socket?.on(clientEvent: .reconnect) { data, _ in
            DispatchQueue.main.async {
                print("[Socket] Reconnect attempt: \(data)")
            }
        }

        socket?.on("error") { data, _ in
            DispatchQueue.main.async {
                print("[Socket] Server error event: \(data)")
            }
        }
    }

    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let previousStatus = self.lastPathStatus
            self.lastPathStatus = path.status

            guard path.status == .satisfied, previousStatus != .satisfied else { return }

            // Network just became available — reconnect if not already connected.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                guard !self.isConnected else { return }
                print("[Socket] Network restored — triggering reconnect")
                self.establishConnection()
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.onevibe.socketNetworkMonitor", qos: .utility))
    }

    func establishConnection() {
        if Thread.isMainThread {
            establishConnectionOnMain(force: false)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.establishConnectionOnMain(force: false)
            }
        }
    }

    /// Tears down any half-open / reconnecting session and connects fresh.
    func forceReconnect() {
        if Thread.isMainThread {
            establishConnectionOnMain(force: true)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.establishConnectionOnMain(force: true)
            }
        }
    }

    private func establishConnectionOnMain(force: Bool) {
        let status = socket?.status
        let urlChanged = lastSocketURL != ChatConfig.socketURL

        if !force && !urlChanged {
            if isSocketConnected() { return }
            if isConnecting || status == .connecting {
                print("[Socket] Already connecting — waiting. status=\(status?.description ?? "nil")")
                return
            }
        }

        guard let token = keychain[ChatConfig.accessTokenKey], !token.isEmpty else {
            print("[Socket] Cannot connect — access token not found in keychain.")
            return
        }

        stopHeartbeat()
        isConnected = false
        isConnecting = false

        socket?.removeAllHandlers()
        socket?.disconnect()
        socket = nil

        lastSocketURL = ChatConfig.socketURL
        print("[Socket] Connecting to \(ChatConfig.socketURL) path=\(ChatConfig.socketPath) force=\(force) — token: \(String(token.prefix(20)))...")

        manager = buildManager(token: token)
        socket = manager.defaultSocket
        setupSocketEvents()
        reattachRegisteredListeners()

        isConnecting = true
        // Socket.IO v3+ auth payload (same as web: auth: { token })
        socket?.connect(withPayload: ["token": token])
        print("[Socket] connect(withPayload:) called. Status: \(socket?.status.description ?? "nil")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self else { return }
            let currentStatus = self.socket?.status.description ?? "nil (socket deallocated)"
            print("[Socket] 4s diagnostic — isConnected: \(self.isConnected)  socketStatus: \(currentStatus)")
            // If still stuck connecting after 4s, clear the connecting latch so callers can retry.
            if !self.isSocketConnected(), self.isConnecting {
                print("[Socket] Still not connected after 4s — clearing isConnecting latch")
                self.isConnecting = false
            }
        }
    }

    func closeConnection() {
        let closeAction = { [weak self] in
            guard let self else { return }
            print("[Socket] Closing connection.")
            self.isConnecting = false
            self.isConnected = false
            self.stopHeartbeat()
            self.socket?.disconnect()
        }
        if Thread.isMainThread {
            closeAction()
        } else {
            DispatchQueue.main.async(execute: closeAction)
        }
    }

    func clearSocketListeners() {
        let clearAction = { [weak self] in
            guard let self else { return }
            self.socket?.removeAllHandlers()
            self.registeredListeners.removeAll()
            self.registeredListenerSocketIds.removeAll()
            self.setupSocketEvents()
        }
        if Thread.isMainThread {
            clearAction()
        } else {
            DispatchQueue.main.async(execute: clearAction)
        }
    }

    func isSocketConnected() -> Bool {
        // Prefer live engine status — flag can lag behind reconnect races
        if socket?.status == .connected { return true }
        return isConnected
    }

    func isSocketConnecting() -> Bool {
        isConnecting || socket?.status == .connecting
    }

    /// Start a connect if idle. Does not tear down an in-flight handshake (unlike `forceReconnect`).
    func ensureConnecting() {
        if Thread.isMainThread {
            if isSocketConnected() { return }
            if isSocketConnecting() {
                print("[Socket] ensureConnecting — handshake already in flight")
                return
            }
            establishConnectionOnMain(force: false)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.ensureConnecting()
            }
        }
    }

    func hasAccessToken() -> Bool {
        guard let token = keychain[ChatConfig.accessTokenKey] else { return false }
        return !token.isEmpty
    }

    private func retryConnection() {
        guard retryCount < maxRetries else {
            print("Maximum retries reached. Could not connect to socket.")
            return
        }

        retryCount += 1
        print("Retrying connection... (Attempt \(retryCount) of \(maxRetries))")
        establishConnection()
    }

    // Function to establish connection with retry logic
    func establishConnectionWithRetry() {
        guard !isSocketConnected() else {
            print("Socket is already connected.")
            return
        }

        establishConnection()
        retryConnection()
    }

    func emitMessage(_ message: String, withData data: [SocketData]) {
        if isSocketConnected() {
            print("[SOCKET SENT] Event: \(message): \(data)")
            socket?.emit(message, with: data, completion: nil)
            return
        }

        print("[SOCKET QUEUE] Not connected — queueing \(message) and reconnecting")
        pendingEmitsLock.lock()
        pendingEmits.append((event: message, data: data))
        // Keep queue bounded
        if pendingEmits.count > 50 {
            pendingEmits.removeFirst(pendingEmits.count - 50)
        }
        pendingEmitsLock.unlock()
        establishConnectionWithRetry()
    }

    private func flushPendingEmits() {
        pendingEmitsLock.lock()
        let queued = pendingEmits
        pendingEmits.removeAll()
        pendingEmitsLock.unlock()

        guard !queued.isEmpty else { return }
        print("[SOCKET QUEUE] Flushing \(queued.count) pending emit(s)")
        for item in queued {
            print("[SOCKET SENT] Event: \(item.event): \(item.data)")
            socket?.emit(item.event, with: item.data, completion: nil)
        }
    }

    // MARK: - Room / viewing (FE parity)

    func joinConversationRoom(_ conversationId: String) {
        guard !conversationId.isEmpty else { return }
        trackedConversationIds.insert(conversationId)
        emitMessage(SocketEvent.joinConversation.rawValue, withData: [conversationId])
        AppLogger.debug("[SocketRoom] join conversation \(conversationId)")
    }

    func leaveConversationRoom(_ conversationId: String) {
        guard !conversationId.isEmpty else { return }
        trackedConversationIds.remove(conversationId)
        if activeViewingConversationId == conversationId {
            activeViewingConversationId = nil
        }
        emitMessage(SocketEvent.leaveConversation.rawValue, withData: [conversationId])
        AppLogger.debug("[SocketRoom] leave conversation \(conversationId)")
    }

    /// Join many inbox rooms so `message:new` updates the list without opening a thread.
    func joinConversationRooms(_ conversationIds: [String]) {
        let ids = conversationIds.filter { !$0.isEmpty }
        lastInboxConversationIds = Set(ids)
        for id in ids {
            joinConversationRoom(id)
        }
    }

    func isInboxConversation(_ conversationId: String) -> Bool {
        lastInboxConversationIds.contains(conversationId)
    }

    /// FE `setConversationViewing` — payload `{ conversationId, active }`.
    func setConversationViewing(conversationId: String, active: Bool) {
        guard !conversationId.isEmpty else { return }
        if active {
            activeViewingConversationId = conversationId
        } else if activeViewingConversationId == conversationId {
            activeViewingConversationId = nil
        }
        emitMessage(
            SocketEvent.conversationViewing.rawValue,
            withData: [["conversationId": conversationId, "active": active]]
        )
        AppLogger.debug("[SocketRoom] viewing conversationId=\(conversationId) active=\(active)")
    }

    func joinChannelRoom(_ channelId: String) {
        guard !channelId.isEmpty else { return }
        trackedChannelIds.insert(channelId)
        emitMessage(SocketEvent.channelJoin.rawValue, withData: [channelId])
        AppLogger.debug("[SocketRoom] join channel \(channelId)")
    }

    /// Join many channel inbox rooms so `channel:message:new` updates the list without opening a thread.
    func joinChannelRooms(_ channelIds: [String]) {
        let ids = channelIds.filter { !$0.isEmpty }
        lastInboxChannelIds = Set(ids)
        for id in ids {
            joinChannelRoom(id)
        }
    }

    func isInboxChannel(_ channelId: String) -> Bool {
        lastInboxChannelIds.contains(channelId)
    }

    func isViewingChannel(_ channelId: String) -> Bool {
        activeViewingChannelId == channelId
    }

    /// FE `setChannelViewing` — payload `{ channelId, active }`.
    func setChannelViewing(channelId: String, active: Bool) {
        guard !channelId.isEmpty else { return }
        if active {
            activeViewingChannelId = channelId
        } else if activeViewingChannelId == channelId {
            activeViewingChannelId = nil
        }
        emitMessage(
            SocketEvent.channelViewing.rawValue,
            withData: [["channelId": channelId, "active": active]]
        )
        AppLogger.debug("[SocketRoom] viewing channelId=\(channelId) active=\(active)")
    }

    func leaveChannelRoom(_ channelId: String) {
        guard !channelId.isEmpty else { return }
        trackedChannelIds.remove(channelId)
        lastInboxChannelIds.remove(channelId)
        if activeViewingChannelId == channelId {
            activeViewingChannelId = nil
        }
        emitMessage(SocketEvent.channelLeave.rawValue, withData: [channelId])
        AppLogger.debug("[SocketRoom] leave channel \(channelId)")
    }

    // MARK: - Social rooms (profile / post / vibe)

    func joinProfileRoom(_ userId: String) {
        retainSocialRoom(
            id: userId,
            counts: &profileRoomRetainCounts,
            joinEvent: SocketEvent.profileJoin.rawValue,
            payloadKey: "userId"
        )
    }

    func leaveProfileRoom(_ userId: String) {
        releaseSocialRoom(
            id: userId,
            counts: &profileRoomRetainCounts,
            leaveEvent: SocketEvent.profileLeave.rawValue,
            payloadKey: "userId"
        )
    }

    func joinPostRoom(_ postId: String) {
        retainSocialRoom(
            id: postId,
            counts: &postRoomRetainCounts,
            joinEvent: SocketEvent.feedPostJoin.rawValue,
            payloadKey: "postId"
        )
    }

    func leavePostRoom(_ postId: String) {
        releaseSocialRoom(
            id: postId,
            counts: &postRoomRetainCounts,
            leaveEvent: SocketEvent.feedPostLeave.rawValue,
            payloadKey: "postId"
        )
    }

    /// Diff join/leave so only currently visible feed posts stay in `post:{id}` rooms.
    func syncPostRooms(_ postIds: [String]) {
        let desired = Set(postIds.filter { !$0.isEmpty })
        let toLeave = syncedPostIds.subtracting(desired)
        let toJoin = desired.subtracting(syncedPostIds)
        syncedPostIds = desired
        for id in toLeave { leavePostRoom(id) }
        for id in toJoin { joinPostRoom(id) }
    }

    func joinVibeRoom(_ vibeId: String) {
        retainSocialRoom(
            id: vibeId,
            counts: &vibeRoomRetainCounts,
            joinEvent: SocketEvent.vibeJoin.rawValue,
            payloadKey: "vibeId"
        )
    }

    func leaveVibeRoom(_ vibeId: String) {
        releaseSocialRoom(
            id: vibeId,
            counts: &vibeRoomRetainCounts,
            leaveEvent: SocketEvent.vibeLeave.rawValue,
            payloadKey: "vibeId"
        )
    }

    func syncVibeRooms(_ vibeIds: [String]) {
        let desired = Set(vibeIds.filter { !$0.isEmpty })
        let toLeave = syncedVibeIds.subtracting(desired)
        let toJoin = desired.subtracting(syncedVibeIds)
        syncedVibeIds = desired
        for id in toLeave { leaveVibeRoom(id) }
        for id in toJoin { joinVibeRoom(id) }
    }

    /// Clear social room tracking (logout). Does not emit leave — connection is closing.
    func clearSocialRoomTracking() {
        profileRoomRetainCounts.removeAll()
        postRoomRetainCounts.removeAll()
        vibeRoomRetainCounts.removeAll()
        syncedPostIds.removeAll()
        syncedVibeIds.removeAll()
    }

    private func retainSocialRoom(
        id: String,
        counts: inout [String: Int],
        joinEvent: String,
        payloadKey: String
    ) {
        guard !id.isEmpty else { return }
        let next = (counts[id] ?? 0) + 1
        counts[id] = next
        guard next == 1 else { return }
        emitMessage(joinEvent, withData: [[payloadKey: id]])
        AppLogger.debug("[SocketRoom] join \(joinEvent) \(id)")
    }

    private func releaseSocialRoom(
        id: String,
        counts: inout [String: Int],
        leaveEvent: String,
        payloadKey: String
    ) {
        guard !id.isEmpty else { return }
        // Already released (e.g. viewDidDisappear + deinit) — do not emit a spurious leave.
        guard let current = counts[id], current > 0 else { return }
        let next = current - 1
        if next <= 0 {
            counts.removeValue(forKey: id)
            emitMessage(leaveEvent, withData: [[payloadKey: id]])
            AppLogger.debug("[SocketRoom] leave \(leaveEvent) \(id)")
        } else {
            counts[id] = next
        }
    }

    private func rejoinTrackedRooms() {
        let conversations = Array(trackedConversationIds)
        let channels = Array(trackedChannelIds)
        let profiles = Array(profileRoomRetainCounts.keys)
        let posts = Array(postRoomRetainCounts.keys)
        let vibes = Array(vibeRoomRetainCounts.keys)
        let viewing = activeViewingConversationId
        let channelViewing = activeViewingChannelId
        guard !conversations.isEmpty || !channels.isEmpty || !profiles.isEmpty
                || !posts.isEmpty || !vibes.isEmpty || viewing != nil || channelViewing != nil else { return }

        AppLogger.debug("[SocketRoom] Rejoining \(conversations.count) conversations, \(channels.count) channels, \(profiles.count) profiles, \(posts.count) posts, \(vibes.count) vibes, viewing=\(viewing ?? "nil") channelViewing=\(channelViewing ?? "nil")")
        for id in conversations {
            socket?.emit(SocketEvent.joinConversation.rawValue, with: [id], completion: nil)
        }
        for id in channels {
            socket?.emit(SocketEvent.channelJoin.rawValue, with: [id], completion: nil)
        }
        for id in profiles {
            socket?.emit(SocketEvent.profileJoin.rawValue, with: [["userId": id]], completion: nil)
        }
        for id in posts {
            socket?.emit(SocketEvent.feedPostJoin.rawValue, with: [["postId": id]], completion: nil)
        }
        for id in vibes {
            socket?.emit(SocketEvent.vibeJoin.rawValue, with: [["vibeId": id]], completion: nil)
        }
        if let viewing {
            socket?.emit(
                SocketEvent.conversationViewing.rawValue,
                with: [["conversationId": viewing, "active": true]],
                completion: nil
            )
        }
        if let channelViewing {
            socket?.emit(
                SocketEvent.channelViewing.rawValue,
                with: [["channelId": channelViewing, "active": true]],
                completion: nil
            )
        }
    }

    // MARK: - Heartbeat

    private func emitHeartbeat() {
        guard isConnected else { return }
        let payload: [String: Any] = ["timestamp": Int(Date().timeIntervalSince1970 * 1000)]
        emitMessage(SocketEvent.heartbeat.rawValue, withData: [payload])
    }

    private func startHeartbeat() {
        guard !isHeartbeatActive else { return }
        isHeartbeatActive = true

        emitHeartbeat()

        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: heartbeatInterval,
            repeats: true
        ) { [weak self] _ in
            self?.emitHeartbeat()
        }
        print("[Socket] Heartbeat started — interval: \(heartbeatInterval)s")
    }

    private func stopHeartbeat() {
        guard isHeartbeatActive else { return }
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        isHeartbeatActive = false
        print("[Socket] Heartbeat stopped")
    }

    // MARK: - App Lifecycle

    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    @objc private func handleAppDidBecomeActive() {
        guard isConnected else { return }
        startHeartbeat()
    }

    @objc private func handleAppWillResignActive() {
        stopHeartbeat()
    }

    @discardableResult
    func listenToEvent(_ eventName: String, completionHandler: @escaping ([Any]) -> Void) -> UUID {
        let listenerId = UUID()
        registeredListeners[listenerId] = ListenerRegistration(eventName: eventName, callback: completionHandler)
        if let socketListenerId = attachRegisteredListener(listenerId) {
            registeredListenerSocketIds[listenerId] = socketListenerId
        }
        return listenerId
    }

    func offEventById(_ id: UUID) {
        if let socketListenerId = registeredListenerSocketIds.removeValue(forKey: id) {
            self.socket?.off(id: socketListenerId)
        }
        registeredListeners.removeValue(forKey: id)
    }

    func offEvent(_ eventName: String) {
        let toRemove = registeredListeners
            .filter { $0.value.eventName == eventName }
            .map { $0.key }
        for id in toRemove {
            registeredListeners.removeValue(forKey: id)
            registeredListenerSocketIds.removeValue(forKey: id)
        }
        self.socket?.off(eventName)
    }

    func newMessageReceived(completionHandler: @escaping NormalCallback){
        self.socket?.on(SocketEvent.getMessage.rawValue, callback: completionHandler)
    }

    func newMessageReceivedOff() {
        self.socket?.off(SocketEvent.getMessage.rawValue)
    }

    func recentUserSocketOff() {
        self.socket?.off(SocketEvent.recentChatUser.rawValue)
    }

    private func attachRegisteredListener(_ listenerId: UUID) -> UUID? {
        guard let registration = registeredListeners[listenerId] else { return nil }
        let id = self.socket?.on(registration.eventName) { data, _ in
//            print("[SOCKET RECEIVED] Event: \(registration.eventName)")
//            if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]),
//               let jsonString = String(data: jsonData, encoding: .utf8) {
//                print("[SOCKET DATA] \(registration.eventName): \(jsonString)")
//            } else {
//                print("[SOCKET DATA] \(registration.eventName): \(data)")
//            }
            registration.callback(data)
        }
        return id
    }

    private func reattachRegisteredListeners() {
        registeredListenerSocketIds.removeAll()
        let listenerIds = Array(registeredListeners.keys)
        for id in listenerIds {
            if let socketListenerId = attachRegisteredListener(id) {
                registeredListenerSocketIds[id] = socketListenerId
            }
        }
    }
}

// MARK: - Socket Notification Names

extension Notification.Name {
    static let chatSocketDidConnect = Notification.Name("chatSocketDidConnect")
    static let chatSocketDidDisconnect = Notification.Name("chatSocketDidDisconnect")
}

// MARK: - Socket Session Coordinator

final class ChatSocketSessionCoordinator {
    static let shared = ChatSocketSessionCoordinator()

    private var hasStarted = false
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        registerObservers()
        activateSessionIfNeeded(reason: "app-start")
    }

    func activateSessionIfNeeded(reason: String) {
        guard ChatSocketManager.shared.hasAccessToken() else {
            print("[SocketSession] Skip connect (\(reason)) — no auth token")
            return
        }
        ChatListSocketService.shared.setupSocketListeners()
        ChannelSocketService.shared.setupSocketListeners()
        print("[SocketSession] Ensuring socket connection (\(reason))")
        ChatSocketManager.shared.establishConnection()
        Self.syncInboxDelivered()
    }

    func handleApplicationWillEnterForeground() {
        activateSessionIfNeeded(reason: "foreground")
        Self.syncInboxDelivered()
    }

    /// FE auth-context onConnect / foreground — POST chat/delivered/sync
    private static func syncInboxDelivered() {
        guard let sessionManager = Container.sharedContainer.resolve(SessionManager.self) else { return }
        _ = sessionManager.syncInboxDelivered()
            .subscribe(onSuccess: { data in
                AppLogger.debug("[DeliveredSync] updated=\(data.updated ?? 0)")
            }, onFailure: { error in
                AppLogger.debug("[DeliveredSync] failed: \(error.localizedDescription)")
            })
    }

    func handleApplicationWillTerminate() {
        ChatSocketManager.shared.closeConnection()
    }

    func shutdownForLogout() {
        ChatListSocketService.shared.invalidateSocketListeners()
        ChannelSocketService.shared.invalidateSocketListeners()
        ChatSocketManager.shared.clearSocialRoomTracking()
        ChatSocketManager.shared.closeConnection()
        ChatSocketManager.shared.clearSocketListeners()
    }

    private func registerObservers() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.activateSessionIfNeeded(reason: "notification-foreground")
            }
        )

        observers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.activateSessionIfNeeded(reason: "notification-active")
            }
        )
    }
}
