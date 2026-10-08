//
//  OutgoingAckPersistenceQueue.swift
//  FlirttimeNew
//

import Foundation

final class OutgoingAckPersistenceQueue {

    struct Metrics {
        var enqueued: Int = 0
        var succeeded: Int = 0
        var failedAttempts: Int = 0
        var dropped: Int = 0
        var queueDepth: Int = 0
    }

    static let metricsDidChangeNotification = Notification.Name("OutgoingAckPersistenceQueueMetricsDidChange")

    static let shared = OutgoingAckPersistenceQueue()

    private struct QueueEntry: Codable {
        let key: String
        var message: ConversationMessage
        var attempt: Int
        var nextRetryAt: Date
        let enqueuedAt: Date
    }

    private let queue = DispatchQueue(label: "com.yandexgram.outgoingAckPersistence", qos: .utility)
    private var entries: [String: QueueEntry] = [:]
    private var processingKey: String?
    private var scheduledRetryWorkItem: DispatchWorkItem?
    private var worker: ((ConversationMessage) async -> Bool)?
    private var metrics = Metrics()

    private let maxAttempts = 8
    private let maxBackoffSeconds: TimeInterval = 300
    private let maxQueueSize = 200

    private let queueFileURL: URL = {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FlirtTimeChat", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("outgoing_ack_persistence_queue.json")
    }()

    private init() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.entries = self.loadEntriesFromDisk()
            self.metrics.queueDepth = self.entries.count
            self.postMetricsUpdate()
        }
    }

    func configure(worker: @escaping (ConversationMessage) async -> Bool) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.worker = worker
            self.processIfPossible()
        }
    }

    func enqueue(message: ConversationMessage, key: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if self.entries.count >= self.maxQueueSize && self.entries[key] == nil {
                AppLogger.debug("[AckQueue] dropping entry, queue at capacity \(self.maxQueueSize)")
                return
            }

            if self.entries[key] != nil {
                self.entries[key]?.message = message
                self.entries[key]?.nextRetryAt = Date()
            } else {
                self.entries[key] = QueueEntry(
                    key: key,
                    message: message,
                    attempt: 0,
                    nextRetryAt: Date(),
                    enqueuedAt: Date()
                )
            }

            self.metrics.enqueued += 1
            self.metrics.queueDepth = self.entries.count
            self.postMetricsUpdate()
            self.persistEntriesToDisk()
            self.processIfPossible()
        }
    }

    func clearAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.entries.removeAll()
            self.metrics.queueDepth = 0
            self.postMetricsUpdate()
            self.persistEntriesToDisk()
            self.scheduledRetryWorkItem?.cancel()
            self.scheduledRetryWorkItem = nil
            self.processingKey = nil
        }
    }

    private func processIfPossible() {
        guard processingKey == nil, let worker = worker else { return }

        guard let dueEntry = entries.values
            .filter({ $0.nextRetryAt <= Date() })
            .min(by: { $0.nextRetryAt < $1.nextRetryAt }) else {
            scheduleNextWakeup()
            return
        }

        processingKey = dueEntry.key
        let message = dueEntry.message

        Task {
            let success = await worker(message)
            self.queue.async { [weak self] in
                guard let self = self else { return }

                if var entry = self.entries[dueEntry.key] {
                    if success {
                        self.entries.removeValue(forKey: dueEntry.key)
                        self.metrics.succeeded += 1
                    } else {
                        entry.attempt += 1
                        self.metrics.failedAttempts += 1
                        if entry.attempt >= self.maxAttempts {
                            self.entries.removeValue(forKey: dueEntry.key)
                            self.metrics.dropped += 1
                            AppLogger.debug("[AckQueue] dropping after \(self.maxAttempts) attempts key=\(entry.key)")
                        } else {
                            let delay = self.backoffDelay(forAttempt: entry.attempt)
                            entry.nextRetryAt = Date().addingTimeInterval(delay)
                            self.entries[dueEntry.key] = entry
                            AppLogger.debug("[AckQueue] retry key=\(entry.key) attempt=\(entry.attempt) delay=\(Int(delay))s")
                        }
                    }
                }

                self.metrics.queueDepth = self.entries.count
                self.postMetricsUpdate()
                self.persistEntriesToDisk()
                self.processingKey = nil
                self.processIfPossible()
            }
        }
    }

    private func scheduleNextWakeup() {
        scheduledRetryWorkItem?.cancel()
        guard let earliestRetryDate = entries.values.map(\.nextRetryAt).min() else { return }

        let delay = max(0, earliestRetryDate.timeIntervalSinceNow)
        let workItem = DispatchWorkItem { [weak self] in
            self?.processIfPossible()
        }
        scheduledRetryWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let raw = pow(2.0, Double(max(0, attempt - 1)))
        let jittered = raw * Double.random(in: 0.85...1.15)
        return min(maxBackoffSeconds, jittered)
    }

    private func postMetricsUpdate() {
        let snapshot = metrics
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: OutgoingAckPersistenceQueue.metricsDidChangeNotification,
                object: nil,
                userInfo: [
                    "enqueued": snapshot.enqueued,
                    "succeeded": snapshot.succeeded,
                    "failedAttempts": snapshot.failedAttempts,
                    "dropped": snapshot.dropped,
                    "queueDepth": snapshot.queueDepth
                ]
            )
        }
    }

    private func loadEntriesFromDisk() -> [String: QueueEntry] {
        guard let data = try? Data(contentsOf: queueFileURL) else { return [:] }
        guard let array = try? JSONDecoder().decode([QueueEntry].self, from: data) else { return [:] }
        var dict = Dictionary<String, QueueEntry>(minimumCapacity: array.count)
        for entry in array {
            dict[entry.key] = entry
        }
        return dict
    }

    private func persistEntriesToDisk() {
        let array = Array(entries.values)
        guard let data = try? JSONEncoder().encode(array) else { return }
        try? data.write(to: queueFileURL, options: .atomic)
    }
}
