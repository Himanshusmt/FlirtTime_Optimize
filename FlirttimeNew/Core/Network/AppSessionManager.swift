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
            if let user = response.user {
                UserDataManager.shared.appUser = user
                UserDataManager.shared.applySubscriptionStatus(user.isSubscribed)
            }
            return response.user
        }
    }

    /// Everything the My Profile screen shows except moments and quick moments, which have their own calls.
    func myProfile() -> Single<MyProfileData> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .myProfile))
            .do(onSuccess: { data in
                UserDataManager.shared.applySubscriptionStatus(data.isSubscribed)
            })
    }

    /// `audio` is an AAC `.m4a` file up to 10 MB; `duration` is in whole seconds (max 60).
    /// Returns `nil` when the response carries no playable URL.
    func uploadVoiceIntro(audio: Data, duration: Int) -> Single<UserVoiceIntro?> {
        let file = AppMultipartFile(name: "audio", fileName: "voice_intro.m4a", mimeType: "audio/x-m4a", data: audio)
        return backendClient.uploadJSON(endPoint: .voiceIntro, fields: ["duration": "\(duration)"], files: [file])
            .map { UserVoiceIntro(json: $0) }
    }

    func voiceIntro() -> Single<UserVoiceIntro?> {
        backendClient.loadJSON(request: AppApiRequest(method: .get, endPoint: .voiceIntro))
            .map { UserVoiceIntro(json: $0) }
    }

    func deleteVoiceIntro() -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .delete, endPoint: .voiceIntro)).map { _ in () }
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

    // MARK: - Edit Profile

    /// Raw `users/profile` body; Edit Profile needs fields (photo ids, moreAboutMe) the typed model skips.
    func myProfileJSON() -> Single<[String: Any]> {
        backendClient.loadJSON(request: AppApiRequest(method: .get, endPoint: .myProfile))
    }

    /// Pass only the fields that change. `dateOfBirth` must be "yyyy-MM-dd" and 18+.
    ///
    /// The server requires the whole profile on every PATCH, so the current `fullName`, `username`,
    /// `dateOfBirth`, `gender` and `about` from `auth/me` are always sent, with `params` on top
    /// (e.g. `location`, `latitude`, `longitude`).
    func updateProfileFields(_ params: [String: Any]) -> Single<Void> {
        let backendClient = self.backendClient
        return getMe()
            .catchAndReturn(UserDataManager.shared.appUser)
            .flatMap { user -> Single<Void> in
                var body = Self.requiredProfileFields(from: user)
                body.merge(params) { _, new in new }
                return backendClient.loadJSON(request: AppApiRequest(method: .patch, endPoint: .updateProfile, parameters: body))
                    .map { _ in () }
            }
    }

    private static func requiredProfileFields(from user: AppUser?) -> [String: Any] {
        func text(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        let nameParts = [user?.firstName, user?.lastName].compactMap(text)
        let fullName = text(user?.fullName) ?? (nameParts.isEmpty ? nil : nameParts.joined(separator: " "))
        var fields: [String: Any] = [:]
        fields["fullName"] = fullName
        fields["username"] = text(user?.username) ?? text(user?.nickName)
        fields["dateOfBirth"] = text(user?.dateOfBirth).map { String($0.prefix(10)) }
        fields["gender"] = text(user?.gender)
        fields["about"] = text(user?.about)
        return fields
    }

    /// Uploads the cover to S3, then saves its key as `coverPicture`. Returns the image URL.
    func updateCoverPicture(imageData: Data) -> Single<String> {
        uploadImageToS3(imageData, folder: "uploads")
            .flatMap { [weak self] upload -> Single<String> in
                guard let self else { return .error(APIError.apiError("Cover photo upload failed")) }
                guard let key = upload.resolvedKey ?? upload.publicUrl else {
                    return .error(APIError.apiError("Couldn't start the photo upload"))
                }
                return self.updateProfileFields(["coverPicture": key]).map { upload.publicUrl ?? key }
            }
    }

    // MARK: - Change email / phone (logged in)

    func requestProfileEmailOTP(email: String) -> Single<OTPResponse> {
        backendClient.load(request: AppApiRequest(method: .post, endPoint: .profileEmailRequestOTP,
                                                  parameters: ["email": email.lowercased()]))
    }

    func verifyProfileEmailOTP(verificationId: String, otp: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .profileEmailVerifyOTP,
                                                      parameters: ["verificationId": verificationId, "otp": otp]))
            .map { _ in () }
    }

    func resendProfileEmailOTP(verificationId: String) -> Single<OTPResponse> {
        backendClient.load(request: AppApiRequest(method: .post, endPoint: .profileEmailResendOTP,
                                                  parameters: ["verificationId": verificationId]))
    }

    /// `countryCode` must include the plus sign, e.g. "+91".
    func requestProfilePhoneOTP(countryCode: String, phone: String) -> Single<OTPResponse> {
        backendClient.load(request: AppApiRequest(method: .post, endPoint: .profilePhoneRequestOTP,
                                                  parameters: ["countryCode": countryCode, "phone": phone]))
    }

    func verifyProfilePhoneOTP(verificationId: String, otp: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .profilePhoneVerifyOTP,
                                                      parameters: ["verificationId": verificationId, "otp": otp]))
            .map { _ in () }
    }

    func resendProfilePhoneOTP(verificationId: String) -> Single<OTPResponse> {
        backendClient.load(request: AppApiRequest(method: .post, endPoint: .profilePhoneResendOTP,
                                                  parameters: ["verificationId": verificationId]))
    }

    /// Keys: drinking, education, height, religion, sexuality, smoking, weight, eyeColor, hairColor, living, relationship.
    func updateMoreAboutMe(_ values: [String: String]) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .patch, endPoint: .moreAboutMe, parameters: values))
            .map { _ in () }
    }

    func updateInterests(ids: [String]) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .put, endPoint: .onboardingInterests,
                                                      parameters: ["interestIds": ids]))
            .map { _ in () }
    }

    func uploadGalleryPhoto(imageData: Data, isPrimary: Bool) -> Single<[String: Any]> {
        let file = AppMultipartFile(name: "photo", fileName: "photo.jpg", mimeType: "image/jpeg", data: imageData)
        return backendClient.uploadJSON(endPoint: .onboardingPhotos, fields: ["isPrimary": isPrimary ? "true" : "false"], files: [file])
    }

    func deleteGalleryPhoto(id: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .delete, endPoint: .onboardingPhoto(photoId: id)))
            .map { _ in () }
    }

    func setPrimaryGalleryPhoto(id: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .patch, endPoint: .onboardingPhotoPrimary(photoId: id)))
            .map { _ in () }
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

    /// `folder` is "uploads" | "photos" | "moments" | "verifications" | "avatars" | "quick-moments" | "audio".
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

    /// Replaces the gallery with 3–5 S3 keys (folder "photos"), in display order.
    func setGalleryPhotos(imageKeys: [String]) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .put, endPoint: .userPhotos,
                                                      parameters: ["imageKeys": imageKeys]))
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

    // MARK: - Discovery filters

    /// Allowed genders, age and distance bounds, looking-for values and interests (UUIDs) for the Filters sheet.
    func discoveryFilterOptions() -> Single<DiscoveryFilterOptions> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .discoveryFilterOptions))
    }

    /// Saved preferences, or the backend defaults when none are saved yet.
    func discoveryFilters() -> Single<DiscoveryFilterPreferences> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .discoveryFilters))
    }

    func updateDiscoveryFilters(_ preferences: DiscoveryFilterPreferences) -> Single<DiscoveryFilterPreferences> {
        backendClient.load(request: AppApiRequest(method: .put, endPoint: .discoveryFilters, parameters: preferences.body))
    }

    func resetDiscoveryFilters() -> Single<DiscoveryFilterPreferences> {
        backendClient.load(request: AppApiRequest(method: .post, endPoint: .discoveryFiltersReset))
    }

    /// Profiles matching `filters`, excluding blocked and already swiped people. `countOnly` returns just `totalCount`.
    func discoverySearch(filters: DiscoveryFilterPreferences, page: Int, limit: Int,
                         countOnly: Bool = false) -> Single<DiscoverySearchData> {
        discoverySearch(style: Self.searchBodyStyle, filters: filters.body, page: page, limit: limit, countOnly: countOnly)
    }

    /// The live server rejects the documented `{ filters, page, limit, countOnly }` body with
    /// "Unknown fields are not allowed in search body", so on a 400 the other shapes are tried and the working one is kept.
    private static var searchBodyStyle = 0

    private static func searchBody(style: Int, filters: [String: Any], page: Int, limit: Int, countOnly: Bool) -> [String: Any]? {
        let paging: [String: Any] = ["page": page, "limit": limit]
        let keepFirst: (Any, Any) -> Any = { first, _ in first }
        switch style {
        case 0: return ["filters": filters, "countOnly": countOnly].merging(paging, uniquingKeysWith: keepFirst)
        case 1: return filters.merging(paging, uniquingKeysWith: keepFirst).merging(["countOnly": countOnly], uniquingKeysWith: keepFirst)
        case 2: return ["filters": filters].merging(paging, uniquingKeysWith: keepFirst)
        case 3: return filters.merging(paging, uniquingKeysWith: keepFirst)
        case 4: return ["filters": filters]
        case 5: return filters
        default: return nil
        }
    }

    private func discoverySearch(style: Int, filters: [String: Any], page: Int, limit: Int,
                                 countOnly: Bool) -> Single<DiscoverySearchData> {
        guard let params = Self.searchBody(style: style, filters: filters, page: page, limit: limit, countOnly: countOnly) else {
            return .error(APIHTTPError(statusCode: 400, message: "Couldn't search right now"))
        }
        let request: Single<DiscoverySearchData> = backendClient.load(
            request: AppApiRequest(method: .post, endPoint: .discoverySearch, parameters: params))
        return request
            .do(onSuccess: { _ in Self.searchBodyStyle = style })
            .catch { [weak self] error in
                guard let self, (error as? APIHTTPError)?.statusCode == 400,
                      Self.searchBody(style: style + 1, filters: filters, page: page, limit: limit, countOnly: countOnly) != nil else {
                    return .error(error)
                }
                return self.discoverySearch(style: style + 1, filters: filters, page: page, limit: limit, countOnly: countOnly)
            }
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

    /// Daily like quota, Super Like coins and Explore tab locks.
    /// Backend registers this as `GET /users/:id/limits` (plain `/users/limits` is treated as an id).
    func userLimits() -> Single<UserLimits> {
        guard let userId = UserDataManager.shared.appUser?.id, !userId.isEmpty else {
            return .error(APIHTTPError(statusCode: 0, message: "Missing user id for limits"))
        }
        return backendClient.load(request: AppApiRequest(method: .get, endPoint: .userLimits(userId: userId)))
    }

    // MARK: - Interactions

    /// `type` is "likes" | "you_liked" | "matches" | "compliments"; pass the previous page's `nextCursor` for more.
    func interactions(type: String, limit: Int = 20, cursor: String? = nil) -> Single<InteractionPage> {
        var params: [String: Any] = ["type": type, "limit": limit]
        if let cursor, !cursor.isEmpty { params["cursor"] = cursor }
        return backendClient.load(request: AppApiRequest(method: .get, endPoint: .interactions,
                                                         parameters: params, encoding: URLEncoding.queryString))
    }

    func interactionCounts() -> Single<InteractionCounts> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .interactionCounts))
    }

    /// Idempotent; only the recipient can mark an interaction read.
    func markInteractionRead(interactionId: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .interactionRead(interactionId: interactionId)))
            .map { _ in () }
    }

    // MARK: - Other users

    func otherUserProfile(userId: String) -> Single<OtherUserProfile> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .userProfile(userId: userId)))
    }

    func blockUser(userId: String, reason: String) -> Single<UserBlockResult> {
        backendClient.load(request: AppApiRequest(method: .post, endPoint: .blockUser(userId: userId),
                                                  parameters: ["reason": reason]))
    }

    func unblockUser(userId: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .delete, endPoint: .blockUser(userId: userId)))
            .map { _ in () }
    }

    /// People whose name, username or city matches `query`.
    func searchUsers(query: String, page: Int, limit: Int = 20) -> Single<UserSearchPage> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .searchUsers,
                                                  parameters: ["query": query, "page": page, "limit": limit],
                                                  encoding: URLEncoding.queryString))
    }

    /// Users the signed-in user has blocked, newest first.
    func blockedUsers(page: Int, limit: Int = 20) -> Single<BlockedUsersPage> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .blockedUsers,
                                                  parameters: ["page": page, "limit": limit], encoding: URLEncoding.queryString))
    }

    /// User and moment reports filed by the signed-in user. `status` is pending | reviewed | dismissed | resolved,
    /// `targetType` is user | moment.
    func myReports(page: Int, limit: Int = 20, status: String? = nil, targetType: String? = nil) -> Single<MyReportsPage> {
        var params: [String: Any] = ["page": page, "limit": limit]
        if let status { params["status"] = status }
        if let targetType { params["targetType"] = targetType }
        return backendClient.load(request: AppApiRequest(method: .get, endPoint: .myReports,
                                                         parameters: params, encoding: URLEncoding.queryString))
    }

    /// `reason` is one of the API codes: harassment, inappropriate_content, spam, scam, fake_profile, underage, other.
    func reportUser(
        userId: String,
        reason: String,
        description: String? = nil,
        conversationId: String? = nil
    ) -> Single<Void> {
        var params: [String: Any] = ["reason": reason]
        if let description, !description.isEmpty { params["description"] = description }
        if let conversationId, !conversationId.isEmpty { params["conversationId"] = conversationId }
        return backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .reportUser(userId: userId),
                                                             parameters: params))
            .map { _ in () }
    }

    func sendCompliment(userId: String, message: String) -> Single<SentCompliment> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .userCompliment(userId: userId),
                                                      parameters: ["message": message]))
            .map(SentCompliment.init(json:))
    }

    // MARK: - Moments

    func momentsFeed(page: Int, limit: Int, momentId: String? = nil) -> Single<MomentFeedPage> {
        var params: [String: Any] = ["page": page, "limit": limit, "type": "feed", "scope": "all"]
        if let momentId, !momentId.isEmpty {
            params["momentId"] = momentId
        }
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

    /// Another user's permanent moments; the backend applies audience and block rules.
    /// `fallbackAuthor` is used for moments that come without a creator.
    func userMoments(userId: String, page: Int, limit: Int, fallbackAuthor: MomentsAuthor? = nil) -> Single<MomentFeedPage> {
        let params: [String: Any] = ["page": page, "limit": limit]
        let request: Single<MomentFeedData> = backendClient.load(request: AppApiRequest(method: .get, endPoint: .userMoments(userId: userId),
                                                                                        parameters: params, encoding: URLEncoding.queryString))
        return request.map { $0.page(fallbackAuthor: fallbackAuthor) }
    }

    /// `imageKeys` are 1 to 5 S3 keys from `media/presigned-url`, in display order. The backend
    /// returns the full `imageUrl` / `thumbnailUrl`. Caption max 500 characters, `location` max 100.
    /// `audience` is "everyone" | "matches_only" | "close_friends".
    /// Returns `nil` when the backend doesn't send the created moment back.
    func createMoment(caption: String, audience: String = "everyone", location: String? = nil,
                      imageKeys: [String]) -> Single<MomentsPost?> {
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

    /// Replies in the thread of top-level comment `commentId`; pass `parentReplyId` when answering a reply in that thread.
    func replyToMomentComment(momentId: String, commentId: String, reply: String, parentReplyId: String? = nil) -> Single<[String: Any]> {
        var params: [String: Any] = ["reply": reply]
        if let parentReplyId, !parentReplyId.isEmpty { params["parentReplyId"] = parentReplyId }
        return backendClient.loadJSON(request: AppApiRequest(method: .post,
                                                             endPoint: .momentCommentReplies(momentId: momentId, commentId: commentId),
                                                             parameters: params))
    }

    /// Sends "like" / "unlike" rather than "toggle" so quick double taps can't flip it the wrong way.
    /// `data` carries the server's `isLiked` and `likesCount`.
    func likeMomentComment(momentId: String, commentId: String, isLiked: Bool) -> Single<[String: Any]> {
        backendClient.loadJSON(request: AppApiRequest(method: .post,
                                                      endPoint: .momentCommentLike(momentId: momentId, commentId: commentId),
                                                      parameters: ["action": isLiked ? "like" : "unlike"]))
    }

    /// Replies to a top-level comment; `limit` max 100.
    func momentCommentReplies(momentId: String, commentId: String, page: Int, limit: Int) -> Single<MomentCommentRepliesData> {
        backendClient.load(request: AppApiRequest(method: .get,
                                                  endPoint: .momentCommentReplies(momentId: momentId, commentId: commentId),
                                                  parameters: ["page": page, "limit": limit], encoding: URLEncoding.queryString))
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

    /// `reason` is one of the API codes: inappropriate_content, nudity, harassment, violence, spam, fake_content, other.
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
        let request: Single<UserQuickMomentsData> = backendClient.load(request: AppApiRequest(method: .get,
                                                                                              endPoint: .userQuickMoments(userId: userId)))
        return request.map(\.stories)
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
    func quickMomentViewers(momentId: String, page: Int = 1, limit: Int = 30) -> Single<QuickMomentViewersPage> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .quickMomentViewers(momentId: momentId),
                                                  parameters: ["page": page, "limit": limit], encoding: URLEncoding.queryString))
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

    func quickMomentReplies(momentId: String, page: Int = 1, limit: Int = 30) -> Single<QuickMomentRepliesPage> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .quickMomentReplies(momentId: momentId),
                                                  parameters: ["page": page, "limit": limit], encoding: URLEncoding.queryString))
    }

    /// Marks the story as seen, which greys out its ring in the tray.
    func markQuickMomentViewed(momentId: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .quickMomentView(momentId: momentId)))
            .map { _ in () }
    }

    // MARK: - Coins

    /// The list is paginated (default limit 10), so ask for every pack in one page.
    func coinPackages() -> Single<CoinsModel> {
        backendClient.loadDirect(request: AppApiRequest(method: .get, endPoint: .coinPackages,
                                                        parameters: ["page": 1, "limit": 50],
                                                        encoding: URLEncoding.queryString))
    }

    /// Verifies an App Store coin purchase with the backend and credits the wallet.
    /// Body: `platform`, `packageId`, `productId`, `transactionId`, `signedTransactionInfo`.
    func verifyCoinPurchase(parameters: [String: Any]) -> Single<CoinPurchaseResponse> {
        backendClient.loadDirect(request: AppApiRequest(method: .post, endPoint: .coinsPurchaseVerify,
                                                        parameters: parameters))
    }

    /// Current coin balance for the signed-in user (`GET /api/v1/wallet/balance`).
    func walletBalance() -> Single<WalletBalanceResponse> {
        backendClient.loadDirect(request: AppApiRequest(method: .get, endPoint: .walletBalance))
    }

    // MARK: - Subscriptions

    func subscriptionPlans() -> Single<SubscriptionModel> {
        backendClient.loadDirect(request: AppApiRequest(method: .get, endPoint: .subscriptions))
    }

    /// Verifies an App Store subscription with the backend and activates Premium.
    /// Body: `platform`, `productId`, `transactionId`, `signedTransactionInfo`.
    func verifySubscriptionPurchase(parameters: [String: Any]) -> Single<SubscriptionPurchaseResponse> {
        backendClient.loadDirect(request: AppApiRequest(method: .post, endPoint: .subscriptionsPurchaseVerify,
                                                        parameters: parameters))
    }

    /// The signed-in user's current subscription, if any (`GET /api/v1/subscriptions/my`).
    func mySubscription() -> Single<MySubscriptionData?> {
        backendClient.loadDirect(request: AppApiRequest(method: .get, endPoint: .mySubscription))
            .map { (response: MySubscriptionResponse) in response.membership }
    }

    // MARK: - Notifications

    /// Sectioned (Today / Yesterday / Earlier) by the server in `timeZone`; pass the previous page's `nextCursor` for more.
    func notifications(limit: Int = 20, cursor: String? = nil,
                       timeZone: String = TimeZone.current.identifier) -> Single<NotificationFeed> {
        var params: [String: Any] = ["limit": limit, "tz": timeZone]
        if let cursor, !cursor.isEmpty { params["cursor"] = cursor }
        return backendClient.loadJSON(request: AppApiRequest(method: .get, endPoint: .notifications,
                                                             parameters: params, encoding: URLEncoding.queryString))
            .map { NotificationFeed(json: $0) }
    }

    func notificationCounts() -> Single<NotificationCounts> {
        backendClient.loadJSON(request: AppApiRequest(method: .get, endPoint: .notificationCounts))
            .map { NotificationCounts(json: $0) }
    }

    func markNotificationRead(id: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .patch, endPoint: .notificationRead(id: id)))
            .map { _ in () }
    }

    func markAllNotificationsRead() -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .patch, endPoint: .notificationsReadAll))
            .map { _ in () }
    }

    func deleteNotification(id: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .delete, endPoint: .notification(id: id)))
            .map { _ in () }
    }

    func getNotificationSettings() -> Single<NotificationSettingsDTO> {
        backendClient.load(request: AppApiRequest(method: .get, endPoint: .notificationSettings))
    }

    func updateNotificationSettings(_ settings: NotificationSettingsDTO) -> Single<NotificationSettingsDTO> {
        backendClient.load(request: AppApiRequest(method: .patch, endPoint: .notificationSettings,
                                                  parameters: settings.asParameters))
    }

    // MARK: - Devices

    /// Registering a token that belongs to another account moves it to the signed-in user.
    func registerDevice(token: String) -> Single<Void> {
        let params: [String: Any] = [
            "deviceToken": token,
            "platform": "ios",
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "deviceModel": Self.deviceModel
        ]
        return backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .deviceRegister, parameters: params))
            .map { _ in () }
    }

    func unregisterDevice(token: String) -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .delete, endPoint: .deviceUnregister,
                                                      parameters: ["deviceToken": token]))
            .map { _ in () }
    }

    /// Hardware identifier such as "iPhone15,2".
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    // MARK: - Session

    /// Invalidates the session on the server. Call while the access token is still present.
    func logoutFromServer() -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .post, endPoint: .logout, parameters: [:]))
            .map { _ in () }
    }

    /// Permanently deletes the signed-in account. Call while the access token is still present.
    func deleteAccount() -> Single<Void> {
        backendClient.loadJSON(request: AppApiRequest(method: .delete, endPoint: .deleteAccount))
            .map { _ in () }
    }

    func logout() {
        AppTokenStore.shared.clear()
        UserDataManager.shared.removeUserData()
        CoinWallet.shared.update(0)
        FreeTierLimitsStore.shared.refresh()
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
            DeviceTokenManager.shared.registerIfNeeded(force: true)
            CoinWallet.shared.refresh()
            FreeTierLimitsStore.shared.refresh()
            return auth
        }
    }
}
