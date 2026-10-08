//
//  ConversationMapper.swift
//  FlirttimeNew
//

import CoreData
import Foundation

enum ConversationMapper {

    static let isoWithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoNoFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoFormatterFallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// True when Core Data has a real last-message payload — not merely a sort timestamp
    /// (`lastMessageTimestamp` / `lastMessageAt` are set for empty/new chats so they sort correctly).
    private static func hasPersistedLastMessageEvidence(_ cdConversation: CDConversation) -> Bool {
        let hasId = !(cdConversation.lastMessageId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasContent = !(cdConversation.lastMessageContent ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSender = !(cdConversation.lastMessageSender ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasType = !(cdConversation.lastMessageType ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasId || hasContent || hasSender || hasType
    }

    // MARK: - To Domain

    static func toDomain(_ cdConversation: CDConversation, sessionManager: SessionManager?) -> ChatMessageRow? {
        var chatRow = ChatMessageRow()
        chatRow.id = cdConversation.id
        chatRow.type = cdConversation.type
        chatRow.unreadCount = Int(cdConversation.unreadCount)
        if cdConversation.participantsCount > 0 {
            chatRow.participantsCount = Int(cdConversation.participantsCount)
        }
        chatRow.title = cdConversation.title

        let bestDate = cdConversation.lastMessageTimestamp ?? cdConversation.lastMessageAt
        if let d = bestDate {
            chatRow.lastMessageAt = isoWithFractionalSeconds.string(from: d)
        }

        // Timestamp alone is used for inbox sorting of empty/new chats — not real message evidence.
        if hasPersistedLastMessageEvidence(cdConversation) {
            chatRow.lastMessage = ConversationLastMessage(
                id: cdConversation.lastMessageId,
                messageType: cdConversation.lastMessageType,
                contentPreview: cdConversation.lastMessageContent,
                senderId: cdConversation.lastMessageSender,
                createdAt: cdConversation.lastMessageTimestamp.map { isoWithFractionalSeconds.string(from: $0) },
                status: cdConversation.lastMessageStatus
            )
        }

        let allCDParticipants: [CDParticipant] = (cdConversation.participants?.allObjects as? [CDParticipant]) ?? []
        let cdParticipantsArray: [CDParticipant]
        if chatRow.type == "direct" {
            cdParticipantsArray = allCDParticipants
        } else {
            cdParticipantsArray = allCDParticipants.filter { $0.isActive }
        }
        if !cdParticipantsArray.isEmpty {
            chatRow.participants = cdParticipantsArray.map { cdParticipant in
                let userDetail = UserDetail(
                    userName: cdParticipant.userName,
                    fullName: cdParticipant.fullName,
                    profilePicture: cdParticipant.profilePicture,
                    profilePictureDetails: cdParticipant.profilePicture != nil ? ProfilePictureDetails(filePath: cdParticipant.profilePicture) : nil
                )

                let participantUser = ParticipantUser(
                    id: cdParticipant.userId,
                    userId: cdParticipant.userId,
                    userDetails: [userDetail],
                    isOnline: cdParticipant.isOnline,
                    isPrivate: cdParticipant.isPrivate,
                    verified: cdParticipant.verified,
                    isFollowing: cdParticipant.isFollowing,
                    isBlock: cdParticipant.isBlock,
                    username: cdParticipant.userName,
                    fullName: cdParticipant.fullName,
                    profileImage: cdParticipant.profilePicture,
                    lastOnline: cdParticipant.lastOnline.map { isoWithFractionalSeconds.string(from: $0) }
                )

                return Participant(
                    id: cdParticipant.id,
                    conversationId: cdParticipant.conversationId,
                    userId: cdParticipant.userId,
                    role: cdParticipant.role,
                    joinedAt: cdParticipant.joinedAt.map { ISO8601DateFormatter().string(from: $0) },
                    leftAt: cdParticipant.leftAt.map { ISO8601DateFormatter().string(from: $0) },
                    isActive: cdParticipant.isActive,
                    createdAt: cdParticipant.createdAt.map { isoWithFractionalSeconds.string(from: $0) },
                    updatedAt: cdParticipant.updatedAt.map { isoWithFractionalSeconds.string(from: $0) },
                    user: participantUser,
                    isVerified: cdParticipant.verified
                )
            }
        }

        if chatRow.type == "direct" {
            let currentUserId = getCurrentUserId(sessionManager: sessionManager)
            if let resolvedTitle = resolvedDirectTitleIfAvailable(
                incomingTitle: chatRow.title,
                participantsFromAPI: nil,
                cdParticipants: cdParticipantsArray,
                currentUserId: currentUserId,
                existingTitle: cdConversation.title,
                sessionManager: sessionManager
            ) {
                if chatRow.title != resolvedTitle {
                    chatRow.title = resolvedTitle
                }
            }
        }

        if let cdSettings = cdConversation.settings {
            chatRow.settings = ConversationSettings(
                isMuted: cdSettings.settingsIsMuted,
                isPinned: cdSettings.settingsIsPinned,
                isArchived: cdSettings.settingsIsArchived,
                isLocked: cdSettings.isLocked,
                isBlocked: cdSettings.settingsIsBlocked,
                disappearingMessages: cdSettings.disappearingMessages.flatMap { Int($0) },
                label: cdSettings.label.map { [$0] },
                pinnedAt: cdSettings.pinnedAt.map { isoWithFractionalSeconds.string(from: $0) },
                labelText: cdSettings.label,
                labelColor: labelColorValue(from: cdSettings)
            )
        }

        chatRow.avatar = cdConversation.avatar
        chatRow.inviteCode = cdConversation.inviteCode
        chatRow.inviteLink = cdConversation.inviteLink
        chatRow.isInviteLinkEnabled = cdConversation.isInviteLinkEnabled
        chatRow.isGroupParticipant = cdConversation.isGroupParticipant
        if let deletedAt = cdConversation.deletedAt {
            chatRow.deletedAt = isoWithFractionalSeconds.string(from: deletedAt)
        }

        return chatRow
    }

    static func toDomainSnapshot(_ cdConversation: CDConversation, sessionManager: SessionManager?) -> ChatMessageRow {
        var chatRow = ChatMessageRow()
        chatRow.id = cdConversation.id
        chatRow.type = cdConversation.type
        chatRow.unreadCount = Int(cdConversation.unreadCount)
        if cdConversation.participantsCount > 0 {
            chatRow.participantsCount = Int(cdConversation.participantsCount)
        }
        chatRow.title = cdConversation.title

        chatRow.avatar = cdConversation.avatar
        chatRow.inviteCode = cdConversation.inviteCode
        chatRow.inviteLink = cdConversation.inviteLink
        chatRow.isInviteLinkEnabled = cdConversation.isInviteLinkEnabled
        chatRow.isGroupParticipant = cdConversation.isGroupParticipant
        if let deletedAt = cdConversation.deletedAt {
            chatRow.deletedAt = isoWithFractionalSeconds.string(from: deletedAt)
        }

        let bestDate = cdConversation.lastMessageTimestamp ?? cdConversation.lastMessageAt
        if let d = bestDate {
            chatRow.lastMessageAt = isoWithFractionalSeconds.string(from: d)
        }

        // Timestamp alone is used for inbox sorting of empty/new chats — not real message evidence.
        if hasPersistedLastMessageEvidence(cdConversation) {
            chatRow.lastMessage = ConversationLastMessage(
                id: cdConversation.lastMessageId,
                messageType: cdConversation.lastMessageType,
                contentPreview: cdConversation.lastMessageContent,
                senderId: cdConversation.lastMessageSender,
                createdAt: cdConversation.lastMessageTimestamp.map { isoWithFractionalSeconds.string(from: $0) },
                status: cdConversation.lastMessageStatus
            )
        }

        let allCDParticipants: [CDParticipant] = (cdConversation.participants?.allObjects as? [CDParticipant]) ?? []
        let cdParticipantsArray: [CDParticipant]
        if chatRow.type == "direct" {
            cdParticipantsArray = allCDParticipants
        } else {
            cdParticipantsArray = allCDParticipants.filter { $0.isActive }
        }
        if !cdParticipantsArray.isEmpty {
            chatRow.participants = cdParticipantsArray.map { cdParticipant in
                let userDetail = UserDetail(
                    userName: cdParticipant.userName,
                    fullName: cdParticipant.fullName,
                    profilePicture: cdParticipant.profilePicture,
                    profilePictureDetails: cdParticipant.profilePicture != nil ? ProfilePictureDetails(filePath: cdParticipant.profilePicture) : nil
                )

                let participantUser = ParticipantUser(
                    id: cdParticipant.userId,
                    userId: cdParticipant.userId,
                    userDetails: [userDetail],
                    isOnline: cdParticipant.isOnline,
                    isPrivate: cdParticipant.isPrivate,
                    verified: cdParticipant.verified,
                    isFollowing: cdParticipant.isFollowing,
                    isBlock: cdParticipant.isBlock,
                    username: cdParticipant.userName,
                    fullName: cdParticipant.fullName,
                    profileImage: cdParticipant.profilePicture,
                    lastOnline: cdParticipant.lastOnline.map { isoWithFractionalSeconds.string(from: $0) }
                )

                return Participant(
                    id: cdParticipant.id,
                    conversationId: cdParticipant.conversationId,
                    userId: cdParticipant.userId,
                    role: cdParticipant.role,
                    joinedAt: cdParticipant.joinedAt.map { ISO8601DateFormatter().string(from: $0) },
                    leftAt: cdParticipant.leftAt.map { ISO8601DateFormatter().string(from: $0) },
                    isActive: cdParticipant.isActive,
                    createdAt: cdParticipant.createdAt.map { isoWithFractionalSeconds.string(from: $0) },
                    updatedAt: cdParticipant.updatedAt.map { isoWithFractionalSeconds.string(from: $0) },
                    user: participantUser,
                    isVerified: cdParticipant.verified
                )
            }
        }

        if chatRow.type == "direct" {
            let currentUserId = getCurrentUserId(sessionManager: sessionManager)
            if let resolvedTitle = resolvedDirectTitleIfAvailable(
                incomingTitle: chatRow.title,
                participantsFromAPI: nil,
                cdParticipants: cdParticipantsArray,
                currentUserId: currentUserId,
                existingTitle: cdConversation.title,
                sessionManager: sessionManager
            ) {
                if chatRow.title != resolvedTitle {
                    chatRow.title = resolvedTitle
                }
            }
        }

        if let cdSettings = cdConversation.settings {
            chatRow.settings = ConversationSettings(
                isMuted: cdSettings.settingsIsMuted,
                isPinned: cdSettings.settingsIsPinned,
                isArchived: cdSettings.settingsIsArchived,
                isLocked: cdSettings.isLocked,
                isBlocked: cdSettings.settingsIsBlocked,
                disappearingMessages: cdSettings.disappearingMessages.flatMap { Int($0) },
                label: cdSettings.label.map { [$0] },
                pinnedAt: cdSettings.pinnedAt.map { isoWithFractionalSeconds.string(from: $0) },
                labelText: cdSettings.label,
                labelColor: labelColorValue(from: cdSettings)
            )
        }

        return chatRow
    }

    // MARK: - Update

    static func update(_ conversation: CDConversation, from chatRow: ChatMessageRow, context: NSManagedObjectContext, sessionManager: SessionManager?) {
        conversation.id = chatRow.id
        conversation.type = chatRow.type
        conversation.participantsCount = Int32(chatRow.participantsCount ?? 0)
        conversation.updatedAt = Date()

        // Prefer an explicit unread from the row. If the payload omitted unreadCount,
        // keep the persisted value so a list refresh cannot wipe socket increments.
        if let incomingUnread = chatRow.unreadCount {
            conversation.unreadCount = Int32(max(0, incomingUnread))
        }

        if let tsString = chatRow.lastMessage?.createdAt, let d = parseDate(tsString) {
            let shouldUpdate = conversation.lastMessageTimestamp.map { d >= $0 } ?? true
            if shouldUpdate {
                conversation.lastMessageTimestamp = d
                conversation.lastMessageAt = d
            }
        } else if let lmAt = chatRow.lastMessageAt, let d = parseDate(lmAt) {
            // Newly created groups often have no lastMessage yet — still sort by created time.
            let shouldUpdateTimestamp = conversation.lastMessageTimestamp.map { d >= $0 } ?? true
            if shouldUpdateTimestamp {
                conversation.lastMessageTimestamp = d
            }
            let shouldUpdateAt = conversation.lastMessageAt.map { d >= $0 } ?? true
            if shouldUpdateAt {
                conversation.lastMessageAt = d
            }
        }

        if let lastMessage = chatRow.lastMessage {
            let incomingTimestamp = parseDate(lastMessage.createdAt)
            let existingTimestamp = conversation.lastMessageTimestamp
            let preserveExisting: Bool
            if let incoming = incomingTimestamp, let existing = existingTimestamp {
                preserveExisting = existing > incoming
            } else {
                preserveExisting = false
            }
            if preserveExisting {
                if let status = lastMessage.status, status == "deleted" {
                    conversation.lastMessageStatus = status
                }
            } else {
                conversation.lastMessageContent = lastMessage.contentPreview
                conversation.lastMessageSender = lastMessage.senderId
                conversation.lastMessageType = lastMessage.messageType
                if let timestamp = incomingTimestamp {
                    conversation.lastMessageTimestamp = timestamp
                }
                conversation.lastMessageId = lastMessage.id
                if lastMessage.isSystemMessage {
                    conversation.lastMessageStatus = nil
                } else if let status = lastMessage.status {
                    conversation.lastMessageStatus = status
                }
            }
        }

        conversation.avatar = chatRow.avatar
        conversation.inviteCode = chatRow.inviteCode
        conversation.inviteLink = chatRow.inviteLink
        conversation.isInviteLinkEnabled = chatRow.isInviteLinkEnabled ?? false
        conversation.isGroupParticipant = chatRow.isGroupParticipant ?? true
        conversation.deletedAt = parseDate(chatRow.deletedAt)

        if let participants = chatRow.participants, !participants.isEmpty {
            let existingParticipants = conversation.participants?.allObjects as? [CDParticipant] ?? []
            var existingByUserId: [String: CDParticipant] = [:]
            for p in existingParticipants {
                if let uid = p.userId { existingByUserId[uid] = p }
            }

            let incomingUserIds = Set(participants.compactMap { $0.userId })

            for participant in participants {
                guard let userId = participant.userId else { continue }
                let profilePicture = participant.user?.userDetails?.first?.profilePictureDetails?.filePath
                    ?? participant.user?.userDetails?.first?.profilePicture

                if let existing = existingByUserId[userId] {
                    existing.userName = participant.user?.userDetails?.first?.userName ?? participant.userProfileData?.userName ?? existing.userName
                    existing.fullName = participant.user?.userDetails?.first?.fullName ?? participant.userProfileData?.fullName ?? existing.fullName
                    if let pp = profilePicture, !pp.isEmpty {
                        existing.profilePicture = pp
                    }
                    existing.role = participant.role ?? existing.role
                    existing.isActive = participant.isActive ?? existing.isActive
                    existing.verified = participant.resolvedIsVerified || (existing.verified)
                    existing.isOnline = participant.user?.isOnline ?? existing.isOnline
                    existing.lastOnline = parseDate(participant.user?.lastOnline) ?? existing.lastOnline
                    existing.isPrivate = participant.user?.isPrivate ?? participant.userProfileData?.isPrivate ?? existing.isPrivate
                    existing.isFollowing = participant.user?.isFollowing ?? participant.userProfileData?.isFollowing ?? existing.isFollowing
                    existing.isBlock = participant.user?.isBlock ?? participant.userProfileData?.isBlock ?? existing.isBlock
                    existing.createdAt = parseDate(participant.createdAt) ?? existing.createdAt
                    existing.updatedAt = parseDate(participant.updatedAt) ?? existing.updatedAt
                } else {
                    let cdParticipant = CDParticipant(context: context)
                    cdParticipant.id = participant.id ?? participant.userId
                    cdParticipant.conversationId = chatRow.id
                    cdParticipant.userId = participant.userId
                    cdParticipant.userName = participant.user?.userDetails?.first?.userName ?? participant.userProfileData?.userName
                    cdParticipant.fullName = participant.user?.userDetails?.first?.fullName ?? participant.userProfileData?.fullName
                    cdParticipant.profilePicture = profilePicture
                    cdParticipant.role = participant.role
                    cdParticipant.isActive = participant.isActive ?? true
                    if let joinedAt = participant.joinedAt {
                        cdParticipant.joinedAt = ISO8601DateFormatter().date(from: joinedAt)
                    }
                    if let leftAt = participant.leftAt {
                        cdParticipant.leftAt = ISO8601DateFormatter().date(from: leftAt)
                    }
                    cdParticipant.verified = participant.resolvedIsVerified
                    cdParticipant.isOnline = participant.user?.isOnline ?? false
                    cdParticipant.lastOnline = parseDate(participant.user?.lastOnline)
                    cdParticipant.isPrivate = participant.user?.isPrivate ?? participant.userProfileData?.isPrivate ?? false
                    cdParticipant.isFollowing = participant.user?.isFollowing ?? participant.userProfileData?.isFollowing ?? false
                    cdParticipant.isBlock = participant.user?.isBlock ?? participant.userProfileData?.isBlock ?? false
                    cdParticipant.createdAt = parseDate(participant.createdAt)
                    cdParticipant.updatedAt = parseDate(participant.updatedAt)

                    cdParticipant.conversation = conversation
                }
            }

            if incomingUserIds.count < existingByUserId.count {
                for (userId, cdParticipant) in existingByUserId where !incomingUserIds.contains(userId) {
                    cdParticipant.isActive = false
                    AppLogger.debug("ConversationRepository: Marked participant \(userId) as inactive in conversation \(chatRow.id ?? "")")
                }
            }
        }

        if chatRow.type == "group" {
            let incomingTrimmed = chatRow.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !incomingTrimmed.isEmpty {
                conversation.title = chatRow.title
            } else if let existing = conversation.title?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
                conversation.title = conversation.title
            } else {
                conversation.title = ChatStrings.chat_groupChat.localizedString()
            }
        } else if chatRow.type == "direct" {
            let currentUserId = getCurrentUserId(sessionManager: sessionManager)
            let resolvedTitle = resolvedDirectTitleIfAvailable(
                incomingTitle: chatRow.title,
                participantsFromAPI: chatRow.participants,
                cdParticipants: nil,
                currentUserId: currentUserId,
                existingTitle: conversation.title,
                sessionManager: sessionManager
            ) ?? "Direct Chat"
            conversation.title = resolvedTitle
        }

        if let settings = chatRow.settings {
            let cdSettings: CDConversationSettings
            if let existingSettings = conversation.settings {
                cdSettings = existingSettings
            } else {
                cdSettings = CDConversationSettings(context: context)
                cdSettings.conversation = conversation
            }
            cdSettings.conversationId = chatRow.id
            cdSettings.settingsIsMuted = settings.isMuted ?? cdSettings.settingsIsMuted
            cdSettings.settingsIsPinned = settings.isPinned ?? cdSettings.settingsIsPinned
            cdSettings.settingsIsArchived = settings.isArchived ?? cdSettings.settingsIsArchived
            cdSettings.settingsIsBlocked = settings.isBlocked ?? cdSettings.settingsIsBlocked
            if let disappearing = settings.disappearingMessages {
                cdSettings.disappearingMessages = String(disappearing)
            }
            if settings.labelText != nil || settings.label != nil {
                let resolved = (settings.labelText ?? settings.label?.first as! String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cdSettings.label = (resolved?.isEmpty == false) ? resolved : nil
            }
            if let labelColor = settings.labelColor {
                let trimmed = labelColor.trimmingCharacters(in: .whitespacesAndNewlines)
                setLabelColorValue(trimmed.isEmpty ? nil : trimmed, on: cdSettings)
            }
            if let pinnedAt = settings.pinnedAt {
                cdSettings.pinnedAt = parseDate(pinnedAt)
            }
            cdSettings.isLocked = settings.isLocked ?? cdSettings.isLocked
            conversation.conversationIsArchived = cdSettings.settingsIsArchived
        }
    }

    static func applySettings(_ settings: ConversationSettings, to cdSettings: CDConversationSettings) {
        cdSettings.conversationId = cdSettings.conversation?.id
        if let v = settings.isMuted { cdSettings.settingsIsMuted = v }
        if let v = settings.isPinned { cdSettings.settingsIsPinned = v }
        if let v = settings.isArchived {
            cdSettings.settingsIsArchived = v
            cdSettings.conversation?.conversationIsArchived = v
        }
        if let v = settings.isLocked { cdSettings.isLocked = v }
        if let v = settings.isBlocked { cdSettings.settingsIsBlocked = v }
        if let pinnedAt = settings.pinnedAt, let d = parseDate(pinnedAt) { cdSettings.pinnedAt = d }
        cdSettings.disappearingMessages = settings.disappearingMessages.map { String($0) }
        if let label = settings.label {
            let resolved = label.first ?? nil
            let trimmed = resolved?.trimmingCharacters(in: .whitespacesAndNewlines)
            cdSettings.label = (trimmed?.isEmpty == false) ? trimmed : nil
        }
        if let labelText = settings.labelText {
            let trimmed = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
            cdSettings.label = trimmed.isEmpty ? nil : trimmed
        }
        if let labelColor = settings.labelColor {
            let trimmed = labelColor.trimmingCharacters(in: .whitespacesAndNewlines)
            setLabelColorValue(trimmed.isEmpty ? nil : trimmed, on: cdSettings)
        }
    }

    // MARK: - labelColor KVC helpers
    // Attribute exists on ChatDataModel_v3; access via KVC so builds succeed even when
    // Xcode's generated CDConversationSettings class hasn't regenerated yet.

    private static func labelColorValue(from cdSettings: CDConversationSettings) -> String? {
        cdSettings.value(forKey: "labelColor") as? String
    }

    private static func setLabelColorValue(_ value: String?, on cdSettings: CDConversationSettings) {
        cdSettings.setValue(value, forKey: "labelColor")
    }

    // MARK: - Date Parsing

    static func parseDate(_ string: String?) -> Date? {
        guard let s = string, !s.isEmpty else { return nil }
        if let d = isoWithFractionalSeconds.date(from: s) { return d }
        if let d = isoNoFractionalSeconds.date(from: s) { return d }
        if let val = Double(s) {
            if val > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: val / 1000.0)
            }
            if val > 1_000_000_000 {
                return Date(timeIntervalSince1970: val)
            }
        }
        return nil
    }

    // MARK: - Direct Title Resolution

    private static func resolveDirectTitle(participantsFromAPI: [Participant]?, cdParticipants: [CDParticipant]?, currentUserId: String) -> String? {
        if let apiParticipants = participantsFromAPI, !apiParticipants.isEmpty {
            if let t = resolveDirectTitleFromAPI(participants: apiParticipants, currentUserId: currentUserId) { return t }
        }
        if let cdParts = cdParticipants, !cdParts.isEmpty {
            if let t = resolveDirectTitleFromCD(participants: cdParts, currentUserId: currentUserId) { return t }
        }
        return nil
    }

    private static func resolveDirectTitleFromAPI(participants: [Participant], currentUserId: String) -> String? {
        let others = participants.filter { $0.userId != currentUserId }
        guard !others.isEmpty else { return nil }
        let sorted = others.sorted { p1, p2 in
            if p1.role == "admin" && p2.role != "admin" { return true }
            if p2.role == "admin" && p1.role != "admin" { return false }
            let d1 = parseDate(p1.joinedAt) ?? Date.distantFuture
            let d2 = parseDate(p2.joinedAt) ?? Date.distantFuture
            if d1 != d2 { return d1 < d2 }
            return (p1.id ?? "") < (p2.id ?? "")
        }
        guard let p = sorted.first else { return nil }
        if let full = p.user?.userDetails?.first?.fullName, !full.isEmpty { return full }
        if let full = p.userProfileData?.fullName, !full.isEmpty { return full }
        if let uname = p.user?.userDetails?.first?.userName, !uname.isEmpty { return uname }
        if let uname = p.userProfileData?.userName, !uname.isEmpty { return uname }
        return nil
    }

    private static func resolveDirectTitleFromCD(participants: [CDParticipant], currentUserId: String) -> String? {
        let others = participants.filter { $0.userId != currentUserId }
        guard !others.isEmpty else { return nil }
        let sorted = others.sorted { p1, p2 in
            if p1.role == "admin" && p2.role != "admin" { return true }
            if p2.role == "admin" && p1.role != "admin" { return false }
            let d1 = p1.joinedAt ?? Date.distantFuture
            let d2 = p2.joinedAt ?? Date.distantFuture
            if d1 != d2 { return d1 < d2 }
            return (p1.id ?? "") < (p2.id ?? "")
        }
        guard let p = sorted.first else { return nil }
        if let full = p.fullName, !full.isEmpty { return full }
        if let uname = p.userName, !uname.isEmpty { return uname }
        return nil
    }

    private static func resolvedDirectTitleIfAvailable(incomingTitle: String?,
                                                       participantsFromAPI: [Participant]?,
                                                       cdParticipants: [CDParticipant]?,
                                                       currentUserId: String,
                                                       existingTitle: String?,
                                                       sessionManager: SessionManager?) -> String? {
        if let resolved = resolveDirectTitle(participantsFromAPI: participantsFromAPI,
                                             cdParticipants: cdParticipants,
                                             currentUserId: currentUserId) {
            return resolved
        }
        if let normalizedIncoming = incomingTitle.normalizedDirectTitleCandidate,
           !isCurrentUserDisplayName(normalizedIncoming, sessionManager: sessionManager) {
            return normalizedIncoming
        }
        if let normalizedExisting = existingTitle.normalizedDirectTitleCandidate,
           !isCurrentUserDisplayName(normalizedExisting, sessionManager: sessionManager) {
            return normalizedExisting
        }
        return nil
    }

    private static func isCurrentUserDisplayName(_ value: String, sessionManager: SessionManager?) -> Bool {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !candidate.isEmpty else { return false }

        let ownFullName = sessionManager?.user?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ownUserName = sessionManager?.user?.userName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return candidate == ownFullName || candidate == ownUserName
    }

    private static func getCurrentUserId(sessionManager: SessionManager?) -> String {
        return sessionManager?.user?.userId ?? ""
    }
}

// MARK: - String Extensions for Title Normalization

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    var normalizedDirectTitleCandidate: String? {
        guard let trimmed = trimmedNonEmpty, !trimmed.isDirectPlaceholderTitle else {
            return nil
        }
        return trimmed
    }
}

private extension String {
    var isDirectPlaceholderTitle: Bool {
        return self == "--" || self.caseInsensitiveCompare("Direct Chat") == .orderedSame
    }
}
