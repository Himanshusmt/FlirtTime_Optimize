//
//  AppSessionManager.swift
//  FlirttimeNew
//

import Alamofire
import Foundation
import RxSwift

/// One function per FlirtTime API.
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

    func verifyEmailOTP(verificationId: String, otp: String) -> Single<AuthResponse> {
        let params: [String: Any] = ["verificationId": verificationId, "otp": otp]
        return authenticate(AppApiRequest(method: .post, endPoint: .emailVerifyOTP, parameters: params))
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

    func verifyPhoneOTP(verificationId: String, otp: String) -> Single<AuthResponse> {
        let params: [String: Any] = ["verificationId": verificationId, "otp": otp]
        return authenticate(AppApiRequest(method: .post, endPoint: .phoneVerifyOTP, parameters: params))
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
                    lastName: String?) -> Single<AuthResponse> {
        var params: [String: Any] = ["identityToken": identityToken]
        if let authorizationCode, !authorizationCode.isEmpty { params["authorizationCode"] = authorizationCode }
        if let nonce, !nonce.isEmpty { params["nonce"] = nonce }
        var name: [String: Any] = [:]
        if let firstName, !firstName.isEmpty { name["firstName"] = firstName }
        if let lastName, !lastName.isEmpty { name["lastName"] = lastName }
        if !name.isEmpty { params["user"] = ["name": name] }
        return authenticate(AppApiRequest(method: .post, endPoint: .appleLogin, parameters: params))
    }

    // MARK: - User

    func getMe() -> Single<AppUser?> {
        let request: Single<MeResponse> = backendClient.load(request: AppApiRequest(method: .get, endPoint: .me))
        return request.map { $0.user }
    }

    /// `dateOfBirth` is "yyyy-MM-dd", `gender` is "male" | "female" | "non-binary" | "other".
    /// The backend requires `fullName`.
    func updateProfile(fullName: String,
                       nickName: String,
                       dateOfBirth: String,
                       gender: String,
                       about: String) -> Single<AppUser> {
        let params: [String: Any] = [
            "fullName": fullName,
            "nickName": nickName,
            "dateOfBirth": dateOfBirth,
            "gender": gender,
            "about": about
        ]
        return backendClient.load(request: AppApiRequest(method: .patch, endPoint: .updateProfile, parameters: params))
    }

    // MARK: - Verification

    /// Stores the photo and makes it the user's primary profile photo. Max 5 MB.
    func uploadProfilePhoto(imageData: Data) -> Single<ProfilePhotoUpload> {
        let file = AppMultipartFile(name: "profilePhoto", fileName: "profile.jpg", mimeType: "image/jpeg", data: imageData)
        return backendClient.upload(endPoint: .profilePhotoUpload, fields: [:], files: [file])
    }

    /// The backend compares the selfie against the user's primary profile photo. Max 5 MB.
    func uploadGestureSelfie(imageData: Data) -> Single<GestureVerification> {
        let file = AppMultipartFile(name: "selfie_image", fileName: "selfie.jpg", mimeType: "image/jpeg", data: imageData)
        return backendClient.upload(endPoint: .gestureUpload,
                                    fields: ["verification_type": "gesture"],
                                    files: [file])
    }

    // MARK: - Discover

    /// `interestId` narrows the feed to people with that interest without changing the user's own interests.
    func discoveryPeople(page: Int, limit: Int, interestId: String? = nil) -> Single<DiscoveryPeopleResponse> {
        var params: [String: Any] = ["page": page, "limit": limit]
        if let interestId, !interestId.isEmpty { params["interestId"] = interestId }
        return backendClient.load(request: AppApiRequest(method: .get, endPoint: .discoveryPeople,
                                                         parameters: params, encoding: URLEncoding.queryString))
    }

    /// `action` is "like", "nope" or "super_like".
    func discoveryAction(targetUserId: String, action: String) -> Single<DiscoveryActionResult> {
        let params: [String: Any] = ["targetUserId": targetUserId, "action": action]
        return backendClient.load(request: AppApiRequest(method: .post, endPoint: .discoveryAction, parameters: params))
    }

    // MARK: - Other users

    func otherUserProfile(userId: String) -> Single<OtherUserProfile> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .userProfile(userId: userId)))
    }

    func blockUser(userId: String, reason: String) -> Single<UserBlockResult> {
        backendClient.load(request: AppApiRequest(method: .post, endPoint: .blockUser(userId: userId),
                                                  parameters: ["reason": reason]))
    }

    /// `reason` is one of the API codes: fake_profile, harassment, inappropriate_content, spam, scam, underage, other.
    func reportUser(userId: String, reason: String, description: String? = nil) -> Single<Void> {
        var params: [String: Any] = ["reason": reason]
        if let description, !description.isEmpty { params["description"] = description }
        return backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .reportUser(userId: userId),
                                                             parameters: params))
            .map { _ in () }
    }

    // MARK: - Session

    func logout() {
        AppTokenStore.shared.clear()
        UserDataManager.shared.removeUserData()
    }

    /// Decodes an auth response and stores its token.
    private func authenticate(_ request: AppApiRequest) -> Single<AuthResponse> {
        let response: Single<AuthResponse> = backendClient.load(request: request)
        return response.map { auth in
            guard let token = auth.token, !token.isEmpty else {
                throw APIHTTPError(statusCode: 0, message: "Login failed. Please try again.")
            }
            AppTokenStore.shared.update(accessToken: token, refreshToken: auth.refreshToken)
            return auth
        }
    }
}
