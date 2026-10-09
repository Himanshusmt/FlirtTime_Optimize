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

    /// Matches `FlirtCustomPopUp.genderOptions` ids.
    static func genderValue(for genderID: Int?) -> String {
        switch genderID {
        case 1: return "male"
        case 2: return "female"
        default: return "other"
        }
    }

    func updateProfile(firstName: String,
                       lastName: String?,
                       nickName: String,
                       dateOfBirth: Date?,
                       genderID: Int?,
                       about: String) {
        guard let dateOfBirth else {
            onError?("Please select your date of birth")
            return
        }

        onLoading?(true)
        sessionManager.updateProfile(firstName: firstName,
                                     lastName: lastName,
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
