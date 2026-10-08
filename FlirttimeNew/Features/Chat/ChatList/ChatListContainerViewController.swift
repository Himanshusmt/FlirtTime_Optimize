//
//  ChatListContainerViewController.swift
//  FlirttimeNew
//
//  Created by Awais on 14/04/26.
//

import UIKit
import SwiftUI
import Combine

final class ChatListContainerViewController: UIViewController {

    let navigator = ChatListNavigator()
    var storyData: OtherStoryResponseModel?
    var selfUserStoryData: StoryResponseModel?

    private var hasPushedChatDetail = false
    private var hostingController: UIHostingController<AnyView>?
    private var inAppBanner: ChatInAppNotificationBanner?
    private var cancellables = Set<AnyCancellable>()
    private var noInternetAlertShown = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        navigator.uikitPushHandler = { [weak self] navData in
            self?.pushChatDetail(navData: navData)
        }
        tapGesture()
        ChatMockSeeder.shared.seedIfNeeded()
        embedChatListView()
        bindInAppBanner()
        bindNetworkMonitor()
        view.enforceRTLIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        noInternetAlertShown = false
        setTabBarCenterButtonHidden(false)
        
        if hasPushedChatDetail {
            hasPushedChatDetail = false
            if let activeId = ChatNotificationState.shared.activeConversationId, !activeId.isEmpty {
                ChatSocketManager.shared.setConversationViewing(conversationId: activeId, active: false)
            }
            ChatNotificationState.shared.isShowingChatDetail = false
            ChatNotificationState.shared.activeConversationId = nil
            ChatNotificationState.shared.isInChatModule = true
            navigator.onChatDetailPopped?()
        }
        
        if !NetworkMonitor.shared.isConnected {
            showNoInternetPopup()
        }
    }
    
    func tapGesture() {
        let tapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }
    
    @objc
    func dismissKeyboard() {
        view.endEditing(true)
    }
    
    private func showNoInternetPopup() {
        guard !noInternetAlertShown,
              presentedViewController == nil else {
            return
        }
        noInternetAlertShown = true
        let alert = UIAlertController(
            title: "No Internet Connection",
            message: "Please check your internet connection and try again.",
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(
                title: "OK",
                style: .default,
                handler: { [weak self] _ in
                    self?.noInternetAlertShown = false
                }
            )
        )
        present(alert, animated: true)
    }
    
    private func bindNetworkMonitor() {

        NetworkMonitor.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in

                guard let self = self else { return }

                if !isConnected {
                    self.showNoInternetPopup()
                }
            }
            .store(in: &cancellables)
    }

    private func embedChatListView() {
        let chatListView = ChatListView(
            navigator: navigator,
            storyData: storyData,
            selfUserStoryData: selfUserStoryData
        )

        let isRTL = UIApplication.isRTL()
        let rootView = AnyView(
            chatListView.environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        )

        let hosting = UIHostingController(rootView: rootView)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hosting)
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        hostingController = hosting
    }

    /// Used by push-notification / in-app banner navigation.
    func openChatDetailFromNotification(navData: ChatNavigationData) {
        pushChatDetail(navData: navData)
    }

    private func pushChatDetail(navData: ChatNavigationData) {
        guard let navController = navigationController else { return }

        // Instagram-style: detail always sits directly above Chats list so Back → list.
        // Live call uses its own PiP window — don't raw-dismiss the call VC here.
        if navController.presentedViewController is AgoraCallViewController {
            AgoraCallService.shared.minimizeToPipIfNeeded()
        } else {
            navController.presentedViewController?.dismiss(animated: false)
        }
        navController.setViewControllers([self], animated: false)

        let detailVC = makeDetailVC(navData: navData)
        detailVC.hidesBottomBarWhenPushed = true

        hasPushedChatDetail = true
        ChatNotificationState.shared.isShowingChatDetail = true
        ChatNotificationState.shared.isInChatModule = true
        let activeId = navData.isChannel ? navData.channelId : navData.chatId
        ChatNotificationState.shared.activeConversationId = activeId.isEmpty ? nil : activeId
        setTabBarCenterButtonHidden(true)
        navController.pushViewController(detailVC, animated: true)
    }

    private func setTabBarCenterButtonHidden(_ hidden: Bool) {
        guard let appTabBarController = tabBarController as? AppTabBarController else { return }
        AppTabBarController.buttonD.isHidden = hidden
        appTabBarController.setCustomButtonHidden(hidden)
    }

    private func makeDetailVC(navData: ChatNavigationData) -> ChatDetailViewController {
        let unreadCount = navData.unreadCount
        return ChatDetailViewController.make(
            selectedId: navData.chatId,
            selectedUserChatID: navData.userChatId,
            user: navData.user,
            activeStatus: navData.activeStatus,
            isGroupChat: navData.isGroupChat,
            groupTitle: navData.groupTitle,
            groupParticipants: navData.groupParticipants,
            isGroupParticipant: navData.isGroupParticipant,
            groupAvatarUrl: navData.groupAvatarUrl,
            isChannel: navData.isChannel,
            channelId: navData.channelId,
            canSendInChannel: navData.canSendInChannel,
            isAlreadyFollowingChannel: navData.isAlreadyFollowingChannel,
            initialFollowersCount: navData.initialFollowersCount,
            initialIsBlocked: navData.initialIsBlocked,
            participantsCount: navData.participantsCount,
            storyData: storyData,
            selfUserStoryData: selfUserStoryData,
            unreadCount: unreadCount,
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        )
    }

    // MARK: - In-App Banner (Chat List Screen)

    private func bindInAppBanner() {
        ChatNotificationState.shared.$pendingBanner
            .receive(on: DispatchQueue.main)
            .sink { [weak self] banner in
                guard let self, let banner else { return }
                // Don't show banner if a chat detail is visible — let ChatDetailVC handle it
                guard !ChatNotificationState.shared.isShowingChatDetail else { return }
                ChatNotificationState.shared.pendingBanner = nil
                // self.showInAppBanner(banner)
            }
            .store(in: &cancellables)
    }

    private func showInAppBanner(_ data: InAppChatBannerData) {
        inAppBanner?.forceRemove()
        inAppBanner = nil
        let banner = ChatInAppNotificationBanner(data: data) { [weak self] bannerData in
            guard let self else { return }
            ChatNotificationState.navigateFromBanner(bannerData)
        }
        banner.show(in: view, below: nil)
        inAppBanner = banner
    }
}

