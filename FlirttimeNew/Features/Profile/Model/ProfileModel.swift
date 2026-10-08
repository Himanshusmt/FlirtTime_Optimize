//
//  ProfileModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 02/07/24.
//

import Foundation

// MARK: - UploadCoverPhotoResponseModel
struct UploadCoverPhotoResponseModel: Codable {
    let status: Bool?
    let message: String?
    let data: UploadCoverPhotoData?
}

// MARK: - DataClass
struct UploadCoverPhotoData: Codable {
    let coverPhoto: String?

    enum CodingKeys: String, CodingKey {
        case coverPhoto = "cover_photo"
    }
}

struct DeleteUserImageResponseModel: Codable {
    let status: Bool?
    let message: String?
}


// MARK: - ProfileModel
//struct UserProfileModel: Codable {
//    let status: Bool
//    let message: String
//    let data: UserProfileData
//}

// MARK: - ProfileModel
struct UserProfileModel: Codable {
    let status: Bool?
    let message: String?
    let data: UserProfileData?
    let img_base_url: String?
}

// MARK: - ProfileData
struct UserProfileData: Codable {
    let profile_verified: Bool?
    let avatar_status: String?
    let profile_status:String?
    let gesture_uploaded: Bool?
    let is_complete:Int?
    let coins_balance: Int?
    let img_base_url: String?
    let users: [UserHome]?
}


struct UserHome: Codable {
    let id: Int?
    let userId: Int?
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
    let avatar: String?
    let banner: String?
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
    let memExpired: Bool?
    let createdAt: String?
    let updatedAt: String?
    let deviceType: String?
    let activeChatId: Int?
    let fcmToken: String?
    let isPremium: Bool?
    let notifySettings: NotifySettings?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
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
        case memExpired = "mem_expired"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deviceType = "device_type"
        case activeChatId = "active_chat_id"
        case fcmToken = "fcm_token"
        case isPremium = "is_premium"
        case notifySettings = "notify_settings"
    }
}



//struct UserHome: Codable {
//    let id: Int?
//    let userId: Int?
//    let fullname: String?
//    let displayName: String?
//    let dob: String?
//    let gender: Int?
//    let relationship: Int?
//    let sexuality: Int?
//    let height: Int?
//    let weight: Int?
//    let eyeColour: Int?
//    let hairColour: Int?
//    let living: Int?
//    let children: Int?
//    let smoking: Int?
//    let drinking: Int?
//    let interests: [Int]?
//    let motherTongue: Int?
//    let maritalStatus: Int?
//    let religion: Int?
//    let education: Int?
//    let employedIn: String?
//    let aboutMe: String?
//    let lat: Double?
//    let lng: Double?
//    let location: String?
//    let avatar: String?
//    let banner: String?
//    let images: [Images]?
//    let isOnline: Bool?
//    let onlineTime: String?
//    let ageShow: Bool?
//    let distanceShow: Bool?
//    let locationShow: Bool?
//    let onlineShow: Bool?
//    let bumpIntoShow: Bool?
//    let enablePublicSearch: Bool?
//    let dobIsVerified: Bool?
//    let genderIsVerified: Bool?
//    let videoIsVerified: Bool?
//    let gestureIsVerified: Bool?
//    let isFake: Bool?
//    let isActive: Bool?
//    let memExpired: Bool?
//    let createdAt: String?
//    let updatedAt: String?
//    
//    let deviceType: String?
//    let activeChatId: Int?
//    let fcmToken: String?
//    let isPremium: Bool?
//    let notifySettings: NotifySettings?
//
//    enum CodingKeys: String, CodingKey {
//        case id
//        case userId = "user_id"
//        case fullname
//        case displayName = "display_name"
//        case dob
//        case gender
//        case relationship
//        case sexuality
//        case height
//        case weight
//        case eyeColour = "eye_colour"
//        case hairColour = "hair_colour"
//        case living
//        case children
//        case smoking
//        case drinking
//        case interests
//        case motherTongue = "mother_tongue"
//        case maritalStatus = "marital_status"
//        case religion
//        case education
//        case employedIn = "employed_in"
//        case aboutMe = "about_me"
//        case lat
//        case lng
//        case location
//        case avatar
//        case banner
//        case images
//        case isOnline = "is_online"
//        case onlineTime = "online_time"
//        case ageShow = "age_show"
//        case distanceShow = "distance_show"
//        case locationShow = "location_show"
//        case onlineShow = "online_show"
//        case bumpIntoShow = "bump_into_show"
//        case enablePublicSearch = "enable_public_search"
//        case dobIsVerified = "dob_is_verified"
//        case genderIsVerified = "gender_is_verified"
//        case videoIsVerified = "video_is_verified"
//        case gestureIsVerified = "gesture_is_verified"
//        case isFake = "is_fake"
//        case isActive = "is_active"
//        case memExpired = "mem_expired"
//        case createdAt = "created_at"
//        case updatedAt = "updated_at"
//        case deviceType = "device_type"
//        case activeChatId = "active_chat_id"
//        case notifySettings = "notify_settings"
//        case fcmToken = "fcm_token"
//        case isPremium = "is_premium"
//    }
//    
////    init(from decoder: Decoder) throws {
////            let container = try decoder.container(keyedBy: CodingKeys.self)
////            
////        if let intArray = try? container.decode([Int].self, forKey: .interests) {
////                self.interests = intArray
////            } else if let singleInt = try? container.decode(Int.self, forKey: .interests) {
////                self.interests = [singleInt]
////            } else {
////                self.interests = nil
////            }
////        
////        if let imgArray = try? container.decode([Images].self, forKey: .images) {
////             self.images = imgArray
////        } else {
////                self.images = nil
////            }
////                id = try? container.decode(Int.self, forKey: .id)
////                userId = try? container.decode(Int.self, forKey: .userId)
////                fullname = try? container.decode(String.self, forKey: .fullname)
////                displayName = try? container.decode(String.self, forKey: .displayName)
////                dob = try? container.decode(String.self, forKey: .dob)
////                gender = try? container.decode(Int.self, forKey: .gender)
////                relationship = try? container.decode(Int.self, forKey: .relationship)
////                sexuality = try? container.decode(Int.self, forKey: .sexuality)
////                height = try? container.decode(Int.self, forKey: .height)
////                weight = try? container.decode(Int.self, forKey: .weight)
////                eyeColour = try? container.decode(Int.self, forKey: .eyeColour)
////                hairColour = try? container.decode(Int.self, forKey: .hairColour)
////                living = try? container.decode(Int.self, forKey: .living)
////                children = try? container.decode(Int.self, forKey: .children)
////                smoking = try? container.decode(Int.self, forKey: .smoking)
////                drinking = try? container.decode(Int.self, forKey: .drinking)
////                motherTongue = try? container.decode(Int.self, forKey: .motherTongue)
////                maritalStatus = try? container.decode(Int.self, forKey: .maritalStatus)
////                religion = try? container.decode(Int.self, forKey: .religion)
////                education = try? container.decode(Int.self, forKey: .education)
////                employedIn = try? container.decode(String.self, forKey: .employedIn)
////                aboutMe = try? container.decode(String.self, forKey: .aboutMe)
////                lat = try? container.decode(Double.self, forKey: .lat)
////                lng = try? container.decode(Double.self, forKey: .lng)
////                location = try? container.decode(String.self, forKey: .location)
////                avatar = try? container.decode(String.self, forKey: .avatar)
////                banner = try? container.decode(String.self, forKey: .banner)
////                isOnline = try? container.decode(Bool.self, forKey: .isOnline)
////                onlineTime = try? container.decode(String.self, forKey: .onlineTime)
////                ageShow = try? container.decode(Bool.self, forKey: .ageShow)
////                distanceShow = try? container.decode(Bool.self, forKey: .distanceShow)
////                locationShow = try? container.decode(Bool.self, forKey: .locationShow)
////                onlineShow = try? container.decode(Bool.self, forKey: .onlineShow)
////                bumpIntoShow = try? container.decode(Bool.self, forKey: .bumpIntoShow)
////                enablePublicSearch = try? container.decode(Bool.self, forKey: .enablePublicSearch)
////                dobIsVerified = try? container.decode(Bool.self, forKey: .dobIsVerified)
////                genderIsVerified = try? container.decode(Bool.self, forKey: .genderIsVerified)
////                videoIsVerified = try? container.decode(Bool.self, forKey: .videoIsVerified)
////                gestureIsVerified = try? container.decode(Bool.self, forKey: .gestureIsVerified)
////                isFake = try? container.decode(Bool.self, forKey: .isFake)
////                isActive = try? container.decode(Bool.self, forKey: .isActive)
////                memExpired = try? container.decode(String.self, forKey: .memExpired)
////                createdAt = try? container.decode(String.self, forKey: .createdAt)
////                updatedAt = try? container.decode(String.self, forKey: .updatedAt)
////            
////        }
//}

struct NotifySettings: Codable {
    let appUpdates: Bool?
    let promotion: Bool?
    let newMatches: Bool?
    let newTipsAvailable: Bool?
    let newServiceAvailable: Bool?
    let profileVisit: Bool?
    let push: Bool?
    let email: Bool?
    let likesCommentsCalls: Bool?
    let discountAvailable: Bool?
    let newMessage: Bool?

    enum CodingKeys: String, CodingKey {
        case appUpdates = "app_updates"
        case promotion
        case newMatches = "new_matches"
        case newTipsAvailable = "new_tips_available"
        case newServiceAvailable = "new_service_available"
        case profileVisit = "profile_visit"
        case push
        case email
        case likesCommentsCalls = "likes_comments_calls"
        case discountAvailable = "discount_available"
        case newMessage = "new_message"
    }
}


// MARK: - Interest
struct Interest: Codable {
    let interestID: Int?
    let name: String?
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case interestID = "interest_id"
        case name, icon
    }
}

// MARK: - Detail
struct Detail: Codable {
    let icon: String?
    let name, key: String?
    let value: String?
}

// MARK: - Image
struct Image: Codable {
    let id: Int?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case imageURL = "image_url"
    }
}



// MARK: - MyMomentsModel
struct MyMomentsModel: Codable {
    let status: Bool?
    let message: String?
    let data: [MomentsDatum]?
    let imgBaseURL: String?

    enum CodingKeys: String, CodingKey {
        case status, message, data
        case imgBaseURL = "img_base_url"
    }
}

// MARK: - Images
struct Images: Codable {
    let image: String?
    let type: String?
    let is_primary: Bool?

    enum CodingKeys: String, CodingKey {
        case image
        case type
        case is_primary
    }
}
