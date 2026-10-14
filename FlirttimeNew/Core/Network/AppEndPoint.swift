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
        case .updateProfile: return "api/v1/users/profile"
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
        case .me, .updateProfile, .gestureUpload, .profilePhotoUpload,
             .discoveryPeople, .discoveryAction, .interestsCatalog, .connectionRequest,
             .interactions, .interactionCounts, .interactionRead,
             .userProfile, .blockUser, .reportUser,
             .mediaPresignedURL, .onboardingPhotos,
             .moments, .myMoments, .momentLike, .momentComments, .momentLikes, .momentReport,
             .momentGifts, .momentGiftsReceived, .moment, .momentComment,
             .quickMoments, .quickMomentsTray, .myQuickMoments, .userQuickMoments, .quickMomentUploadURL,
             .quickMoment, .quickMomentReactions, .quickMomentReact, .quickMomentReply,
             .quickMomentView, .quickMomentViewers:
            return false
        }
    }
}
