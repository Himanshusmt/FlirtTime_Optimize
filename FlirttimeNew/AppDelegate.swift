//
//  AppDelegate.swift
//  FlirttimeNew
//
//  Created by Aasif on 07/10/26.
//

import UIKit
import IQKeyboardManagerSwift
import GoogleMaps

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        IQKeyboardManager.shared.isEnabled = true
        IQKeyboardManager.shared.resignOnTouchOutside = true
        IQKeyboardManager.shared.toolbarConfiguration.tintColor = AppColor.Punch
        UITextField.appearance().tintColor = AppColor.Punch
        UITextView.appearance().tintColor = AppColor.Punch
        startChat()
        startStore()
        return true
    }

    private func startStore() {
        StoreManager.shared.start()
        _ = CoinWallet.shared
        PremiumViewModel.refreshMembership()
    }

    private func startChat() {
        let mapsKey = ChatConfig.googleMapsAPIKey
        if !mapsKey.isEmpty {
            GMSServices.provideAPIKey(mapsKey)
        }
        _ = CallKitManager.shared
        _ = CoreDataManager.shared.viewContext
        ChatSocketSessionCoordinator.shared.start()
        Task { @MainActor in
            AgoraCallService.shared.start()
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        ChatSocketSessionCoordinator.shared.handleApplicationWillTerminate()
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
