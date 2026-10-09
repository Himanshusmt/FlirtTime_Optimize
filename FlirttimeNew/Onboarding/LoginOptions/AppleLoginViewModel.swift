//
//  AppleLoginViewModel.swift
//  FlirttimeNew
//

import UIKit
import RxSwift
import Swinject

/// Shared by `LoginOptionsViewController` and `LoginViewController`.
final class AppleLoginViewModel {

    private let sessionManager: AppSessionManager
    private let appleSignIn = AppleSignInManager()
    private let disposeBag = DisposeBag()

    var onLoading: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onLoggedIn: ((_ isProfileComplete: Bool) -> Void)?

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    func signIn(from window: UIWindow?) {
        appleSignIn.signIn(from: window) { [weak self] result in
            switch result {
            case .success(let credential):
                self?.login(with: credential)
            case .failure(AppleSignInError.cancelled):
                break
            case .failure(let error):
                self?.onError?(error.localizedDescription)
            }
        }
    }

    private func login(with credential: AppleCredential) {
        onLoading?(true)
        sessionManager.appleLogin(identityToken: credential.identityToken,
                                  authorizationCode: credential.authorizationCode,
                                  nonce: nil,
                                  firstName: credential.firstName,
                                  lastName: credential.lastName)
            .subscribe(onSuccess: { [weak self] json in
                self?.onLoading?(false)
                let isProfileComplete = AppJSON.bool(json, keys: ["isProfileComplete", "profileCompleted", "isOnboarded"]) ?? false
                self?.onLoggedIn?(isProfileComplete)
            }, onFailure: { [weak self] error in
                self?.onLoading?(false)
                self?.onError?(parseError(error) ?? "Something went wrong")
            })
            .disposed(by: disposeBag)
    }
}
