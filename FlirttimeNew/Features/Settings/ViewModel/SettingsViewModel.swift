//
//  SettingsViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

// TODO: replace the MockDataStore calls with the notify-settings, change-email and delete-account endpoints.
final class SettingsViewModel {

    @Published private(set) var user: UserDetailsData?
    /// The signed-in account from `auth/me` (cached first, then refreshed).
    @Published private(set) var appUser: AppUser?
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
    }

    /// The backend requires the full body on every PATCH, so the other fields are sent back unchanged.
    func updateFullName(_ name: String, completion: @escaping (Bool) -> Void) {
        let current = appUser ?? UserDataManager.shared.appUser
        var params: [String: Any] = [
            "fullName": name,
            "nickName": current?.nickName ?? current?.username ?? ""
        ]
        if let dateOfBirth = current?.dateOfBirth { params["dateOfBirth"] = String(dateOfBirth.prefix(10)) }
        if let gender = current?.gender { params["gender"] = gender }
        if let about = current?.about { params["about"] = about }

        let sessionManager = self.sessionManager
        sessionManager.updateProfileFields(params)
            .flatMap { sessionManager.getMe() }
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] user in
                if let user { self?.appUser = user }
                completion(true)
            }, onFailure: { [weak self] error in
                self?.errorMessage = parseError(error) ?? "Unable to update your name"
                completion(false)
            })
            .disposed(by: disposeBag)
    }

    func updateNotificationSettings(_ settings: [NotificationSettingKey: Bool]) {
        let payload = Dictionary(uniqueKeysWithValues: settings.map { ($0.key.rawValue, $0.value) })
        store.updateUser(with: ["notify_settings": payload])
        user = store.currentUserResponse()?.data
    }

    func updateVisibility(_ key: VisibilitySettingKey, isOn: Bool) {
        store.updateUser(with: [key.rawValue: isOn])
        user = store.currentUserResponse()?.data
    }

    func requestEmailChangeCode(for email: String, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        respond {
            completion(.success(()))
        }
    }

    func verifyEmailChange(email: String, code: String, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        respond { [weak self] in
            guard let self else { return }
            guard code.count == ChangeEmailViewController.codeLength, code.allSatisfy(\.isNumber) else {
                completion(.failure(MomentsError(message: "That code doesn't look right. Please try again.")))
                return
            }
            self.store.updateUser(with: ["email": email])
            self.user = self.store.currentUserResponse()?.data
            completion(.success(()))
        }
    }

    func deleteAccount(completion: @escaping () -> Void) {
        respond(completion)
    }

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }
}
