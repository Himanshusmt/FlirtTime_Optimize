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
    static let momentLike = NotificationType(rawValue: "moment_like")
    static let momentComment = NotificationType(rawValue: "moment_comment")
    static let momentCommentLike = NotificationType(rawValue: "moment_comment_like")
    static let momentGift = NotificationType(rawValue: "moment_gift")
    static let momentReaction = NotificationType(rawValue: "moment_reaction")
    static let profileVisit = NotificationType(rawValue: "profile_visit")

    static let allTypes: [NotificationType] = [
        .message, .like, .favorite,
        .match, .incomplete, .gestureVerified, .gestureUnverified,
        .profileImageVerified, .profileImageUnverified, .imageVerified,
        .imageUnverified, .membershipUpgrade, .compliment, .call, .missedCall,
        .momentLike, .momentComment, .momentCommentLike, .momentGift, .momentReaction, .profileVisit
    ]

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    private static let aliases: [String: NotificationType] = [
        "super_like": .favorite, "superlike": .favorite, "super-like": .favorite,
        "new_match": .match, "new_message": .message, "chat_message": .message, "chat": .message,
        "missed_call": .missedCall, "profile_verified": .profileImageVerified,
        "photo_approved": .imageVerified, "photo_rejected": .imageUnverified,
        "photo_not_approved": .imageUnverified, "profile_incomplete": .incomplete,
        "subscription": .membershipUpgrade, "premium": .membershipUpgrade,
        "moment_like": .momentLike, "moment-like": .momentLike,
        "moment_comment": .momentComment, "moment-comment": .momentComment,
        "moment_comment_like": .momentCommentLike, "moment-comment-like": .momentCommentLike,
        "comment_like": .momentCommentLike, "comment-like": .momentCommentLike,
        "moment_gift": .momentGift, "moment-gift": .momentGift,
        "moment_reaction": .momentReaction, "moment-reaction": .momentReaction,
        "quick_moment": .momentReaction, "quick-moment": .momentReaction,
        "quick_moment_reaction": .momentReaction, "quick-moment-reaction": .momentReaction,
        "profile_visit": .profileVisit, "profile-visit": .profileVisit,
        "moment": .momentLike
    ]

    init(from userInfo: [AnyHashable: Any]) {
        let rawType = (userInfo["notify_type"] ?? userInfo["type"] ?? userInfo["navType"] ?? userInfo["action"]) as? String
        guard let rawType else {
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
        case moments = 0
        case explore = 1
        case home = 2
        case messages = 3
        case profile = 4
    }

    private var pendingUserInfo: [AnyHashable: Any]?
    private var retryWorkItem: DispatchWorkItem?

    /// Push tap from `AppDelegate`. Finds the tab bar even if the top VC is not a `BaseViewController`.
    func handleNotification(_ userInfo: [AnyHashable: Any]) {
        let type = NotificationType(from: userInfo)
        #if DEBUG
        print("FCM handle tap: \(type.rawValue) → \(userInfo)")
        #endif
        guard let tabBar = appTabBarController() else {
            pendingUserInfo = userInfo
            scheduleRetry()
            return
        }
        pendingUserInfo = nil
        route(type, data: userInfo, tabBar: tabBar)
    }

    func handleNotification(_ userInfo: [AnyHashable: Any], from viewController: BaseViewController) {
        let type = NotificationType(from: userInfo)
        if let tabBar = viewController.tabBarController as? AppTabBarController ?? appTabBarController() {
            pendingUserInfo = nil
            route(type, data: userInfo, tabBar: tabBar, from: viewController)
            return
        }
        handleNotification(userInfo)
    }

    /// Call after the tab bar is on screen (cold start from a killed app).
    func consumePendingNotification() {
        guard let pending = pendingUserInfo else { return }
        pendingUserInfo = nil
        handleNotification(pending)
    }

    // MARK: - Navigation

    private func route(_ notificationType: NotificationType,
                       data: [AnyHashable: Any],
                       tabBar: AppTabBarController,
                       from viewController: BaseViewController? = nil) {
        tabBar.presentedViewController?.dismiss(animated: false)
        if let outerNav = tabBar.navigationController {
            outerNav.popToViewController(tabBar, animated: false)
        }

        switch notificationType {
        case .like, .favorite, .match, .compliment:
            let exploreTab: ExploreTab
            switch notificationType {
            case .match: exploreTab = .matches
            case .compliment: exploreTab = .compliments
            default: exploreTab = .likes
            }
            openExplore(tabBar, tab: exploreTab)

        case .gestureVerified, .imageVerified, .profileImageVerified:
            select(tabBar, .home)

        case .gestureUnverified:
            select(tabBar, .home)
            let vc = GestureVerificationViewController.instantiateFromStoryboard()
            vc.directRedirection = true
            vc.hidesBottomBarWhenPushed = true
            push(vc, from: viewController, tabBar: tabBar)

        case .profileImageUnverified:
            select(tabBar, .home)
            let vc = StartProfileVerificationViewController.instantiateFromStoryboard()
            vc.directRedirection = true
            vc.hidesBottomBarWhenPushed = true
            push(vc, from: viewController, tabBar: tabBar)

        case .imageUnverified, .incomplete:
            select(tabBar, .home)
            let vc: EditProfileViewController = EditProfileViewController.instantiateFromStoryboard()
            if let banner = UserDataManager.shared.saveUserInfo?.data?.userInfo?.banner {
                vc.coverImageUrl = ApiName.imgBaseURL + banner
            }
            vc.isFromNotificationVC = true
            vc.hidesBottomBarWhenPushed = true
            push(vc, from: viewController, tabBar: tabBar)

        case .membershipUpgrade:
            presenter(from: viewController, tabBar: tabBar)?.openPremium()

        case .message:
            openChat(tabBar, data: data)

        case .momentLike:
            openMoments(tabBar, momentId: stringValue(data, keys: ["momentId", "navTargetId", "entityId"]))

        case .momentComment, .momentCommentLike:
            openMoments(tabBar,
                        momentId: stringValue(data, keys: ["momentId", "navTargetId", "entityId"]),
                        sheet: .comments)

        case .momentGift:
            openMoments(tabBar,
                        momentId: stringValue(data, keys: ["momentId", "navTargetId", "entityId"]),
                        sheet: .receivedGifts)

        case .momentReaction:
            openQuickMoment(tabBar, momentId: stringValue(data, keys: ["quickMomentId", "momentId", "navTargetId", "entityId"]))

        case .profileVisit:
            openProfileVisit(tabBar, data: data)

        case .missedCall:
            presenter(from: viewController, tabBar: tabBar)?.showComingSoon("Calls")

        default:
            break
        }
    }

    private func openMoments(_ tabBar: AppTabBarController,
                             momentId: String?,
                             sheet: MomentsListViewController.NotificationSheet? = nil) {
        guard let momentsNav = tabBar.viewControllers?[Tab.moments.rawValue] as? UINavigationController else {
            tabBar.selectedIndex = Tab.moments.rawValue
            return
        }
        momentsNav.popToRootViewController(animated: false)
        if let momentId, !momentId.isEmpty,
           let momentsVC = momentsNav.viewControllers.first as? MomentsListViewController {
            momentsVC.openFromNotification(momentId: momentId, sheet: sheet)
            _ = momentsVC.view
        }
        tabBar.selectedIndex = Tab.moments.rawValue
    }

    private func openQuickMoment(_ tabBar: AppTabBarController, momentId: String?) {
        guard let profileNav = tabBar.viewControllers?[Tab.profile.rawValue] as? UINavigationController else {
            tabBar.selectedIndex = Tab.profile.rawValue
            return
        }
        profileNav.popToRootViewController(animated: false)
        tabBar.selectedIndex = Tab.profile.rawValue
        if let momentId, !momentId.isEmpty,
           let profileVC = profileNav.viewControllers.first as? ProfileViewController {
            profileVC.openFromNotification(quickMomentId: momentId)
            _ = profileVC.view
        }
    }

    private func openProfileVisit(_ tabBar: AppTabBarController, data: [AnyHashable: Any]) {
        let visitorId = stringValue(data, keys: ["visitorId", "navTargetId", "entityId", "actor_id", "senderId"])
        guard let visitorId, !visitorId.isEmpty else {
            select(tabBar, .profile)
            return
        }
        var name = stringValue(data, keys: ["visitorName", "senderName"])
        if name?.caseInsensitiveCompare("Someone") == .orderedSame {
            name = nil
        }
        select(tabBar, .home)
        guard let discoverNav = tabBar.viewControllers?[Tab.home.rawValue] as? UINavigationController,
              let presenter = discoverNav.topViewController else { return }
        OtherUserProfileRouter.open(OtherUserProfileRouter.Seed(userID: visitorId, name: name), from: presenter)
    }

    private func openExplore(_ tabBar: AppTabBarController, tab: ExploreTab) {
        guard let exploreNav = tabBar.viewControllers?[Tab.explore.rawValue] as? UINavigationController else {
            tabBar.selectedIndex = Tab.explore.rawValue
            return
        }
        exploreNav.popToRootViewController(animated: false)
        let exploreVC = exploreNav.viewControllers.first as? ExploreViewController
        exploreVC?.openFromNotification(tab)
        tabBar.selectedIndex = Tab.explore.rawValue
    }

    private func openChat(_ tabBar: AppTabBarController, data: [AnyHashable: Any]) {
        let conversationId = stringValue(data, keys: ["conversationId", "navTargetId", "entityId"])
        let senderId = stringValue(data, keys: ["senderId", "user_id", "actor_id"]) ?? ""
        let senderName = stringValue(data, keys: ["senderName", "title"]) ?? ""

        select(tabBar, .messages)
        guard let conversationId, !conversationId.isEmpty else { return }

        let navData = ChatNotificationState.buildNavigationData(
            conversationId: conversationId,
            senderId: senderId,
            senderName: senderName
        )

        guard let chatNav = tabBar.viewControllers?[Tab.messages.rawValue] as? UINavigationController,
              let container = chatNav.viewControllers.first as? ChatListContainerViewController else {
            ChatNotificationState.shared.pendingChatNavigation = navData
            return
        }
        _ = container.view
        container.openChatDetailFromNotification(navData: navData)
    }

    private func stringValue(_ data: [AnyHashable: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = data[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func select(_ tabBar: AppTabBarController, _ tab: Tab) {
        if let nav = tabBar.viewControllers?[tab.rawValue] as? UINavigationController {
            nav.popToRootViewController(animated: false)
        }
        tabBar.selectedIndex = tab.rawValue
    }

    private func push(_ viewController: UIViewController, from source: BaseViewController?, tabBar: AppTabBarController) {
        if let nav = source?.navigationController {
            nav.pushViewController(viewController, animated: true)
            return
        }
        (tabBar.selectedViewController as? UINavigationController)?
            .pushViewController(viewController, animated: true)
    }

    private func presenter(from source: BaseViewController?, tabBar: AppTabBarController) -> BaseViewController? {
        source
            ?? tabBar.selectedViewController as? BaseViewController
            ?? (tabBar.selectedViewController as? UINavigationController)?.topViewController as? BaseViewController
    }

    private func scheduleRetry() {
        retryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.consumePendingNotification()
        }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func appTabBarController() -> AppTabBarController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) {
            if let found = findTabBar(in: window.rootViewController) { return found }
        }
        return nil
    }

    private func findTabBar(in controller: UIViewController?) -> AppTabBarController? {
        guard let controller else { return nil }
        if let tab = controller as? AppTabBarController { return tab }
        if let nav = controller as? UINavigationController {
            for child in nav.viewControllers {
                if let found = findTabBar(in: child) { return found }
            }
        }
        if let tab = controller as? UITabBarController {
            for child in tab.viewControllers ?? [] {
                if let found = findTabBar(in: child) { return found }
            }
        }
        return findTabBar(in: controller.presentedViewController)
    }
}
