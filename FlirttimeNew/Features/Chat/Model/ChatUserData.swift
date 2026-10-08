//
//  ChatUserData.swift
//  FlirttimeNew
//
//  Created by Devesh Pareek on 28/03/24.
//

import Foundation


struct ChatMessageUserData: DataClass, Codable {
    let count: Int?
    var rows: [ChatMessageRow]?
    var serverTime: String?
    var deletedConversationIds: [String]?
    var pinnedConversationIds: [String]?
    var unpinnedConversationIds: [String]?
    var archivedConversationIds: [String]?
    var unarchivedConversationIds: [String]?
    var mutedConversationIds: [String]?
    var unmutedConversationIds: [String]?
    var blockedConversationIds: [String]?
    var unblockedConversationIds: [String]?
    var limit: Int?
    var nextCursor: String?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode count
        do {
            self.count = try container.decodeIfPresent(Int.self, forKey: .count)
        } catch {
            self.count = nil
        }

        self.limit = try? container.decodeIfPresent(Int.self, forKey: .limit)
        self.nextCursor = try? container.decodeIfPresent(String.self, forKey: .nextCursor)
        
        // Try to decode rows
        do {
            self.rows = try container.decodeIfPresent([ChatMessageRow].self, forKey: .rows)
        } catch {
            AppLogger.debug("ChatMessageUserData: failed to decode rows — \(error)")
            self.rows = []
        }

        // Try to decode delta fields
        do {
            self.serverTime = try container.decodeIfPresent(String.self, forKey: .serverTime)
            self.deletedConversationIds = try container.decodeIfPresent([String].self, forKey: .deletedConversationIds)
            self.pinnedConversationIds = try container.decodeIfPresent([String].self, forKey: .pinnedConversationIds)
            self.unpinnedConversationIds = try container.decodeIfPresent([String].self, forKey: .unpinnedConversationIds)
            self.archivedConversationIds = try container.decodeIfPresent([String].self, forKey: .archivedConversationIds)
            self.unarchivedConversationIds = try container.decodeIfPresent([String].self, forKey: .unarchivedConversationIds)
            self.mutedConversationIds = try container.decodeIfPresent([String].self, forKey: .mutedConversationIds)
            self.unmutedConversationIds = try container.decodeIfPresent([String].self, forKey: .unmutedConversationIds)
            self.blockedConversationIds = try container.decodeIfPresent([String].self, forKey: .blockedConversationIds)
            self.unblockedConversationIds = try container.decodeIfPresent([String].self, forKey: .unblockedConversationIds)
        } catch {
            self.serverTime = nil
            self.deletedConversationIds = nil
            self.pinnedConversationIds = nil
            self.unpinnedConversationIds = nil
            self.archivedConversationIds = nil
            self.unarchivedConversationIds = nil
            self.mutedConversationIds = nil
            self.unmutedConversationIds = nil
            self.blockedConversationIds = nil
            self.unblockedConversationIds = nil
        }
        
    }

    private enum CodingKeys: String, CodingKey {
        case count
        case rows
        case serverTime
        case deletedConversationIds
        case pinnedConversationIds
        case unpinnedConversationIds
        case archivedConversationIds
        case unarchivedConversationIds
        case mutedConversationIds
        case unmutedConversationIds
        case blockedConversationIds
        case unblockedConversationIds
        case limit
        case nextCursor
    }
}

/// Live group call attached to a conversation row (`GET chat/conversations`).
struct ConversationActiveCall: DataClass, Codable, Equatable {
    var id: String?
    var callId: String?
    var type: String?
    var status: String?
    var channelName: String?

    var resolvedCallId: String {
        let a = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { return a }
        return (callId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isLive: Bool {
        let s = (status ?? "ongoing").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return !resolvedCallId.isEmpty }
        return s == "ongoing" || s == "ringing" || s == "active" || s == "in_progress" || s == "in-progress"
    }

    var isVideo: Bool {
        (type ?? "").lowercased().contains("video")
    }

    private enum CodingKeys: String, CodingKey {
        case id, callId, type, status, channelName
        case call_id, callType, call_type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        callId = try c.decodeIfPresent(String.self, forKey: .callId)
            ?? c.decodeIfPresent(String.self, forKey: .call_id)
        type = try c.decodeIfPresent(String.self, forKey: .type)
            ?? c.decodeIfPresent(String.self, forKey: .callType)
            ?? c.decodeIfPresent(String.self, forKey: .call_type)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        channelName = try c.decodeIfPresent(String.self, forKey: .channelName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(callId, forKey: .callId)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(channelName, forKey: .channelName)
    }
}

struct ChatMessageRow: DataClass, Codable {
    // Core conversation properties from new API
    var id: String?
    var title: String?
    var type: String?
    var lastMessageAt: String?
    var avatar: String?
    var participants: [Participant]?
    var unreadCount: Int?
    var lastMessage: ConversationLastMessage?
    var settings: ConversationSettings?
    var isGroupParticipant: Bool?
    var participantsCount: Int?
    var inviteCode: String?
    var inviteLink: String?
    var isInviteLinkEnabled: Bool?
    var deletedAt: String?
    /// NEW list/detail API — `admin` | `member`; null means left / not a member
    var myRole: String?
    /// NEW list API peer (direct chats) — synthesized into `participants` on decode.
    var peer: ConversationPeer?
    /// Direct-chat presence from GET conversations/{id} (nested or top-level online/lastSeen).
    var onlineStatus: OnlineStatus?
    /// Ongoing group call from list API — drives chat-list “Group call ongoing” + Join banner.
    var activeCall: ConversationActiveCall?
    /// True when the JSON included an active-call key (even if null) — used to clear ended calls.
    var activeCallKeyPresent: Bool = false

    // Default initializer
    init() {
        self.id = nil
        self.title = nil
        self.type = nil
        self.lastMessageAt = nil
        self.avatar = nil
        self.participants = nil
        self.unreadCount = nil
        self.lastMessage = nil
        self.settings = nil
        self.isGroupParticipant = nil
        self.participantsCount = nil
        self.inviteCode = nil
        self.inviteLink = nil
        self.isInviteLinkEnabled = nil
        self.deletedAt = nil
        self.myRole = nil
        self.peer = nil
        self.onlineStatus = nil
        self.activeCall = nil
        self.activeCallKeyPresent = false
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, type, lastMessageAt, avatar, avatarPath
        case participants, members, unreadCount, unread, unread_count, lastMessage, settings
        case isGroupParticipant, participantsCount
        case inviteCode, inviteLink, isInviteLinkEnabled, deletedAt
        case peer, myRole, onlineStatus
        case online, lastSeen, lastSeenAt, status
        case lastMessagePreview, lastMessageType, lastMessageSenderId
        case lastMessageReceiptStatus, createdAt
        case activeCall, ongoingCall, currentCall, active_call
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        lastMessageAt = try container.decodeIfPresent(String.self, forKey: .lastMessageAt)
        // Empty groups often have null lastMessageAt — fall back to createdAt so inbox sorts them to top.
        if lastMessageAt == nil || lastMessageAt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lastMessageAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        }
        // NEW: avatarPath; OLD: avatar
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
            ?? container.decodeIfPresent(String.self, forKey: .avatarPath)
        participants = try container.decodeIfPresent([Participant].self, forKey: .participants)
        // NEW detail/list: flat `members` (id/username/fullName/profilePicture/role)
        if participants == nil || participants?.isEmpty == true {
            participants = try container.decodeIfPresent([Participant].self, forKey: .members)
        }
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount)
            ?? container.decodeIfPresent(Int.self, forKey: .unread)
            ?? container.decodeIfPresent(Int.self, forKey: .unread_count)
        lastMessage = try container.decodeIfPresent(ConversationLastMessage.self, forKey: .lastMessage)
        settings = try container.decodeIfPresent(ConversationSettings.self, forKey: .settings)
        isGroupParticipant = try container.decodeIfPresent(Bool.self, forKey: .isGroupParticipant)
        participantsCount = try container.decodeIfPresent(Int.self, forKey: .participantsCount)
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode)
        inviteLink = try container.decodeIfPresent(String.self, forKey: .inviteLink)
        isInviteLinkEnabled = try container.decodeIfPresent(Bool.self, forKey: .isInviteLinkEnabled)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        peer = try container.decodeIfPresent(ConversationPeer.self, forKey: .peer)
        myRole = try container.decodeIfPresent(String.self, forKey: .myRole)
        onlineStatus = try container.decodeIfPresent(OnlineStatus.self, forKey: .onlineStatus)
        let activeCallKeys: [CodingKeys] = [.activeCall, .ongoingCall, .currentCall, .active_call]
        activeCallKeyPresent = activeCallKeys.contains { container.contains($0) }
        activeCall = try container.decodeIfPresent(ConversationActiveCall.self, forKey: .activeCall)
            ?? container.decodeIfPresent(ConversationActiveCall.self, forKey: .ongoingCall)
            ?? container.decodeIfPresent(ConversationActiveCall.self, forKey: .currentCall)
            ?? container.decodeIfPresent(ConversationActiveCall.self, forKey: .active_call)
        // Detail API may also send flat `online` / `lastSeen` on the conversation.
        if onlineStatus == nil,
           container.contains(.online) || container.contains(.lastSeen) || container.contains(.lastSeenAt) {
            let flatOnline = try container.decodeIfPresent(Bool.self, forKey: .online)
            let flatLastSeen = try container.decodeIfPresent(String.self, forKey: .lastSeen)
                ?? container.decodeIfPresent(String.self, forKey: .lastSeenAt)
            let flatStatus = try container.decodeIfPresent(String.self, forKey: .status)
            onlineStatus = OnlineStatus(
                isOnline: flatOnline,
                lastSeen: flatLastSeen,
                status: flatStatus
            )
        }

        // NEW FE: membership via `myRole` (null = left). Inbox groups without the flag are members.
        if let role = myRole?.trimmingCharacters(in: .whitespacesAndNewlines), !role.isEmpty {
            isGroupParticipant = true
        } else if container.contains(.myRole) {
            // Explicit null myRole → not a participant
            isGroupParticipant = false
        } else if isGroupParticipant == nil, type?.lowercased() == "group" {
            isGroupParticipant = deletedAt == nil
        }

        // NEW list payload: flatten peer → participants so getUserDetails()/UI keep working
        if (participants == nil || participants?.isEmpty == true), let peer {
            participants = [peer.asParticipant()]
            if (avatar ?? "").isEmpty {
                avatar = peer.profilePicture
            }
            if (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let name = (peer.fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                title = name.isEmpty ? peer.username : name
            }
        }

        // NEW list payload: lastMessagePreview / type / sender / receipt → lastMessage.
        // Do not synthesize from lastMessageAt alone — empty/new chats often only have a
        // sort timestamp (createdAt/lastMessageAt) and must not show a fake last message + tick.
        if lastMessage == nil {
            let preview = try container.decodeIfPresent(String.self, forKey: .lastMessagePreview)
            let messageType = try container.decodeIfPresent(String.self, forKey: .lastMessageType)
            let senderId = try container.decodeIfPresent(String.self, forKey: .lastMessageSenderId)
            let receipt = try container.decodeIfPresent(String.self, forKey: .lastMessageReceiptStatus)
            let hasRealMessageEvidence =
                !(preview ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !(messageType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !(senderId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !(receipt ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasRealMessageEvidence {
                lastMessage = ConversationLastMessage(
                    id: nil,
                    messageType: messageType,
                    contentPreview: preview,
                    senderId: senderId,
                    createdAt: lastMessageAt,
                    status: receipt
                )
            }
        }

        // NEW: unread lives under settings
        if unreadCount == nil {
            unreadCount = settings?.unreadCount
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(lastMessageAt, forKey: .lastMessageAt)
        try container.encodeIfPresent(avatar, forKey: .avatar)
        try container.encodeIfPresent(participants, forKey: .participants)
        try container.encodeIfPresent(unreadCount, forKey: .unreadCount)
        try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try container.encodeIfPresent(settings, forKey: .settings)
        try container.encodeIfPresent(isGroupParticipant, forKey: .isGroupParticipant)
        try container.encodeIfPresent(participantsCount, forKey: .participantsCount)
        try container.encodeIfPresent(inviteCode, forKey: .inviteCode)
        try container.encodeIfPresent(inviteLink, forKey: .inviteLink)
        try container.encodeIfPresent(isInviteLinkEnabled, forKey: .isInviteLinkEnabled)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeIfPresent(peer, forKey: .peer)
        try container.encodeIfPresent(onlineStatus, forKey: .onlineStatus)
        try container.encodeIfPresent(activeCall, forKey: .activeCall)
    }
    
    // Helper computed properties
    var otherParticipant: Participant? {
        guard type == "direct" else { return nil }
        let currentUserId = getCurrentUserId()

        // If we have a valid current user ID, filter normally
        if !currentUserId.isEmpty {
            return participants?.first(where: { $0.userId != currentUserId })
        }

        if let participants = participants, participants.count == 2 {
            if let storedId = ChatAuthStore.shared.currentUser?.userId, !storedId.isEmpty {
                return participants.first(where: { $0.userId != storedId })
            }

            return participants.last
        }

        // NEW peer-only lists often have a single "other" participant
        if let participants, participants.count == 1 {
            return participants.first
        }

        return participants?.first(where: { $0.userId != currentUserId })
    }
    
    var isGroup: Bool {
        return type?.lowercased() == "group"
    }

    /// Resolved membership for opening group chat (NEW API often omits `isGroupParticipant`).
    /// Inbox rows are treated as members; hide composer only after leave / soft-delete / explicit null `myRole`.
    var resolvedIsGroupParticipant: Bool {
        if !isGroup { return true }
        if deletedAt != nil { return false }
        if let role = myRole?.trimmingCharacters(in: .whitespacesAndNewlines), !role.isEmpty {
            return true
        }
        // Stale Core Data defaults `isGroupParticipant` to false when the field was missing —
        // do not hide the input for an active inbox group.
        return true
    }
    
    private func isCurrentUser(userId: String?) -> Bool {
        let currentUserId = getCurrentUserId()
        return userId == currentUserId
    }

    private func getCurrentUserId() -> String {
        let stored = ChatAuthStore.shared.currentUser?.userId ?? ""
        return stored.isEmpty ? "" : stored
    }
    
    var currentUserParticipant: Participant? {
        guard let participants = participants else { return nil }
        return participants.first(where: { isCurrentUser(userId: $0.userId) })
    }
    
    func getUserDetails() -> (userId: String?, userName: String?, fullName: String?, profilePicture: String?)? {
        if let participant = otherParticipant {
            if let userDetails = participant.user?.userDetails?.first {
                let raw = userDetails.profilePictureDetails?.filePath ?? userDetails.profilePicture
                return (
                    participant.userId,
                    userDetails.userName,
                    userDetails.fullName,
                    resolveAvatarURL(raw)
                )
            }

            if let profile = participant.userProfileData {
                return (
                    participant.userId,
                    profile.userName,
                    profile.fullName,
                    resolveAvatarURL(profile.profileImage)
                )
            }

            if let user = participant.user {
                return (
                    participant.userId ?? user.id,
                    user.username,
                    user.fullName,
                    resolveAvatarURL(user.profileImage)
                )
            }
        }

        // Direct fallback to NEW peer object
        if let peer {
            return (
                peer.id,
                peer.username,
                peer.fullName,
                resolveAvatarURL(peer.profilePicture)
            )
        }

        return nil
    }
    
    var isArchived: Bool { settings?.isArchived == true }

    func getArchiveStatus() -> Bool {
        return settings?.isArchived ?? false
    }

    // MARK: - Delivery status helpers

    var isLastMessageFromSelf: Bool {
        guard let lastMessage = lastMessage else { return false }
        if lastMessage.isSystemMessage { return false }
        guard let senderId = lastMessage.senderId else { return false }
        return senderId == getCurrentUserId()
    }

    var lastMessageDeliveryStatus: MessageDeliveryStatus {
        guard isLastMessageFromSelf, let statusStr = lastMessage?.status else { return .unknown }
        return MessageDeliveryStatus.from(statusStr)
    }
}

// MARK: - ConversationPeer (NEW chat/conversations list)
struct ConversationPeer: Codable {
    let id: String?
    let username: String?
    let fullName: String?
    let profilePicture: String?
    let isVerified: Bool?

    func asParticipant() -> Participant {
        let detail = UserDetail(
            userName: username,
            fullName: fullName,
            profilePicture: profilePicture,
            profilePictureDetails: profilePicture.map { ProfilePictureDetails(filePath: $0) }
        )
        let user = ParticipantUser(
            id: id,
            userId: id,
            userDetails: [detail],
            verified: isVerified,
            username: username,
            fullName: fullName,
            profileImage: profilePicture
        )
        return Participant(userId: id, isActive: true, user: user, isVerified: isVerified == true)
    }
}

// MARK: - ConversationLastMessage (New API format)
struct ConversationLastMessage: Codable {
    let id: String?
    let messageType: String?
    var contentPreview: String?
    let senderId: String?
    var createdAt: String?
    var status: String? = nil

    private enum CodingKeys: String, CodingKey {
        case id, messageType, contentPreview, content, body, senderId, createdAt, status
    }

    init(
        id: String? = nil,
        messageType: String? = nil,
        contentPreview: String? = nil,
        senderId: String? = nil,
        createdAt: String? = nil,
        status: String? = nil
    ) {
        self.id = id
        self.messageType = messageType
        self.contentPreview = contentPreview
        self.senderId = senderId
        self.createdAt = createdAt
        self.status = status
    }

    /// Group/channel system events must not show inbox delivery ticks.
    var isSystemMessage: Bool {
        (messageType ?? "").lowercased() == "system"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        messageType = try c.decodeIfPresent(String.self, forKey: .messageType)
        contentPreview = try c.decodeIfPresent(String.self, forKey: .contentPreview)
            ?? c.decodeIfPresent(String.self, forKey: .content)
            ?? c.decodeIfPresent(String.self, forKey: .body)
        senderId = try c.decodeIfPresent(String.self, forKey: .senderId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        status = try c.decodeIfPresent(String.self, forKey: .status)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(messageType, forKey: .messageType)
        try c.encodeIfPresent(contentPreview, forKey: .contentPreview)
        try c.encodeIfPresent(senderId, forKey: .senderId)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(status, forKey: .status)
    }
}

// MARK: - Participant
struct Participant: Codable {
    let id: String?
    let conversationId: String?
    let userId: String?
    let role: String?
    let joinedAt: String?
    let leftAt: String?
    var isActive: Bool?
    let createdAt: String?
    let updatedAt: String?
    let user: ParticipantUser?
    let userProfileData: ChatUserProfileData?
    /// NEW flat `members[].isVerified` (also mirrored onto `user.verified`)
    let isVerified: Bool

    /// Prefer flat member flag, then nested user / profile flags.
    var resolvedIsVerified: Bool {
        isVerified
            || user?.verified == true
            || userProfileData?.verified == true
    }

    init(
        id: String? = nil,
        conversationId: String? = nil,
        userId: String? = nil,
        role: String? = nil,
        joinedAt: String? = nil,
        leftAt: String? = nil,
        isActive: Bool? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        user: ParticipantUser? = nil,
        userProfileData: ChatUserProfileData? = nil,
        isVerified: Bool = false
    ) {
        self.id = id
        self.conversationId = conversationId
        self.userId = userId
        self.role = role
        self.joinedAt = joinedAt
        self.leftAt = leftAt
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.user = user
        self.userProfileData = userProfileData
        self.isVerified = isVerified || user?.verified == true || userProfileData?.verified == true
    }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationIdCamel = "conversationId"
        case conversationIdSnake = "conversation_id"
        case userIdCamel = "userId"
        case userIdSnake = "user_id"
        case role
        case joinedAtCamel = "joinedAt"
        case joinedAtSnake = "joined_at"
        case leftAtCamel = "leftAt"
        case leftAtSnake = "left_at"
        case isActiveCamel = "isActive"
        case isActiveSnake = "is_active"
        case createdAtCamel = "createdAt"
        case createdAtSnake = "created_at"
        case updatedAtCamel = "updatedAt"
        case updatedAtSnake = "updated_at"
        case user
        case userProfileData
        // NEW flat ConversationMember fields
        case username, userName, fullName, profilePicture, isVerified, verified
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        conversationId = try c.decodeIfPresent(String.self, forKey: .conversationIdCamel)
        ?? c.decodeIfPresent(String.self, forKey: .conversationIdSnake)
        // NEW members: `id` is the user id; OLD: separate userId
        userId = try c.decodeIfPresent(String.self, forKey: .userIdCamel)
        ?? c.decodeIfPresent(String.self, forKey: .userIdSnake)
        ?? id
        role = try c.decodeIfPresent(String.self, forKey: .role)
        joinedAt = try c.decodeIfPresent(String.self, forKey: .joinedAtCamel)
        ?? c.decodeIfPresent(String.self, forKey: .joinedAtSnake)
        leftAt = try c.decodeIfPresent(String.self, forKey: .leftAtCamel)
        ?? c.decodeIfPresent(String.self, forKey: .leftAtSnake)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActiveCamel)
        ?? c.decodeIfPresent(Bool.self, forKey: .isActiveSnake)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAtCamel)
        ?? c.decodeIfPresent(String.self, forKey: .createdAtSnake)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAtCamel)
        ?? c.decodeIfPresent(String.self, forKey: .updatedAtSnake)
        var decodedUser = try c.decodeIfPresent(ParticipantUser.self, forKey: .user)
        userProfileData = try c.decodeIfPresent(ChatUserProfileData.self, forKey: .userProfileData)

        let flatUserName = try c.decodeIfPresent(String.self, forKey: .username)
            ?? c.decodeIfPresent(String.self, forKey: .userName)
        let flatFullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        let flatPicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
        let flatVerified = try c.decodeIfPresent(Bool.self, forKey: .isVerified)
            ?? c.decodeIfPresent(Bool.self, forKey: .verified)

        // Synthesize / enrich nested user from flat NEW member payload
        if decodedUser == nil {
            if flatUserName != nil || flatFullName != nil || flatPicture != nil || userId != nil {
                let detail = UserDetail(
                    userName: flatUserName,
                    fullName: flatFullName,
                    profilePicture: flatPicture,
                    profilePictureDetails: flatPicture.map { ProfilePictureDetails(filePath: $0) }
                )
                decodedUser = ParticipantUser(
                    id: userId ?? id,
                    userId: userId ?? id,
                    userDetails: [detail],
                    verified: flatVerified,
                    username: flatUserName,
                    fullName: flatFullName,
                    profileImage: flatPicture
                )
            }
        } else if (decodedUser?.username == nil && decodedUser?.fullName == nil
                   && (decodedUser?.userDetails?.first?.userName == nil)
                   && (decodedUser?.userDetails?.first?.fullName == nil)),
                  (flatUserName != nil || flatFullName != nil) {
            // Nested `user` present but empty — fill from flat member fields
            let detail = UserDetail(
                userName: flatUserName,
                fullName: flatFullName,
                profilePicture: flatPicture ?? decodedUser?.profileImage,
                profilePictureDetails: (flatPicture ?? decodedUser?.profileImage).map { ProfilePictureDetails(filePath: $0) }
            )
            decodedUser = ParticipantUser(
                id: decodedUser?.id ?? userId ?? id,
                userId: decodedUser?.userId ?? userId ?? id,
                userDetails: [detail],
                verified: decodedUser?.verified ?? flatVerified,
                username: flatUserName,
                fullName: flatFullName,
                profileImage: flatPicture ?? decodedUser?.profileImage
            )
        }

        // Flat NEW member `isVerified` wins when nested user omitted it
        if let flatVerified, decodedUser?.verified == nil {
            decodedUser?.verified = flatVerified
        }
        user = decodedUser
        isVerified = flatVerified == true || decodedUser?.verified == true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id,             forKey: .id)
        try c.encodeIfPresent(conversationId, forKey: .conversationIdCamel)
        try c.encodeIfPresent(userId,         forKey: .userIdCamel)
        try c.encodeIfPresent(role,           forKey: .role)
        try c.encodeIfPresent(joinedAt,       forKey: .joinedAtCamel)
        try c.encodeIfPresent(leftAt,         forKey: .leftAtCamel)
        try c.encodeIfPresent(isActive,       forKey: .isActiveCamel)
        try c.encodeIfPresent(createdAt,      forKey: .createdAtCamel)
        try c.encodeIfPresent(updatedAt,      forKey: .updatedAtCamel)
        try c.encodeIfPresent(user,           forKey: .user)
        try c.encodeIfPresent(userProfileData, forKey: .userProfileData)
        if isVerified {
            try c.encode(true, forKey: .isVerified)
        }
    }
}

// MARK: - ParticipantUser
struct ParticipantUser: Codable {
    let id: String?
    var userDetails: [UserDetail]?
    var isOnline: Bool?
    var isPrivate: Bool?
    var verified: Bool?
    var isFollowing: Bool?
    var isBlock: Bool?
    var username: String?
    var fullName: String?
    var profileImage: String?
    var lastOnline: String?

    var userId: String?

    enum CodingKeys: String, CodingKey {
        case id, userId
        case userDetails, isOnline, isPrivate, verified, isVerified, isFollowing, isBlock
        case username, fullName, profileImage, lastOnline
    }

    init(
        id: String? = nil,
        userId: String? = nil,
        userDetails: [UserDetail]? = nil,
        isOnline: Bool? = nil,
        isPrivate: Bool? = nil,
        verified: Bool? = nil,
        isFollowing: Bool? = nil,
        isBlock: Bool? = nil,
        username: String? = nil,
        fullName: String? = nil,
        profileImage: String? = nil,
        lastOnline: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.userDetails = userDetails
        self.isOnline = isOnline
        self.isPrivate = isPrivate
        self.verified = verified
        self.isFollowing = isFollowing
        self.isBlock = isBlock
        self.username = username
        self.fullName = fullName
        self.profileImage = profileImage
        self.lastOnline = lastOnline
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try c.decodeIfPresent(String.self, forKey: .id)
        let decodedUserId = try c.decodeIfPresent(String.self, forKey: .userId)
        id = decodedId ?? decodedUserId
        userId = decodedUserId ?? decodedId
        isOnline = try c.decodeIfPresent(Bool.self, forKey: .isOnline)
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate)
        verified = try c.decodeIfPresent(Bool.self, forKey: .verified)
            ?? c.decodeIfPresent(Bool.self, forKey: .isVerified)
        isFollowing = try c.decodeIfPresent(Bool.self, forKey: .isFollowing)
        isBlock = try c.decodeIfPresent(Bool.self, forKey: .isBlock)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        profileImage = try c.decodeIfPresent(String.self, forKey: .profileImage)
        lastOnline = try c.decodeIfPresent(String.self, forKey: .lastOnline)

        let decoded = try c.decodeIfPresent([UserDetail].self, forKey: .userDetails)
        if let decoded, !decoded.isEmpty {
            userDetails = decoded
        } else if username != nil || fullName != nil || profileImage != nil {
            userDetails = [UserDetail(userName: username, fullName: fullName, profilePicture: profileImage, profilePictureDetails: nil)]
        } else {
            userDetails = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(userDetails, forKey: .userDetails)
        try c.encodeIfPresent(isOnline, forKey: .isOnline)
        try c.encodeIfPresent(isPrivate, forKey: .isPrivate)
        try c.encodeIfPresent(verified, forKey: .verified)
        if verified == true {
            try c.encode(true, forKey: .isVerified)
        }
        try c.encodeIfPresent(isFollowing, forKey: .isFollowing)
        try c.encodeIfPresent(isBlock, forKey: .isBlock)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(profileImage, forKey: .profileImage)
        try c.encodeIfPresent(lastOnline, forKey: .lastOnline)
    }
}

// MARK: - UserDetail
struct UserDetail: Codable {
    let userName: String?
    let fullName: String?
    let profilePicture: String?
    let profilePictureDetails: ProfilePictureDetails?

    enum CodingKeys: String, CodingKey {
        case userName, username, fullName, profilePicture, profilePictureDetails
    }

    init(
        userName: String? = nil,
        fullName: String? = nil,
        profilePicture: String? = nil,
        profilePictureDetails: ProfilePictureDetails? = nil
    ) {
        self.userName = userName
        self.fullName = fullName
        self.profilePicture = profilePicture
        self.profilePictureDetails = profilePictureDetails
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // NEW API uses `username`; OLD / Core Data uses `userName`
        userName = try c.decodeIfPresent(String.self, forKey: .userName)
            ?? c.decodeIfPresent(String.self, forKey: .username)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        profilePicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
        profilePictureDetails = try c.decodeIfPresent(ProfilePictureDetails.self, forKey: .profilePictureDetails)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(userName, forKey: .userName)
        try c.encodeIfPresent(fullName, forKey: .fullName)
        try c.encodeIfPresent(profilePicture, forKey: .profilePicture)
        try c.encodeIfPresent(profilePictureDetails, forKey: .profilePictureDetails)
    }
}

// MARK: - ConversationSettings
struct ConversationSettings: Codable {
    var isMuted: Bool?
    var isPinned: Bool?
    var isArchived: Bool?
    var isLocked: Bool?
    var isBlocked: Bool?
    var disappearingMessages: Int?
    var label: [String?]?
    var pinnedAt: String?
    // NEW chat/conversations settings fields
    var unreadCount: Int?
    var labelText: String?
    var labelColor: String?
    var lastReadMessageId: String?
    var lastDeliveredMessageId: String?

    init(
        isMuted: Bool? = nil,
        isPinned: Bool? = nil,
        isArchived: Bool? = nil,
        isLocked: Bool? = nil,
        isBlocked: Bool? = nil,
        disappearingMessages: Int? = nil,
        label: [String?]? = nil,
        pinnedAt: String? = nil,
        unreadCount: Int? = nil,
        labelText: String? = nil,
        labelColor: String? = nil,
        lastReadMessageId: String? = nil,
        lastDeliveredMessageId: String? = nil
    ) {
        self.isMuted = isMuted
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.isLocked = isLocked
        self.isBlocked = isBlocked
        self.disappearingMessages = disappearingMessages
        self.label = label
        self.pinnedAt = pinnedAt
        self.unreadCount = unreadCount
        self.labelText = labelText
        self.labelColor = labelColor
        self.lastReadMessageId = lastReadMessageId
        self.lastDeliveredMessageId = lastDeliveredMessageId
    }
}

extension ConversationSettings {
    private enum CodingKeys: String, CodingKey {
        case isMuted, isPinned, isArchived, isLocked, isBlocked
        case disappearingMessages, label, pinnedAt
        case unreadCount, unread, unread_count, labelText, labelColor
        case lastReadMessageId, lastDeliveredMessageId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked)
        isBlocked = try container.decodeIfPresent(Bool.self, forKey: .isBlocked)
        disappearingMessages = try container.decodeIfPresent(Int.self, forKey: .disappearingMessages)
        pinnedAt = try container.decodeIfPresent(String.self, forKey: .pinnedAt)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount)
            ?? container.decodeIfPresent(Int.self, forKey: .unread)
            ?? container.decodeIfPresent(Int.self, forKey: .unread_count)
        labelText = try container.decodeIfPresent(String.self, forKey: .labelText)
        labelColor = try container.decodeIfPresent(String.self, forKey: .labelColor)
        lastReadMessageId = try container.decodeIfPresent(String.self, forKey: .lastReadMessageId)
        lastDeliveredMessageId = try container.decodeIfPresent(String.self, forKey: .lastDeliveredMessageId)

        if let singleLabel = try? container.decodeIfPresent(String.self, forKey: .label) {
            label = [singleLabel]
        } else if let labelText, !labelText.isEmpty {
            label = [labelText]
        } else {
            label = try? container.decodeIfPresent([String?].self, forKey: .label)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(isMuted, forKey: .isMuted)
        try container.encodeIfPresent(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(isArchived, forKey: .isArchived)
        try container.encodeIfPresent(isLocked, forKey: .isLocked)
        try container.encodeIfPresent(isBlocked, forKey: .isBlocked)
        try container.encodeIfPresent(disappearingMessages, forKey: .disappearingMessages)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
        try container.encodeIfPresent(unreadCount, forKey: .unreadCount)
        try container.encodeIfPresent(labelText, forKey: .labelText)
        try container.encodeIfPresent(labelColor, forKey: .labelColor)
        try container.encodeIfPresent(lastReadMessageId, forKey: .lastReadMessageId)
        try container.encodeIfPresent(lastDeliveredMessageId, forKey: .lastDeliveredMessageId)
    }
}



private func resolveAvatarURL(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
    return "\(ChatConfig.mediaBaseURL)/\(raw)"
}

