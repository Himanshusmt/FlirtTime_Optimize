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

    init(from userInfo: [AnyHashable: Any]) {
        if let rawType = userInfo["notify_type"] as? String {
            self = NotificationType.allTypes.first(where: { $0.rawValue == rawType }) ?? .unknown
        } else {
            self = .unknown
        }
    }
}

// TODO: add push registration / UNUserNotificationCenterDelegate from FlirtTime once push is set up.
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
            // TODO: push PremiumVC once the subscription module is ported.
            viewController.showComingSoon("Premium")

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
