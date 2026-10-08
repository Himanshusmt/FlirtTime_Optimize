//
//  ConversationDraftStore.swift
//  FlirttimeNew
//
//  Created by Awais on 28/04/26.
//

import Foundation

final class ConversationDraftStore {

    static let shared = ConversationDraftStore()

    private let queue = DispatchQueue(label: "com.yandexgram.conversationDrafts", qos: .utility)
    private var pendingWriteWorkItem: DispatchWorkItem?

    private var _cache: [String: DraftEntry]?
    private var cache: [String: DraftEntry] {
        if let cached = _cache { return cached }
        let loaded = loadAllFromDisk()
        _cache = loaded
        return loaded
    }

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("FlirtTimeChat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversation_drafts.json")
    }

    private init() {
        queue.async { [weak self] in
            _ = self?.cache
        }
    }

    // MARK: - Public API

    func save(conversationId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remove(conversationId: conversationId)
            return
        }

        let entry = DraftEntry(text: trimmed, updatedAt: Date())
        _cache?[conversationId] = entry

        queue.async { [weak self] in
            guard let self else { return }
            var drafts = self.cache
            drafts[conversationId] = entry
            self._cache = drafts
            self.scheduleDiskWrite(drafts)
        }
    }

    func load(conversationId: String) -> String? {
        return cache[conversationId]?.text
    }

    func remove(conversationId: String) {
        _cache?.removeValue(forKey: conversationId)

        queue.async { [weak self] in
            guard let self else { return }
            var drafts = self.cache
            drafts.removeValue(forKey: conversationId)
            self._cache = drafts
            self.writeToDisk(drafts)
        }
    }

    func clearAll() {
        _cache = [:]

        queue.async { [weak self] in
            guard let self else { return }
            self._cache = [:]
            self.writeToDisk([:])
        }
    }

    // MARK: - Internal

    private func loadAllFromDisk() -> [String: DraftEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: DraftEntry].self, from: data) else {
            return [:]
        }
        return entries
    }

    private func writeToDisk(_ entries: [String: DraftEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func scheduleDiskWrite(_ entries: [String: DraftEntry]) {
        pendingWriteWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.writeToDisk(entries)
        }
        pendingWriteWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
}

private struct DraftEntry: Codable {
    let text: String
    let updatedAt: Date
}
