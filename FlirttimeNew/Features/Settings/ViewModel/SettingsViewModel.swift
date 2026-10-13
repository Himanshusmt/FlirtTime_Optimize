//
//  SettingsViewModel.swift
//  FlirttimeNew
//

import Foundation

// TODO: replace the MockDataStore calls with the profile, notify-settings, change-email and delete-account endpoints.
final class SettingsViewModel {

    @Published private(set) var user: UserDetailsData?
    @Published var errorMessage: String?

    private let store = MockDataStore.shared

    var notifySettings: NotifySettings? { user?.userInfo?.notifySettings }

    func loadProfile() {
        respond { [weak self] in
            guard let self else { return }
            guard let response = self.store.currentUserResponse() else {
                self.errorMessage = "Unable to load your details"
                return
            }
            self.user = response.data
        }
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
