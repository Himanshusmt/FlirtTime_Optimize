//
//  MessageStatusManager.swift
//  FlirttimeNew
//

import Foundation
import Combine

@MainActor
final class MessageStatusManager: ObservableObject {

    static let shared = MessageStatusManager()

    // MARK: - Published State

    @Published private(set) var messageStatuses: [String: MessageDeliveryStatus] = [:]

    @Published private(set) var readTimestamps: [String: Date] = [:]

    // MARK: - Callbacks

    var onStatusChanged: ((String, MessageDeliveryStatus) -> Void)?
    var onMessageUpdated: ((ConversationMessage) -> Void)?

    // MARK: - Private Properties

    private var messageRepository: MessageRepositoryAsync?
    private let statusQueue = DispatchQueue(label: "com.onevibe.messagestatus", qos: .userInitiated)

    // MARK: - Socket Event Names — https://socket.onevibe.walit.in/console

    enum StatusSocketEvent: String {
        case markConversationMessagesSeen = "chat:message:seen" // NEW — OLD: mark-conversation-messages-seen
        case markConversationMessagesSeenAck = "chat:message:seen:ack" // NEW — OLD: mark-conversation-messages-seen-ack
        case conversationMessageStatusUpdate = "chat:message:status" // NEW — OLD: conversation-message-status-update
    }

    // MARK: - Callback Types

    /// Called when message status updates are received (for updating UI indicators)
    var onMessagesStatusUpdated: ((String, [String], String, String) -> Void)?

    /// Called when mark-seen-ack is received (confirmation that messages were marked as seen)
    var onMarkSeenAcknowledged: ((String, Int) -> Void)?

    // MARK: - Initialization

    private init() {
        setupSocketListeners()
    }

    func configure(messageRepository: MessageRepositoryAsync) {
        self.messageRepository = messageRepository
    }

    // MARK: - Socket Setup

    private func setupSocketListeners() {
        // Socket listeners for backend-implemented events can be added here when needed
        AppLogger.debug("MessageStatusManager: Socket listeners registered")
    }

    // MARK: - Public Methods

    /// Get status for a message
    func status(for messageId: String) -> MessageDeliveryStatus {
        return messageStatuses[messageId] ?? .unknown
    }

    /// Update status for a message locally
    func updateStatus(_ messageId: String, status: MessageDeliveryStatus) {
        messageStatuses[messageId] = status
        onStatusChanged?(messageId, status)

        // Persist to database
        persistStatus(messageId: messageId, status: status)
    }

    func cacheStatus(_ messageId: String, status: MessageDeliveryStatus) {
        let current = messageStatuses[messageId] ?? .unknown
        if status > current {
            messageStatuses[messageId] = status
        }
    }

    /// Clear all cached statuses (on logout)
    func clearAllStatuses() {
        messageStatuses.removeAll()
        readTimestamps.removeAll()
        AppLogger.debug("MessageStatusManager: Cleared all statuses")
    }

    // MARK: - Persistence

    private func persistStatus(messageId: String, status: MessageDeliveryStatus) {
        guard let repository = messageRepository else { return }

        Task {
            do {
                try await repository.updateMessageStatus(id: messageId, status: status.rawValue)
                AppLogger.debug("MessageStatusManager: Persisted status for \(messageId)")
            } catch {
                AppLogger.debug("MessageStatusManager: Failed to persist status: \(error)")
            }
        }
    }
}

// MARK: - ConversationMessage Extension for Status Updates

extension ConversationMessage {

    /// Create an updated message with new status
    func withStatus(_ newStatus: MessageDeliveryStatus) -> ConversationMessage {
        guard let encoded = try? JSONEncoder().encode(self),
              var dict = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] else {
            return self
        }

        dict["status"] = newStatus.rawValue

        let iso = ISO8601DateFormatter()
        switch newStatus {
        case .sent:
            if dict["sentAt"] == nil { dict["sentAt"] = iso.string(from: Date()) }
        case .delivered:
            if dict["deliveredAt"] == nil { dict["deliveredAt"] = iso.string(from: Date()) }
            // Server vocabulary often uses "seen"; keep "delivered" for this case
        case .read:
            // Persist as "seen" so it matches socket/API vocabulary and FRC reloads
            dict["status"] = "seen"
            if dict["deliveredAt"] == nil { dict["deliveredAt"] = iso.string(from: Date()) }
            if dict["seenAt"] == nil { dict["seenAt"] = iso.string(from: Date()) }
        default:
            break
        }

        guard let updated = try? JSONSerialization.data(withJSONObject: dict),
              let result = try? JSONDecoder().decode(ConversationMessage.self, from: updated) else {
            return self
        }
        return result
    }
}
