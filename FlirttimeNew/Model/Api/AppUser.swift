//
//  AppUser.swift
//  FlirttimeNew
//

import Foundation

/// FlirtTime user: `user` in auth responses and `auth/me`, and the `data` of PATCH `users/profile`.
struct AppUser: Codable {
    let id: String?
    let username: String?
    let email: String?
    let phone: String?
    let isPhoneVerified: Bool?
    let role: String?
    let isActive: Bool?
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let nickName: String?
    /// "yyyy-MM-dd"
    let dateOfBirth: String?
    /// "male" | "female" | "non-binary" | "other"
    let gender: String?
    let about: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?
    let genderPreference: String?
    let lookingFor: String?
    let religion: String?
    let voicePromptUrl: String?
    /// Seconds
    let voicePromptDuration: Double?
    let profilePicture: String?
    let isFaceVerified: Bool?
    let faceVerifiedAt: String?
    let isProfileComplete: Bool?
    /// Server Premium flag from `auth/me` when present.
    let isSubscribed: Bool?
    let createdAt: String?
    let updatedAt: String?
}

/// `data` of GET `auth/username/availability`.
struct UsernameAvailability: Codable {
    let available: Bool?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let flag = try? single.decode(Bool.self) {
            available = flag
            return
        }
        let c = try decoder.container(keyedBy: QMKey.self)
        if let flag = c.first(Bool.self, "available", "isAvailable", "is_available") {
            available = flag
            return
        }
        if let taken = c.first(Bool.self, "taken", "exists", "isTaken") {
            available = !taken
            return
        }
        available = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: QMKey.self)
        try c.encodeIfPresent(available, forKey: QMKey("available"))
    }

    var isAvailable: Bool { available ?? false }
}
