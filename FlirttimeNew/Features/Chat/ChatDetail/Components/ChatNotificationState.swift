//
//  ChatNotificationState.swift
//  FlirttimeNew
//
//  Created by Awais on 5/03/26.
//

import Foundation
import Combine
import Swinject
import UIKit
import UserNotifications

final class ChatNotificationState: ObservableObject {
    static let shared = ChatNotificationState()
    @Published var isInChatModule: Bool = false
    @Published var activeConversationId: String?
    @Published var pendingBanner: InAppChatBannerData?
    @Published var pendingChatNavigation: ChatNavigationData?
    @Published var isShowingChatDetail: Bool = false
    @Published var isChatListViewReady: Bool = false

    private var lastBannerConversationId: String?
    private var lastBannerMessageId: String?
    private var lastBannerTime: [String: Date] = [:]

    private init() {}

    // MARK: - Notification Tray Management

    static func clearNotifications(for conversationId: String) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            let matchingRequestIds = notifications.filter { notification in
                extractConversationId(from: notification.request.content.userInfo) == conversationId
            }.map { $0.request.identifier }

            if !matchingRequestIds.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: matchingRequestIds)
                AppLogger.debug("[NotificationClear] removed \(matchingRequestIds.count) notifications for conversation=\(conversationId)")
            }

            recalculateBadge()
        }
    }

    /// Removes all delivered notifications (e.g. on logout or when all chats are read).
    static func clearAllChatNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    /// Recalculates the badge number from remaining delivered notifications.
    private static func recalculateBadge() {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            let chatNotifications = notifications.filter { notification in
                let type = pushType(from: notification.request.content.userInfo)
                return type?.uppercased() == "MESSAGE"
            }
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = chatNotifications.count
            }
        }
    }

    // MARK: - Notification Payload Parsing Helpers

    private static func extractConversationId(from userInfo: [AnyHashable: Any]) -> String? {
        if let topLevel = userInfo["conversationId"] as? String, !topLevel.isEmpty {
            return topLevel
        }

        // Try structured data field first (NEW camelCase + OLD snake_case)
        if let dataString = userInfo["data"] as? String,
           let data = dataString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let meta = json["meta"] as? [String: Any] {
                if let convId = meta["conversationId"] as? String, !convId.isEmpty {
                    return convId
                }
                if let convId = meta["conversation_id"] as? String, !convId.isEmpty {
                    return convId
                }
                if let messageDict = meta["message"] as? [String: Any] {
                    if let convId = messageDict["conversationId"] as? String, !convId.isEmpty {
                        return convId
                    }
                    if let convId = messageDict["conversation_id"] as? String, !convId.isEmpty {
                        return convId
                    }
                }
            }
            if let link = json["link"] as? String {
                let parts = link.split(separator: "/").map(String.init)
                if let idx = parts.firstIndex(of: "conversations"), idx + 1 < parts.count {
                    let id = parts[idx + 1]
                    if !id.isEmpty { return id }
                }
            }
        }

        if let link = userInfo["link"] as? String {
            let parts = link.split(separator: "/").map(String.init)
            if let idx = parts.firstIndex(of: "conversations"), idx + 1 < parts.count {
                let id = parts[idx + 1]
                if !id.isEmpty { return id }
            }
        }
        return nil
    }

    private static func pushType(from userInfo: [AnyHashable: Any]) -> String? {
        if let dataString = userInfo["data"] as? String,
           let data = dataString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json["type"] as? String
        }
        return nil
    }

    func setPendingBanner(_ banner: InAppChatBannerData, messageId: String = "") {
        let now = Date()

        if !messageId.isEmpty,
           lastBannerConversationId == banner.conversationId,
           lastBannerMessageId == messageId {
            return
        }

        if let lastTime = lastBannerTime[banner.conversationId],
           now.timeIntervalSince(lastTime) < 5.0 {
            return
        }

        lastBannerConversationId = banner.conversationId
        lastBannerMessageId = messageId
        lastBannerTime[banner.conversationId] = now
        pendingBanner = banner
    }

    func isViewingConversation(_ conversationId: String) -> Bool {
        guard let active = activeConversationId, !active.isEmpty else { return false }
        return active == conversationId
    }

    @MainActor
    static func popActiveChatDetail() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else { return }

        guard let container = findViewController(ofType: ChatListContainerViewController.self, in: root) else { return }
        // Dismiss any presented sheets (message options, media viewer, etc.)
        if let presented = container.navigationController?.presentedViewController {
            if presented is AgoraCallViewController {
                AgoraCallService.shared.minimizeToPipIfNeeded()
            } else {
                presented.dismiss(animated: false)
            }
        }
        container.navigationController?.popViewController(animated: true)
        shared.isShowingChatDetail = false
    }

    @MainActor
    static func popActiveChatDetail(completion: @escaping () -> Void) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else {
            completion()
            return
        }

        guard let container = findViewController(ofType: ChatListContainerViewController.self, in: root) else {
            completion()
            return
        }

        if let presented = container.navigationController?.presentedViewController {
            if presented is AgoraCallViewController {
                AgoraCallService.shared.minimizeToPipIfNeeded()
            } else {
                presented.dismiss(animated: false)
            }
        }

        guard let navController = container.navigationController else {
            shared.isShowingChatDetail = false
            completion()
            return
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            completion()
        }
        navController.popViewController(animated: true)
        CATransaction.commit()

        shared.isShowingChatDetail = false
    }

    private static func findViewController<T: UIViewController>(ofType type: T.Type, in vc: UIViewController) -> T? {
        if let match = vc as? T { return match }
        for child in vc.children {
            if let found = findViewController(ofType: type, in: child) { return found }
        }
        return nil
    }

    static func navigateFromBanner(_ bannerData: InAppChatBannerData) {
        let conversationId = bannerData.conversationId
        let senderName = bannerData.senderName

        // Clear all notifications for this conversation from the tray.
        clearNotifications(for: conversationId)

        Task { @MainActor in
            // Dismiss any open keyboard before navigating.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

            let navData: ChatNavigationData

            if bannerData.chatType == "channel" {
                navData = buildChannelNavigationData(channelId: conversationId)
            } else {
                let chatRow = await lookupConversation(id: conversationId)
                if let chat = chatRow {
                    AppLogger.debug("[bannerNav] CoreData hit for \(conversationId)")
                    navData = buildNavigationData(from: chat)
                } else {
                    AppLogger.debug("[bannerNav] CoreData miss for \(conversationId), using notification data")
                    navData = buildNavigationData(conversationId: conversationId, senderId: "", senderName: senderName)
                }
            }

            NotificationCenter.default.post(
                name: NSNotification.Name("ChatUnreadCountUpdated"),
                object: nil,
                userInfo: ["conversationId": conversationId]
            )

            shared.pendingChatNavigation = navData
        }
    }

    private static func lookupConversation(id: String) async -> ChatMessageRow? {
        guard let repo = Container.sharedContainer.resolve(ConversationRepositoryProtocol.self) else {
            return nil
        }
        return try? await repo.getConversationWithParticipants(id: id)
    }

    // MARK: - ChatNavigationData builders

    static func buildChannelNavigationData(channelId: String) -> ChatNavigationData {
        let cached = ChannelRepository().getCachedChannel(id: channelId)
        let resolvedTitle: String
        if let cached = cached, !cached.name.isEmpty {
            resolvedTitle = cached.name
        } else {
            resolvedTitle = ChatStrings.chat_channels.localizedString()
        }
        let resolvedAvatar = cached?.icon ?? ""

        return ChatNavigationData(
            chatId: "",
            userChatId: "",
            user: nil,
            activeStatus: "",
            isGroupChat: true,
            groupTitle: resolvedTitle,
            groupParticipants: [],
            isGroupParticipant: true,
            groupAvatarUrl: resolvedAvatar,
            isChannel: true,
            channelId: channelId,
            canSendInChannel: false,
            isAlreadyFollowingChannel: cached?.hasFollowed ?? false
        )
    }

    static func buildNavigationData(from chat: ChatMessageRow) -> ChatNavigationData {
        let conversationId = chat.id ?? ""

        if chat.isGroup {
            let groupParticipants = extractGroupParticipants(from: chat)
            return ChatNavigationData(
                chatId: conversationId,
                userChatId: "",
                user: nil,
                activeStatus: "",
                isGroupChat: true,
                groupTitle: chat.title ?? ChatStrings.chat_groupChat.localizedString(),
                groupParticipants: groupParticipants,
                isGroupParticipant: chat.resolvedIsGroupParticipant,
                groupAvatarUrl: chat.avatar ?? ""
            )
        }

        let userDetails = chat.getUserDetails()
        let participantDetails = chat.otherParticipant?.user?.userDetails?.first
        let resolvedUserId = userDetails?.userId ?? chat.otherParticipant?.userId
        let resolvedUserName = userDetails?.userName ?? participantDetails?.userName
        let resolvedFullName = userDetails?.fullName ?? participantDetails?.fullName ?? chat.title
        let resolvedAvatar = userDetails?.profilePicture ?? participantDetails?.profilePictureDetails?.filePath ?? participantDetails?.profilePicture

        let user = UserRes(
            id: resolvedUserId,
            userId: resolvedUserId,
            userName: resolvedUserName,
            fullName: resolvedFullName,
            type: nil,
            profilePicture: resolvedAvatar,
            isPrivate: nil,
            verified: nil,
            profilePictureDetails: resolvedAvatar != nil ? ProfilePictureDetails(filePath: resolvedAvatar) : nil,
            follower_profile: nil,
            isFollowing: nil,
            isSelected: nil,
            searchedAt: nil
        )

        return ChatNavigationData(
            chatId: conversationId,
            userChatId: resolvedUserId ?? "",
            user: user,
            activeStatus: "",
            isGroupChat: false,
            groupTitle: "",
            groupParticipants: [],
            isGroupParticipant: true,
            groupAvatarUrl: ""
        )
    }

    static func buildNavigationData(conversationId: String, senderId: String, senderName: String) -> ChatNavigationData {
        let user = UserRes(
            id: senderId.isEmpty ? nil : senderId,
            userId: senderId.isEmpty ? nil : senderId,
            userName: senderName,
            fullName: senderName,
            type: nil,
            profilePicture: nil,
            isPrivate: nil,
            verified: nil,
            profilePictureDetails: nil,
            follower_profile: nil,
            isFollowing: nil,
            isSelected: nil,
            searchedAt: nil
        )
        return ChatNavigationData(
            chatId: conversationId,
            userChatId: senderId,
            user: user,
            activeStatus: "",
            isGroupChat: false,
            groupTitle: "",
            groupParticipants: [],
            isGroupParticipant: true,
            groupAvatarUrl: ""
        )
    }
}

struct InAppChatBannerData: Identifiable {
    let id = UUID()
    let conversationId: String
    let senderName: String
    let senderAvatarURL: URL?
    let messagePreview: String
    let isGroupChat: Bool
    let groupName: String?
    let chatType: String // "direct", "group", "channel"
}
