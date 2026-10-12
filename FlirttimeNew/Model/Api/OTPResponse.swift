//
//  OTPResponse.swift
//  FlirttimeNew
//

import Foundation

/// `data` of email/phone `request-otp` and `resend-otp`.
struct OTPResponse: Codable {
    let verificationId: String?
    /// Seconds until the code expires.
    let expiresIn: Int?
    /// Seconds before "Resend" may be used again.
    let resendAfter: Int?
}
