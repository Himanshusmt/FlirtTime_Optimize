//
//  ChatProfileRouter.swift
//  FlirttimeNew
//

import UIKit

/// Opens FlirtTime's profile screen for a chat participant.
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
}
