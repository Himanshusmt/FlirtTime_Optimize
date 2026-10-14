//
//  AppEndPoint.swift
//  FlirttimeNew
//

import Foundation
import Alamofire

struct AppApiRequest {
    let method: HTTPMethod
    let endPoint: AppEndPoint
    var parameters: [String: Any]? = nil
    var encoding: ParameterEncoding = JSONEncoding.default
}

/// A file part of a multipart/form-data request.
struct AppMultipartFile {
    let name: String
    let fileName: String
    let mimeType: String
    let data: Data
}

/// FlirtTime REST paths, relative to `AppConfig.baseURL`.
enum AppEndPoint: CustomStringConvertible {

    case health

    // Email OTP — LoginViewController / VerifyOTPViewController
    case emailRequestOTP
    case emailVerifyOTP
    case emailResendOTP

    // Phone OTP — LoginViewController / VerifyOTPViewController
    case phoneRequestOTP
    case phoneVerifyOTP
    case phoneResendOTP

    // Sign in with Apple — LoginOptionsViewController / LoginViewController
    case appleLogin

    // Session — SplashScreenVC
    case me

    // Introduce yourself — UserDetailsViewController
    case updateProfile

    // My Profile — ProfileViewModel
    case myProfile

    // Change email / phone (logged in) — ChangeEmailViewController
    case profileEmailRequestOTP
    case profileEmailVerifyOTP
    case profileEmailResendOTP
    case profilePhoneRequestOTP
    case profilePhoneVerifyOTP
    case profilePhoneResendOTP

    // Voice intro — VoiceIntroService (POST / GET / DELETE)
    case voiceIntro

    // Edit Profile — EditProfileViewModel / EditAboutViewModel
    case moreAboutMe
    case onboardingInterests
    case onboardingPhoto(photoId: String)
    case onboardingPhotoPrimary(photoId: String)

    // Gesture selfie — GestureVerificationViewController
    case gestureUpload

    // Profile photo — StartProfileVerificationViewController
    case profilePhotoUpload

    // Discover — DiscoverViewModel
    case discoveryPeople
    case discoveryAction
    case interestsCatalog
    case connectionRequest

    // Explore tabs — ExploreViewModel
    case interactions
    case interactionCounts
    case interactionRead(interactionId: String)

    // Vibe Details — VibeProfileViewController
    case userProfile(userId: String)
    case blockUser(userId: String)
    case reportUser(userId: String)

    // Media — S3 presigned uploads
    case mediaPresignedURL
    case onboardingPhotos

    // Moments — VibeFeedViewModel / VibeUploadViewModel / VibeCommentViewModel
    case moments
    case myMoments
    case momentLike(momentId: String)
    case momentComments(momentId: String)
    case momentLikes(momentId: String)
    case moment(momentId: String)
    case momentComment(momentId: String, commentId: String)
    case momentGifts(momentId: String)
    case momentGiftsReceived(momentId: String)
    case momentReport(momentId: String)

    // Quick Moments (24h stories) — ProfileViewModel / QuickMomentActivityViewController
    case quickMoments
    case quickMomentsTray
    case myQuickMoments
    case userQuickMoments(userId: String)
    case quickMomentUploadURL
    case quickMoment(momentId: String)
    case quickMomentReactions(momentId: String)
    case quickMomentReact(momentId: String)
    case quickMomentReply(momentId: String)
    case quickMomentView(momentId: String)
    case quickMomentViewers(momentId: String)

    // Coin Shop — CoinPackStore
    case coinPackages

    // Premium — SubscriptionPlanStore
    case subscriptions

    var description: String {
        switch self {
        case .health: return "health"
        case .emailRequestOTP: return "api/v1/auth/email/request-otp"
        case .emailVerifyOTP: return "api/v1/auth/email/verify-otp"
        case .emailResendOTP: return "api/v1/auth/email/resend-otp"
        case .phoneRequestOTP: return "api/v1/auth/phone/request-otp"
        case .phoneVerifyOTP: return "api/v1/auth/phone/verify-otp"
        case .phoneResendOTP: return "api/v1/auth/phone/resend-otp"
        case .appleLogin: return "api/v1/auth/apple"
        case .me: return "api/v1/auth/me"
        case .updateProfile, .myProfile: return "api/v1/users/profile"
        case .profileEmailRequestOTP: return "api/v1/users/profile/email/request-otp"
        case .profileEmailVerifyOTP: return "api/v1/users/profile/email/verify-otp"
        case .profileEmailResendOTP: return "api/v1/users/profile/email/resend-otp"
        case .profilePhoneRequestOTP: return "api/v1/users/profile/phone/request-otp"
        case .profilePhoneVerifyOTP: return "api/v1/users/profile/phone/verify-otp"
        case .profilePhoneResendOTP: return "api/v1/users/profile/phone/resend-otp"
        case .voiceIntro: return "api/v1/onboarding/audio"
        case .moreAboutMe: return "api/v1/users/more-about-me"
        case .onboardingInterests: return "api/v1/onboarding/interests"
        case .onboardingPhoto(let photoId): return "api/v1/onboarding/photos/\(photoId)"
        case .onboardingPhotoPrimary(let photoId): return "api/v1/onboarding/photos/\(photoId)/primary"
        case .gestureUpload: return "api/v1/gesture-upload"
        case .profilePhotoUpload: return "api/v1/onboarding/profile-photo"
        case .discoveryPeople: return "api/v1/discovery/people"
        case .discoveryAction: return "api/v1/discovery/actions"
        case .interestsCatalog: return "api/v1/interests"
        case .connectionRequest: return "api/v1/connections/request"
        case .interactions: return "api/v1/interactions"
        case .interactionCounts: return "api/v1/interactions/counts"
        case .interactionRead(let interactionId): return "api/v1/interactions/\(interactionId)/read"
        case .userProfile(let userId): return "api/v1/users/\(userId)/profile"
        case .blockUser(let userId): return "api/v1/users/\(userId)/block"
        case .reportUser(let userId): return "api/v1/users/\(userId)/report"
        case .mediaPresignedURL: return "api/v1/media/presigned-url"
        case .onboardingPhotos: return "api/v1/onboarding/photos"
        case .moments: return "api/v1/moments"
        case .myMoments: return "api/v1/moments/me"
        case .momentLike(let momentId): return "api/v1/moments/\(momentId)/like"
        case .momentComments(let momentId): return "api/v1/moments/\(momentId)/comments"
        case .momentLikes(let momentId): return "api/v1/moments/\(momentId)/likes"
        case .moment(let momentId): return "api/v1/moments/\(momentId)"
        case .momentComment(let momentId, let commentId): return "api/v1/moments/\(momentId)/comments/\(commentId)"
        case .momentGifts(let momentId): return "api/v1/moments/\(momentId)/gifts"
        case .momentGiftsReceived(let momentId): return "api/v1/moments/\(momentId)/gifts/received"
        case .momentReport(let momentId): return "api/v1/moments/\(momentId)/report"
        case .quickMoments: return "api/v1/quick-moments"
        case .quickMomentsTray: return "api/v1/quick-moments/tray"
        case .myQuickMoments: return "api/v1/quick-moments/me"
        case .userQuickMoments(let userId): return "api/v1/quick-moments/user/\(userId)"
        case .quickMomentUploadURL: return "api/v1/quick-moments/upload-url"
        case .quickMoment(let momentId): return "api/v1/quick-moments/\(momentId)"
        case .quickMomentReactions(let momentId): return "api/v1/quick-moments/\(momentId)/reactions"
        case .quickMomentReact(let momentId): return "api/v1/quick-moments/\(momentId)/react"
        case .quickMomentReply(let momentId): return "api/v1/quick-moments/\(momentId)/reply"
        case .quickMomentView(let momentId): return "api/v1/quick-moments/\(momentId)/view"
        case .quickMomentViewers(let momentId): return "api/v1/quick-moments/\(momentId)/viewers"
        case .coinPackages: return "api/v1/coin-packages"
        case .subscriptions: return "api/v1/subscriptions"
        }
    }

    /// A 401 on these means "wrong credentials", not "session expired".
    var isAuthEndPoint: Bool {
        switch self {
        case .health,
             .emailRequestOTP, .emailVerifyOTP, .emailResendOTP,
             .phoneRequestOTP, .phoneVerifyOTP, .phoneResendOTP,
             .appleLogin:
            return true
        case .me, .updateProfile, .myProfile, .voiceIntro,
             .profileEmailRequestOTP, .profileEmailVerifyOTP, .profileEmailResendOTP,
             .profilePhoneRequestOTP, .profilePhoneVerifyOTP, .profilePhoneResendOTP, .gestureUpload, .profilePhotoUpload,
             .moreAboutMe, .onboardingInterests, .onboardingPhoto, .onboardingPhotoPrimary,
             .discoveryPeople, .discoveryAction, .interestsCatalog, .connectionRequest,
             .interactions, .interactionCounts, .interactionRead,
             .userProfile, .blockUser, .reportUser,
             .mediaPresignedURL, .onboardingPhotos,
             .moments, .myMoments, .momentLike, .momentComments, .momentLikes, .momentReport,
             .momentGifts, .momentGiftsReceived, .moment, .momentComment,
             .quickMoments, .quickMomentsTray, .myQuickMoments, .userQuickMoments, .quickMomentUploadURL,
             .quickMoment, .quickMomentReactions, .quickMomentReact, .quickMomentReply,
             .quickMomentView, .quickMomentViewers,
             .coinPackages, .subscriptions:
            return false
        }
    }
}
