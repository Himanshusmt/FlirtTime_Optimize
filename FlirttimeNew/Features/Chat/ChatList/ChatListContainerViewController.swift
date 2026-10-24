//
//  ChatListContainerViewController.swift
//  FlirttimeNew
//
//  Created by Awais on 14/04/26.
//

import UIKit
import SwiftUI
import Combine
import RxSwift
import Swinject

final class ChatListContainerViewController: BaseViewController {

    let navigator = ChatListNavigator()
    var storyData: OtherStoryResponseModel?
    var selfUserStoryData: StoryResponseModel?

    private var hasPushedChatDetail = false
    private var hostingController: UIHostingController<AnyView>?
    private var inAppBanner: ChatInAppNotificationBanner?
    private var cancellables = Set<AnyCancellable>()
    private var noInternetAlertShown = false
    private let disposeBag = DisposeBag()
    private lazy var quickMomentsHost = DiscoverViewModel()
    private lazy var profileViewModel = ProfileViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addBlushBackground()

        navigator.uikitPushHandler = { [weak self] navData in
            self?.pushChatDetail(navData: navData)
        }
        navigator.onOpenCoinShop = { [weak self] in
            self?.openCoinShop()
        }
        navigator.onOpenNotifications = { [weak self] in
            self?.openNotifications()
        }
        navigator.onAddQuickMoment = { [weak self] in
            self?.openAddQuickMoment()
        }
        navigator.onOpenQuickMoment = { [weak self] item, isMine, tray in
            self?.openQuickMoments(of: item, isMine: isMine, tray: tray)
        }
        tapGesture()
        ChatMockSeeder.shared.seedIfNeeded()
        embedChatListView()
        bindInAppBanner()
        bindNetworkMonitor()
        bindOwnAvatar()
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

    private func bindOwnAvatar() {
        navigator.ownAvatarPath = UserDataManager.shared.avatarPath
        profileViewModel.$myProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                guard let url = profile?.profile?.avatarURL, !url.isEmpty else { return }
                self?.navigator.ownAvatarPath = url
            }
            .store(in: &cancellables)
        profileViewModel.getMyProfile()
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

    func openCallsFromNotification() {
        navigationController?.popToViewController(self, animated: false)
        navigator.openCalls()
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

    // MARK: - Header + Quick Moments

    private func openNotifications() {
        let notifications: NotificationViewController = NotificationViewController.instantiateFromStoryboard()
        navigationController?.pushViewController(notifications, animated: true)
    }

    private func openAddQuickMoment() {
        let composer = AddQuickMomentViewController()
        composer.onShare = { [weak self] text, background, image in
            guard let self else { return }
            self.setLoading(true)
            self.profileViewModel.createQuickMoment(text: text, background: background, image: image) { [weak self] result in
                guard let self else { return }
                self.setLoading(false)
                switch result {
                case .success:
                    self.aCustomToastView.show(message: "Quick moment shared")
                    self.quickMomentsHost.loadQuickMomentTray()
                    self.navigator.onChatDetailPopped?()
                case .failure(let error):
                    self.aCustomToastView.show(message: error.message)
                }
            }
        }
        present(composer, animated: true)
    }

    private func openQuickMoments(of item: QuickMomentTrayItem, isMine: Bool, tray: QuickMomentTray?) {
        quickMomentsHost.quickMoments(of: item, isMine: isMine) { [weak self] stories in
            guard let self else { return }
            if isMine {
                self.presentQuickMoments(stories, of: item, isMine: true, tray: tray)
                return
            }
            guard !stories.isEmpty else {
                self.aCustomToastView.show(message: "These moments have expired")
                self.quickMomentsHost.loadQuickMomentTray()
                return
            }
            self.presentQuickMoments(stories, of: item, isMine: false, tray: tray)
        }
    }

    private func presentQuickMoments(_ stories: [QuickMoment], of item: QuickMomentTrayItem, isMine: Bool, tray: QuickMomentTray?) {
        guard !stories.isEmpty else { return }
        let (pages, start) = QuickMomentViewerPage.sequence(tray: tray, selected: item, isMine: isMine)
        let pager = QuickMomentsPagerViewController(pages: pages, startIndex: start, initialStories: stories)
        pager.onLoadStories = { [weak self] page, done in
            self?.quickMomentsHost.quickMoments(of: page.item, isMine: page.isMine, completion: done)
        }
        pager.onBindViewer = { [weak self] viewer, stories, page in
            self?.bindQuickMomentViewer(viewer, stories: stories, isMine: page.isMine)
        }
        pager.onDismiss = { [weak self] in
            self?.quickMomentsHost.loadQuickMomentTray()
            self?.navigator.onChatDetailPopped?()
        }
        (navigationController ?? self).present(pager, animated: true)
    }

    private func bindQuickMomentViewer(_ viewer: QuickMomentViewController, stories: [QuickMoment], isMine: Bool) {
        if isMine {
            viewer.onShowActivity = { index, presenter in
                guard stories.indices.contains(index) else { return }
                let activity = QuickMomentActivityViewController(moment: stories[index])
                activity.modalPresentationStyle = .pageSheet
                if let sheet = activity.sheetPresentationController {
                    sheet.detents = [.medium(), .large()]
                    sheet.prefersGrabberVisible = true
                }
                presenter.present(activity, animated: true)
            }
            viewer.onDelete = { [weak self] index in
                guard stories.indices.contains(index) else { return }
                self?.quickMomentsHost.deleteQuickMoment(id: stories[index].id) { message in
                    self?.aCustomToastView.show(message: message ?? "Quick moment deleted")
                }
            }
            return
        }

        var seen = Set<String>()
        viewer.onMomentShown = { [weak self] index in
            guard stories.indices.contains(index), !stories[index].hasViewed,
                  seen.insert(stories[index].id).inserted else { return }
            self?.quickMomentsHost.markQuickMomentViewed(id: stories[index].id)
        }
        viewer.onReact = { [weak self] index, emoji in
            guard stories.indices.contains(index) else { return }
            self?.quickMomentsHost.reactToQuickMoment(id: stories[index].id, emoji: emoji) { message in
                self?.aCustomToastView.show(message: message)
            }
        }
        viewer.onReply = { [weak self] index, message in
            guard stories.indices.contains(index) else { return }
            self?.quickMomentsHost.replyToQuickMoment(id: stories[index].id, message: message) { error in
                self?.aCustomToastView.show(message: error)
            }
        }
        viewer.onViewProfile = { [weak self] profile in
            self?.dismiss(animated: true) {
                let profileVC = CardDetailViewController(profile: profile)
                profileVC.hidesBottomBarWhenPushed = true
                self?.navigationController?.pushViewController(profileVC, animated: true)
            }
        }
    }
}

