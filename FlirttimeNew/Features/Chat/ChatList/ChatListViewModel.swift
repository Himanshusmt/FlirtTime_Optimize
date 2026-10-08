//
//  ChatListViewModel.swift
//  FlirttimeNew
//
//  Created by Awais on 11/07/2025.
//

import Foundation
import Combine
import Swinject
import UIKit
import Network
import RxSwift

@MainActor
class ChatListViewModel: ObservableObject {
    // MARK: - Published Properties (Reactive UI State)

    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var isLoadingArchived: Bool = false
    @Published var errorMessage: String? = nil
    @Published private(set) var chatsSnapshot: [ChatMessageRow] = []
    @Published private(set) var markedUnreadChatIds: Set<String> = []

    @Published private(set) var typingConversationIds: Set<String> = []

    @Published private(set) var pendingConversationIds: Set<String> = []
    @Published private(set) var hasMorePages: Bool = true
    @Published var showNoInternetAlert = false
    /// Bumped when group ongoing-call registry changes — forces list row subtitle refresh.
    @Published private(set) var ongoingGroupCallRevision: Int = 0
    
    // MARK: - Computed Properties

    var chats: [ChatMessageRow] { chatsSnapshot }

    var pinnedChats: [ChatMessageRow] {
        chatsSnapshot.filter { $0.settings?.isPinned == true && $0.settings?.isArchived != true }
    }

    var unpinnedChats: [ChatMessageRow] {
        chatsSnapshot.filter { $0.settings?.isPinned != true && $0.settings?.isArchived != true }
    }

    var archivedChats: [ChatMessageRow] {
        chatsSnapshot.filter { $0.settings?.isArchived == true || $0.isArchived }
    }

    var activeUsers: [ChatMessageRow] {
        let currentUserId = getCurrentUserId()
        return chatsSnapshot.filter { chat in
            guard !chat.isGroup,
                  chat.type == "direct" || chat.type == nil || chat.type == "private",
                  chat.settings?.isBlocked != true,
                  let otherParticipant = chat.otherParticipant,
                  let otherUserId = otherParticipant.userId,
                  !otherUserId.isEmpty,
                  otherUserId != currentUserId,
                  !BlockedUsersManager.shared.isBlocked(id: otherUserId) else {
                return false
            }
            return ChatListSocketService.shared.onlineUserIds.contains(otherUserId)
        }
    }

    var onlineUserIds: Set<String> { ChatListSocketService.shared.onlineUserIds }
    var pinnedChatIds: Set<String> {
        Set(chatsSnapshot.compactMap { chat in
            guard let id = chat.id,
                  chat.settings?.isPinned == true,
                  chat.settings?.isArchived != true else { return nil }
            return id
        })
    }
    var mutedChatIds: Set<String> {
        Set(chatsSnapshot.compactMap { chat in
            guard let id = chat.id, chat.settings?.isMuted == true else { return nil }
            return id
        })
    }

    // MARK: - Private Properties

    private let chatDataService: ChatDataService
    private let chatSearchService: ChatSearchService
    private let chatSyncService: ChatSyncService
    private let sessionManager: SessionManager
    private let conversationRepository: ConversationRepositoryAsync
    private let conversationPresentationStore = ConversationPresentationStore.shared

    private var cancellables = Set<AnyCancellable>()
    private let disposeBag = DisposeBag()
    private var realtimeSyncTask: Task<Void, Never>?
    private let realtimeSyncDebounceNanoseconds: UInt64 = 400_000_000
    private var appliedConversationPresentationTokens: [String: String] = [:]
    /// Debounce timers that clear a conversationId from typingConversationIds after 5 s of silence.
    private var typingCleanupTimers: [String: Timer] = [:]

    // MARK: - Initialization

    init(sessionManager: SessionManager,
         conversationRepository: ConversationRepositoryAsync? = nil,
         chatDataService: ChatDataService? = nil,
         chatSocketService: ChatListSocketService? = nil,
         chatSearchService: ChatSearchService? = nil,
         chatSyncService: ChatSyncService? = nil) {
        self.sessionManager = sessionManager
        // Create repository that conforms to BOTH protocols
        let repository = (conversationRepository as? ConversationRepository) ?? ConversationRepository()
        self.conversationRepository = repository
        // ChatDataService still uses legacy protocol, but that's OK - repository conforms to both
        let resolvedDataService = chatDataService ?? ChatDataService(conversationRepository: repository)
        let resolvedSearchService = chatSearchService ?? ChatSearchService()
        let resolvedSyncService = chatSyncService ?? ChatSyncService(
            sessionManager: sessionManager,
            chatDataService: resolvedDataService
        )
        self.chatDataService = resolvedDataService
        self.chatSearchService = resolvedSearchService
        self.chatSyncService = resolvedSyncService

        setupSocketCallbacks()
        setupSearchObserver()
        bindSyncState()
        bindDataObservers()
        setupRefreshListener()
        setupForegroundObserver()
        setupOngoingGroupCallObserver()
        bindConversationPresentationState()
        ChatListSocketService.shared.setupSocketListeners()
    }

    /// Ongoing group call for a conversation (list subtitle + Join).
    func ongoingGroupCall(for conversationId: String) -> AgoraRejoinableGroupCall? {
        _ = ongoingGroupCallRevision
        return AgoraCallService.shared.ongoingGroupCall(for: conversationId)
    }

    private func setupOngoingGroupCallObserver() {
        NotificationCenter.default.addObserver(
            forName: .agoraGroupCallRejoinDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ongoingGroupCallRevision &+= 1
        }
        // Cold start — restore persisted ongoing calls for list text.
        AgoraCallService.shared.start()
        ongoingGroupCallRevision &+= 1
    }

    convenience init() {
        guard let sessionManager = Container.sharedContainer.resolve(SessionManager.self) else {
            fatalError("ChatListViewModel requires a SessionManager instance.")
        }
        // Use shared ConversationRepository (conforms to both protocols)
        self.init(sessionManager: sessionManager, conversationRepository: ConversationRepository())
    }

    deinit {
        realtimeSyncTask?.cancel()
    }

    // MARK: - Lifecycle

    private var hasRequestedOnlineUsers = false

    func onAppear() {
        if chatsSnapshot.isEmpty {
            let cached = chatDataService.loadCachedChatsSync()
            if !cached.isEmpty {
                chatsSnapshot = chatDataService.enrichChats(cached)
                refreshPendingConversationIds(from: cached)
                let inboxIds = cached.compactMap { $0.id }.filter { !$0.isEmpty }
                ChatSocketManager.shared.joinConversationRooms(inboxIds)
            }
        } else {
            let inboxIds = chatsSnapshot.compactMap { $0.id }.filter { !$0.isEmpty }
            ChatSocketManager.shared.joinConversationRooms(inboxIds)
        }
        chatSyncService.syncChats(loadPolicy: .ifStale, forceRefresh: false, bypassCooldown: true)
        ChatDataPreloader.shared.preloadRecentConversationMessages()
        ChatListSocketService.shared.requestOnlineUsers()
        subscribeInboxPresence()
        if chatsSnapshot.contains(where: { ($0.unreadCount ?? 0) > 0 }) {
            NotificationCenter.default.post(name: .ChatHasUnreadMessages, object: nil)
        } else {
            NotificationCenter.default.post(name: .ChatUnreadCleared, object: nil)
        }
    }

    /// FE ConversationsPage: presence:get for all direct peers in the inbox.
    private func subscribeInboxPresence() {
        let peerIds = chatsSnapshot.compactMap { chat -> String? in
            guard !chat.isGroup else { return nil }
            return chat.otherParticipant?.userId
        }
        ChatListSocketService.shared.subscribePresence(userIds: peerIds)
    }

    func refresh() {
        guard checkInternetConnection() else {
                return
            }
        chatSyncService.syncChats(loadPolicy: .always, forceRefresh: true)
        // After sync settles, recalculate badge from server-fresh unread counts.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s — wait for sync to settle
            guard let repo = Container.sharedContainer.resolve(ConversationRepositoryProtocol.self) else { return }
            let conversations = (try? await repo.getAllConversations()) ?? []
            let totalUnread = conversations.reduce(0) { $0 + ($1.unreadCount ?? 0) }
            UIApplication.shared.applicationIconBadgeNumber = totalUnread
        }
    }

    private func checkInternetConnection() -> Bool {

        if !NetworkMonitor.shared.isConnected {
            showNoInternetAlert = true
            return false
        }

        return true
    }
    
    func loadNextPage() {
        chatSyncService.loadNextPage()
    }

    func forceRefreshChats() {
        guard checkInternetConnection() else {
                return
            }
        chatSyncService.syncChats(forceRefresh: true)
    }

    /// After local group create — insert/promote row so it appears at top immediately
    /// (empty groups have no lastMessage; list sorts by lastMessageAt / lastMessageTimestamp).
    func handleGroupCreated(conversationId: String, title: String) {
        guard !conversationId.isEmpty else {
            forceRefreshChats()
            return
        }
        var row = ChatMessageRow()
        row.id = conversationId
        row.title = title
        row.type = "group"
        row.unreadCount = 0
        row.myRole = "admin"
        row.isGroupParticipant = true
        row.lastMessageAt = Self.isoNowString()
        chatDataService.upsertConversation(row)
        ChatSocketManager.shared.joinConversationRoom(conversationId)
        // Soft refresh for server fields without waiting to show the row.
        forceRefreshChats()
    }

    /// New Chat → user tap: `POST /chat/conversations` `{ type: "direct", participantIds }` → conversation id.
    /// Reuses an existing local direct chat when present (same as FollowersProfile open-chat path).
    func createOrResolveDirectConversation(
        peerUserId: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let peerId = peerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !peerId.isEmpty else {
            completion(.failure(NSError(
                domain: "ChatList",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid user"]
            )))
            return
        }

        if let existingId = ConversationRepository().findConversationIdByParticipant(userId: peerId),
           !existingId.isEmpty {
            ChatSocketManager.shared.joinConversationRoom(existingId)
            completion(.success(existingId))
            return
        }

        guard let session = Container.sharedContainer.resolve(SessionManager.self) else {
            completion(.failure(NSError(
                domain: "ChatList",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Session unavailable"]
            )))
            return
        }

        AppLogger.debug("[NewChat] POST chat/conversations type=direct participantIds=[\(peerId)]")
        session.createChatConversation(participantIds: [peerId], type: "direct")
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] response in
                    let conversationId = Self.conversationId(fromCreateResponse: response)
                    guard !conversationId.isEmpty else {
                        AppLogger.debug("[NewChat] create response missing id keys=\(response.keys.sorted())")
                        completion(.failure(NSError(
                            domain: "ChatList",
                            code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to create conversation"]
                        )))
                        return
                    }
                    AppLogger.debug("[NewChat] conversation ready id=\(conversationId)")
                    ChatSocketManager.shared.joinConversationRoom(conversationId)
                    var row = ChatMessageRow()
                    row.id = conversationId
                    row.type = "direct"
                    row.lastMessageAt = Self.isoNowString()
                    self?.chatDataService.upsertConversation(row)
                    completion(.success(conversationId))
                },
                onFailure: { error in
                    AppLogger.debug("[NewChat] create failed: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            )
            .disposed(by: disposeBag)
    }

    private static func conversationId(fromCreateResponse response: [String: Any]) -> String {
        if let id = response["id"] as? String, !id.isEmpty { return id }
        if let id = response["conversationId"] as? String, !id.isEmpty { return id }
        if let data = response["data"] as? [String: Any] {
            if let id = data["id"] as? String, !id.isEmpty { return id }
            if let id = data["conversationId"] as? String, !id.isEmpty { return id }
            if let conversation = data["conversation"] as? [String: Any] {
                if let id = conversation["id"] as? String, !id.isEmpty { return id }
                if let id = conversation["conversationId"] as? String, !id.isEmpty { return id }
            }
        }
        if let conversation = response["conversation"] as? [String: Any] {
            if let id = conversation["id"] as? String, !id.isEmpty { return id }
            if let id = conversation["conversationId"] as? String, !id.isEmpty { return id }
        }
        return ""
    }

    private static func isoNowString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    /// FE — GET `chat/conversations?limit=30&archived=true` when Archived tab opens.
    func loadArchivedChats() {
        guard checkInternetConnection() else { return }
        chatSyncService.loadArchivedConversations()
    }

    func loadCachedChatsImmediately() {
        chatSyncService.preloadCache(policy: .always)
    }

    // MARK: - Chat Actions

    func togglePin(chatId: String) {
        guard !chatId.isEmpty else { return }
        let newValue = !isPinned(chatId: chatId)
        applyConversationSettings(chatId: chatId, settings: ["isPinned": newValue])
    }

    func toggleMute(chatId: String) {
        guard !chatId.isEmpty else { return }
        if isMuted(chatId: chatId) {
            unmuteChat(id: chatId)
        } else {
            muteChat(id: chatId)
        }
    }

    func isMuted(chatId: String) -> Bool {
        mutedChatIds.contains(chatId)
    }

    func unmuteChat(id chatId: String) {
        guard !chatId.isEmpty else { return }
        applyConversationSettings(chatId: chatId, settings: ["isMuted": false])
    }

    func muteChat(id chatId: String) {
        guard !chatId.isEmpty else { return }
        applyConversationSettings(chatId: chatId, settings: ["isMuted": true])
    }

    func isPinned(chatId: String) -> Bool {
        pinnedChatIds.contains(chatId)
    }

    func pinChat(id chatId: String) {
        guard !chatId.isEmpty else { return }
        applyConversationSettings(chatId: chatId, settings: ["isPinned": true])
    }

    func unpinChat(id chatId: String) {
        guard !chatId.isEmpty else { return }
        applyConversationSettings(chatId: chatId, settings: ["isPinned": false])
    }

    func archiveChat(chatId: String, isArchived: Bool) {
        guard !chatId.isEmpty else { return }
        if isArchived {
            applyConversationSettings(chatId: chatId, settings: ["isArchived": true, "isPinned": false])
            loadCachedChatsImmediately()
        } else {
            applyConversationSettings(chatId: chatId, settings: ["isArchived": false])
        }
    }

    func updateChatArchiveStatus(chatId: String, isArchived: Bool) {
        archiveChat(chatId: chatId, isArchived: isArchived)
    }

    func deleteConversation(conversationId: String, forEveryone: Bool = false) {
        guard !conversationId.isEmpty else { return }
        if forEveryone {
            // Explicit single-chat path: DELETE /chat/conversations/{id}?scope=everyone
            deleteConversationForEveryone(conversationId: conversationId)
        } else {
            deleteConversations(ids: [conversationId], forEveryone: false)
        }
    }

    /// DELETE `/api/v1/chat/conversations/{id}?scope=everyone` (ChatList “Delete for everyone”).
    func deleteConversationForEveryone(conversationId: String) {
        guard !conversationId.isEmpty else { return }

        chatDataService.removeChat(conversationId, deleteFromStore: true)

        _ = sessionManager.deleteChatConversation(id: conversationId, scope: "everyone")
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: {
                    AppLogger.debug("[DeleteChat] REST ok id=\(conversationId) scope=everyone")
                },
                onFailure: { error in
                    AppLogger.debug("[DeleteChat] REST scope=everyone failed: \(error.localizedDescription) — socket fallback")
                    ChatListSocketService.shared.emitDeleteConversation(
                        conversationId: conversationId,
                        forEveryone: true
                    )
                }
            )
            .disposed(by: disposeBag)
    }

    /// Delete one or many chats via REST.
    /// Single → `DELETE /chat/conversations/{id}?scope=me|everyone`
    /// Multiple → body `{ id: [...], scope: "me"|"everyone" }`
    func deleteConversations(ids: [String], forEveryone: Bool = false) {
        let uniqueIds = Array(Set(ids.filter { !$0.isEmpty }))
        guard !uniqueIds.isEmpty else { return }

        if forEveryone, uniqueIds.count == 1 {
            deleteConversationForEveryone(conversationId: uniqueIds[0])
            return
        }

        let scope = forEveryone ? "everyone" : "me"

        // Optimistic local remove
        for conversationId in uniqueIds {
            chatDataService.removeChat(conversationId, deleteFromStore: true)
        }

        _ = sessionManager.deleteChatConversations(ids: uniqueIds, scope: scope)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: {
                    AppLogger.debug("[DeleteChat] REST ok ids=\(uniqueIds.count) scope=\(scope)")
                },
                onFailure: { error in
                    AppLogger.debug("[DeleteChat] REST failed: \(error.localizedDescription) — socket fallback")
                    for conversationId in uniqueIds {
                        ChatListSocketService.shared.emitDeleteConversation(
                            conversationId: conversationId,
                            forEveryone: forEveryone
                        )
                    }
                }
            )
            .disposed(by: disposeBag)
    }

    func deleteChat(chatId: String) {
        deleteConversation(conversationId: chatId)
    }

    // MARK: - Read/Unread Actions (Clean Async/Await)

    func toggleChatReadStatus(chatId: String) {
        guard let chat = chat(for: chatId) else { return }
        let hasUnreadCount = (chat.unreadCount ?? 0) > 0
        let isMarkedUnread = markedUnreadChatIds.contains(chatId)

        if hasUnreadCount || isMarkedUnread {
            markChatAsRead(chatId: chatId)
        } else {
            markChatAsUnread(chatId: chatId)
        }
    }

    func markChatAsRead(chatId: String) {
        guard chat(for: chatId) != nil else { return }

        // Optimistically update UI - clear both unread count and marked unread state
        let previousCount = chat(for: chatId)?.unreadCount ?? 0
        let wasMarkedUnread = markedUnreadChatIds.contains(chatId)
        chatDataService.setUnreadCount(for: chatId, unreadCount: 0)
        markedUnreadChatIds.remove(chatId)

        // Perform async operation
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.conversationRepository.markAsRead(conversationId: chatId)
                await self.chatSyncService.syncChats(forceRefresh: false)
            } catch {
                // Revert on error
                await MainActor.run {
                    self.chatDataService.setUnreadCount(for: chatId, unreadCount: previousCount)
                    if wasMarkedUnread {
                        self.markedUnreadChatIds.insert(chatId)
                    }
                    self.handleError(error)
                }
            }
        }
    }

    func markChatAsUnread(chatId: String) {
        guard chat(for: chatId) != nil else { return }

        // Add to manually marked unread set (shows as dot, not count)
        markedUnreadChatIds.insert(chatId)

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.conversationRepository.markAsUnread(conversationId: chatId)
            } catch {
                await MainActor.run {
                    self.markedUnreadChatIds.remove(chatId)
                    self.handleError(error)
                }
            }
        }
    }

    /// Check if a chat is manually marked as unread (shows as dot, not count)
    func isMarkedUnread(chatId: String) -> Bool {
        markedUnreadChatIds.contains(chatId)
    }

    /// Optimistically clear unread count when opening a chat (before API call completes)
    func clearUnreadCountOptimistically(chatId: String) {
        chatDataService.setUnreadCount(for: chatId, unreadCount: 0)
        markedUnreadChatIds.remove(chatId)
    }

    // MARK: - Block Actions

    func isBlockedChat(chatId: String) -> Bool {
        chat(for: chatId)?.settings?.isBlocked == true
    }

    func blockChat(chatId: String) {
        guard !chatId.isEmpty else { return }
        applyConversationSettings(chatId: chatId, settings: ["isBlocked": true])
        notifyBlockStatusChanged(conversationId: chatId, isBlocked: true)

        // FE blocks via users/{id}/block — server fans out `user:blocked`.
        if let peerId = peerUserId(for: chatId), !peerId.isEmpty {
            BlockedUsersManager.shared.blockUser(id: peerId)
            _ = sessionManager.blockUser(id: peerId, userId: getCurrentUserId())
                .subscribe(onFailure: { error in
                    AppLogger.debug("[Block] users/\(peerId)/block failed: \(error.localizedDescription)")
                })
                .disposed(by: disposeBag)
        }
    }

    func unblockChat(chatId: String) {
        guard !chatId.isEmpty else { return }
        applyConversationSettings(chatId: chatId, settings: ["isBlocked": false])
        notifyBlockStatusChanged(conversationId: chatId, isBlocked: false)

        if let peerId = peerUserId(for: chatId), !peerId.isEmpty {
            BlockedUsersManager.shared.unblockUser(id: peerId)
            _ = sessionManager.unblockUser(id: peerId)
                .subscribe(onFailure: { error in
                    AppLogger.debug("[Block] users/\(peerId)/block DELETE failed: \(error.localizedDescription)")
                })
                .disposed(by: disposeBag)
        }
    }

    private func peerUserId(for chatId: String) -> String? {
        let chat = chat(for: chatId)
        return chat?.getUserDetails()?.userId ?? chat?.otherParticipant?.userId
    }

    private func conversationId(forPeerUserId userId: String) -> String? {
        guard !userId.isEmpty else { return nil }
        return chatsSnapshot.first(where: { chat in
            guard !chat.isGroup, chat.type?.lowercased() != "channel" else { return false }
            let peer = chat.getUserDetails()?.userId ?? chat.otherParticipant?.userId
            return peer == userId
        })?.id
    }

    private func notifyBlockStatusChanged(conversationId: String, isBlocked: Bool) {
        NotificationCenter.default.post(
            name: .ChatBlockStatusChanged,
            object: nil,
            userInfo: ["conversationId": conversationId, "isBlocked": isBlocked]
        )
    }

    private func applyUserBlockSocket(actorId: String, targetId: String, isBlocked: Bool) {
        let myId = getCurrentUserId()
        guard !myId.isEmpty else { return }

        // I blocked them → show overlay on my DM; they blocked me → still gate that DM.
        // Local BlockedUsersManager is already updated in ChatListSocketService for actor==me.
        let peerId: String?
        if actorId == myId {
            peerId = targetId
        } else if targetId == myId {
            peerId = actorId
        } else {
            return
        }

        guard let peerId, let cid = conversationId(forPeerUserId: peerId), !cid.isEmpty else {
            if actorId == myId {
                NotificationCenter.default.post(
                    name: .ChatBlockStatusChanged,
                    object: nil,
                    userInfo: ["peerUserId": targetId, "isBlocked": isBlocked]
                )
            }
            return
        }

        applySettingsToSnapshot(chatId: cid, settings: ["isBlocked": isBlocked])
        chatDataService.updateChatSettings(conversationId: cid, settings: ["isBlocked": isBlocked])
        notifyBlockStatusChanged(conversationId: cid, isBlocked: isBlocked)
    }

    // MARK: - Label Actions

    func getChatLabel(chatId: String) -> String {
        let settings = chat(for: chatId)?.settings
        if let text = settings?.labelText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        return settings?.label?.first as? String ?? ""
    }

    func getChatLabelColor(chatId: String) -> String? {
        chat(for: chatId)?.settings?.labelColor
    }

    func toggleChatLabel(chatId: String, label: String) {
        setChatLabel(chatId: chatId, label: label, color: nil)
    }

    /// FE — PATCH settings `{ labelText, labelColor }` (color = badge background; text is white in UI).
    func setChatLabel(chatId: String, label: String, color: String?) {
        guard !chatId.isEmpty else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            applyConversationSettings(chatId: chatId, settings: [
                "labelText": "",
                "labelColor": "",
                "label": ""
            ])
            return
        }

        let resolvedColor: String = {
            if let color = color?.trimmingCharacters(in: .whitespacesAndNewlines), !color.isEmpty {
                return color.hasPrefix("#") ? color : "#\(color)"
            }
            return getChatLabelColor(chatId: chatId) ?? LabelChatModal.labelColors[0]
        }()

        applyConversationSettings(chatId: chatId, settings: [
            "labelText": trimmed,
            "labelColor": resolvedColor,
            "label": trimmed
        ])
    }

    // MARK: - Search

    func filteredChats(for query: String) -> ChatSearchService.SearchResult {
        chatSearchService.searchChats(
            chats,
            query: query,
            pinnedIds: pinnedChatIds,
            mutedIds: mutedChatIds
        )
    }

    // MARK: - User Management

    func getCurrentUserId() -> String {
        sessionManager.user?.userId ?? ""
    }

    // MARK: - Private Setup

    private func setupForegroundObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            ChatListSocketService.shared.requestOnlineUsers()
            self?.subscribeInboxPresence()
        }
    }

    private func setupRefreshListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RefreshConversationList"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.debug("RefreshConversationList notification received")
            self?.forceRefreshChats()
        }

        // Lightweight unread count update — no full API sync
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ChatUnreadCountUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let conversationId = notification.userInfo?["conversationId"] as? String else { return }
            self?.chatDataService.setUnreadCount(for: conversationId, unreadCount: 0)
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ChatLastMessageUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let conversationId = notification.userInfo?["conversationId"] as? String,
                  let message = notification.userInfo?["message"] as? ConversationMessage else { return }
            self.chatDataService.applyIncomingMessage(
                conversationId: conversationId,
                message: message,
                currentUserId: self.getCurrentUserId(),
                shouldIncrementUnread: false
            )
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ChatConversationUpsert"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let conversation = notification.userInfo?["conversation"] as? ChatMessageRow else { return }
            AppLogger.debug("ChatListViewModel: ChatConversationUpsert → upserting \(conversation.id ?? "")")
            self.chatDataService.upsertConversation(conversation)
        }

        NotificationCenter.default.addObserver(
            forName: .conversationIconUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let conversationId = notification.userInfo?["conversationId"] as? String,
                  let iconURL = notification.userInfo?["iconURL"] as? String,
                  !iconURL.isEmpty else { return }
            AppLogger.debug("ChatListViewModel: conversationIconUpdated → \(conversationId)")
            self.chatDataService.updateChatAvatar(conversationId: conversationId, newAvatar: iconURL)
        }

        NotificationCenter.default.addObserver(
            forName: .ChatLastMessageDeleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let conversationId = notification.userInfo?["conversationId"] as? String,
                  let messageId = notification.userInfo?["messageId"] as? String,
                  !conversationId.isEmpty, !messageId.isEmpty else { return }
            AppLogger.debug("ChatListViewModel: ChatLastMessageDeleted → conversation=\(conversationId) message=\(messageId.prefix(8))")
            self.chatDataService.updateLastMessageAsDeleted(conversationId: conversationId, messageId: messageId)
        }

        NotificationCenter.default.addObserver(
            forName: .ChatBlockStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let cid = notification.userInfo?["conversationId"] as? String,
               let isBlocked = notification.userInfo?["isBlocked"] as? Bool,
               !cid.isEmpty {
                self.chatDataService.updateChatSettings(
                    conversationId: cid,
                    settings: ["isBlocked": isBlocked]
                )
            } else {
                self.forceRefreshChats()
            }
        }
    }

    private func setupSocketCallbacks() {
        ChatListSocketService.shared.settingsUpdated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversationId, settings in
                self?.chatDataService.updateChatSettings(conversationId: conversationId, settings: settings)
                self?.applySettingsToSnapshot(chatId: conversationId, settings: settings)
                if let blocked = SocketAckParser.boolValue(from: settings["isBlocked"]) {
                    self?.notifyBlockStatusChanged(conversationId: conversationId, isBlocked: blocked)
                }
            }
            .store(in: &cancellables)

        ChatListSocketService.shared.userBlockUpdated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] actorId, targetId, isBlocked in
                self?.applyUserBlockSocket(actorId: actorId, targetId: targetId, isBlocked: isBlocked)
            }
            .store(in: &cancellables)

        // Profile / feed block (BlockedUsersManager) — keep open chat + list in sync without refresh.
        NotificationCenter.default.publisher(for: .userBlocked)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let peerId = notification.object as? String,
                      !peerId.isEmpty else { return }
                if let cid = self.conversationId(forPeerUserId: peerId) {
                    self.applySettingsToSnapshot(chatId: cid, settings: ["isBlocked": true])
                    self.chatDataService.updateChatSettings(conversationId: cid, settings: ["isBlocked": true])
                    self.notifyBlockStatusChanged(conversationId: cid, isBlocked: true)
                } else {
                    NotificationCenter.default.post(
                        name: .ChatBlockStatusChanged,
                        object: nil,
                        userInfo: ["peerUserId": peerId, "isBlocked": true]
                    )
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .userUnblocked)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let peerId = notification.object as? String,
                      !peerId.isEmpty else { return }
                if let cid = self.conversationId(forPeerUserId: peerId) {
                    self.applySettingsToSnapshot(chatId: cid, settings: ["isBlocked": false])
                    self.chatDataService.updateChatSettings(conversationId: cid, settings: ["isBlocked": false])
                    self.notifyBlockStatusChanged(conversationId: cid, isBlocked: false)
                } else {
                    NotificationCenter.default.post(
                        name: .ChatBlockStatusChanged,
                        object: nil,
                        userInfo: ["peerUserId": peerId, "isBlocked": false]
                    )
                }
            }
            .store(in: &cancellables)

        ChatListSocketService.shared.messageReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                AppLogger.debug("ChatListViewModel: Received socket message for \(event.conversationId)")
                self?.handleNewMessage(conversationId: event.conversationId, messageData: event.rawData)
            }
            .store(in: &cancellables)

        ChatListSocketService.shared.conversationDeleted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversationId in
                self?.chatDataService.removeChat(conversationId, deleteFromStore: true)
                self?.scheduleRealtimeSync(forceRefresh: false)
            }
            .store(in: &cancellables)

        ChatListSocketService.shared.conversationCreated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversation in
                guard let self = self else { return }
                let convId = conversation.id ?? ""
                let currentUserId = self.getCurrentUserId()

                // Always upsert to catch metadata changes (title, avatar, participants)
                // even when the last message is our own.
                let isSelfSent = conversation.lastMessage?.senderId == currentUserId
                let isDuplicateMessage: Bool
                if isSelfSent,
                   let existing = self.chatDataService.chat(withId: convId),
                   existing.lastMessage?.id == conversation.lastMessage?.id {
                    isDuplicateMessage = true
                } else {
                    isDuplicateMessage = false
                }

                AppLogger.debug("ChatListViewModel: create-conversation received → upsertConversation \(convId) (isSelfSent=\(isSelfSent), isDuplicate=\(isDuplicateMessage))")
                self.chatDataService.upsertConversation(conversation)
                self.scheduleRealtimeSync(forceRefresh: false)

                // Show in-app banner for new messages from others while in chat module
                if let lastMsg = conversation.lastMessage,
                   lastMsg.senderId != currentUserId,
                   ChatNotificationState.shared.isInChatModule,
                   !ChatNotificationState.shared.isViewingConversation(convId) {
                    // Resolve sender info from the conversation's participant data
                    let senderParticipant = conversation.participants?.first { $0.userId == lastMsg.senderId }
                    let senderUserDetails = senderParticipant?.user?.userDetails?.first
                    let message = ConversationMessage(
                        id: lastMsg.id ?? "",
                        conversationId: convId,
                        sender: ConversationMessageSender(
                            id: lastMsg.senderId,
                            userName: senderUserDetails?.userName,
                            fullName: senderUserDetails?.fullName,
                            profilePicture: senderUserDetails?.profilePicture
                        ),
                        messageType: lastMsg.messageType,
                        content: lastMsg.contentPreview,
                        status: "delivered",
                        createdAt: lastMsg.createdAt ?? "",
                        isDeleted: false
                    )
                    self.showInAppBanner(conversationId: convId, message: message)
                }
            }
            .store(in: &cancellables)

        // FE: `chat:inbox:refresh` → scheduleRefresh() so new groups appear without pull-to-refresh
        ChatListSocketService.shared.inboxRefreshNeeded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reason in
                AppLogger.debug("ChatListViewModel: inbox:refresh reason=\(reason ?? "nil") → forceRefreshChats")
                self?.forceRefreshChats()
            }
            .store(in: &cancellables)

        ChatListSocketService.shared.memberAdded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversationId, _ in
                AppLogger.debug("ChatListViewModel: member:added conversation=\(conversationId) → forceRefreshChats")
                ChatSocketManager.shared.joinConversationRoom(conversationId)
                // Mid-call invites: new member never got `call:incoming` — seed Join from detail/list.
                AgoraCallService.shared.refreshRejoinableState(for: conversationId)
                self?.forceRefreshChats()
            }
            .store(in: &cancellables)

        ChatListSocketService.shared.userStatusChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                // Trigger UI refresh when user status changes
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        ChatListSocketService.shared.$onlineUserIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // MARK: - New Combine Publisher Bindings

        // Typing indicator: show "typing…" in chat list row, auto-clear after 5 s
        ChatListSocketService.shared.typingReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                // Don't show typing for own device
                guard event.userId != self.getCurrentUserId() else { return }
                let convId = event.conversationId
                if event.isTyping {
                    self.typingConversationIds.insert(convId)
                    // Reset debounce timer — clear after 5 s if no further typing event
                    self.typingCleanupTimers[convId]?.invalidate()
                    self.typingCleanupTimers[convId] = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                        self?.typingConversationIds.remove(convId)
                        self?.typingCleanupTimers.removeValue(forKey: convId)
                    }
                } else {
                    self.typingCleanupTimers[convId]?.invalidate()
                    self.typingCleanupTimers.removeValue(forKey: convId)
                    self.typingConversationIds.remove(convId)
                }
            }
            .store(in: &cancellables)

        // Delivery/read status: update the in-memory last-message status so the tick in the row updates instantly.
        ChatListSocketService.shared.messageStatusUpdated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                // Apply the new status to every affected message id.
                // Most events carry one id; bulk events also handled here.
                for messageId in event.messageIds {
                    self.chatDataService.updateLastMessageStatus(
                        conversationId: event.conversationId,
                        messageId: messageId,
                        status: event.status
                    )
                }
            }
            .store(in: &cancellables)
    }

    private func setupSearchObserver() {
        $searchQuery
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.chatSearchService.clearCache()
            }
            .store(in: &cancellables)
    }

    private func bindSyncState() {
        chatSyncService.$isLoading
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .assign(to: &$isLoading)

        chatSyncService.$isLoadingArchived
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .assign(to: &$isLoadingArchived)

        chatSyncService.$errorMessage
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .assign(to: &$errorMessage)

        chatSyncService.$hasMorePages
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .assign(to: &$hasMorePages)
    }

    private func bindDataObservers() {
        chatDataService.frcChatsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] frcChats in
                guard let self = self else { return }
                self.chatsSnapshot = self.chatDataService.enrichChats(frcChats)
                // FE joins all listed conversation rooms so message:new updates inbox
                let inboxIds = frcChats.compactMap { $0.id }.filter { !$0.isEmpty }
                if !inboxIds.isEmpty {
                    ChatSocketManager.shared.joinConversationRooms(inboxIds)
                }
                self.subscribeInboxPresence()
                if !frcChats.isEmpty {
                    self.preCacheProfilePictures(from: frcChats)
                    let inChatDetail = ChatNotificationState.shared.activeConversationId != nil
                    if !inChatDetail {
                        let convIds = frcChats.prefix(10).compactMap { $0.id }
                        ChatDataPreloader.shared.preloadFromNetworkIfEmpty(
                            conversationIds: Array(convIds),
                            sessionManager: self.sessionManager
                        )
                    }
                }
                // Re-derive pending set whenever the chat list changes
                self.refreshPendingConversationIds(from: frcChats)
            }
            .store(in: &cancellables)

        // Keep pendingConversationIds in sync whenever PendingMessageStore changes
        PendingMessageStore.shared.pendingChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.refreshPendingConversationIds(from: self.chatsSnapshot)
            }
            .store(in: &cancellables)
    }

    private func bindConversationPresentationState() {
        conversationPresentationStore.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshots in
                guard let self else { return }

                for (conversationId, snapshot) in snapshots {
                    let token = "\(snapshot.title ?? "")|\(snapshot.avatarURL ?? "")|\(snapshot.description ?? "")"
                    if self.appliedConversationPresentationTokens[conversationId] == token {
                        continue
                    }
                    self.appliedConversationPresentationTokens[conversationId] = token

                    if let title = snapshot.title, !title.isEmpty {
                        self.chatDataService.updateChatTitle(conversationId: conversationId, newTitle: title)
                    }

                    if let avatarURL = snapshot.avatarURL, !avatarURL.isEmpty {
                        self.chatDataService.updateChatAvatar(conversationId: conversationId, newAvatar: avatarURL)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Private Helpers

    private func preCacheProfilePictures(from chats: [ChatMessageRow]) {
        var profilePicturesToCache: [(userId: String, urlString: String?)] = []

        for chat in chats {
            if chat.type == "direct" {
                if let participants = chat.participants {
                    for participant in participants {
                        if let userId = participant.userId, !userId.isEmpty {
                            let profilePicture = participant.user?.userDetails?.first?.profilePicture
                            profilePicturesToCache.append((userId: userId, urlString: profilePicture))
                        }
                    }
                }
            } else if let avatarUrl = chat.avatar, !avatarUrl.isEmpty {
                let groupKey = chat.id.map { "group_\($0)" } ?? "group_\(abs(avatarUrl.hashValue))"
                profilePicturesToCache.append((userId: groupKey, urlString: avatarUrl))
            }
        }

        if !profilePicturesToCache.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async {
                ProfilePictureCache.shared.preCacheProfilePictures(profilePicturesToCache)
            }
        }
    }

    private func handleNewMessage(conversationId: String, messageData: [String: Any]) {
        guard let message = ConversationMessage.fromDictionary(messageData) else {
            scheduleRealtimeSync(forceRefresh: true)
            return
        }

        // Skip notifications for own messages (sent from another device)
        let isOwnMessage = message.sender?.id == getCurrentUserId()

        ChatDataPreloader.shared.refreshPreload(conversationId: conversationId, newMessages: [message])

        let shouldIncrementUnread = !ChatNotificationState.shared.isViewingConversation(conversationId)
        let serverUnreadCount = Self.unreadCount(from: messageData)

        let conversationExisted = chatDataService.applyIncomingMessage(
            conversationId: conversationId,
            message: message,
            currentUserId: getCurrentUserId(),
            shouldIncrementUnread: shouldIncrementUnread,
            serverUnreadCount: serverUnreadCount
        )

        // Show in-app banner when user is in chat module but not viewing this conversation
        // Skip for system messages (screenshot notifications, etc.) — no banner needed
        if !isOwnMessage,
           !message.isSystemMessage,
           ChatNotificationState.shared.isInChatModule,
           !ChatNotificationState.shared.isViewingConversation(conversationId) {
            showInAppBanner(conversationId: conversationId, message: message)
        }

        AppLogger.debug("ChatListViewModel: applyIncomingMessage completed. existedPreviously=\(conversationExisted)")
        scheduleRealtimeSync(forceRefresh: !conversationExisted)
    }

    private func showInAppBanner(conversationId: String, message: ConversationMessage) {
        let chatRow = chatDataService.chat(withId: conversationId)
        let chatType = chatRow?.type?.lowercased() ?? "direct"

        let senderName = (message.sender?.fullName?.isEmpty == false ? message.sender?.fullName : nil)
            ?? (message.sender?.userName?.isEmpty == false ? message.sender?.userName : nil)
            ?? "Unknown"

        // For groups/channels use the conversation avatar; for direct chats use sender's profile picture
        let avatarStr: String?
        if chatType == "group" || chatType == "channel" {
            avatarStr = chatRow?.avatar
        } else {
            avatarStr = message.sender?.profilePicture ?? message.sender?.userDetails?.dataValues?.profilePicture
        }
        let senderAvatarURL: URL? = avatarStr.map {
            let full = $0.hasPrefix("http") ? $0 : "\(ChatConfig.mediaBaseURL)/\($0)"
            return URL(string: full)
        } ?? nil

        let messagePreview: String
        if let text = message.content, !text.isEmpty {
            messagePreview = String(text.htmlToString.prefix(80))
        } else if message.messageType == "image" {
            messagePreview = "Photo"
        } else if message.messageType == "video" {
            messagePreview = "Video"
        } else if message.messageType == "audio" || message.messageType == "voice" {
            messagePreview = "Audio"
        } else {
            messagePreview = "New message"
        }

        ChatNotificationState.shared.setPendingBanner(
            InAppChatBannerData(
                conversationId: conversationId,
                senderName: senderName,
                senderAvatarURL: senderAvatarURL,
                messagePreview: messagePreview,
                isGroupChat: chatType == "group",
                groupName: chatRow?.title,
                chatType: chatType
            ),
            messageId: message.id
        )
    }

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func applyConversationSettings(chatId: String, settings: [String: Any]) {
        // 1) Optimistic UI — refresh mute/pin/archive icon immediately
        applySettingsToSnapshot(chatId: chatId, settings: settings)
        chatDataService.updateChatSettings(conversationId: chatId, settings: settings)

        // 2) REST — FE PATCH /chat/conversations/{id}/settings `{ isMuted?, isPinned?, ... }`
        let payload = restSettingsPayload(from: settings)
        AppLogger.debug("[Settings] ▶ PATCH chat/conversations/\(chatId)/settings \(payload)")
        sessionManager.updateConversationSettings(conversationId: chatId, settings: payload)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] data in
                    guard let self else { return }
                    if let remote = data.settings {
                        var merged: [String: Any] = [:]
                        if let v = remote.isMuted { merged["isMuted"] = v }
                        if let v = remote.isPinned { merged["isPinned"] = v }
                        if let v = remote.isArchived { merged["isArchived"] = v }
                        if let v = remote.isBlocked { merged["isBlocked"] = v }
                        if let v = remote.isLocked { merged["isLocked"] = v }
                        if let v = remote.labelText { merged["labelText"] = v }
                        if let v = remote.labelColor { merged["labelColor"] = v }
                        if !merged.isEmpty {
                            self.applySettingsToSnapshot(chatId: chatId, settings: merged)
                            self.chatDataService.updateChatSettings(conversationId: chatId, settings: merged)
                        }
                    }
                    AppLogger.debug("[Settings] ✅ Updated conversation \(chatId)")
                },
                onFailure: { [weak self] error in
                    AppLogger.debug("[Settings] ❌ \(error.localizedDescription)")
                    self?.handleError(error)
                }
            )
            .disposed(by: disposeBag)
    }

    /// Keep `chatsSnapshot` in sync so SwiftUI re-renders mute icon without waiting for FRC.
    private func applySettingsToSnapshot(chatId: String, settings: [String: Any]) {
        guard let index = chatsSnapshot.firstIndex(where: { $0.id == chatId }) else { return }
        var chat = chatsSnapshot[index]
        var current = chat.settings ?? ConversationSettings()
        if let value = SocketAckParser.boolValue(from: settings["isMuted"]) { current.isMuted = value }
        if let value = SocketAckParser.boolValue(from: settings["isPinned"]) { current.isPinned = value }
        if let value = SocketAckParser.boolValue(from: settings["isArchived"]) { current.isArchived = value }
        if let value = SocketAckParser.boolValue(from: settings["isLocked"]) { current.isLocked = value }
        if let value = SocketAckParser.boolValue(from: settings["isBlocked"]) { current.isBlocked = value }
        if let value = settings["disappearingMessages"] as? Int { current.disappearingMessages = value }
        if settings.keys.contains("label") {
            let text = (settings["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            current.label = [(text?.isEmpty == false) ? text : nil]
            current.labelText = (text?.isEmpty == false) ? text : nil
        }
        if let value = settings["labelText"] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            current.labelText = trimmed.isEmpty ? nil : trimmed
            current.label = [trimmed.isEmpty ? nil : trimmed]
        }
        if settings.keys.contains("labelColor") {
            let color = settings["labelColor"] as? String
            current.labelColor = (color?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? color : nil
        }
        chat.settings = current
        chatsSnapshot[index] = chat
    }

    /// Map local settings keys to FE REST body (`label` → `labelText`).
    private func restSettingsPayload(from settings: [String: Any]) -> [String: Any] {
        var payload = settings
        if payload.keys.contains("label") {
            let labelValue = payload.removeValue(forKey: "label")
            if let text = labelValue as? String {
                payload["labelText"] = text
            } else if let arr = labelValue as? [String?], let first = arr.first {
                payload["labelText"] = first ?? ""
            } else {
                payload["labelText"] = ""
            }
        }
        return payload
    }

    private func chat(for chatId: String) -> ChatMessageRow? {
        chatsSnapshot.first(where: { $0.id == chatId }) ?? chatDataService.chat(withId: chatId)
    }

    private static func unreadCount(from messageData: [String: Any]) -> Int? {
        func intValue(_ value: Any?) -> Int? {
            if let int = value as? Int { return int }
            if let number = value as? NSNumber { return number.intValue }
            if let string = value as? String { return Int(string) }
            return nil
        }

        if let unread = intValue(messageData["unreadCount"]) ?? intValue(messageData["unread_count"]) {
            return unread
        }
        if let conversation = messageData["conversation"] as? [String: Any] {
            return intValue(conversation["unreadCount"])
                ?? intValue(conversation["unread_count"])
                ?? intValue((conversation["settings"] as? [String: Any])?["unreadCount"])
        }
        if let settings = messageData["settings"] as? [String: Any] {
            return intValue(settings["unreadCount"]) ?? intValue(settings["unread_count"])
        }
        return nil
    }

    private func scheduleRealtimeSync(forceRefresh: Bool) {
        realtimeSyncTask?.cancel()
        realtimeSyncTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: realtimeSyncDebounceNanoseconds)
            await MainActor.run {
                AppLogger.debug("ChatListViewModel: Triggering realtime sync (forceRefresh=\(forceRefresh))")
                self.chatSyncService.syncChats(loadPolicy: .ifStale, forceRefresh: forceRefresh)
            }
        }
    }

    private func refreshPendingConversationIds(from chats: [ChatMessageRow]) {
        let store = PendingMessageStore.shared
        let pending = Set(chats.compactMap { chat -> String? in
            guard let id = chat.id else { return nil }
            return store.hasPending(for: id) ? id : nil
        })
        if pending != pendingConversationIds {
            pendingConversationIds = pending
        }
    }

}
