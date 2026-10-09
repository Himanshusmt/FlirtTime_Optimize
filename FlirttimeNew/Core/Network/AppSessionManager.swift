//
//  AppSessionManager.swift
//  FlirttimeNew
//

import Foundation
import RxSwift

/// One function per FlirtTime API. Calls whose response shape is not confirmed yet return `[String: Any]`.
final class AppSessionManager {

    let backendClient: AppBackendClient

    init(backendClient: AppBackendClient) {
        self.backendClient = backendClient
    }

    var isLoggedIn: Bool { AppTokenStore.shared.hasAccessToken }

    // MARK: - Health

    func checkHealth() -> Single<[String: Any]> {
        backendClient.loadJSON(request: AppApiRequest(method: .get, endPoint: .health))
    }

    // MARK: - Email OTP

    func requestEmailOTP(email: String) -> Single<OTPResponse> {
        let params: [String: Any] = ["email": email.lowercased()]
        return backendClient.load(request: AppApiRequest(method: .post, endPoint: .emailRequestOTP, parameters: params))
    }

    func verifyEmailOTP(verificationId: String, otp: String) -> Single<[String: Any]> {
        let params: [String: Any] = ["verificationId": verificationId, "otp": otp]
        return backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .emailVerifyOTP, parameters: params))
            .do(onSuccess: { [weak self] json in self?.persistAuthSession(from: json) })
    }

    func resendEmailOTP(verificationId: String) -> Single<OTPResponse> {
        let params: [String: Any] = ["verificationId": verificationId]
        return backendClient.load(request: AppApiRequest(method: .post, endPoint: .emailResendOTP, parameters: params))
    }

    // MARK: - Phone OTP

    /// `countryCode` must include the plus sign, e.g. "+91".
    func requestPhoneOTP(countryCode: String, phone: String) -> Single<OTPResponse> {
        let params: [String: Any] = ["countryCode": countryCode, "phone": phone]
        return backendClient.load(request: AppApiRequest(method: .post, endPoint: .phoneRequestOTP, parameters: params))
    }

    func verifyPhoneOTP(verificationId: String, otp: String) -> Single<[String: Any]> {
        let params: [String: Any] = ["verificationId": verificationId, "otp": otp]
        return backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .phoneVerifyOTP, parameters: params))
            .do(onSuccess: { [weak self] json in self?.persistAuthSession(from: json) })
    }

    func resendPhoneOTP(verificationId: String) -> Single<OTPResponse> {
        let params: [String: Any] = ["verificationId": verificationId]
        return backendClient.load(request: AppApiRequest(method: .post, endPoint: .phoneResendOTP, parameters: params))
    }

    // MARK: - Apple

    func appleLogin(identityToken: String,
                    authorizationCode: String?,
                    nonce: String?,
                    firstName: String?,
                    lastName: String?) -> Single<[String: Any]> {
        var params: [String: Any] = ["identityToken": identityToken]
        if let authorizationCode, !authorizationCode.isEmpty { params["authorizationCode"] = authorizationCode }
        if let nonce, !nonce.isEmpty { params["nonce"] = nonce }
        var name: [String: Any] = [:]
        if let firstName, !firstName.isEmpty { name["firstName"] = firstName }
        if let lastName, !lastName.isEmpty { name["lastName"] = lastName }
        if !name.isEmpty { params["user"] = ["name": name] }
        return backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .appleLogin, parameters: params))
            .do(onSuccess: { [weak self] json in self?.persistAuthSession(from: json) })
    }

    // MARK: - User

    func getMe() -> Single<[String: Any]> {
        backendClient.loadJSON(request: AppApiRequest(method: .get, endPoint: .me))
    }

    /// `dateOfBirth` is "yyyy-MM-dd", `gender` is "male" | "female" | "other".
    func updateProfile(firstName: String,
                       lastName: String?,
                       nickName: String,
                       dateOfBirth: String,
                       gender: String,
                       about: String) -> Single<[String: Any]> {
        var params: [String: Any] = [
            "firstName": firstName,
            "nickName": nickName,
            "dateOfBirth": dateOfBirth,
            "gender": gender,
            "about": about
        ]
        if let lastName, !lastName.isEmpty { params["lastName"] = lastName }
        return backendClient.loadJSON(request: AppApiRequest(method: .patch, endPoint: .updateProfile, parameters: params))
    }

    // MARK: - Session

    func logout() {
        AppTokenStore.shared.clear()
        UserDataManager.shared.removeUserData()
    }

    private func persistAuthSession(from json: [String: Any]) {
        guard let token = AppJSON.accessToken(in: json) else {
            print("AppSessionManager: no access token found in auth response")
            return
        }
        AppTokenStore.shared.update(accessToken: token, refreshToken: AppJSON.refreshToken(in: json))
    }
}
