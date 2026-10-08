//
//  ChatMockSeeder.swift
//  FlirttimeNew
//
//  Seeds dummy 1:1 conversations into the local chat database while the chat backend is not
//  configured (`CHAT_*` build settings empty). Payloads use the same JSON shape the chat API
//  returns and are decoded with the real models, so the list and detail screens behave as
//  they will against the live backend.
//

import Foundation

final class ChatMockSeeder {

    static let shared = ChatMockSeeder()

    static var isMockMode: Bool { !ChatConfig.isConfigured }

    private let seededKey = "flirttimeChatMockSeeded_v3"

    private init() {}

    func seedIfNeeded() {
        guard Self.isMockMode else { return }
        applyMockPresence()
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        let meId = currentUserId
        let conversations = Self.dummyConversations
        let rows = conversations.compactMap { row(for: $0, meId: meId) }
        let messageLists = conversations.map { messages(for: $0, meId: meId) }

        Task {
            do {
                let conversationRepository = ConversationRepository()
                let messageRepository = MessageRepository()
                try await conversationRepository.saveConversations(rows)
                for (conversation, list) in zip(conversations, messageLists) {
                    try await messageRepository.saveMessages(list, conversationId: conversation.id)
                }
                UserDefaults.standard.set(true, forKey: seededKey)
                AppLogger.debug("[ChatMock] seeded \(rows.count) conversations")
            } catch {
                AppLogger.debug("[ChatMock] seeding failed: \(error.localizedDescription)")
            }
        }
    }

    /// No presence socket in mock mode, so mark the dummy peers flagged `isOnline` as online.
    private func applyMockPresence() {
        let onlineIds = Self.dummyConversations.filter(\.isOnline).map(\.peerId)
        DispatchQueue.main.async {
            ChatListSocketService.shared.onlineUserIds.formUnion(onlineIds)
        }
    }

    /// Mock profile details for the empty-conversation card.
    static func profile(forPeerId peerId: String) -> ChatEmptyProfileCardView.Profile? {
        guard isMockMode, let conversation = dummyConversations.first(where: { $0.peerId == peerId }) else { return nil }
        return ChatEmptyProfileCardView.Profile(
            name: conversation.name,
            age: conversation.age,
            avatarURL: conversation.avatar,
            distanceMiles: conversation.distanceMiles,
            interests: conversation.interests
        )
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: seededKey)
    }

    /// Server-style copy of an optimistic message, as the send API would echo it back.
    static func sentCopy(of message: ConversationMessage) -> ConversationMessage {
        var copy = ConversationMessage(
            id: UUID().uuidString.lowercased(),
            conversationId: message.conversationId,
            channelId: message.channelId,
            sender: message.sender,
            type: message.type,
            messageType: message.messageType,
            content: message.content,
            media: message.media,
            thumbnail: message.thumbnail,
            replyToId: message.replyToId,
            isEdited: message.isEdited,
            statuses: message.statuses,
            myStatus: message.myStatus,
            status: "sent",
            metadata: message.metadata,
            createdAt: message.createdAt,
            updatedAt: message.updatedAt,
            sentAt: message.createdAt,
            senderId: message.senderId
        )
        copy.serverLocation = message.serverLocation
        return copy
    }

    // MARK: - Builders

    private var currentUserId: String {
        ChatAuthStore.shared.currentUserId
    }

    private func row(for conversation: DummyConversation, meId: String) -> ChatMessageRow? {
        let last = conversation.lines.last
        let lastAt = Self.timestamp(minutesAgo: conversation.lastMinutesAgo)
        var payload: [String: Any] = [
            "id": conversation.id,
            "type": "direct",
            "lastMessageAt": lastAt,
            "unreadCount": conversation.unreadCount,
            "peer": [
                "id": conversation.peerId,
                "username": conversation.username,
                "fullName": conversation.name,
                "profilePicture": conversation.avatar,
                "isVerified": conversation.isVerified
            ],
            "settings": [
                "isPinned": conversation.isPinned,
                "isMuted": false,
                "isArchived": false,
                "unreadCount": conversation.unreadCount
            ]
        ]
        if let last {
            payload["lastMessage"] = [
                "id": "\(conversation.id)-m\(conversation.lines.count - 1)",
                "messageType": "text",
                "contentPreview": last.text,
                "senderId": last.fromMe ? meId : conversation.peerId,
                "createdAt": lastAt,
                "status": last.fromMe ? "seen" : "delivered"
            ]
        }
        return decode(ChatMessageRow.self, from: payload)
    }

    private func messages(for conversation: DummyConversation, meId: String) -> [ConversationMessage] {
        let count = conversation.lines.count
        return conversation.lines.enumerated().compactMap { index, line in
            let minutesAgo = conversation.lastMinutesAgo + (count - 1 - index) * conversation.spacingMinutes
            let createdAt = Self.timestamp(minutesAgo: minutesAgo)
            let senderId = line.fromMe ? meId : conversation.peerId
            let isUnread = !line.fromMe && index >= count - conversation.unreadCount
            var payload: [String: Any] = [
                "id": "\(conversation.id)-m\(index)",
                "conversationId": conversation.id,
                "type": "text",
                "messageType": "text",
                "body": line.text,
                "senderId": senderId,
                "sender": [
                    "id": senderId,
                    "userName": line.fromMe ? "me" : conversation.username,
                    "fullName": line.fromMe ? "Me" : conversation.name,
                    "profilePicture": line.fromMe ? "" : conversation.avatar
                ],
                "status": line.fromMe ? "seen" : (isUnread ? "delivered" : "seen"),
                "createdAt": createdAt,
                "sentAt": createdAt
            ]
            if let replyIndex = line.replyTo, replyIndex < index {
                let original = conversation.lines[replyIndex]
                payload["replyToId"] = "\(conversation.id)-m\(replyIndex)"
                payload["replyTo"] = [
                    "id": "\(conversation.id)-m\(replyIndex)",
                    "body": original.text,
                    "type": "text",
                    "senderId": original.fromMe ? meId : conversation.peerId,
                    "sender": [
                        "id": original.fromMe ? meId : conversation.peerId,
                        "fullName": original.fromMe ? ChatStrings.chat_you.localizedString() : conversation.name
                    ]
                ]
            }
            return decode(ConversationMessage.self, from: payload)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: [String: Any]) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            AppLogger.debug("[ChatMock] decode \(type) failed: \(error)")
            return nil
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func timestamp(minutesAgo: Int) -> String {
        isoFormatter.string(from: Date().addingTimeInterval(-Double(minutesAgo) * 60))
    }
}

// MARK: - Dummy data

private struct DummyLine {
    let fromMe: Bool
    let text: String
    var replyTo: Int? = nil
}

private struct DummyConversation {
    let id: String
    let peerId: String
    let name: String
    let username: String
    let avatar: String
    var isVerified = false
    var isOnline = false
    var isPinned = false
    var unreadCount = 0
    /// Age of the newest message.
    let lastMinutesAgo: Int
    /// Gap between consecutive messages; large gaps produce date separators.
    let spacingMinutes: Int
    let lines: [DummyLine]
    var age: Int? = nil
    var distanceMiles: Int? = nil
    var interests: [String] = []
}

private extension ChatMockSeeder {

    static var dummyConversations: [DummyConversation] {
        [
            DummyConversation(
                id: "mock-conv-sophia",
                peerId: "mock-user-sophia",
                name: "Sophia Carter",
                username: "sophia.c",
                avatar: "https://randomuser.me/api/portraits/women/44.jpg",
                isVerified: true,
                isOnline: true,
                isPinned: true,
                unreadCount: 2,
                lastMinutesAgo: 3,
                spacingMinutes: 6,
                lines: [
                    DummyLine(fromMe: false, text: "Hey! I saw we matched 😊"),
                    DummyLine(fromMe: true, text: "Hi Sophia! Yes, your travel photos are amazing"),
                    DummyLine(fromMe: false, text: "Thank you! That one was from Goa last winter"),
                    DummyLine(fromMe: true, text: "I've been planning a Goa trip forever"),
                    DummyLine(fromMe: false, text: "You should go in December, the weather is perfect"),
                    DummyLine(fromMe: true, text: "Noted 📝 Any café recommendations?", replyTo: 4),
                    DummyLine(fromMe: false, text: "So many! Let me make you a list"),
                    DummyLine(fromMe: true, text: "That would be awesome"),
                    DummyLine(fromMe: false, text: "Also, are you free this weekend?"),
                    DummyLine(fromMe: false, text: "There's a live music night near my place 🎶")
                ]
            ),
            DummyConversation(
                id: "mock-conv-aarav",
                peerId: "mock-user-aarav",
                name: "Aarav Mehta",
                username: "aarav.m",
                avatar: "https://randomuser.me/api/portraits/men/32.jpg",
                unreadCount: 1,
                lastMinutesAgo: 45,
                spacingMinutes: 20,
                lines: [
                    DummyLine(fromMe: true, text: "Hey Aarav, how was the trek?"),
                    DummyLine(fromMe: false, text: "It was incredible! Sunrise at the top was unreal"),
                    DummyLine(fromMe: true, text: "Send pics!!"),
                    DummyLine(fromMe: false, text: "Will do once I'm back home"),
                    DummyLine(fromMe: true, text: "Which trail did you take?"),
                    DummyLine(fromMe: false, text: "Kedarkantha, the winter route", replyTo: 4),
                    DummyLine(fromMe: true, text: "Adding it to my bucket list"),
                    DummyLine(fromMe: false, text: "We should plan one together sometime")
                ]
            ),
            DummyConversation(
                id: "mock-conv-emma",
                peerId: "mock-user-emma",
                name: "Emma Wilson",
                username: "emma.w",
                avatar: "https://randomuser.me/api/portraits/women/68.jpg",
                isVerified: true,
                isOnline: true,
                lastMinutesAgo: 180,
                spacingMinutes: 35,
                lines: [
                    DummyLine(fromMe: false, text: "Good morning ☀️"),
                    DummyLine(fromMe: true, text: "Morning Emma! Coffee already?"),
                    DummyLine(fromMe: false, text: "Second cup 😅"),
                    DummyLine(fromMe: true, text: "Respect. What are you up to today?"),
                    DummyLine(fromMe: false, text: "Painting class in the evening"),
                    DummyLine(fromMe: true, text: "That sounds fun, what are you painting?"),
                    DummyLine(fromMe: false, text: "Watercolour landscapes, still a beginner though"),
                    DummyLine(fromMe: true, text: "I'd love to see it when it's done"),
                    DummyLine(fromMe: false, text: "Deal, but no judging!"),
                    DummyLine(fromMe: true, text: "Promise 🤞")
                ]
            ),
            DummyConversation(
                id: "mock-conv-riya",
                peerId: "mock-user-riya",
                name: "Riya Sharma",
                username: "riya.s",
                avatar: "https://randomuser.me/api/portraits/women/12.jpg",
                lastMinutesAgo: 60 * 26,
                spacingMinutes: 60 * 4,
                lines: [
                    DummyLine(fromMe: true, text: "Hi Riya! Loved your bio 😄"),
                    DummyLine(fromMe: false, text: "Haha thanks! Which part?"),
                    DummyLine(fromMe: true, text: "\"Will travel for street food\" — same here"),
                    DummyLine(fromMe: false, text: "Finally someone who gets it 🍜"),
                    DummyLine(fromMe: true, text: "Best pani puri you've ever had?"),
                    DummyLine(fromMe: false, text: "Indore, Sarafa Bazaar. No contest", replyTo: 4),
                    DummyLine(fromMe: true, text: "I live in Indore!"),
                    DummyLine(fromMe: false, text: "No way, then you owe me a food tour"),
                    DummyLine(fromMe: true, text: "Challenge accepted")
                ]
            ),
            DummyConversation(
                id: "mock-conv-kabir",
                peerId: "mock-user-kabir",
                name: "Kabir Singh",
                username: "kabir.s",
                avatar: "https://randomuser.me/api/portraits/men/75.jpg",
                lastMinutesAgo: 60 * 24 * 3,
                spacingMinutes: 60 * 6,
                lines: [
                    DummyLine(fromMe: false, text: "Hey, are you into football?"),
                    DummyLine(fromMe: true, text: "Big time! You?"),
                    DummyLine(fromMe: false, text: "Sunday league every week ⚽"),
                    DummyLine(fromMe: true, text: "Which position?"),
                    DummyLine(fromMe: false, text: "Midfield mostly"),
                    DummyLine(fromMe: true, text: "Nice, I'm a decent goalkeeper"),
                    DummyLine(fromMe: false, text: "We need one! Join us this Sunday?"),
                    DummyLine(fromMe: true, text: "Count me in 🙌")
                ]
            ),
            DummyConversation(
                id: "mock-conv-cindy",
                peerId: "mock-user-cindy",
                name: "Cindy M",
                username: "cindy.m",
                avatar: "https://randomuser.me/api/portraits/women/26.jpg",
                isOnline: true,
                lastMinutesAgo: 1,
                spacingMinutes: 1,
                lines: [],
                age: 18,
                distanceMiles: 14,
                interests: ["Travel", "Music", "Movies", "Coffee"]
            )
        ]
    }
}
