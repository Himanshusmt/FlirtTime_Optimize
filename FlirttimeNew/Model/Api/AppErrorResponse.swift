//
//  AppErrorResponse.swift
//  FlirttimeNew
//

import Foundation

/// Body of every failed FlirtTime API call, e.g. a wrong OTP:
/// `{ "success": false, "message": "Invalid verification code" }`.
struct AppErrorResponse: Decodable {
    let success: Bool?
    let message: String?
    let error: [AppFieldError]?
    let code: String?

    private enum CodingKeys: String, CodingKey {
        case success, message, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try? container.decodeIfPresent(Bool.self, forKey: .success)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        error = try? container.decodeIfPresent([AppFieldError].self, forKey: .error)
        code = try? container.decodeIfPresent(String.self, forKey: .error)
    }

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
