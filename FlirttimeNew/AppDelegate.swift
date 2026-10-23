//
//  AppDelegate.swift
//  FlirttimeNew
//

import UIKit
import IQKeyboardManagerSwift
import GoogleMaps
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // OneVibe: PushKit + CallKit MUST be first. A killed-app VoIP wake drops the
        // push if the registry is created after Firebase / UI work.
        _ = CallKitManager.shared
        VoIPPushManager.shared.start()
        IncomingCallPushRouter.registerCallNotificationCategory()
        AppLogger.killCall(
            "didFinishLaunching — PushKit + CallKit FIRST appState=\(application.applicationState.rawValue) (0=active 1=inactive 2=background)"
        )

        IQKeyboardManager.shared.isEnabled = true
        IQKeyboardManager.shared.resignOnTouchOutside = true
        IQKeyboardManager.shared.toolbarConfiguration.tintColor = AppColor.Punch
        UITextField.appearance().tintColor = AppColor.Punch
        UITextView.appearance().tintColor = AppColor.Punch
        configureFirebasePush(application)
        startChat()
        startStore()

        // Cold start from a tapped call notification (app was killed).
        if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            DispatchQueue.main.async {
                _ = IncomingCallPushRouter.handleIncomingCallPushIfNeeded(
                    userInfo: remote,
                    source: "launchOptions"
                )
            }
        }
        return true
    }

    private func configureFirebasePush(_ application: UIApplication) {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        requestPushAuthorizationAndRegister(application)
    }

    private func requestPushAuthorizationAndRegister(_ application: UIApplication) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    DispatchQueue.main.async {
                        application.registerForRemoteNotifications()
                    }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            case .denied:
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            @unknown default:
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
    }

    private func startStore() {
        StoreManager.shared.start()
        _ = CoinWallet.shared
        CoinPackStore.shared.preload()
        SubscriptionPlanStore.shared.preload()
        PremiumViewModel.refreshMembership()
    }

    private func startChat() {
        let mapsKey = ChatConfig.googleMapsAPIKey
        if !mapsKey.isEmpty {
            GMSServices.provideAPIKey(mapsKey)
        }
        _ = CoreDataManager.shared.viewContext
        ChatSocketSessionCoordinator.shared.start()
        Task { @MainActor in
            AgoraCallService.shared.start()
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        #if DEBUG
        let apns = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs device token: \(apns)")
        #endif
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if IncomingCallPushRouter.handleIncomingCallPushIfNeeded(userInfo: userInfo, source: "remoteNotification") {
            completionHandler(.newData)
            return
        }
        completionHandler(.noData)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        ChatSocketSessionCoordinator.shared.handleApplicationWillTerminate()
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        #if DEBUG
        print("FCM Token: \(fcmToken)")
        #endif
        DeviceTokenManager.shared.update(fcmToken: fcmToken)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if IncomingCallPushRouter.handleIncomingCallPushIfNeeded(
            userInfo: notification.request.content.userInfo,
            source: "willPresent"
        ) {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if IncomingCallPushRouter.handleNotificationAction(response) {
            completionHandler()
            return
        }
        let userInfo = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            if let base = UIApplication.shared.topViewController() as? BaseViewController {
                NotificationManager.shared.handleNotification(userInfo, from: base)
            }
        }
        completionHandler()
    }
}
