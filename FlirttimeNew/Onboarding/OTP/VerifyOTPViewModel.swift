//
//  VerifyOTPViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

final class VerifyOTPViewModel {

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    var signUpOption: SignUpOption = .phoneNumber
    var verificationId = ""

    var onLoading: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onWrongOTP: ((String) -> Void)?
    var onVerified: ((_ isProfileComplete: Bool) -> Void)?
    var onResent: ((_ resendAfter: Int?) -> Void)?

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    func verify(otp: String) {
        let request = signUpOption == .email
            ? sessionManager.verifyEmailOTP(verificationId: verificationId, otp: otp)
            : sessionManager.verifyPhoneOTP(verificationId: verificationId, otp: otp)

        onLoading?(true)
        request
            .subscribe(onSuccess: { [weak self] json in
                self?.onLoading?(false)
                let isProfileComplete = AppJSON.bool(json, keys: ["isProfileComplete", "profileCompleted", "isOnboarded"]) ?? false
                self?.onVerified?(isProfileComplete)
            }, onFailure: { [weak self] error in
                self?.onLoading?(false)
                let message = parseError(error) ?? "Something went wrong"
                if let code = httpStatusCode(from: error), (400..<500).contains(code) {
                    self?.onWrongOTP?(message)
                } else {
                    self?.onError?(message)
                }
            })
            .disposed(by: disposeBag)
    }

    func resend() {
        let request = signUpOption == .email
            ? sessionManager.resendEmailOTP(verificationId: verificationId)
            : sessionManager.resendPhoneOTP(verificationId: verificationId)

        onLoading?(true)
        request
            .subscribe(onSuccess: { [weak self] response in
                self?.onLoading?(false)
                if let newId = response.verificationId, !newId.isEmpty {
                    self?.verificationId = newId
                }
                self?.onResent?(response.resendAfter)
            }, onFailure: { [weak self] error in
                self?.onLoading?(false)
                self?.onError?(parseError(error) ?? "Something went wrong")
            })
            .disposed(by: disposeBag)
    }
}
