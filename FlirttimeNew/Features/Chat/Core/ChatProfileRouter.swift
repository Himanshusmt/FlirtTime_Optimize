//
//  ChatProfileRouter.swift
//  FlirttimeNew
//

import UIKit

/// Routes between FlirtTime's profile screens and chat conversations.
enum ChatProfileRouter {
    static func openProfile(of user: UserRes, from presenter: UIViewController) {
        guard let userId = Int(user.userId ?? user.id ?? "") else {
            AppLogger.debug("[ChatProfileRouter] non-numeric user id, profile not opened")
            return
        }
        var payload: [String: Any] = ["user_id": userId, "id": userId]
        if let name = user.fullName ?? user.userName { payload["display_name"] = name; payload["fullname"] = name }
        if let avatar = user.profilePicture { payload["avatar"] = avatar }
        if let bio = user.bio { payload["about_me"] = bio }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let info = try? JSONDecoder().decode(UserDetailInfo.self, from: data) else { return }

        let profileVC: OtherUserProfileViewController = OtherUserProfileViewController.instantiateFromStoryboard()
        profileVC.fromChatScreen = true
        profileVC.userDetailInfo = info
        presenter.navigationController?.pushViewController(profileVC, animated: true)
    }

    /// Opens the 1:1 conversation with a FlirtTime user, reusing the existing thread when there is one.
    /// A new thread is created when the first message is sent.
    static func openChat(userID: Int, name: String, avatarPath: String?, isVerified: Bool, from presenter: UIViewController) {
        guard let navigationController = presenter.navigationController else { return }
        ChatMockSeeder.shared.seedIfNeeded()

        let chatUserID = String(userID)
        let conversationID = ConversationRepository().findConversationIdByParticipant(userId: chatUserID) ?? ""
        let user = UserRes(
            id: chatUserID,
            userId: chatUserID,
            userName: name,
            fullName: name,
            type: nil,
            profilePicture: avatarPath,
            isPrivate: nil,
            verified: isVerified,
            profilePictureDetails: avatarPath.map { ProfilePictureDetails(filePath: $0) },
            follower_profile: nil,
            isFollowing: nil,
            isSelected: nil, searchedAt: nil
        )
        let isOnline = ChatListSocketService.shared.onlineUserIds.contains(chatUserID)

        let detailVC = ChatDetailViewController.make(
            selectedId: conversationID,
            selectedUserChatID: chatUserID,
            user: user,
            activeStatus: isOnline ? ChatStrings.getLocalizeString(title: .online) : "",
            initialIsBlocked: BlockedUsersManager.shared.isBlocked(id: chatUserID)
        )
        detailVC.hidesBottomBarWhenPushed = true
        navigationController.pushViewController(detailVC, animated: true)
    }
}
