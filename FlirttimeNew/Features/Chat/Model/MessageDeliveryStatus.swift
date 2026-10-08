//
//  MessageDeliveryStatus.swift
//  FlirttimeNew
//

import Foundation
import SwiftUI
import Swinject

// MARK: - Message Delivery Status Enum

enum MessageDeliveryStatus: String, Codable, CaseIterable {
    case sending = "sending"
    case sent = "sent"
    case delivered = "delivered"
    case read = "read"
    case failed = "failed"
    case unknown = "unknown"

    // MARK: - Computed Properties

    var isTerminal: Bool {
        switch self {
        case .failed, .read:
            return true
        default:
            return false
        }
    }

    var isSent: Bool {
        switch self {
        case .sent, .delivered, .read:
            return true
        default:
            return false
        }
    }

    var sortOrder: Int {
        switch self {
        case .sending: return 0
        case .sent: return 1
        case .delivered: return 2
        case .read: return 3
        case .failed: return -1
        case .unknown: return -2
        }
    }

    // MARK: - Factory Methods
    static func from(
        status: String?,
        sentAt: String?,
        deliveredAt: String?,
        seenAt: String?
    ) -> MessageDeliveryStatus {
        if let status = status?.lowercased() {
            if status == "seen" { return .read }
            if let deliveryStatus = MessageDeliveryStatus(rawValue: status) {
                return deliveryStatus
            }
        }

        if let seenAt = seenAt, !seenAt.isEmpty {
            return .read
        }

        if let deliveredAt = deliveredAt, !deliveredAt.isEmpty {
            return .delivered
        }

        if let sentAt = sentAt, !sentAt.isEmpty {
            return .sent
        }

        return .unknown
    }

    static func from(_ status: String?) -> MessageDeliveryStatus {
        guard let status = status?.lowercased() else { return .unknown }

        // Map "seen" to "read" (API returns "seen", we use "read" internally)
        if status == "seen" { return .read }

        return MessageDeliveryStatus(rawValue: status) ?? .unknown
    }
}

// MARK: - Status Comparison

extension MessageDeliveryStatus: Comparable {
    static func < (lhs: MessageDeliveryStatus, rhs: MessageDeliveryStatus) -> Bool {
        return lhs.sortOrder < rhs.sortOrder
    }

    static func <= (lhs: MessageDeliveryStatus, rhs: MessageDeliveryStatus) -> Bool {
        return lhs.sortOrder <= rhs.sortOrder
    }

    static func > (lhs: MessageDeliveryStatus, rhs: MessageDeliveryStatus) -> Bool {
        return lhs.sortOrder > rhs.sortOrder
    }

    static func >= (lhs: MessageDeliveryStatus, rhs: MessageDeliveryStatus) -> Bool {
        return lhs.sortOrder >= rhs.sortOrder
    }
}

// MARK: - ConversationMessage Extension

extension ConversationMessage {

    var deliveryStatus: MessageDeliveryStatus {
        let currentUserId = Container.sharedContainer.resolve(SessionManager.self)?.user?.userId ?? ""

        let isFromSelf = sender?.id == currentUserId || senderId == currentUserId

        if isFromSelf {
            return getOtherUserStatus(currentUserId: currentUserId)
        } else {
            return .unknown
        }
    }

    private func getOtherUserStatus(currentUserId: String) -> MessageDeliveryStatus {
        let topLevelStatus = MessageDeliveryStatus.from(
            status: status,
            sentAt: sentAt,
            deliveredAt: deliveredAt,
            seenAt: seenAt
        )

        guard let statuses = statuses, !statuses.isEmpty else {
            return topLevelStatus
        }

        let otherStatuses = statuses.filter { $0.userId != currentUserId }
        let bestFromArray = otherStatuses
            .map { MessageDeliveryStatus.from($0.status) }
            .max() ?? .unknown


        return max(bestFromArray, topLevelStatus)
    }

    func isSentByCurrentUser(_ currentUserId: String) -> Bool {
        return sender?.id == currentUserId || senderId == currentUserId
    }

    func statusForUser(_ userId: String) -> MessageDeliveryStatus? {
        guard let statuses = statuses else { return nil }
        let userStatus = statuses.first { $0.userId == userId }
        return userStatus.map { MessageDeliveryStatus.from($0.status) }
    }

    var hasBeenRead: Bool {
        guard let statuses = statuses else { return false }
        return statuses.contains { $0.status.lowercased() == "seen" }
    }

    var hasBeenDelivered: Bool {
        guard let statuses = statuses else { return false }
        return statuses.contains {
            let s = $0.status.lowercased()
            return s == "delivered" || s == "seen"
        }
    }
}

// MARK: - Status View Component

struct MessageStatusIndicator: View {

    let status: MessageDeliveryStatus
    var size: CGFloat = 12

    var body: some View {
        switch status {
        case .sending:
            SwiftUI.Image(systemName: "clock")
                .font(.chat(.regular, size: size))
                .foregroundColor(.chatPrimary)

        case .sent:
            SwiftUI.Image(systemName: "checkmark")
                .font(.chat(.medium, size: size - 2))
                .foregroundColor(.gray.opacity(0.8))

        case .delivered:
            doubleTicksImage
                .foregroundColor(.gray.opacity(0.8))

        case .read:
            doubleTicksImage
                .foregroundColor(.chatPrimary)

        case .failed:
            SwiftUI.Image(systemName: "exclamationmark.circle.fill")
                .font(.chat(.semibold, size: size))
                .foregroundColor(.red)

        case .unknown:
            Color.clear.frame(width: 0, height: 0)
        }
    }

    // MARK: - Tick Components

    private var doubleTicksImage: some View {
        if let _ = UIImage(named: ChatAssets.tickDelivered) {
            return SwiftUI.Image(ChatAssets.tickDelivered)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size + 4, height: size)
                .eraseToAnyView()
        } else {
            return ZStack {
                SwiftUI.Image(systemName: "checkmark")
                    .font(.chat(.medium, size: size - 3))
                    .offset(x: -2, y: 0)
                SwiftUI.Image(systemName: "checkmark")
                    .font(.chat(.medium, size: size - 3))
                    .offset(x: 2, y: 0)
            }
            .frame(width: size + 6, height: size)
            .eraseToAnyView()
        }
    }
}

// MARK: - View Extension for Type Erasure

extension View {
    func eraseToAnyView() -> AnyView {
        return AnyView(self)
    }
}

// MARK: - Legacy Support (if the tick asset doesn't exist)

struct LegacyMessageStatusIndicator: View {

    let status: MessageDeliveryStatus
    var size: CGFloat = 10

    var body: some View {
        switch status {
        case .sending:
            SwiftUI.Image(systemName: "clock")
                .font(.chat(size: size))
                .foregroundColor(.chatPrimary)

        case .sent:
            SwiftUI.Image(systemName: "checkmark")
                .font(.chat(.medium, size: size))
                .foregroundColor(.gray)

        case .delivered:
            SwiftUI.Image(systemName: "checkmark.checkmark")
                .font(.chat(size: size - 2))
                .foregroundColor(.gray)

        case .read:
            SwiftUI.Image(systemName: "checkmark.checkmark")
                .font(.chat(size: size - 2))
                .foregroundColor(.blue)

        case .failed:
            SwiftUI.Image(systemName: "exclamationmark.circle.fill")
                .font(.chat(size: size))
                .foregroundColor(.red)

        case .unknown:
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 20) {
        MessageStatusIndicator(status: .sending)
        MessageStatusIndicator(status: .sent)
        MessageStatusIndicator(status: .delivered)
        MessageStatusIndicator(status: .read)
        MessageStatusIndicator(status: .failed)
    }
    .padding()
}
