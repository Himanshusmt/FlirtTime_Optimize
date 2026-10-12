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

    // Vibe Details — VibeProfileViewController
    case userProfile(userId: String)
    case blockUser(userId: String)
    case reportUser(userId: String)

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
        case .userProfile(let userId): return "api/v1/users/\(userId)/profile"
        case .blockUser(let userId): return "api/v1/users/\(userId)/block"
        case .reportUser(let userId): return "api/v1/users/\(userId)/report"
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
             .discoveryPeople, .discoveryAction,
             .userProfile, .blockUser, .reportUser:
            return false
        }
    }
}
