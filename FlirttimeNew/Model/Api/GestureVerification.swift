//
//  GestureVerification.swift
//  FlirttimeNew
//

import Foundation

/// The `data` of POST `gesture-upload`.
struct GestureVerification: Codable {
    let verificationId: String?
    let verificationType: String?
    let attemptNo: Int?
    let isLatest: Bool?
    let faceDetected: Bool?
    let faceCount: Int?
    let similarity: Double?
    /// "approved" when the selfie matches the user's primary profile photo.
    let status: String?
    let reasonCode: String?
    let reasonMessage: String?
    let rejectionReason: String?
    let liveness: Liveness?
    let quality: Quality?

    var isApproved: Bool { status?.lowercased() == "approved" }

    struct Liveness: Codable {
        let status: String?
        let message: String?
    }

    struct Quality: Codable {
        let brightness: Double?
        let sharpness: Double?
        let confidence: Double?
    }
}
