//
//  GetUserDetails.swift
//  FlirtTime
//
//  Created by Smt MacMini on 29/11/24.
//

import Foundation

// Root Response
struct UserResponse: Codable {
    let status: Bool
    let message: String
    let data: UserDetailsData?
}

// User Data
struct UserDetailsData: Codable {
    let user_images:[UserImage]?
    let id: Int?
    let username: String?
    let email: String?
    let phoneCode: String?
    let phone: String?
    let referralBy: String?
    let googleID: String?
    let appleID: String?
    let gestureImage: String?
    let dobCertificate: String?
    let veriVideo: String?
    let gestureVerifiedAt: String?
    let dobVerifiedAt: String?
    let videoVerifiedAt: String?
    let phoneVerifiedAt: String?
    let emailVerifiedAt: String?
    let isCompleted: Int?
    let profile_complete: Int?
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
    let page_redirect:String?
    var userInfo: UserDetailInfo?
    
    // Custom coding keys to map snake_case to camelCase
    private enum CodingKeys: String, CodingKey {
        case user_images,id, username, email, page_redirect, profile_complete
        case phoneCode = "phone_code"
        case phone, referralBy = "referral_by"
        case googleID = "google_id"
        case appleID = "apple_id"
        case gestureImage = "gesture_image"
        case dobCertificate = "dob_certificate"
        case veriVideo = "veri_video"
        case gestureVerifiedAt = "gesture_verified_at"
        case dobVerifiedAt = "dob_verified_at"
        case videoVerifiedAt = "video_verified_at"
        case phoneVerifiedAt = "phone_verified_at"
        case emailVerifiedAt = "email_verified_at"
        case isCompleted = "is_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case userInfo = "user_info"
    }
}

//UserImage
struct UserImage: Codable {
    let createdAt: String?
    let userId: Int?
    let filetype: String?
    let updatedAt: String?
    let filename: String?
    let id: Int?
    let filefor: String?
    let isPrimary: Bool?
    let deletedAt: String?
    let status: Int?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case userId = "user_id"
        case filetype
        case updatedAt = "updated_at"
        case filename
        case id
        case filefor
        case isPrimary = "is_primary"
        case deletedAt = "deleted_at"
        case status
    }
}

// User Info
struct UserDetailInfo: Codable {
    let id: Int?
    let userID: Int?
    let fullname: String?
    let displayName: String?
    let dob: String?
    let gender: Int?
    let relationship: Int?
    let sexuality: Int?
    let height: Int?
    let weight: Int?
    let eyeColour: Int?
    let hairColour: Int?
    let living: Int?
    let children: Int?
    let smoking: Int?
    let drinking: Int?
    let interests: [Int]?
    let motherTongue: Int?
    let maritalStatus: Int?
    let religion: Int?
    let education: Int?
    let employedIn: String?
    let aboutMe: String?
    let lat: Double?
    let lng: Double?
    let location: String?
    var avatar: String?
    var banner: String?
    let images: [Images]?
    let isOnline: Bool?
    let onlineTime: String?
    let ageShow: Bool?
    let distanceShow: Bool?
    let locationShow: Bool?
    let onlineShow: Bool?
    let bumpIntoShow: Bool?
    let enablePublicSearch: Bool?
    let dobIsVerified: Bool?
    let genderIsVerified: Bool?
    let videoIsVerified: Bool?
    let gestureIsVerified: Bool?
    let isFake: Bool?
    let isActive: Bool?
    let memExpired: String?
    let createdAt: String?
    let updatedAt: String?
    var img_type:String?
    
    // Custom coding keys to map snake_case to camelCase
    private enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case fullname
        case displayName = "display_name"
        case dob, gender, relationship, sexuality, height, weight, img_type
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
        case memExpired = "mem_expired"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
        if let intArray = try? container.decode([Int].self, forKey: .interests) {
                self.interests = intArray
            } else if let singleInt = try? container.decode(Int.self, forKey: .interests) {
                self.interests = [singleInt]
            } else {
                self.interests = nil
            }
        
        if let strArray = try? container.decode([Images].self, forKey: .images) {
            self.images = strArray
        } else {
                self.images = nil
            }
                id = try? container.decode(Int.self, forKey: .id)
                userID = try? container.decode(Int.self, forKey: .userID)
                fullname = try? container.decode(String.self, forKey: .fullname)
                displayName = try? container.decode(String.self, forKey: .displayName)
                dob = try? container.decode(String.self, forKey: .dob)
                gender = try? container.decode(Int.self, forKey: .gender)
                relationship = try? container.decode(Int.self, forKey: .relationship)
                sexuality = try? container.decode(Int.self, forKey: .sexuality)
                height = try? container.decode(Int.self, forKey: .height)
                weight = try? container.decode(Int.self, forKey: .weight)
                eyeColour = try? container.decode(Int.self, forKey: .eyeColour)
                hairColour = try? container.decode(Int.self, forKey: .hairColour)
                living = try? container.decode(Int.self, forKey: .living)
                children = try? container.decode(Int.self, forKey: .children)
                smoking = try? container.decode(Int.self, forKey: .smoking)
                drinking = try? container.decode(Int.self, forKey: .drinking)
                motherTongue = try? container.decode(Int.self, forKey: .motherTongue)
                maritalStatus = try? container.decode(Int.self, forKey: .maritalStatus)
                religion = try? container.decode(Int.self, forKey: .religion)
                education = try? container.decode(Int.self, forKey: .education)
                employedIn = try? container.decode(String.self, forKey: .employedIn)
                aboutMe = try? container.decode(String.self, forKey: .aboutMe)
                lat = try? container.decode(Double.self, forKey: .lat)
                lng = try? container.decode(Double.self, forKey: .lng)
                location = try? container.decode(String.self, forKey: .location)
                avatar = try? container.decode(String.self, forKey: .avatar)
                banner = try? container.decode(String.self, forKey: .banner)
                isOnline = try? container.decode(Bool.self, forKey: .isOnline)
                onlineTime = try? container.decode(String.self, forKey: .onlineTime)
                ageShow = try? container.decode(Bool.self, forKey: .ageShow)
                distanceShow = try? container.decode(Bool.self, forKey: .distanceShow)
                locationShow = try? container.decode(Bool.self, forKey: .locationShow)
                onlineShow = try? container.decode(Bool.self, forKey: .onlineShow)
                bumpIntoShow = try? container.decode(Bool.self, forKey: .bumpIntoShow)
                enablePublicSearch = try? container.decode(Bool.self, forKey: .enablePublicSearch)
                dobIsVerified = try? container.decode(Bool.self, forKey: .dobIsVerified)
                genderIsVerified = try? container.decode(Bool.self, forKey: .genderIsVerified)
                videoIsVerified = try? container.decode(Bool.self, forKey: .videoIsVerified)
                gestureIsVerified = try? container.decode(Bool.self, forKey: .gestureIsVerified)
                isFake = try? container.decode(Bool.self, forKey: .isFake)
                isActive = try? container.decode(Bool.self, forKey: .isActive)
                memExpired = try? container.decode(String.self, forKey: .memExpired)
                createdAt = try? container.decode(String.self, forKey: .createdAt)
                updatedAt = try? container.decode(String.self, forKey: .updatedAt)
            
        }
}

