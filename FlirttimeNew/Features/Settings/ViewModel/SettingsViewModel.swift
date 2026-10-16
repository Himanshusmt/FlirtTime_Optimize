//
//  SettingsViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

final class SettingsViewModel {

    @Published private(set) var user: UserDetailsData?
    /// The signed-in account from `auth/me` (cached first, then refreshed).
    @Published private(set) var appUser: AppUser?
    /// `users/profile`, for the header photo and verified badge.
    @Published private(set) var myProfile: MyProfileData?
    /// Manage Notifications screen — from `GET/PATCH users/notification-settings`.
    @Published private(set) var notificationSettings: [NotificationSettingKey: Bool]?
    @Published var errorMessage: String?

    private let store = MockDataStore.shared
    private lazy var sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!
    private let disposeBag = DisposeBag()

    var notifySettings: NotifySettings? { user?.userInfo?.notifySettings }

    func loadProfile() {
        respond { [weak self] in
            guard let self else { return }
            self.user = self.store.currentUserResponse()?.data
        }
        loadAccount()
    }

    func loadAccount() {
        if appUser == nil {
            appUser = UserDataManager.shared.appUser
        }
        sessionManager.getMe()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] user in
                guard let self else { return }
                if let user { self.appUser = user }
            }, onFailure: { [weak self] error in
                guard let self, self.appUser == nil else { return }
                self.errorMessage = parseError(error) ?? "Unable to load your details"
            })
            .disposed(by: disposeBag)
        sessionManager.myProfile()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] profile in
                self?.myProfile = profile
            }, onFailure: { _ in })
            .disposed(by: disposeBag)
    }

    /// Sends only `fields` (e.g. `fullName`, `nickName`, `dateOfBirth`), then reloads the account.
    func updateProfile(_ fields: [String: Any], completion: @escaping (Bool) -> Void) {
        let sessionManager = self.sessionManager
        sessionManager.updateProfileFields(fields)
            .flatMap { sessionManager.getMe() }
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] user in
                if let user { self?.appUser = user }
                completion(true)
            }, onFailure: { [weak self] error in
                self?.errorMessage = parseError(error) ?? "Unable to save your changes"
                completion(false)
            })
            .disposed(by: disposeBag)
    }

    func loadNotificationSettings() {
        sessionManager.getNotificationSettings()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] dto in
                self?.notificationSettings = dto.asSwitchMap
            }, onFailure: { [weak self] error in
                self?.errorMessage = parseError(error) ?? "Unable to load notification settings"
                if self?.notificationSettings == nil {
                    self?.notificationSettings = Dictionary(
                        uniqueKeysWithValues: NotificationSettingKey.managedKeys.map { ($0, $0.defaultValue) }
                    )
                }
            })
            .disposed(by: disposeBag)
    }

    func updateNotificationSettings(_ settings: [NotificationSettingKey: Bool]) {
        let previous = notificationSettings
        notificationSettings = settings
        let dto = NotificationSettingsDTO(from: settings)
        sessionManager.updateNotificationSettings(dto)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] updated in
                self?.notificationSettings = updated.asSwitchMap
            }, onFailure: { [weak self] error in
                self?.notificationSettings = previous
                self?.errorMessage = parseError(error) ?? "Unable to save notification settings"
            })
            .disposed(by: disposeBag)
    }

    func updateVisibility(_ key: VisibilitySettingKey, isOn: Bool) {
        store.updateUser(with: [key.rawValue: isOn])
        user = store.currentUserResponse()?.data
    }

    // MARK: - Change email / phone

    enum ContactKind { case email, phone }

    private var contactVerificationId: String?

    /// Sends a code to the new email, or to `countryCode` + `value` for a phone. Returns the resend delay in seconds.
    func requestContactCode(kind: ContactKind, value: String, countryCode: String? = nil,
                            completion: @escaping (Result<Int?, MomentsError>) -> Void) {
        let request: Single<OTPResponse>
        switch kind {
        case .email: request = sessionManager.requestProfileEmailOTP(email: value)
        case .phone: request = sessionManager.requestProfilePhoneOTP(countryCode: countryCode ?? "", phone: value)
        }
        handleCode(request, completion: completion) { error in
            guard let httpError = error as? APIHTTPError,
                  httpError.statusCode == 409 || httpError.code?.hasSuffix("ALREADY_IN_USE") == true else { return nil }
            return kind == .email ? "Email already in use" : "Phone number already in use"
        }
    }

    func resendContactCode(kind: ContactKind, completion: @escaping (Result<Int?, MomentsError>) -> Void) {
        guard let verificationId = contactVerificationId else {
            completion(.failure(MomentsError(message: "Please request a new code.")))
            return
        }
        let request: Single<OTPResponse>
        switch kind {
        case .email: request = sessionManager.resendProfileEmailOTP(verificationId: verificationId)
        case .phone: request = sessionManager.resendProfilePhoneOTP(verificationId: verificationId)
        }
        handleCode(request, completion: completion)
    }

    func verifyContactCode(kind: ContactKind, code: String, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        guard let verificationId = contactVerificationId else {
            completion(.failure(MomentsError(message: "Please request a new code.")))
            return
        }
        let sessionManager = self.sessionManager
        let verify: Single<Void>
        switch kind {
        case .email: verify = sessionManager.verifyProfileEmailOTP(verificationId: verificationId, otp: code)
        case .phone: verify = sessionManager.verifyProfilePhoneOTP(verificationId: verificationId, otp: code)
        }
        verify
            .flatMap { sessionManager.getMe().catchAndReturn(nil) }
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] user in
                if let user { self?.appUser = user }
                self?.contactVerificationId = nil
                completion(.success(()))
            }, onFailure: { error in
                completion(.failure(MomentsError(message: parseError(error) ?? "That code doesn't look right. Please try again.")))
            })
            .disposed(by: disposeBag)
    }

    private func handleCode(_ request: Single<OTPResponse>,
                            completion: @escaping (Result<Int?, MomentsError>) -> Void,
                            title: @escaping (Error) -> String? = { _ in nil }) {
        request
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] response in
                if let id = response.verificationId, !id.isEmpty { self?.contactVerificationId = id }
                completion(.success(response.resendAfter))
            }, onFailure: { error in
                completion(.failure(MomentsError(message: parseError(error) ?? "Couldn't send the code. Please try again.",
                                                 title: title(error))))
            })
            .disposed(by: disposeBag)
    }

    /// Deletes the account on the server. `completion(true)` only on success so the UI can leave the screen.
    func deleteAccount(completion: @escaping (Bool) -> Void) {
        sessionManager.deleteAccount()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { _ in
                completion(true)
            }, onFailure: { [weak self] error in
                self?.errorMessage = parseError(error) ?? "Unable to delete your account. Please try again."
                completion(false)
            })
            .disposed(by: disposeBag)
    }

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }
}
