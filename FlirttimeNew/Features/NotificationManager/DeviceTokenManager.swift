//
//  DeviceTokenManager.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

/// Keeps the FCM token registered with the backend (`devices/register`) for the signed-in user.
/// Firebase wiring lives in `AppDelegate` (`FirebaseApp.configure`, Messaging + APNs delegates).
final class DeviceTokenManager {

    static let shared = DeviceTokenManager()

    private static let fcmTokenKey = "fcmDeviceToken"
    private static let registeredTokenKey = "fcmRegisteredDeviceToken"

    private let defaults = UserDefaults.standard
    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    private init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    private(set) var fcmToken: String? {
        get { defaults.string(forKey: Self.fcmTokenKey) }
        set { defaults.set(newValue, forKey: Self.fcmTokenKey) }
    }

    /// The token last accepted by the backend for the current session.
    private var registeredToken: String? {
        get { defaults.string(forKey: Self.registeredTokenKey) }
        set { defaults.set(newValue, forKey: Self.registeredTokenKey) }
    }

    func update(fcmToken token: String) {
        guard !token.isEmpty else { return }
        if token != fcmToken {
            fcmToken = token
            registeredToken = nil
        }
        registerIfNeeded()
    }

    /// Call after login and on launch with a valid session.
    func registerIfNeeded(force: Bool = false) {
        guard sessionManager.isLoggedIn, let token = fcmToken, !token.isEmpty else { return }
        guard force || registeredToken != token else { return }
        sessionManager.registerDevice(token: token)
            .subscribe(onSuccess: { [weak self] in
                self?.registeredToken = token
            })
            .disposed(by: disposeBag)
    }

    /// Call on logout while the access token is still present.
    func unregister() {
        registeredToken = nil
        guard sessionManager.isLoggedIn, let token = fcmToken, !token.isEmpty else { return }
        sessionManager.unregisterDevice(token: token)
            .subscribe()
            .disposed(by: disposeBag)
    }
}
