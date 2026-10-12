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
    let profilePicture: String?
    let isFaceVerified: Bool?
    let faceVerifiedAt: String?
    let isProfileComplete: Bool?
    let createdAt: String?
    let updatedAt: String?
}
