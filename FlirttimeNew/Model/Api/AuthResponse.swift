//
//  AuthResponse.swift
//  FlirttimeNew
//

import Foundation

/// `data` of `auth/login`, `auth/register`, email/phone `verify-otp` and `auth/apple`.
struct AuthResponse: Codable {
    let user: AppUser?
    let token: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case user, token, accessToken, refreshToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decodeIfPresent(AppUser.self, forKey: .user)
        token = try container.decodeIfPresent(String.self, forKey: .token)
            ?? container.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encodeIfPresent(token, forKey: .token)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
    }
}

/// `data` of `auth/me`.
struct MeResponse: Codable {
    let user: AppUser?
}
