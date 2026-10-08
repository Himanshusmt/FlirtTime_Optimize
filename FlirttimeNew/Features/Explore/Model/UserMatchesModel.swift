//
//  UserMatchesModel.swift
//  FlirtTime
//
//  Created by Smt MacMini on 29/01/25.
//

import Foundation

// MARK: - Main Response
struct MatchResponse: Codable {
    let status: Bool
    let message: String
    let data: [MatchedUser]
}

// MARK: - Matched User
struct MatchedUser: Codable {
    let matchedUserID, id, userID: Int?
    let fullname, displayName, dob: String?
    let gender, relationship, sexuality, height: Int?
    let weight: Int?
    let eyeColour, hairColour, living, children: Int?
    let smoking, drinking: Int?
    let interests: [Int]
    let motherTongue, maritalStatus, religion, education: Int?
    let employedIn, aboutMe, lat, lng: String?
    let location: String?
    let avatar: String?
    let banner: String?
    let images: [Images]
    let isOnline: Bool?
    let onlineTime: String?
    let ageShow, distanceShow, locationShow, onlineShow: Bool?
    let bumpIntoShow, enablePublicSearch: Bool?
    let dobIsVerified, genderIsVerified, videoIsVerified, gestureIsVerified: Bool?
    let isFake : Bool?
    let isActive: Bool?
    let deviceType: String?
    let fcmToken: String?
    let memExpired: String?
    let createdAt, updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case matchedUserID = "matched_user_id"
        case id
        case userID = "user_id"
        case fullname
        case displayName = "display_name"
        case dob, gender, relationship, sexuality, height, weight
        case eyeColour = "eye_colour"
        case hairColour = "hair_colour"
        case living, children, smoking, drinking, interests
        case motherTongue = "mother_tongue"
        case maritalStatus = "marital_status"
        case religion, education
        case employedIn = "employed_in"
        case aboutMe = "about_me"
        case lat, lng, location, avatar, banner, images
        case isOnline = "is_online"
        case onlineTime = "online_time"
        case ageShow = "age_show"
        case distanceShow = "distance_show"
        case locationShow = "location_show"
        case onlineShow = "online_show"
        case bumpIntoShow = "bump_into_show"
        case enablePublicSearch = "enable_public_search"
        case dobIsVerified = "dob_is_verified"
        case genderIsVerified = "gender_is_verified"
        case videoIsVerified = "video_is_verified"
        case gestureIsVerified = "gesture_is_verified"
        case isFake = "is_fake"
        case isActive = "is_active"
        case deviceType = "device_type"
        case fcmToken = "fcm_token"
        case memExpired = "mem_expired"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
