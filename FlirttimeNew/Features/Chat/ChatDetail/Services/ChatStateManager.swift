//
//  ChatStateManager.swift
//  FlirttimeNew
//
//  Created by Awais on 25/09/25.
//

import Foundation
import Combine
import Kingfisher

struct MessageGroup: Equatable {
    let date: String
    let messages: [ConversationMessage]
}

protocol ChatStateManagerProtocol {
    var messages: AnyPublisher<[ConversationMessage], Never> { get }
    var groupedMessages: AnyPublisher<[MessageGroup], Never> { get }
    var newMessageIds: AnyPublisher<Set<String>, Never> { get }
    var currentPage: AnyPublisher<Int, Never> { get }
    var hasMorePages: AnyPublisher<Bool, Never> { get }
    var isLoadingMessages: AnyPublisher<Bool, Never> { get }

    func setMessages(_ messages: [ConversationMessage])
    func addMessages(_ newMessages: [ConversationMessage])
    func prependMessages(_ olderMessages: [ConversationMessage]) // Add older messages at the beginning
    func prependMessagesSilently(_ olderMessages: [ConversationMessage]) // Add without triggering UI updates
    func replaceMessage(tempId: String, with serverMessage: ConversationMessage)
    func updateMessage(_ message: ConversationMessage)
    func batchUpdateMessages(_ messages: [ConversationMessage])
    func removeMessage(id: String)
    func clearMessages()
    func setLoadingState(_ isLoading: Bool)
    func incrementPage()
    func resetPagination()
    func markMessagesAsSeen(_ messageIds: [String])
    func messageById(_ id: String) -> ConversationMessage?
    func beginBatchUpdate()
    func endBatchUpdate()
    func getGroupedMessagesSnapshot() -> [MessageGroup]
    func silentSync(_ messages: [ConversationMessage])
}

class ChatStateManager: ChatStateManagerProtocol {

    private var _messages: [ConversationMessage] = []
    private var _groupedMessages: [MessageGroup] = []
    private var _newMessageIds: Set<String> = []

    private let _messagesSubject = CurrentValueSubject<[ConversationMessage], Never>([])
    private let _groupedMessagesSubject = CurrentValueSubject<[MessageGroup], Never>([])
    private let _newMessageIdsSubject = CurrentValueSubject<Set<String>, Never>([])
    @Published private var _currentPage: Int = 1
    @Published private var _hasMorePages: Bool = true
    @Published private var _isLoadingMessages: Bool = false

    private var _messageById: [String: ConversationMessage] = [:]
    private let maxMessageWindow: Int = 500
    private let emissionThrottleInterval: TimeInterval = 0.15

    private var cachedCurrentUserId: String = {
        return ChatUserDefaultsStore.shared.userId ?? ""
    }()

    private enum DedupKey: Hashable {
        case byId(String)
        case byContent(senderId: String, createdAt: String, content: String)
    }
    private var _seenDedupKeys: Set<DedupKey> = []

    private var _batchUpdateDepth: Int = 0

    private let lock = NSLock()

    var messages: AnyPublisher<[ConversationMessage], Never> {
        _messagesSubject
            .throttle(for: .seconds(emissionThrottleInterval), scheduler: DispatchQueue.main, latest: true)
            .eraseToAnyPublisher()
    }

    var groupedMessages: AnyPublisher<[MessageGroup], Never> {
        _groupedMessagesSubject
            .throttle(for: .seconds(emissionThrottleInterval), scheduler: DispatchQueue.main, latest: true)
            .eraseToAnyPublisher()
    }

    var newMessageIds: AnyPublisher<Set<String>, Never> {
        _newMessageIdsSubject
            .throttle(for: .seconds(emissionThrottleInterval), scheduler: DispatchQueue.main, latest: true)
            .eraseToAnyPublisher()
    }

    var currentPage: AnyPublisher<Int, Never> {
        $_currentPage.eraseToAnyPublisher()
    }

    var hasMorePages: AnyPublisher<Bool, Never> {
        $_hasMorePages.eraseToAnyPublisher()
    }

    var isLoadingMessages: AnyPublisher<Bool, Never> {
        $_isLoadingMessages.eraseToAnyPublisher()
    }

    private func filterUniqueMessagesLocked(_ newMessages: [ConversationMessage]) -> [ConversationMessage] {
        guard !newMessages.isEmpty else { return [] }

        var unique: [ConversationMessage] = []

        for message in newMessages {
            if let key = deduplicationKey(for: message) {
                guard !_seenDedupKeys.contains(key) else { continue }
                _seenDedupKeys.insert(key)
            }
            unique.append(message)
        }

        return unique
    }

    func updateMessage(_ message: ConversationMessage) {
        lock.lock()
        let messageId = message.id
        guard let index = _messages.firstIndex(where: { $0.id == messageId }) else {
            lock.unlock()
            return
        }

        let old = _messages[index]
        _messages[index] = message
        _messageById[messageId] = message

        let needsSort = old.createdAt != message.createdAt

        if needsSort {
            AppLogger.debug("[StateManager] updateMessage: createdAt changed – re-sorting (\(old.createdAt) → \(message.createdAt))")
            sortMessages()
            rebuildLookup()
            let dateKey = String(message.createdAt.prefix(10))
            updateSingleDateGroup(dateKey)
        } else {
            let updated = updateGroupedMessageInPlace(messageId: messageId, replacement: message)
            if !updated {
                let dateKey = String(message.createdAt.prefix(10))
                updateSingleDateGroup(dateKey)
            }
        }

        let currentUserId = cachedCurrentUserId
        if message.sender?.id != currentUserId, message.seenAt == nil {
            _newMessageIds.insert(messageId)
        } else {
            _newMessageIds.remove(messageId)
        }

        emitState()
        lock.unlock()
    }

    @discardableResult
    private func updateGroupedMessageInPlace(messageId: String, replacement: ConversationMessage) -> Bool {
        for gi in 0..<_groupedMessages.count {
            if let mi = _groupedMessages[gi].messages.firstIndex(where: { $0.id == messageId }) {
                var msgs = _groupedMessages[gi].messages
                msgs[mi] = replacement
                _groupedMessages[gi] = MessageGroup(date: _groupedMessages[gi].date, messages: msgs)
                return true
            }
        }
        return false
    }

    func batchUpdateMessages(_ messages: [ConversationMessage]) {
        lock.lock()
        var affectedDates = Set<String>()
        var changed = false

        for message in messages {
            let messageId = message.id
            guard let index = _messages.firstIndex(where: { $0.id == messageId }) else { continue }

            _messages[index] = message
            _messageById[messageId] = message

            let currentUserId = cachedCurrentUserId
            if message.sender?.id != currentUserId, message.seenAt == nil {
                _newMessageIds.insert(messageId)
            } else {
                _newMessageIds.remove(messageId)
            }

            let dateKey = String(message.createdAt.prefix(10))
            affectedDates.insert(dateKey)
            changed = true
        }

        guard changed else {
            lock.unlock()
            return
        }

        for dateKey in affectedDates {
            updateSingleDateGroup(dateKey)
        }

        emitState()
        lock.unlock()
    }

    func removeMessage(id: String) {
        lock.lock()
        let dateKey: String? = _messages.first(where: { $0.id == id }).flatMap {
            String(($0.createdAt ?? "").prefix(10))
        }

        _messages.removeAll { $0.id == id }
        _messageById.removeValue(forKey: id)
        rebuildNewMessageIds()

        if let dateKey = dateKey {
            updateSingleDateGroup(dateKey)
        }
        emitState()
        lock.unlock()
    }

    func clearMessages() {
        lock.lock()
        _messages.removeAll()
        _messageById.removeAll()
        _newMessageIds.removeAll()
        _groupedMessages.removeAll()
        resetPagination()
        emitState()
        lock.unlock()
    }

    func markMessagesAsSeen(_ messageIds: [String]) {
        lock.lock()
        _newMessageIds.subtract(messageIds)
        let ids = _newMessageIds
        lock.unlock()
        _newMessageIdsSubject.send(ids)
    }

    func messageById(_ id: String) -> ConversationMessage? {
        lock.lock()
        defer { lock.unlock() }
        return _messageById[id]
    }

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Batch Updates

    func beginBatchUpdate() {
        lock.lock()
        _batchUpdateDepth += 1
        lock.unlock()
    }

    func endBatchUpdate() {
        lock.lock()
        _batchUpdateDepth = max(0, _batchUpdateDepth - 1)
        if _batchUpdateDepth == 0 {
            emitState()
        }
        lock.unlock()
    }

    // MARK: - Mutation Methods (Thread-Safe)

    func setMessages(_ messages: [ConversationMessage]) {
        lock.lock()
        let deduplicated = deduplicateMessages(messages)
        _messages = collapseStableIdentityCollisions(deduplicated)

        _seenDedupKeys = Set(_messages.compactMap { deduplicationKey(for: $0) })
        sortMessages()
        applyWindowingIfNeeded()
        rebuildLookup()
        rebuildNewMessageIds()
        rebuildGroupedMessages()
        prefetchVideoThumbnails(_messages)
        emitState()
        lock.unlock()
    }

    func addMessages(_ newMessages: [ConversationMessage]) {
        lock.lock()
        guard !newMessages.isEmpty else {
            lock.unlock()
            return
        }

        var seenDedupKeys = _seenDedupKeys
        var insertedCount = 0
        var updatedCount = 0
        var deduplicatedCount = 0

        for incoming in newMessages {
            if let existingIndex = findExistingMessageIndexLocked(for: incoming) {
                let merged = resolveIdentityCollision(existing: _messages[existingIndex], incoming: incoming)
                if _messages[existingIndex] != merged {
                    _messages[existingIndex] = merged
                    updatedCount += 1
                } else {
                    deduplicatedCount += 1
                }
                if let key = deduplicationKey(for: merged) {
                    seenDedupKeys.insert(key)
                }
                continue
            }

            if let key = deduplicationKey(for: incoming), seenDedupKeys.contains(key) {
                deduplicatedCount += 1
                continue
            }

            if let key = deduplicationKey(for: incoming) {
                seenDedupKeys.insert(key)
            }
            _messages.append(incoming)
            insertedCount += 1
        }

        guard insertedCount > 0 || updatedCount > 0 else {
            AppLogger.debug("[StateManager] addMessages: ALL \(newMessages.count) msg(s) deduplicated – skipping (ids: \(newMessages.map { $0.id.prefix(8) }.joined(separator: ", ")))")
            lock.unlock()
            return
        }

        AppLogger.debug("[StateManager] addMessages: inserted=\(insertedCount) updated=\(updatedCount) deduplicated=\(deduplicatedCount) total=\(_messages.count)")

        sortMessages()
        applyWindowingIfNeeded()
        rebuildLookup()
        rebuildNewMessageIds()
        _seenDedupKeys = Set(_messages.compactMap { deduplicationKey(for: $0) })

        // Rebuild for correctness: upserts can move messages across dates.
        rebuildGroupedMessages()
        prefetchVideoThumbnails(newMessages)
        emitState()
        lock.unlock()
    }

    func prependMessages(_ olderMessages: [ConversationMessage]) {
        lock.lock()
        let uniqueOlderMessages = olderMessages.filter { msg in
            findExistingMessageIndexLocked(for: msg) == nil
        }
        guard !uniqueOlderMessages.isEmpty else {
            lock.unlock()
            return
        }

        _messages.insert(contentsOf: uniqueOlderMessages, at: 0)
        sortMessages()
        applyWindowingIfNeeded(trimming: .newest)
        rebuildLookup()
        rebuildNewMessageIds()
        _seenDedupKeys = Set(_messages.compactMap { deduplicationKey(for: $0) })
        incrementalGroupUpdate(affectedMessages: uniqueOlderMessages)
        emitState()
        lock.unlock()
    }

    func prependMessagesSilently(_ olderMessages: [ConversationMessage]) {
        lock.lock()
        let uniqueOlderMessages = olderMessages.filter { msg in
            findExistingMessageIndexLocked(for: msg) == nil
        }
        guard !uniqueOlderMessages.isEmpty else {
            lock.unlock()
            return
        }

        _messages.insert(contentsOf: uniqueOlderMessages, at: 0)
        sortMessages()
        applyWindowingIfNeeded(trimming: .newest)
        rebuildLookup()
        _seenDedupKeys = Set(_messages.compactMap { deduplicationKey(for: $0) })
        rebuildGroupedMessages()
        emitState()
        lock.unlock()
    }

    func replaceMessage(tempId: String, with serverMessage: ConversationMessage) {
        lock.lock()
        if let index = _messages.firstIndex(where: { $0.id == tempId }) {
            AppLogger.debug("[StateManager] replaceMessage: tempId=\(tempId) → serverId=\(serverMessage.id) at flatIndex=\(index) | total=\(_messages.count) | stableId=\(serverMessage.stableId)")
            _messages[index] = serverMessage

            _messageById.removeValue(forKey: tempId)
            _messageById[serverMessage.id] = serverMessage

            // Full rebuild instead of in-place update to guarantee _groupedMessages
            // stays perfectly in sync with _messages and never emits duplicate stableIds.
            rebuildGroupedMessages()
            rebuildNewMessageIds()
            emitState()
        } else {
            AppLogger.debug("[StateManager] replaceMessage: tempId=\(tempId) NOT FOUND in _messages (count=\(_messages.count))")
        }
        lock.unlock()
    }

    func setLoadingState(_ isLoading: Bool) {
        if Thread.isMainThread {
            _isLoadingMessages = isLoading
        } else {
            DispatchQueue.main.async { self._isLoadingMessages = isLoading }
        }
    }

    func incrementPage() {
        if Thread.isMainThread {
            _currentPage += 1
        } else {
            DispatchQueue.main.async { self._currentPage += 1 }
        }
    }

    func resetPagination() {
        if Thread.isMainThread {
            _currentPage = 1
            _hasMorePages = true
        } else {
            DispatchQueue.main.async {
                self._currentPage = 1
                self._hasMorePages = true
            }
        }
    }

    /// Fully synchronizes stateManager's internal state from a flat list of messages
    /// without triggering any Combine emissions or UI updates.
    /// Used by the FRC to keep stateManager in sync when the FRC fast-path was taken
    /// during initial load (which bypasses setMessages). After calling this, any
    /// subsequent mutation (updateMessage, addMessages) will produce a correct, complete
    /// emitState rather than a partial single-group state.
    func silentSync(_ messages: [ConversationMessage]) {
        lock.lock()
        _messages = messages
        _messageById = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        _seenDedupKeys = Set(_messages.compactMap { deduplicationKey(for: $0) })
        rebuildGroupedMessages()
        rebuildNewMessageIds()
        lock.unlock()
    }

    /// Returns a thread-safe snapshot of the current grouped messages.
    /// Use this to bypass the throttled Combine pipeline for latency-critical paths.
    func getGroupedMessagesSnapshot() -> [MessageGroup] {
        lock.lock()
        let snapshot = _groupedMessages
        lock.unlock()
        return snapshot
    }

    // MARK: - Private Helper Methods

    private func emitState() {
        guard _batchUpdateDepth == 0 else { return }
        _messagesSubject.send(_messages)
        _groupedMessagesSubject.send(_groupedMessages)
        _newMessageIdsSubject.send(_newMessageIds)
    }

    private func prefetchVideoThumbnails(_ messages: [ConversationMessage]) {
        let urls: [URL] = messages.compactMap { msg in
            guard (msg.type == "video" || msg.messageType == "video" ||
                   msg.media?.first?.type == "video") else { return nil }

            if InMemoryMediaCache.shared.getCachedImage(for: msg.id) != nil { return nil }
            let urlString = msg.thumbnail ?? msg.media?.first?.thumbnail
            guard let s = urlString, !s.isEmpty, let url = URL(string: s) else { return nil }
            return url
        }
        guard !urls.isEmpty else { return }
        let prefetcher = ImagePrefetcher(urls: urls)
        prefetcher.start()
    }

    private func findExistingMessageIndexLocked(for incoming: ConversationMessage) -> Int? {
        let messageId = incoming.id
        if !messageId.isEmpty,
           let byId = _messages.firstIndex(where: { $0.id == messageId }) {
            return byId
        }

        let incomingStableId = incoming.stableId
        return _messages.firstIndex(where: { $0.stableId == incomingStableId })
    }

    private func resolveIdentityCollision(existing: ConversationMessage,
                                          incoming: ConversationMessage) -> ConversationMessage {
        let existingLooksTemporary = existing.id == existing.stableId
        let incomingLooksTemporary = incoming.id == incoming.stableId

        if existingLooksTemporary && !incomingLooksTemporary { return incoming }
        if !existingLooksTemporary && incomingLooksTemporary { return existing }
        return incoming
    }

    private func collapseStableIdentityCollisions(_ messages: [ConversationMessage]) -> [ConversationMessage] {
        guard !messages.isEmpty else { return messages }

        var orderedStableIds: [String] = []
        var byStableId: [String: ConversationMessage] = [:]

        for message in messages {
            let stableId = message.stableId
            if let existing = byStableId[stableId] {
                byStableId[stableId] = resolveIdentityCollision(existing: existing, incoming: message)
            } else {
                orderedStableIds.append(stableId)
                byStableId[stableId] = message
            }
        }

        if orderedStableIds.count != messages.count {
            AppLogger.debug("[StateManager] setMessages: collapsed stable identity collisions from \(messages.count) to \(orderedStableIds.count)")
        }

        return orderedStableIds.compactMap { byStableId[$0] }
    }

    private func rebuildLookup() {
        var dict = [String: ConversationMessage](minimumCapacity: _messages.count)
        for message in _messages {
            dict[message.id] = message
        }
        _messageById = dict
    }

    private func sortMessages() {
        _messages.sort {
            let lhs = $0.createdAt ?? ""
            let rhs = $1.createdAt ?? ""
            // Empty/nil dates sort to the END (newest), not the top
            if lhs.isEmpty { return false }
            if rhs.isEmpty { return true }
            return lhs < rhs
        }
    }

    private func rebuildNewMessageIds() {
        _newMessageIds.removeAll()
        updateUnseenMessages(_messages)
    }

    private enum TrimDirection { case oldest, newest }

    private func applyWindowingIfNeeded(trimming: TrimDirection = .oldest) {
        guard maxMessageWindow > 0, _messages.count > maxMessageWindow else { return }
        let overflow = _messages.count - maxMessageWindow
        guard overflow > 0 else { return }
        switch trimming {
        case .oldest: _messages.removeFirst(overflow)
        case .newest: _messages.removeLast(overflow)
        }
    }

    private func rebuildGroupedMessages() {
        _groupedMessages = groupMessagesByDate(_messages)
    }

    private func incrementalGroupUpdate(affectedMessages: [ConversationMessage]) {
        let affectedDates = Set(affectedMessages.compactMap { String(($0.createdAt ?? "").prefix(10)) })

        if affectedDates.isEmpty {
            rebuildGroupedMessages()
            return
        }

        if affectedDates.count > 5 {
            rebuildGroupedMessages()
            return
        }

        for dateKey in affectedDates {
            updateSingleDateGroup(dateKey)
        }

        // Ensure groups are sorted
        _groupedMessages.sort { $0.date < $1.date }
    }

    private func updateSingleDateGroup(_ dateKey: String) {
        let messagesForDate = _messages.filter {
            String(($0.createdAt ?? "").prefix(10)) == dateKey
        }.sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }

        if messagesForDate.isEmpty {
            _groupedMessages.removeAll { $0.date == dateKey }
        } else if let idx = _groupedMessages.firstIndex(where: { $0.date == dateKey }) {
            _groupedMessages[idx] = MessageGroup(date: dateKey, messages: messagesForDate)
        } else {
            let newGroup = MessageGroup(date: dateKey, messages: messagesForDate)
            if let insertIdx = _groupedMessages.firstIndex(where: { $0.date > dateKey }) {
                _groupedMessages.insert(newGroup, at: insertIdx)
            } else {
                _groupedMessages.append(newGroup)
            }
        }
    }

    private func filterUniqueMessages(_ newMessages: [ConversationMessage]) -> [ConversationMessage] {
        guard !newMessages.isEmpty else { return [] }

        var unique: [ConversationMessage] = []

        for message in newMessages {
            if let key = deduplicationKey(for: message) {
                guard !_seenDedupKeys.contains(key) else { continue }
                _seenDedupKeys.insert(key)
            }
            unique.append(message)
        }

        return unique
    }

    private func deduplicateMessages(_ messages: [ConversationMessage]) -> [ConversationMessage] {
        var seenKeys: Set<DedupKey> = []
        var result: [ConversationMessage] = []

        for message in messages {
            if let key = deduplicationKey(for: message) {
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
            }
            result.append(message)
        }

        return result
    }

    private func deduplicationKey(for message: ConversationMessage) -> DedupKey? {
        let id = message.id
        if !id.isEmpty {
            return .byId(id)
        }

        let senderId = message.sender?.id ?? message.senderId ?? ""
        let createdAt = message.createdAt
        let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !senderId.isEmpty || !createdAt.isEmpty || !content.isEmpty else { return nil }

        return .byContent(senderId: senderId, createdAt: createdAt, content: content)
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        return isoFormatter.date(from: dateString) ?? fallbackFormatter.date(from: dateString)
    }

    private func updateUnseenMessages(_ newMessages: [ConversationMessage]) {
        let currentUserId = cachedCurrentUserId

        for message in newMessages {
            let messageId = message.id
            if message.sender?.id != currentUserId,
               message.seenAt == nil {
                _newMessageIds.insert(messageId)
            }
        }
    }

    private func groupMessagesByDate(_ messages: [ConversationMessage]) -> [MessageGroup] {
        var groups: [String: [ConversationMessage]] = [:]

        for message in messages {
            let dateString = message.createdAt
            let dateKey = dateString.isEmpty ? "unknown" : String(dateString.prefix(10))
            groups[dateKey, default: []].append(message)
        }

        return groups.map { date, msgs in
            MessageGroup(
                date: date,
                messages: msgs.sorted {
                    let lhs = $0.createdAt ?? ""
                    let rhs = $1.createdAt ?? ""
                    if lhs.isEmpty { return false }
                    if rhs.isEmpty { return true }
                    return lhs < rhs
                }
            )
        }.sorted { $0.date < $1.date }
    }

    private func getCurrentUserId() -> String {
        return ChatUserDefaultsStore.shared.userId ?? ""
    }

}
