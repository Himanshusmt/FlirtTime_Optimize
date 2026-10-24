//
//  UserDetailsViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

final class UserDetailsViewModel {

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    var onLoading: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onProfileUpdated: (() -> Void)?
    var onUsernameResult: ((_ available: Bool, _ message: String?) -> Void)?
    private var lastRequestedUsername: String?

    private static let dobFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    func checkUsername(_ username: String) {
        lastRequestedUsername = username
        sessionManager.checkUsernameAvailability(username: username)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] available in
                guard let self, self.lastRequestedUsername == username else { return }
                self.onUsernameResult?(available, available ? nil : Constants.UserDetails.usernameTaken)
            }, onFailure: { [weak self] error in
                guard let self, self.lastRequestedUsername == username else { return }
                self.onUsernameResult?(false, parseError(error) ?? "Unable to check display name")
            })
            .disposed(by: disposeBag)
    }

    /// Matches `FlirtCustomPopUp.genderOptions` ids.
    static func genderValue(for genderID: Int?) -> String {
        switch genderID {
        case 1: return "male"
        case 2: return "female"
        default: return "other"
        }
    }

    func updateProfile(fullName: String,
                       nickName: String,
                       dateOfBirth: Date?,
                       genderID: Int?,
                       about: String) {
        guard let dateOfBirth else {
            onError?("Please select your date of birth")
            return
        }

        onLoading?(true)
        sessionManager.updateProfile(fullName: fullName,
                                     nickName: nickName,
                                     dateOfBirth: Self.dobFormatter.string(from: dateOfBirth),
                                     gender: Self.genderValue(for: genderID),
                                     about: about)
            .subscribe(onSuccess: { [weak self] _ in
                self?.onLoading?(false)
                self?.onProfileUpdated?()
            }, onFailure: { [weak self] error in
                self?.onLoading?(false)
                self?.onError?(parseError(error) ?? "Something went wrong")
            })
            .disposed(by: disposeBag)
    }
}
