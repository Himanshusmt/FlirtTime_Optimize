//
//  NotificationManager.swift
//  FlirtTime
//
//  Created by himanshu pal on 18/07/25.
//

import UIKit

struct NotificationType: Equatable {
    let rawValue: String

    static let like = NotificationType(rawValue: "like")
    static let favorite = NotificationType(rawValue: "favorite")
    static let match = NotificationType(rawValue: "match")
    static let incomplete = NotificationType(rawValue: "incomplete")
    static let gestureVerified = NotificationType(rawValue: "gesture-verified")
    static let gestureUnverified = NotificationType(rawValue: "gesture-unverified")
    static let profileImageVerified = NotificationType(rawValue: "profile-image-verified")
    static let profileImageUnverified = NotificationType(rawValue: "profile-image-unverified")
    static let imageVerified = NotificationType(rawValue: "image-verified")
    static let imageUnverified = NotificationType(rawValue: "image-unverified")
    static let membershipUpgrade = NotificationType(rawValue: "membership-upgrade")
    static let compliment = NotificationType(rawValue: "compliment")
    static let unknown = NotificationType(rawValue: "unknown")
    static let message = NotificationType(rawValue: "message")
    static let call = NotificationType(rawValue: "call")
    static let missedCall = NotificationType(rawValue: "missedCall")

    static let allTypes: [NotificationType] = [
        .message, .like, .favorite,
        .match, .incomplete, .gestureVerified, .gestureUnverified,
        .profileImageVerified, .profileImageUnverified, .imageVerified,
        .imageUnverified, .membershipUpgrade, .compliment, .call, .missedCall
    ]

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    // TODO: confirm the backend `type` values once a sample notifications response is available.
    private static let aliases: [String: NotificationType] = [
        "super_like": .favorite, "superlike": .favorite, "super-like": .favorite,
        "new_match": .match, "new_message": .message, "chat_message": .message,
        "missed_call": .missedCall, "profile_verified": .profileImageVerified,
        "photo_approved": .imageVerified, "photo_rejected": .imageUnverified,
        "photo_not_approved": .imageUnverified, "profile_incomplete": .incomplete,
        "subscription": .membershipUpgrade, "premium": .membershipUpgrade
    ]

    init(from userInfo: [AnyHashable: Any]) {
        guard let rawType = (userInfo["notify_type"] ?? userInfo["type"]) as? String else {
            self = .unknown
            return
        }
        let normalized = rawType.lowercased()
        self = NotificationType.allTypes.first(where: { $0.rawValue.lowercased() == normalized })
            ?? Self.aliases[normalized]
            ?? Self.aliases[normalized.replacingOccurrences(of: "-", with: "_")]
            ?? .unknown
    }
}

final class NotificationManager {

    static let shared = NotificationManager()
    private init() {}

    private enum Tab: Int {
        case explore = 1
        case home = 2
    }

    func handleNotification(_ userInfo: [AnyHashable: Any], from viewController: BaseViewController) {
        pushToScreen(notificationType: NotificationType(from: userInfo), data: userInfo, from: viewController)
    }

    // MARK: - Navigation

    private func pushToScreen(notificationType: NotificationType, data: [AnyHashable: Any], from viewController: BaseViewController) {
        guard let nav = viewController.navigationController else { return }

        switch notificationType {
        case .like, .favorite, .match, .compliment:
            let exploreVC = (viewController.tabBarController?.viewControllers?[Tab.explore.rawValue] as? UINavigationController)?
                .viewControllers.first as? ExploreViewController
            switch notificationType {
            case .match:
                exploreVC?.strSelectedLike = Constants.UserInteractionTypes.matches
            case .compliment:
                exploreVC?.strSelectedLike = Constants.UserInteractionTypes.compliment
            default:
                exploreVC?.strSelectedLike = Constants.UserInteractionTypes.likeYou
            }
            selectTab(.explore, from: viewController)

        case .gestureVerified, .imageVerified, .profileImageVerified:
            selectTab(.home, from: viewController)

        case .gestureUnverified:
            let aGestureVerificationViewController = GestureVerificationViewController.instantiateFromStoryboard()
            aGestureVerificationViewController.directRedirection = true
            aGestureVerificationViewController.hidesBottomBarWhenPushed = true
            nav.pushViewController(aGestureVerificationViewController, animated: true)

        case .profileImageUnverified:
            let aStartProfileVerificationViewController = StartProfileVerificationViewController.instantiateFromStoryboard()
            aStartProfileVerificationViewController.directRedirection = true
            aStartProfileVerificationViewController.hidesBottomBarWhenPushed = true
            nav.pushViewController(aStartProfileVerificationViewController, animated: true)

        case .imageUnverified, .incomplete:
            let aEditProfileViewController:EditProfileViewController = EditProfileViewController.instantiateFromStoryboard()
            if let banner = UserDataManager.shared.saveUserInfo?.data?.userInfo?.banner {
                aEditProfileViewController.coverImageUrl = ApiName.imgBaseURL + banner
            }
            aEditProfileViewController.isFromNotificationVC = true
            aEditProfileViewController.hidesBottomBarWhenPushed = true
            nav.pushViewController(aEditProfileViewController, animated: true)

        case .membershipUpgrade:
            viewController.openPremium()

        case .message:
            // TODO: push ChatViewController with data["user_id"] once chat is ported.
            viewController.showComingSoon("Chat")

        case .missedCall:
            viewController.showComingSoon("Calls")

        default:
            break
        }
    }

    private func selectTab(_ tab: Tab, from viewController: UIViewController) {
        let tabBarController = viewController.tabBarController
        viewController.navigationController?.popToRootViewController(animated: false)
        tabBarController?.selectedIndex = tab.rawValue
    }
}
