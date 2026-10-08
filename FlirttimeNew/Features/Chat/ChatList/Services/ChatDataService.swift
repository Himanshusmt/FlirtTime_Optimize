//
//  ChatDataService.swift
//  FlirttimeNew
//
//  Created by Awais on 29/09/2025.
//

import Foundation
import Combine

@MainActor
class ChatDataService: ObservableObject {
    // MARK: - Published State

    private(set) var chats: [ChatMessageRow] = []

    // MARK: - Private Properties

    private let conversationRepository: ConversationRepositoryAsync
    private let conversationPresentationStore = ConversationPresentationStore.shared
    private var recentlyClearedUnreadAt: [String: Date] = [:]
    private let unreadSuppressionWindow: TimeInterval = 30
    /// Last inbound message id that already incremented unread, so socket + FRC races don't double-count or skip.
    private var lastUnreadCountedMessageId: [String: String] = [:]
    private let frcManager = ChatListFRCManager()
    private var frcCancellable: AnyCancellable?

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterFallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Initialization

    init(conversationRepository: ConversationRepositoryAsync) {
        self.conversationRepository = conversationRepository
        startFRCSubscription()
    }

    private func startFRCSubscription() {
        frcCancellable = frcManager.$chats
            .receive(on: RunLoop.main)
            .sink { [weak self] frcChats in
                guard let self else { return }
                self.chats = self.mergeServerUnreadCounts(frcChats)
            }
        frcManager.start()
    }

    var frcChatsPublisher: Published<[ChatMessageRow]>.Publisher { frcManager.$chats }

    func enrichChats(_ chats: [ChatMessageRow]) -> [ChatMessageRow] {
        applyPresentationAndSuppression(to: mergeServerUnreadCounts(chats))
    }

    private func applyPresentationAndSuppression(to chats: [ChatMessageRow]) -> [ChatMessageRow] {
        guard !recentlyClearedUnreadAt.isEmpty || !conversationPresentationStore.snapshots.isEmpty else {
            return chats
        }
        let now = Date()
        var expiredIds: [String] = []

        let result = chats.map { chat -> ChatMessageRow in
            var processed = chat

            if let id = chat.id,
               let clearedAt = recentlyClearedUnreadAt[id],
               (processed.unreadCount ?? 0) > 0 {
                if now.timeIntervalSince(clearedAt) <= unreadSuppressionWindow {
                    processed.unreadCount = 0
                } else {
                    expiredIds.append(id)
                }
            }

            if let id = processed.id,
               let snapshot = conversationPresentationStore.snapshot(for: id) {
                if let title = snapshot.title, !title.isEmpty {
                    processed.title = title
                }
                if let avatarURL = snapshot.avatarURL, !avatarURL.isEmpty {
                    processed.avatar = avatarURL
                }
            }

            return processed
        }

        for id in expiredIds {
            recentlyClearedUnreadAt.removeValue(forKey: id)
        }

        return result
    }

    // MARK: - Public Methods

    func updateChats(_ newChats: [ChatMessageRow], replaceExisting: Bool = false) {
        let deduplicated = removeDuplicates(from: newChats)
        let processed = processChatData(deduplicated)
        let reconciled = applyConversationPresentationSnapshots(to: processed)
        AppLogger.debug("ChatDataService: updateChats with \(newChats.count) chats (replaceExisting=\(replaceExisting)); persisting \(reconciled.count) to CoreData")
        Task { [weak self] in
            do {
                try await self?.conversationRepository.saveConversations(reconciled)
            } catch {
                AppLogger.debug("ChatDataService: updateChats save error: \(error)")
            }
        }
    }

    func updateChatSettings(conversationId: String, settings: [String: Any]) {
        // Optimistic in-memory update so mute/pin/archive icons refresh immediately
        // even before CoreData → FRC round-trip completes.
        if let index = chats.firstIndex(where: { $0.id == conversationId }) {
            var chat = chats[index]
            applySettingsDictionary(settings, to: &chat)
            chats[index] = chat
        }
        persistChatSettings(conversationId: conversationId, settings: settings)
    }

    private func applySettingsDictionary(_ settings: [String: Any], to chat: inout ChatMessageRow) {
        var current = chat.settings ?? ConversationSettings()
        if let value = SocketAckParser.boolValue(from: settings["isMuted"]) { current.isMuted = value }
        if let value = SocketAckParser.boolValue(from: settings["isPinned"]) { current.isPinned = value }
        if let value = SocketAckParser.boolValue(from: settings["isArchived"]) { current.isArchived = value }
        if let value = SocketAckParser.boolValue(from: settings["isLocked"]) { current.isLocked = value }
        if let value = SocketAckParser.boolValue(from: settings["isBlocked"]) { current.isBlocked = value }
        if let value = settings["disappearingMessages"] as? Int { current.disappearingMessages = value }
        if settings.keys.contains("label") {
            current.label = [normalizedOptionalString(from: settings["label"])]
            if let text = normalizedOptionalString(from: settings["label"]) {
                current.labelText = text
            } else {
                current.labelText = nil
            }
        }
        if let value = settings["labelText"] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                current.labelText = nil
                current.label = [nil]
            } else {
                current.labelText = trimmed
                current.label = [trimmed]
            }
        }
        if settings.keys.contains("labelColor") {
            if let value = settings["labelColor"] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                current.labelColor = value
            } else {
                current.labelColor = nil
            }
        }
        chat.settings = current
    }

    func removeChat(_ conversationId: String, deleteFromStore: Bool = false) {
        ChatDataPreloader.shared.consumePreloadedMessages(for: conversationId)
        cleanupLinkedData(for: conversationId)

        guard deleteFromStore else { return }

        Task { [weak self] in
            do {
                try await self?.conversationRepository.deleteConversation(id: conversationId)
                AppLogger.debug("ChatDataService: Conversation \(conversationId) deleted from store")
            } catch {
                AppLogger.debug("ChatDataService: Failed to delete conversation \(conversationId): \(error)")
            }
        }
    }

    private func cleanupLinkedData(for conversationId: String) {
        ConversationDraftStore.shared.remove(conversationId: conversationId)
        PendingMessageStore.shared.removeAll(for: conversationId)
        ChatDataPreloader.shared.storePinState(for: conversationId, message: nil)
    }

    func chat(withId conversationId: String) -> ChatMessageRow? {
        chats.first(where: { $0.id == conversationId })
    }

    func upsertConversation(_ conversation: ChatMessageRow) {
        guard let id = conversation.id, !id.isEmpty else { return }

        var sanitized = conversation
        // Ensure sort keys exist for brand-new groups (no messages yet).
        if (sanitized.lastMessageAt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            sanitized.lastMessageAt = formatter.string(from: Date())
        }

        let isAlreadyTracked = chats.contains { $0.id == id }
        if !isAlreadyTracked && (sanitized.lastMessage == nil || sanitized.lastMessage?.id == nil) {
            let incomingParticipants = sanitized.participants?.filter { $0.isActive != false }
            sanitized.participants = incomingParticipants
            saveConversationToDatabase(sanitized)
            return
        }

        let incomingParticipants = sanitized.participants?.filter { $0.isActive != false }
        sanitized.participants = incomingParticipants
        if sanitized.lastMessage?.senderId == getCurrentUserId() {
            sanitized.unreadCount = 0
        }
        if let existing = chats.first(where: { $0.id == id }) {
            if let incoming = incomingParticipants, !incoming.isEmpty,
               let existingParts = existing.participants, !existingParts.isEmpty,
               incoming.count < existingParts.count {
                let incomingUserIds = Set(incoming.compactMap { $0.userId })
                let existingUserIds = Set(existingParts.compactMap { $0.userId })
                let removedUserIds = existingUserIds.subtracting(incomingUserIds)

                for removedUserId in removedUserIds {
                    AppLogger.debug("ChatDataService: Detected member removal via create-conversation: \(removedUserId) from group \(id)")
                    Task { [weak self] in
                        try? await self?.conversationRepository.removeParticipant(conversationId: id, userId: removedUserId)
                    }
                    NotificationCenter.default.post(
                        name: NSNotification.Name("GroupMembersUpdated"),
                        object: nil,
                        userInfo: ["groupId": id, "action": "removed", "memberId": removedUserId]
                    )
                }
                sanitized.participants = incoming
            } else {
                sanitized.participants = (existing.participants?.count ?? 0) > (incomingParticipants?.count ?? 0) ? existing.participants : incomingParticipants
            }

            if sanitized.lastMessage == nil && existing.lastMessage != nil {
                sanitized.lastMessage = existing.lastMessage
            }

            sanitized.unreadCount = resolvedUnreadCount(
                conversationId: id,
                incoming: sanitized.unreadCount,
                existing: existing.unreadCount
            )
        }
        saveConversationToDatabase(sanitized)
    }

    func setUnreadCount(for conversationId: String, unreadCount: Int) {
        if unreadCount == 0 {
            recentlyClearedUnreadAt[conversationId] = Date()
        } else {
            recentlyClearedUnreadAt.removeValue(forKey: conversationId)
        }
        Task { [weak self] in
            do {
                try await self?.conversationRepository.updateUnreadCount(conversationId: conversationId, unreadCount: max(0, unreadCount))
            } catch {
                AppLogger.debug("ChatDataService: setUnreadCount error: \(error)")
            }
        }
    }

    func updateChatTitle(conversationId: String, newTitle: String) {
        Task { [weak self] in
            do {
                try await self?.conversationRepository.updateConversationTitle(id: conversationId, newTitle: newTitle)
                AppLogger.debug("ChatDataService: Title persisted for conversation \(conversationId)")
            } catch {
                AppLogger.debug("ChatDataService: Title persistence error: \(error)")
            }
        }
    }

    func updateLastMessageStatus(conversationId: String, messageId: String, status: String) {
        guard !conversationId.isEmpty, !messageId.isEmpty else { return }
        Task { [weak self] in
            await self?.conversationRepository.updateLastMessageStatusIfLatest(conversationId: conversationId, messageId: messageId, status: status)
        }
    }

    func updateLastMessageAsDeleted(conversationId: String, messageId: String) {
        guard !conversationId.isEmpty, !messageId.isEmpty else { return }
        Task { [weak self] in
            await self?.conversationRepository.markLastMessageAsDeleted(conversationId: conversationId, messageId: messageId)
        }
    }

    func updateChatAvatar(conversationId: String, newAvatar: String) {
        let oldAvatar = chats.first(where: { $0.id == conversationId })?.avatar
        if let old = oldAvatar, !old.isEmpty {
            ProfilePictureCache.shared.removeCachedImage(userId: "group_\(conversationId)")
        }
        Task { [weak self] in
            do {
                try await self?.conversationRepository.updateConversationAvatar(id: conversationId, newAvatar: newAvatar)
                AppLogger.debug("ChatDataService: Avatar persisted for conversation \(conversationId)")
            } catch {
                AppLogger.debug("ChatDataService: Avatar persistence error: \(error)")
            }
        }
    }

    func addGroupParticipant(conversationId: String, participant: GroupParticipant) {
        Task { [weak self] in
            do {
                try await self?.conversationRepository.addParticipant(conversationId: conversationId, participant: participant)
                AppLogger.debug("ChatDataService: Participant \(participant.userId) added for conversation \(conversationId)")
            } catch {
                AppLogger.debug("ChatDataService: Add participant error: \(error)")
            }
        }
    }

    func removeGroupParticipant(conversationId: String, userId: String) {
        Task { [weak self] in
            do {
                try await self?.conversationRepository.removeParticipant(conversationId: conversationId, userId: userId)
                AppLogger.debug("ChatDataService: Participant \(userId) removed for conversation \(conversationId)")
            } catch {
                AppLogger.debug("ChatDataService: Remove participant error: \(error)")
            }
        }
    }

    func updateParticipantRole(conversationId: String, userId: String, newRole: String) {
        Task { [weak self] in
            do {
                try await self?.conversationRepository.updateParticipantRole(conversationId: conversationId, userId: userId, newRole: newRole)
                AppLogger.debug("ChatDataService: Participant \(userId) role updated to \(newRole) for conversation \(conversationId)")
            } catch {
                AppLogger.debug("ChatDataService: Update role error: \(error)")
            }
        }
    }

    @discardableResult
    func applyIncomingMessage(
        conversationId: String,
        message: ConversationMessage,
        currentUserId: String,
        shouldIncrementUnread: Bool = true,
        serverUnreadCount: Int? = nil
    ) -> Bool {
        guard !conversationId.isEmpty else { return false }

        AppLogger.debug("ChatDataService: Incoming message \(message.id) for conversation \(conversationId)")

        let existing = chats.first { $0.id == conversationId }
        var updatedChat = existing ?? ChatMessageRow()

        if existing != nil {
            AppLogger.debug("ChatDataService: Conversation \(conversationId) already tracked. Updating existing entry")
        } else {
            AppLogger.debug("ChatDataService: Conversation \(conversationId) not found in-cache. Creating placeholder entry")
        }

        if updatedChat.id == nil {
            updatedChat.id = conversationId
        }

        if updatedChat.participants == nil || updatedChat.participants?.isEmpty == true {
            if let sender = message.sender, sender.id != currentUserId {
                let senderDetail = UserDetail(
                    userName: sender.userName ?? sender.fullName,
                    fullName: sender.fullName ?? sender.userName,
                    profilePicture: sender.profilePicture,
                    profilePictureDetails: nil
                )
                let senderUser = ParticipantUser(
                    id: sender.id,
                    userDetails: [senderDetail],
                    isOnline: nil
                )
                let senderParticipant = Participant(
                    id: nil,
                    conversationId: conversationId,
                    userId: sender.id,
                    role: nil,
                    joinedAt: nil,
                    leftAt: nil,
                    isActive: true,
                    createdAt: nil,
                    updatedAt: nil,
                    user: senderUser
                )

                let currentUserParticipant = Participant(
                    id: nil,
                    conversationId: conversationId,
                    userId: currentUserId,
                    role: nil,
                    joinedAt: nil,
                    leftAt: nil,
                    isActive: true,
                    createdAt: nil,
                    updatedAt: nil,
                    user: nil
                )

                updatedChat.participants = [currentUserParticipant, senderParticipant]
            }
        }

        if updatedChat.type == nil {
            updatedChat.type = message.type ?? message.messageType
        }

        let incomingTimestamp = normalizedTimestamp(for: message)
        let incomingDate = parseDate(incomingTimestamp)
        let existingTimestampString = updatedChat.lastMessage?.createdAt ?? updatedChat.lastMessageAt
        let existingDate = parseDate(existingTimestampString)
        let isSameMessage = (message.id != nil && message.id == updatedChat.lastMessage?.id)
        let messageSummary = lastMessageSummary(for: message)
        let senderId = message.sender?.id ?? message.senderId

        let messageType = message.type ?? message.messageType ?? updatedChat.lastMessage?.messageType
        let messageStatus = message.status ?? message.statuses?.last?.status

        var updatedLastMessage = ConversationLastMessage(
            id: message.id.isEmpty ? updatedChat.lastMessage?.id : message.id,
            messageType: messageType,
            contentPreview: messageSummary.isEmpty ? updatedChat.lastMessage?.contentPreview : messageSummary,
            senderId: senderId ?? updatedChat.lastMessage?.senderId,
            createdAt: incomingTimestamp,
            status: messageStatus
        )

        let shouldPromote = !isSameMessage && (existingTimestampString == nil || incomingDate >= existingDate)
        let shouldUpdateTimestamp = shouldPromote || existingTimestampString == nil
        let timestampToUse = shouldUpdateTimestamp ? incomingTimestamp : (existingTimestampString ?? incomingTimestamp)
        updatedLastMessage.createdAt = timestampToUse
        updatedChat.lastMessage = updatedLastMessage

        if shouldPromote || updatedChat.lastMessageAt == nil {
            updatedChat.lastMessageAt = timestampToUse
        }

        if !message.isSystemMessage {
            applyUnreadForIncomingMessage(
                to: &updatedChat,
                conversationId: conversationId,
                messageId: message.id,
                senderId: senderId,
                currentUserId: currentUserId,
                shouldIncrementUnread: shouldIncrementUnread,
                serverUnreadCount: serverUnreadCount
            )
        }

        if existing == nil {
            if updatedChat.unreadCount == nil {
                updatedChat.unreadCount = (senderId == currentUserId || !shouldIncrementUnread) ? 0 : 1
            }
            if updatedChat.unreadCount ?? 0 > 0 {
                NotificationCenter.default.post(name: .ChatHasUnreadMessages, object: nil)
            }
        }

        replaceInMemoryChat(updatedChat)

        let hasParticipantData = !(updatedChat.participants?.isEmpty ?? true)
        if existing != nil || hasParticipantData {
            AppLogger.debug("ChatDataService: Persisting conversation \(conversationId) to Core Data")
            saveConversationToDatabase(updatedChat)
        } else {
            AppLogger.debug("ChatDataService: Skipping Core Data persist — placeholder has no participant data for \(conversationId)")
        }

        return existing != nil
    }

    // MARK: - Cache Loading

    func loadCachedChats() async -> [ChatMessageRow] {
        AppLogger.debug("ChatDataService: Loading cached chats from database...")
        let startTime = Date()

        do {
            let chats = try await conversationRepository.getAllConversationsIncludingArchived()
            let duration = Date().timeIntervalSince(startTime)
            let uniqueChats = removeDuplicates(from: chats)
            AppLogger.debug("ChatDataService: Loaded \(uniqueChats.count) cached chats in \(String(format: "%.3f", duration))s")
            return uniqueChats
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            AppLogger.debug("ChatDataService: Failed to load cached chats in \(String(format: "%.3f", duration))s: \(error.localizedDescription)")
            return []
        }
    }

    func loadCachedChatsFast() async -> [ChatMessageRow] {
        // Use the same async method - the repository handles fast loading internally
        await loadCachedChats()
    }

    func loadCachedChatsSync() -> [ChatMessageRow] {
        if !chats.isEmpty {
            return chats
        }

        guard let repo = conversationRepository as? ConversationRepository else {
            return chats
        }

        let cached = repo.getAllConversationsSync()
        if !cached.isEmpty {
            AppLogger.debug("ChatDataService: loadCachedChatsSync loaded \(cached.count) chats (pre-FRC)")
            return processChatData(cached)
        }
        return chats
    }

    // MARK: - Database Operations

    func saveChatsToDatabase(_ chats: [ChatMessageRow]) async {
        do {
            let mergedUnread = mergeServerUnreadCounts(chats)
            let reconciled = applyConversationPresentationSnapshots(to: mergedUnread)
            try await conversationRepository.saveConversations(reconciled)
            AppLogger.debug("ChatDataService: Saved \(reconciled.count) chats to database with participants")
        } catch {
            AppLogger.debug("ChatDataService: Database save error: \(error)")
        }
    }

    func pruneStaleConversations(keepingIds ids: Set<String>) async {
        do {
            try await conversationRepository.deleteConversations(notIn: ids)
        } catch {
            AppLogger.debug("ChatDataService: Failed to prune stale conversations: \(error)")
        }
    }

    private func saveConversationToDatabase(_ chat: ChatMessageRow) {
        Task { [weak self] in
            do {
                try await self?.conversationRepository.saveConversation(chat)
                AppLogger.debug("ChatDataService: Saved conversation \(chat.id ?? "") to database")
            } catch {
                AppLogger.debug("ChatDataService: Conversation save error: \(error)")
            }
        }
    }

    // MARK: - Private Helpers

    private func getCurrentUserId() -> String {
        ChatAuthStore.shared.currentUserId
    }

    private func applyUnreadForIncomingMessage(
        to chat: inout ChatMessageRow,
        conversationId: String,
        messageId: String,
        senderId: String?,
        currentUserId: String,
        shouldIncrementUnread: Bool,
        serverUnreadCount: Int?
    ) {
        let resolvedSender = senderId ?? ""
        guard !resolvedSender.isEmpty, resolvedSender != currentUserId else { return }

        if shouldIncrementUnread {
            let alreadyCounted = !messageId.isEmpty && lastUnreadCountedMessageId[conversationId] == messageId
            var next = chat.unreadCount ?? 0
            if !alreadyCounted {
                next += 1
                if !messageId.isEmpty {
                    lastUnreadCountedMessageId[conversationId] = messageId
                }
            }
            if let serverUnreadCount {
                next = max(next, serverUnreadCount)
            }
            chat.unreadCount = next
            recentlyClearedUnreadAt.removeValue(forKey: conversationId)
            AppLogger.debug("ChatDataService: Unread count for conversation \(conversationId) is \(next)")
            if next > 0 {
                NotificationCenter.default.post(name: .ChatHasUnreadMessages, object: nil)
            }
        } else {
            chat.unreadCount = 0
            recentlyClearedUnreadAt[conversationId] = Date()
            if !messageId.isEmpty {
                lastUnreadCountedMessageId[conversationId] = messageId
            }
        }
    }

    private func replaceInMemoryChat(_ chat: ChatMessageRow) {
        guard let id = chat.id, !id.isEmpty else { return }
        if let index = chats.firstIndex(where: { $0.id == id }) {
            chats[index] = chat
        } else {
            chats.insert(chat, at: 0)
        }
    }

    private func mergeServerUnreadCounts(_ serverChats: [ChatMessageRow]) -> [ChatMessageRow] {
        serverChats.map { chat in
            guard let id = chat.id, !id.isEmpty else { return chat }
            var merged = chat
            merged.unreadCount = resolvedUnreadCount(
                conversationId: id,
                incoming: chat.unreadCount,
                existing: chats.first(where: { $0.id == id })?.unreadCount
            )
            return merged
        }
    }

    private func resolvedUnreadCount(conversationId: String, incoming: Int?, existing: Int?) -> Int? {
        if let clearedAt = recentlyClearedUnreadAt[conversationId],
           Date().timeIntervalSince(clearedAt) <= unreadSuppressionWindow {
            return 0
        }
        let local = existing ?? 0
        guard let incoming else { return existing }
        return max(incoming, local)
    }

    private func processChatData(_ chats: [ChatMessageRow]) -> [ChatMessageRow] {
        chats.map { chat in
            var updatedChat = chat
            if let resolvedTitle = resolveTitle(for: updatedChat) {
                updatedChat.title = resolvedTitle
            }
            if updatedChat.lastMessage?.senderId == getCurrentUserId() {
                updatedChat.unreadCount = 0
            }
            updatedChat.participants = updatedChat.participants?.filter { $0.isActive != false }
            return updatedChat
        }
    }

    private func applyConversationPresentationSnapshots(to chats: [ChatMessageRow]) -> [ChatMessageRow] {
        guard !conversationPresentationStore.snapshots.isEmpty else { return chats }

        return chats.map { chat in
            guard let conversationId = chat.id,
                  let snapshot = conversationPresentationStore.snapshot(for: conversationId) else {
                return chat
            }

            var reconciled = chat
            let originalTitle = chat.title
            let originalAvatar = chat.avatar

            if let title = snapshot.title, !title.isEmpty {
                reconciled.title = title
            }

            if let avatarURL = snapshot.avatarURL, !avatarURL.isEmpty {
                reconciled.avatar = avatarURL
            }

            if originalTitle != reconciled.title || originalAvatar != reconciled.avatar {
                let snapshotTimestamp = Int(snapshot.updatedAt.timeIntervalSince1970)
                let oldAvatarTail = originalAvatar.map { String($0.suffix(80)) } ?? "nil"
                let newAvatarTail = reconciled.avatar.map { String($0.suffix(80)) } ?? "nil"
                AppLogger.debug("[AvatarReconcile] conversation=\(conversationId) snapshotTs=\(snapshotTimestamp) title:\(originalTitle ?? "nil") -> \(reconciled.title ?? "nil") avatarTail:\(oldAvatarTail) -> \(newAvatarTail)")
            }

            return reconciled
        }
    }

    private func persistChatSettings(conversationId: String, settings: [String: Any]) {
        let labelPayload: [String?]? = settings.keys.contains("label") || settings.keys.contains("labelText")
            ? [normalizedOptionalString(from: settings["labelText"] ?? settings["label"])]
            : nil
        let labelText: String? = settings.keys.contains("labelText")
            ? normalizedOptionalString(from: settings["labelText"])
            : (settings.keys.contains("label") ? normalizedOptionalString(from: settings["label"]) : nil)
        let labelColor: String? = {
            guard settings.keys.contains("labelColor") else { return nil }
            return normalizedOptionalString(from: settings["labelColor"]) ?? ""
        }()
        let conversationSettings = ConversationSettings(
            isMuted: settings["isMuted"] as? Bool,
            isPinned: settings["isPinned"] as? Bool,
            isArchived: settings["isArchived"] as? Bool,
            isLocked: settings["isLocked"] as? Bool,
            isBlocked: settings["isBlocked"] as? Bool,
            disappearingMessages: settings["disappearingMessages"] as? Int,
            label: labelPayload,
            labelText: labelText,
            labelColor: labelColor
        )

        Task { [weak self] in
            do {
                try await self?.conversationRepository.updateConversationSettings(
                    id: conversationId,
                    settings: conversationSettings
                )
                AppLogger.debug("ChatDataService: Settings persisted for conversation \(conversationId)")
            } catch {
                AppLogger.debug("ChatDataService: Settings persistence error: \(error)")
            }
        }
    }

    private func removeDuplicates(from chats: [ChatMessageRow]) -> [ChatMessageRow] {
        var uniqueChats: [ChatMessageRow] = []
        var seenIds = Set<String>()

        for chat in chats {
            guard let id = chat.id, !seenIds.contains(id) else { continue }
            seenIds.insert(id)
            uniqueChats.append(chat)
        }

        return uniqueChats.sorted { chat1, chat2 in
            let chat1Pinned = chat1.settings?.isPinned == true && chat1.settings?.isArchived != true
            let chat2Pinned = chat2.settings?.isPinned == true && chat2.settings?.isArchived != true

            if chat1Pinned != chat2Pinned {
                return chat1Pinned && !chat2Pinned
            }

            let date1 = parseDate(chat1.lastMessage?.createdAt ?? chat1.lastMessageAt)
            let date2 = parseDate(chat2.lastMessage?.createdAt ?? chat2.lastMessageAt)

            if date1 != date2 {
                return date1 > date2
            }

            return (chat1.title ?? "").lowercased() < (chat2.title ?? "").lowercased()
        }
    }

    private func parseDate(_ dateString: String?) -> Date {
        guard let dateString = dateString, !dateString.isEmpty else {
            return Date.distantPast
        }
        return Self.isoFormatter.date(from: dateString) ?? Self.isoFormatterFallback.date(from: dateString) ?? Date.distantPast
    }

    private func normalizedTimestamp(for message: ConversationMessage) -> String {
        let candidateTimestamps = [
            message.updatedAt,
            message.createdAt,
            message.sentAt,
            message.deliveredAt,
            message.seenAt
        ]

        for candidate in candidateTimestamps {
            if let candidate = candidate, let normalized = normalizeTimestampString(candidate) {
                return normalized
            }
        }

        return Self.isoFormatter.string(from: Date())
    }

    private func normalizeTimestampString(_ timestamp: String) -> String? {
        if let date = Self.isoFormatter.date(from: timestamp) {
            return Self.isoFormatter.string(from: date)
        }

        if let date = Self.isoFormatterFallback.date(from: timestamp) {
            return Self.isoFormatter.string(from: date)
        }

        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func lastMessageSummary(for message: ConversationMessage) -> String {
        let msgType = (message.type ?? message.messageType)?.lowercased() ?? ""
        if msgType == "call" || msgType.contains("call") {
            return ConversationMessage.callPreviewText(
                content: message.content,
                messageType: msgType
            )
        }
        if let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
            // Prefer body for text / system; for media types use the type label
            if msgType.isEmpty || msgType == "text" || msgType == "system" {
                return content.htmlToString
            }
        }
        let name = ConversationMessage.messageTypeDisplayName(msgType)
        if name.isEmpty {
            let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return content.isEmpty ? ChatStrings.chat_newMessage.localizedString() : content.htmlToString
        }
        return name
    }
}

// MARK: - Title Resolution

private extension ChatDataService {
    func normalizedOptionalString(from value: Any?) -> String? {
        if value is NSNull { return nil }
        return value as? String
    }

    func resolveTitle(for chat: ChatMessageRow) -> String? {
        guard chat.type?.lowercased() == "direct" else {
            if let sanitized = sanitizeTitle(chat.title), !sanitized.isEmpty {
                return sanitized
            }
            return chat.title
        }

        if let details = chat.getUserDetails() {
            if let fullName = sanitizeTitle(details.fullName), !fullName.isEmpty { return fullName }
            if let userName = sanitizeTitle(details.userName), !userName.isEmpty { return userName }
        }

        if let sanitized = sanitizeTitle(chat.title), !sanitized.isEmpty, !isCurrentUserName(sanitized, in: chat) {
            return sanitized
        }

        return chat.title
    }

    func isCurrentUserName(_ title: String, in chat: ChatMessageRow) -> Bool {
        guard let current = chat.currentUserParticipant?.user?.userDetails?.first else { return false }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ownFull = current.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ownUser = current.userName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == ownFull || normalized == ownUser
    }

    func sanitizeTitle(_ title: String?) -> String? {
        guard let raw = title else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let lower = trimmed.lowercased()
        if lower == "--" || lower == "direct chat" { return "" }
        return trimmed
    }
}
