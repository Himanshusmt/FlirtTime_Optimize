//
//  ChatUser.swift
//  FlirttimeNew
//

import Foundation

/// The signed-in chat user (name kept as `User` so the ported chat code compiles unchanged).
struct User: Codable {
    var userId: String?
    var fullName: String?
    var userName: String?
    var email: String?
    var phoneNumber: String?
    var profilePicture: String?
    var profilePictureDetails: ProfilePictureDetails?
    var isVerified: Bool?
    var verified: Bool?
    var bio: String?

    init(
        userId: String?,
        fullName: String? = nil,
        userName: String? = nil,
        email: String? = nil,
        phoneNumber: String? = nil,
        profilePicture: String? = nil,
        profilePictureDetails: ProfilePictureDetails? = nil,
        isVerified: Bool? = nil,
        verified: Bool? = nil,
        bio: String? = nil
    ) {
        self.userId = userId
        self.fullName = fullName
        self.userName = userName
        self.email = email
        self.phoneNumber = phoneNumber
        self.profilePicture = profilePicture
        self.profilePictureDetails = profilePictureDetails
        self.isVerified = isVerified
        self.verified = verified
        self.bio = bio
    }
}
