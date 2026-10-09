//
//  AppErrorResponse.swift
//  FlirttimeNew
//

import Foundation

/// Body of every failed FlirtTime API call, e.g. a wrong OTP:
/// `{ "success": false, "message": "Invalid verification code" }`.
/// Validation failures also carry `error`.
struct AppErrorResponse: Codable {
    let success: Bool?
    let message: String?
    let error: [AppFieldError]?

    /// Prefers the first field error ("phone is required") over a generic "Validation failed".
    var displayMessage: String {
        if let first = error?.first?.message, !first.isEmpty {
            return first
        }
        if let message, !message.isEmpty {
            return message
        }
        return "Something went wrong"
    }
}

struct AppFieldError: Codable {
    /// e.g. "body.lastName"
    let field: String?
    let message: String?
}
