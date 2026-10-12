//
//  LoginViewModel.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject

final class LoginViewModel {

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    var onLoading: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onOTPSent: ((OTPResponse) -> Void)?

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    func requestOTP(signUpOption: SignUpOption, email: String?, countryCode: String?, phone: String?) {
        let request: Single<OTPResponse>
        switch signUpOption {
        case .email:
            request = sessionManager.requestEmailOTP(email: email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        case .phoneNumber, .apple:
            request = sessionManager.requestPhoneOTP(countryCode: countryCode ?? "", phone: phone?.replacingOccurrences(of: " ", with: "") ?? "")
        }

        onLoading?(true)
        request
            .subscribe(onSuccess: { [weak self] response in
                self?.onLoading?(false)
                guard let verificationId = response.verificationId, !verificationId.isEmpty else {
                    self?.onError?("verificationId missing in response")
                    return
                }
                self?.onOTPSent?(response)
            }, onFailure: { [weak self] error in
                self?.onLoading?(false)
                self?.onError?(parseError(error) ?? "Something went wrong")
            })
            .disposed(by: disposeBag)
    }
}
