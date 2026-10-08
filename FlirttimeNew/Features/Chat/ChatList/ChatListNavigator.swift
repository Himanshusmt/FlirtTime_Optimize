//
//  ChatListNavigator.swift
//  FlirttimeNew
//
//  Created by Awais on 27/08/2025.
//

import SwiftUI

private extension Optional where Wrapped == String {
    var trimmedOrNil: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ChatNavigationData {
    let chatId: String
    let userChatId: String
    let user: UserRes?
    let activeStatus: String
    let isGroupChat: Bool
    let groupTitle: String
    let groupParticipants: [GroupParticipant]
    let isGroupParticipant: Bool
    let groupAvatarUrl: String
    // Channel-specific fields
    let isChannel: Bool
    let channelId: String
    let canSendInChannel: Bool
    let isAlreadyFollowingChannel: Bool
    let initialFollowersCount: Int?
    let initialIsBlocked: Bool
    let participantsCount: Int?
    var unreadCount: Int = 0

    init(chatId: String,
         userChatId: String,
         user: UserRes?,
         activeStatus: String,
         isGroupChat: Bool,
         groupTitle: String,
         groupParticipants: [GroupParticipant],
         isGroupParticipant: Bool,
         groupAvatarUrl: String = "",
         isChannel: Bool = false,
         channelId: String = "",
         canSendInChannel: Bool = false,
         isAlreadyFollowingChannel: Bool = false,
         initialFollowersCount: Int? = nil,
         initialIsBlocked: Bool = false,
         participantsCount: Int? = nil) {
        self.chatId = chatId
        self.userChatId = userChatId
        self.user = user
        self.activeStatus = activeStatus
        self.isGroupChat = isGroupChat
        self.groupTitle = groupTitle
        self.groupParticipants = groupParticipants
        self.isGroupParticipant = isGroupParticipant
        self.groupAvatarUrl = groupAvatarUrl
        self.isChannel = isChannel
        self.channelId = channelId
        self.canSendInChannel = canSendInChannel
        self.isAlreadyFollowingChannel = isAlreadyFollowingChannel
        self.initialFollowersCount = initialFollowersCount
        self.initialIsBlocked = initialIsBlocked
        self.participantsCount = participantsCount
    }
}

final class ChatListNavigator: ObservableObject {
    @Published var navigateToChatDetail = false
    @Published var navigateToSettings = false
    @Published var navigateToCreateGroup = false
    @Published var showSearchSheet = false
    @Published var showCreateChannel = false

    var uikitPushHandler: ((ChatNavigationData) -> Void)?
    var onChatDetailPopped: (() -> Void)?

    private(set) var currentNavigationData: ChatNavigationData?
    
    func navigateToChat(from source: ChatNavigationSource, unreadCount: Int? = nil) {
        var data = buildNavigationData(from: source)
            data.unreadCount = unreadCount ?? 0  
            currentNavigationData = data
        if let handler = uikitPushHandler, let data = currentNavigationData {
            handler(data)
        } else {
            navigateToChatDetail = true
        }
    }

    /// Drives navigation with pre-built data (used by notification/banner routing).
    func navigateTo(data: ChatNavigationData) {
        currentNavigationData = data
        if let handler = uikitPushHandler {
            handler(data)
        } else {
            navigateToChatDetail = true
        }
    }

    func navigateToChannel(_ channel: ChannelSummary, isAdmin: Bool, isOwner: Bool) {
        var data = ChatNavigationData(
            chatId: channel.id,
            userChatId: "",
            user: nil,
            activeStatus: "",
            isGroupChat: true,
            groupTitle: channel.name,
            groupParticipants: [],
            isGroupParticipant: true,
            groupAvatarUrl: channel.icon ?? "",
            isChannel: true,
            channelId: channel.id,
            canSendInChannel: isAdmin,
            isAlreadyFollowingChannel: channel.hasFollowed ?? false,
            initialFollowersCount: channel.followersCount
        )
        data.unreadCount = channel.unreadCount ?? 0
        navigateTo(data: data)
    }

    func navigateToNewChannel(id: String, name: String, icon: String?, followersCount: Int = 0) {
        let data = ChatNavigationData(
            chatId: id,
            userChatId: "",
            user: nil,
            activeStatus: "",
            isGroupChat: true,
            groupTitle: name,
            groupParticipants: [],
            isGroupParticipant: true,
            groupAvatarUrl: icon ?? "",
            isChannel: true,
            channelId: id,
            canSendInChannel: true,
            isAlreadyFollowingChannel: true,
            // Owner is not a follower — use API/selected count (0 when none invited).
            initialFollowersCount: max(0, followersCount)
        )
        navigateTo(data: data)
    }
    
    private func buildNavigationData(from source: ChatNavigationSource) -> ChatNavigationData {
        switch source {
        case .existingChat(let chat), .activeUser(let chat):
            return buildNavigationData(from: chat)
        case .newUserChat(let user):
            return buildNavigationData(from: user)
        }
    }

    private func buildNavigationData(from chat: ChatMessageRow) -> ChatNavigationData {
        let conversationId = chat.id ?? ""
        if chat.isGroup {
            return makeGroupNavigationData(
                conversationId: conversationId,
                title: chat.title,
                participants: chat,
                isParticipant: chat.resolvedIsGroupParticipant,
                avatarUrl: chat.avatar
            )
        }

        let userDetails = chat.getUserDetails()
        let participantDetails = chat.otherParticipant?.user?.userDetails?.first
        let resolvedUserId = userDetails?.userId ?? chat.otherParticipant?.userId
        let resolvedUserName = userDetails?.userName ?? participantDetails?.userName ?? chat.otherParticipant?.user?.userId
        let resolvedFullName = userDetails?.fullName ?? participantDetails?.fullName ?? chat.title
        let resolvedAvatar = userDetails?.profilePicture ?? participantDetails?.profilePictureDetails?.filePath ?? participantDetails?.profilePicture
        return makeDirectNavigationData(
            conversationId: conversationId,
            userId: resolvedUserId,
            userName: resolvedUserName,
            fullName: resolvedFullName,
            avatarPath: resolvedAvatar,
            displayTitle: chat.title,
            existingUser: nil,
            verified: chat.otherParticipant?.resolvedIsVerified == true
                ? true
                : chat.otherParticipant?.userProfileData?.verified,
            initialIsBlocked: chat.settings?.isBlocked == true
                || (!(resolvedUserId ?? "").isEmpty && BlockedUsersManager.shared.isBlocked(id: resolvedUserId ?? ""))
        )
    }

    private func buildNavigationData(from user: UserRes) -> ChatNavigationData {
        let avatarPath = user.profilePictureDetails?.filePath ?? user.profilePicture
        return makeDirectNavigationData(
            conversationId: nil,
            userId: user.userId ?? user.id,
            userName: user.userName,
            fullName: user.fullName,
            avatarPath: avatarPath,
            displayTitle: nil,
            existingUser: user
        )
    }

    private func makeDirectNavigationData(conversationId: String?,
                                          userId: String?,
                                          userName: String?,
                                          fullName: String?,
                                          avatarPath: String?,
                                          displayTitle: String?,
                                          existingUser: UserRes?,
                                          verified: Bool? = nil,
                                          initialIsBlocked: Bool = false) -> ChatNavigationData {
        let trimmedFullName = fullName.trimmedOrNil
        let displayNameFallback = displayTitle.trimmedOrNil
        let fallbackName = userName.trimmedOrNil ?? displayNameFallback

        var resolvedUser: UserRes? = existingUser

        if resolvedUser == nil {
            if trimmedFullName != nil || fallbackName != nil || userId != nil {
                resolvedUser = UserRes(
                    id: userId,
                    userId: userId,
                    userName: userName,
                    fullName: trimmedFullName ?? fallbackName,
                    type: nil,
                    profilePicture: avatarPath,
                    isPrivate: nil,
                    verified: verified,
                    profilePictureDetails: avatarPath != nil ? ProfilePictureDetails(filePath: avatarPath) : nil,
                    follower_profile: nil,
                    isFollowing: nil,
                    isSelected: nil, searchedAt: nil
                )
            }
        } else {
            if resolvedUser?.userId == nil {
                resolvedUser?.userId = userId
            }
            if resolvedUser?.id == nil {
                resolvedUser?.id = userId
            }
            if resolvedUser?.fullName.trimmedOrNil == nil {
                resolvedUser?.fullName = trimmedFullName ?? fallbackName
            }
            if resolvedUser?.userName.trimmedOrNil == nil {
                resolvedUser?.userName = userName.trimmedOrNil ?? fallbackName
            }
            if resolvedUser?.profilePictureDetails == nil, let avatarPath {
                resolvedUser?.profilePictureDetails = ProfilePictureDetails(filePath: avatarPath)
            }
            if resolvedUser?.profilePicture == nil {
                resolvedUser?.profilePicture = avatarPath
            }
        }

        let resolvedActiveStatus: String = {
            guard let uid = userId, !uid.isEmpty else { return "" }
            if ChatListSocketService.shared.onlineUserIds.contains(uid) {
                return ChatStrings.getLocalizeString(title: .online)
            }
            return ""
        }()

        return ChatNavigationData(
            chatId: conversationId ?? "",
            userChatId: userId ?? "",
            user: resolvedUser,
            activeStatus: resolvedActiveStatus,
            isGroupChat: false,
            groupTitle: "",
            groupParticipants: [],
            isGroupParticipant: true,
            groupAvatarUrl: "",
            initialIsBlocked: initialIsBlocked
        )
    }

    private func makeGroupNavigationData(conversationId: String,
                                         title: String?,
                                         participants: ChatMessageRow,
                                         isParticipant: Bool,
                                         avatarUrl: String? = nil) -> ChatNavigationData {
        return ChatNavigationData(
            chatId: conversationId,
            userChatId: "",
            user: nil,
            activeStatus: "",
            isGroupChat: true,
            groupTitle: title?.trimmedOrNil ?? ChatStrings.chat_groupChat.localizedString(),
            groupParticipants: extractGroupParticipants(from: participants),
            isGroupParticipant: isParticipant,
            groupAvatarUrl: avatarUrl ?? "",
            participantsCount: participants.participantsCount
        )
    }

    func reset() {
        navigateToChatDetail = false
        navigateToSettings = false
        navigateToCreateGroup = false
        showSearchSheet = false
        showCreateChannel = false
        currentNavigationData = nil
    }
}

enum ChatNavigationSource {
    case existingChat(ChatMessageRow)
    case newUserChat(UserRes)
    case activeUser(ChatMessageRow)
}
