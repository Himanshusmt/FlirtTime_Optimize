//
//  DeviceTokenManager.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

/// Keeps FCM + PushKit VoIP tokens registered with the backend (`devices/register`).
/// Firebase wiring lives in `AppDelegate`; VoIP token updates come from `VoIPPushManager`.
final class DeviceTokenManager {

    static let shared = DeviceTokenManager()

    private static let fcmTokenKey = "fcmDeviceToken"
    private static let voipTokenKey = "voipDeviceToken"
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

    private(set) var voipToken: String? {
        get { defaults.string(forKey: Self.voipTokenKey) }
        set { defaults.set(newValue, forKey: Self.voipTokenKey) }
    }

    /// Fingerprint of the last FCM+VoIP pair accepted by the backend.
    private var registeredToken: String? {
        get { defaults.string(forKey: Self.registeredTokenKey) }
        set { defaults.set(newValue, forKey: Self.registeredTokenKey) }
    }

    private var registrationFingerprint: String {
        "\(fcmToken ?? "")|\(voipToken ?? "")"
    }

    func update(fcmToken token: String) {
        guard !token.isEmpty else { return }
        if token != fcmToken {
            fcmToken = token
            registeredToken = nil
        }
        registerIfNeeded()
    }

    func update(voipToken token: String) {
        guard !token.isEmpty else { return }
        if token != voipToken {
            voipToken = token
            registeredToken = nil
        }
        registerIfNeeded()
    }

    func clearVoIPToken() {
        voipToken = nil
        registeredToken = nil
    }

    /// OneVibe: re-upsert FCM + VoIP after login so `devices.voipToken` is not null.
    func registerPushTokensAfterLogin(reason: String) {
        AppLogger.killCall("registerPushTokensAfterLogin reason=\(reason) fcm=\(fcmToken?.count ?? 0) voip=\(voipToken?.count ?? 0)")
        registerIfNeeded(force: true)
    }

    /// Call after login and on launch with a valid session.
    func registerIfNeeded(force: Bool = false) {
        guard sessionManager.isLoggedIn else {
            if fcmToken != nil || voipToken != nil {
                AppLogger.killCall("registerDevice skip — not logged in fcm=\(fcmToken?.count ?? 0) voip=\(voipToken?.count ?? 0)")
            }
            return
        }
        guard let token = fcmToken, !token.isEmpty else {
            AppLogger.killCall("registerDevice skip — FCM empty voip=\(voipToken?.count ?? 0)")
            return
        }
        let fingerprint = registrationFingerprint
        guard force || registeredToken != fingerprint else { return }
        if voipToken == nil || voipToken?.isEmpty == true {
            AppLogger.killCall("registerDevice sending FCM without VoIP — killed-app CallKit will fail until VoIP token syncs")
        }
        sessionManager.registerDevice(token: token, voipToken: voipToken)
            .subscribe(onSuccess: { [weak self] in
                self?.registeredToken = fingerprint
                AppLogger.killCall("registerDevice OK voipSent=\(!(self?.voipToken ?? "").isEmpty)")
            }, onFailure: { error in
                AppLogger.killCall("registerDevice FAILED: \(error.localizedDescription)")
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
