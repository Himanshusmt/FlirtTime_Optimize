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
        return request.map { response in
            if let user = response.user { UserDataManager.shared.appUser = user }
            return response.user
        }
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

    // MARK: - Media (S3)

    /// `folder` is "moments" | "photos" | "quick-moments" | "avatars".
    func presignedUpload(folder: String, mimeType: String = "image/jpeg") -> Single<PresignedUpload> {
        backendClient.load(request: AppApiRequest(method: .post, endPoint: .mediaPresignedURL,
                                                  parameters: ["folder": folder, "mimeType": mimeType]))
    }

    /// Gets a presigned URL and PUTs the JPEG straight to S3. The backend saves the returned key.
    func uploadImageToS3(_ data: Data, folder: String) -> Single<PresignedUpload> {
        let mimeType = "image/jpeg"
        return presignedUpload(folder: folder, mimeType: mimeType)
            .flatMap { upload -> Single<PresignedUpload> in
                guard let uploadUrl = upload.uploadUrl, !uploadUrl.isEmpty,
                      upload.resolvedKey != nil || upload.publicUrl?.isEmpty == false else {
                    return .error(APIError.apiError("Couldn't start the photo upload"))
                }
                return S3MediaUploader.put(data: data, to: uploadUrl, contentType: mimeType).map { upload }
            }
    }

    /// Makes an uploaded S3 photo (folder "photos") the main profile photo.
    func setProfilePhoto(imageKey: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .profilePhotoUpload,
                                                      parameters: ["imageKey": imageKey]))
            .map { _ in () }
    }

    /// Adds an uploaded S3 photo (folder "photos") to the profile gallery.
    func addGalleryPhoto(imageKey: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .onboardingPhotos,
                                                      parameters: ["imageKey": imageKey]))
            .map { _ in () }
    }

    // MARK: - Discover

    /// `interestId` narrows the feed to people with that interest without changing the user's own interests.
    func discoveryPeople(page: Int, limit: Int, interestId: String? = nil) -> Single<DiscoveryPeopleResponse> {
        var params: [String: Any] = ["page": page, "limit": limit]
        if let interestId, !interestId.isEmpty { params["interestId"] = interestId }
        return backendClient.load(request: AppApiRequest(method: .get, endPoint: .discoveryPeople,
                                                         parameters: params, encoding: URLEncoding.queryString))
    }

    /// Active interests, A to Z.
    func interestsCatalog() -> Single<[InterestCatalogItem]> {
        let request: Single<InterestsCatalogData> = backendClient.load(request: AppApiRequest(method: .get, endPoint: .interestsCatalog))
        return request.map { data in
            data.interests
                .filter { $0.isActive != false }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    /// Sends a connection request with an optional "Connect because…" reason.
    func sendConnectionRequest(targetUserId: String, reason: String?) -> Single<ConnectionRequestResult> {
        var params: [String: Any] = ["targetUserId": targetUserId]
        if let reason, !reason.isEmpty { params["reason"] = reason }
        return backendClient.load(request: AppApiRequest(method: .post, endPoint: .connectionRequest, parameters: params))
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

    // MARK: - Moments

    func momentsFeed(page: Int, limit: Int) -> Single<MomentFeedPage> {
        let params: [String: Any] = ["page": page, "limit": limit, "type": "feed"]
        let request: Single<MomentFeedData> = backendClient.load(request: AppApiRequest(method: .get, endPoint: .moments,
                                                                                        parameters: params, encoding: URLEncoding.queryString))
        return request.map { $0.page() }
    }

    /// The signed-in user's own moments; they're shown with the user's own name and photo.
    func myMoments(page: Int, limit: Int) -> Single<MomentFeedPage> {
        let params: [String: Any] = ["page": page, "limit": limit]
        let request: Single<MomentFeedData> = backendClient.load(request: AppApiRequest(method: .get, endPoint: .myMoments,
                                                                                        parameters: params, encoding: URLEncoding.queryString))
        return request.map { $0.page(fallbackAuthor: .currentUser) }
    }

    /// `imageKeys` are 1 to 5 S3 keys from `media/presigned-url`, in display order. The backend
    /// returns the full `imageUrl` / `thumbnailUrl`. Caption max 500 characters, `location` max 100.
    /// `audience` is "everyone" | "matches_only" | "close_friends".
    /// Returns `nil` when the backend doesn't send the created moment back.
    func createMoment(caption: String, audience: String = "everyone", location: String? = nil,
                      imageKeys: [String]) -> Single<Vibe?> {
        var params: [String: Any] = ["caption": caption, "audience": audience]
        if imageKeys.count == 1 {
            params["imageKey"] = imageKeys[0]
        } else {
            params["imageKeys"] = imageKeys
        }
        if let location, !location.isEmpty { params["location"] = ["name": location] }
        return backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .moments, parameters: params))
            .map { json in
                guard let data = json["data"],
                      let body = try? JSONSerialization.data(withJSONObject: data),
                      let created = try? JSONDecoder().decode(MomentCreateData.self, from: body) else { return nil }
                return created.moment?.vibe(fallbackAuthor: .currentUser)
            }
    }

    /// Sets the like explicitly (not a toggle) so quick double taps can't flip it the wrong way.
    /// `data` carries the server's `isLiked` and `likesCount`.
    func likeMoment(momentId: String, isLiked: Bool) -> Single<[String: Any]> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .momentLike(momentId: momentId),
                                                      parameters: ["isLiked": isLiked]))
    }

    /// `limit` max 100.
    func momentComments(momentId: String, page: Int, limit: Int) -> Single<MomentCommentsData> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .momentComments(momentId: momentId),
                                                  parameters: ["page": page, "limit": limit], encoding: URLEncoding.queryString))
    }

    func commentOnMoment(momentId: String, comment: String) -> Single<[String: Any]> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .momentComments(momentId: momentId),
                                                      parameters: ["comment": comment]))
    }

    /// People who liked the moment; `limit` max 100.
    func momentLikes(momentId: String, page: Int, limit: Int) -> Single<MomentLikesData> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .momentLikes(momentId: momentId),
                                                  parameters: ["page": page, "limit": limit], encoding: URLEncoding.queryString))
    }

    // MARK: - Moment gifts

    /// Gift options for the "Send a gift" sheet plus the signed-in user's coin balance.
    func momentGiftCatalog(momentId: String) -> Single<MomentGiftsData> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .momentGifts(momentId: momentId)))
    }

    /// Deducts the sender's coins. `data` may be empty, so it's decoded leniently.
    func sendMomentGift(momentId: String, giftCode: String, quantity: Int = 1, message: String? = nil) -> Single<MomentGiftSendData?> {
        var params: [String: Any] = ["giftCode": giftCode, "quantity": quantity]
        if let message, !message.isEmpty { params["message"] = message }
        return backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .momentGifts(momentId: momentId), parameters: params))
            .map { json in
                guard let data = json["data"] as? [String: Any],
                      let body = try? JSONSerialization.data(withJSONObject: data) else { return nil }
                return try? JSONDecoder().decode(MomentGiftSendData.self, from: body)
            }
    }

    func momentReceivedGifts(momentId: String, page: Int, limit: Int) -> Single<MomentReceivedGiftsPage> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .momentGiftsReceived(momentId: momentId),
                                                  parameters: ["page": page, "limit": limit], encoding: URLEncoding.queryString))
    }

    /// `reason` is one of the API codes: spam, inappropriate_content, harassment, hate_speech, fake_profile, other.
    func reportMoment(momentId: String, reason: String, description: String? = nil) -> Single<Void> {
        var params: [String: Any] = ["reason": reason]
        if let description, !description.isEmpty { params["description"] = description }
        return backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .momentReport(momentId: momentId),
                                                             parameters: params))
            .map { _ in () }
    }

    /// Deletes one of the signed-in user's own moments.
    func deleteMoment(momentId: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .delete, endPoint: .moment(momentId: momentId)))
            .map { _ in () }
    }

    /// Deletes one of the signed-in user's own comments on a moment.
    func deleteMomentComment(momentId: String, commentId: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .delete,
                                                      endPoint: .momentComment(momentId: momentId, commentId: commentId)))
            .map { _ in () }
    }

    // MARK: - Quick Moments

    /// Story bar: the user's own bubble plus other users' active stories with unread state.
    func quickMomentsTray() -> Single<QuickMomentTray> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .quickMomentsTray))
    }

    /// The signed-in user's active (under 24h) Quick Moments.
    func myQuickMoments() -> Single<[QuickMoment]> {
        let request: Single<QMList<QuickMoment>> = backendClient.load(request: AppApiRequest(method: .get, endPoint: .myQuickMoments))
        return request.map(\.items)
    }

    func userQuickMoments(userId: String) -> Single<[QuickMoment]> {
        let request: Single<QMList<QuickMoment>> = backendClient.load(request: AppApiRequest(method: .get,
                                                                                             endPoint: .userQuickMoments(userId: userId)))
        return request.map(\.items)
    }

    /// `backgroundColor` / `textColor` are hex like "#2d0b1e". Returns `nil` when the backend
    /// doesn't send the created Quick Moment back.
    func createTextQuickMoment(text: String, backgroundColor: String, textColor: String) -> Single<QuickMoment?> {
        createQuickMoment(["type": "text", "text": text, "backgroundColor": backgroundColor, "textColor": textColor])
    }

    /// Gets a Quick Moment presigned URL and PUTs the JPEG straight to S3.
    func uploadQuickMomentImage(_ data: Data) -> Single<PresignedUpload> {
        let mimeType = "image/jpeg"
        let presign: Single<PresignedUpload> = backendClient.load(request: AppApiRequest(
            method: .post, endPoint: .quickMomentUploadURL,
            parameters: ["mimeType": mimeType, "folder": "quick_moments"]))
        return presign.flatMap { upload -> Single<PresignedUpload> in
            guard let uploadUrl = upload.uploadUrl, !uploadUrl.isEmpty, upload.resolvedKey != nil else {
                return .error(APIError.apiError("Couldn't start the photo upload"))
            }
            return S3MediaUploader.put(data: data, to: uploadUrl, contentType: mimeType).map { upload }
        }
    }

    /// `imageKey` is the S3 key from `uploadQuickMomentImage`.
    func createImageQuickMoment(imageKey: String, caption: String?, locationLabel: String? = nil) -> Single<QuickMoment?> {
        var params: [String: Any] = ["imageKey": imageKey]
        if let caption, !caption.isEmpty { params["caption"] = caption }
        if let locationLabel, !locationLabel.isEmpty { params["locationLabel"] = locationLabel }
        return createQuickMoment(params)
    }

    private func createQuickMoment(_ params: [String: Any]) -> Single<QuickMoment?> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .quickMoments, parameters: params))
            .map { json in
                guard let data = json["data"],
                      let body = try? JSONSerialization.data(withJSONObject: data),
                      let created = try? JSONDecoder().decode(QuickMomentCreateData.self, from: body) else { return nil }
                return created.moment
            }
    }

    func deleteQuickMoment(momentId: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .delete, endPoint: .quickMoment(momentId: momentId)))
            .map { _ in () }
    }

    func quickMomentReactions(momentId: String, page: Int = 1, limit: Int = 50) -> Single<QuickMomentReactionsPage> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .quickMomentReactions(momentId: momentId),
                                                  parameters: ["page": page, "limit": limit], encoding: URLEncoding.queryString))
    }

    /// Story author only.
    func quickMomentViewers(momentId: String) -> Single<[QuickMomentViewer]> {
        let request: Single<QMList<QuickMomentViewer>> = backendClient.load(request: AppApiRequest(
            method: .get, endPoint: .quickMomentViewers(momentId: momentId)))
        return request.map(\.items)
    }

    /// `emoji` is one of 😍 🔥 😂 😮 👏 ❤️. Sending the same emoji again removes the reaction.
    func reactToQuickMoment(momentId: String, emoji: String) -> Single<[String: Any]> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .quickMomentReact(momentId: momentId),
                                                      parameters: ["emoji": emoji]))
    }

    func replyToQuickMoment(momentId: String, message: String) -> Single<[String: Any]> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .quickMomentReply(momentId: momentId),
                                                      parameters: ["message": message]))
    }

    /// Marks the story as seen, which greys out its ring in the tray.
    func markQuickMomentViewed(momentId: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .quickMomentView(momentId: momentId)))
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
            if let user = auth.user { UserDataManager.shared.appUser = user }
            return auth
        }
    }
}
