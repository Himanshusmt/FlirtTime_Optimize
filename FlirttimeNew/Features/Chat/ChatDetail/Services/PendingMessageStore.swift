//
//  PendingMessageStore.swift
//  FlirttimeNew
//
//  Created by Awais on 25/02/26.
//

import Foundation
import Combine

final class PendingMessageStore {

    static let shared = PendingMessageStore()

    private let queue = DispatchQueue(label: "com.yandexgram.pendingMessages", qos: .utility)
    private let queueSpecificKey = DispatchSpecificKey<Void>()

    /// Fires on the internal serial queue whenever the pending set changes.
    /// Consumers should use `.receive(on: DispatchQueue.main)` before subscribing.
    let pendingChanged = PassthroughSubject<Void, Never>()
    private var pendingWriteWorkItem: DispatchWorkItem?

    private var _cache: [String: PendingEntry]?
    private var cache: [String: PendingEntry] {
        if let cached = _cache { return cached }
        let loaded = loadAllFromDisk()
        _cache = loaded
        return loaded
    }

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("FlirtTimeChat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending_messages.json")
    }

    private init() {
        queue.setSpecific(key: queueSpecificKey, value: ())
        queue.async { [weak self] in
            _ = self?.cache
        }
    }

    // MARK: - Public API

    func save(tempId: String, message: ConversationMessage, conversationId: String) {
        performSync { [weak self] in
            guard let self = self else { return }
            var pending = self.cache
            pending[tempId] = PendingEntry(message: message, conversationId: conversationId, createdAt: Date())
            self._cache = pending
            self.scheduleDiskWrite(pending)
        }
        pendingChanged.send()
    }

    func remove(tempId: String) {
        performSync { [weak self] in
            guard let self = self else { return }
            var pending = self.cache
            pending.removeValue(forKey: tempId)
            self._cache = pending
            self.scheduleDiskWrite(pending)
        }
        pendingChanged.send()
    }

    /// Returns `true` if there is at least one pending (unacked) message for the given conversation.
    func hasPending(for conversationId: String) -> Bool {
        performSync {
            cache.values.contains { $0.conversationId == conversationId }
        }
    }

    func pendingMessages(for conversationId: String) -> [(tempId: String, message: ConversationMessage)] {
        performSync {
            cache
                .filter { $0.value.conversationId == conversationId }
                .sorted { $0.value.createdAt < $1.value.createdAt }
                .map { (tempId: $0.key, message: $0.value.message) }
        }
    }

    func removeAll(for conversationId: String) {
        performSync { [weak self] in
            guard let self = self else { return }
            let pending = self.cache.filter { $0.value.conversationId != conversationId }
            self._cache = pending
            self.writeToDisk(pending)
        }
    }

    func allPendingEntriesWithConversationId() -> [(tempId: String, message: ConversationMessage, conversationId: String)] {
        performSync {
            cache
                .sorted { $0.value.createdAt < $1.value.createdAt }
                .map { (tempId: $0.key, message: $0.value.message, conversationId: $0.value.conversationId) }
        }
    }

    func clearStale(olderThan hours: Int = 24) {
        performSync { [weak self] in
            guard let self = self else { return }
            let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
            let pending = self.cache.filter { $0.value.createdAt > cutoff }
            self._cache = pending
            self.scheduleDiskWrite(pending)
        }
    }

    // MARK: - Internal

    private func loadAllFromDisk() -> [String: PendingEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: PendingEntry].self, from: data) else {
            return [:]
        }
        return entries
    }

    private func writeToDisk(_ entries: [String: PendingEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func scheduleDiskWrite(_ entries: [String: PendingEntry]) {
        pendingWriteWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.writeToDisk(entries)
        }
        pendingWriteWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func performSync<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            return work()
        }
        return queue.sync(execute: work)
    }
}

// MARK: - Pending Entry

private struct PendingEntry: Codable {
    let message: ConversationMessage
    let conversationId: String
    let createdAt: Date
}
