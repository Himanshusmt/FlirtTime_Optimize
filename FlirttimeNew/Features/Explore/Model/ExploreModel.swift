//
//  ExploreModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 21/05/24.
//

import Foundation
import UIKit

struct ExploreModel{
    var image:UIImage?
    var name:String?
    var isVerifiedUser:Bool?
}

struct FilterModel:Codable {
    var gender:String?
    var minAge:String?
    var maxAge:String?
    var distance:String?
    var isVerified:String?
    var isOnline:String?
}

struct InteractionResponse: Codable {
    let status: Bool
    let message: String
    let data: [UserInteraction]?
    let imgBaseURL: String
    
    enum CodingKeys: String, CodingKey {
        case status, message, data
        case imgBaseURL = "img_base_url"
    }
}

struct UserInteraction: Codable {
    let id: Int
    let userID: Int
    let toUserID: Int
    let interactionType: Int
    let createdAt: String
    let updatedAt: String
    let userInfo: UserDetailInfo?
    let toUserInfo: UserDetailInfo?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case toUserID = "to_user_id"
        case interactionType = "interaction_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userInfo = "user_info"
        case toUserInfo = "to_user_info"
    }
}

struct MyLikeInteractionResponse: Codable {
    let status: Bool
    let message: String
    var data: [MyLikeUserInteraction]
    let imgBaseURL: String
    
    enum CodingKeys: String, CodingKey {
        case status, message, data
        case imgBaseURL = "img_base_url"
    }
}

struct MyLikeUserInteraction: Codable {
    let id: Int
    let userID: Int
    let toUserID: Int
    let interactionType: Int
    let createdAt: String
    let updatedAt: String
    let userInfo: UserDetailInfo
    
    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case toUserID = "to_user_id"
        case interactionType = "interaction_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userInfo = "to_user_info"
    }
}

// MARK: - Root
struct ComplimentListResponse: Codable {
    let status: Bool
    let message: String?
    let data: ComplimentData?
    let imgBaseURL: String?

    enum CodingKeys: String, CodingKey {
        case status, message, data
        case imgBaseURL = "img_base_url"
    }
}

// MARK: - ComplimentData
struct ComplimentData: Codable {
    let currentPage: Int
    let compliments: [Compliment]?
    let firstPageURL: String
    let from: Int?
    let lastPage: Int
    let lastPageURL: String
    let links: [PageLink]?
    let nextPageURL: String?
    let path: String
    let perPage: Int
    let prevPageURL: String?
    let to: Int?
    let total: Int

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case compliments = "data"
        case firstPageURL = "first_page_url"
        case from, lastPage = "last_page"
        case lastPageURL = "last_page_url"
        case links
        case nextPageURL = "next_page_url"
        case path, perPage = "per_page"
        case prevPageURL = "prev_page_url"
        case to, total
    }
}

// MARK: - Compliment
struct Compliment: Codable { 
    let id: Int
    let senderID: Int
    let receiverID: Int
    let content: String
    let attachment: String?
    let isRead: Int
    let createdAt: String
    let updatedAt: String
    let sender: SenderProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case senderID = "sender_id"
        case receiverID = "receiver_id"
        case content, attachment
        case isRead = "is_read"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sender
    }
}

// MARK: - SenderProfile
struct SenderProfile: Codable {
    let id: Int?
    let userID: Int?
    let fullname: String
    let displayName: String
    let dob: String
    let gender: Int?
    let relationship: Int?
    let sexuality: Int?
    let height, weight: Int?
    let eyeColour:Int?
    let hairColour: Int?
    let living: Int?
    let children: Int?
    let drinking: Int?
    let motherTongue: String?
    let smoking: Int?
    let interests: [Int]?
    let religion: Int?
    let maritalStatus: Int?
    let education: Int?
    let employedIn: String?
    let aboutMe: String?
    let lat, lng: Double?
    let location: String?
    let avatar: String
    let banner: String?
    let images: [GalleryImage]
    let isOnline: Bool?
    let onlineTime: String
    let ageShow, distanceShow, locationShow, onlineShow: Bool?
    let bumpIntoShow, enablePublicSearch: Bool?
    let dobIsVerified, genderIsVerified, videoIsVerified, gestureIsVerified: Bool?
    let isFake, isActive: Bool
    let deviceType: String
    let fcmToken: String
    let memExpired: String?
    let activeChatID: Int?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case fullname, displayName = "display_name"
        case dob, gender, relationship, sexuality, height, weight
        case eyeColour = "eye_colour"
        case hairColour = "hair_colour"
        case living, children, smoking, drinking, interests
        case motherTongue = "mother_tongue"
        case maritalStatus = "marital_status"
        case religion, education, employedIn = "employed_in"
        case aboutMe = "about_me"
        case lat, lng, location, avatar, images
        case banner
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
        case activeChatID = "active_chat_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - GalleryImage
struct GalleryImage: Codable {
    let image: String
    let type: String
    let isPrimary: Bool?

    enum CodingKeys: String, CodingKey {
        case image, type
        case isPrimary = "is_primary"
    }
}

// MARK: - PageLink
struct PageLink: Codable {
    let url: String?
    let label: String
    let active: Bool
}

struct ReadComplimentResponse: Codable {
    let status: Bool
    let message: String?
    let data: ReadComplimentData?
    let imgBaseURL: String

    enum CodingKeys: String, CodingKey {
        case status, message, data
        case imgBaseURL = "img_base_url"
    }
}

struct ReadComplimentData: Codable {
    let id: Int
    let senderID: Int
    let receiverID: Int
    let content: String
    let attachment: String?
    let isRead: Int
    let createdAt: String
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case senderID = "sender_id"
        case receiverID = "receiver_id"
        case content, attachment
        case isRead = "is_read"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct GetCountModel : Codable {
    let status : Bool?
    let message : String?
    let data : GetCountData?
    let img_base_url : String?

    enum CodingKeys: String, CodingKey {

        case status = "status"
        case message = "message"
        case data = "data"
        case img_base_url = "img_base_url"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = try values.decodeIfPresent(Bool.self, forKey: .status)
        message = try values.decodeIfPresent(String.self, forKey: .message)
        data = try values.decodeIfPresent(GetCountData.self, forKey: .data)
        img_base_url = try values.decodeIfPresent(String.self, forKey: .img_base_url)
    }

}

struct GetCountData : Codable {
    let like_count : Int?
    let like_you_count : Int?
    let favorite_you_count : Int?
    let favorite_count : Int?
    let match_count : Int?
    let compliment_count : Int?

    enum CodingKeys: String, CodingKey {

        case like_count = "like_count"
        case like_you_count = "like_you_count"
        case favorite_you_count = "favorite_you_count"
        case favorite_count = "favorite_count"
        case match_count = "match_count"
        case compliment_count = "compliment_count"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        like_count = try values.decodeIfPresent(Int.self, forKey: .like_count)
        like_you_count = try values.decodeIfPresent(Int.self, forKey: .like_you_count)
        favorite_you_count = try values.decodeIfPresent(Int.self, forKey: .favorite_you_count)
        favorite_count = try values.decodeIfPresent(Int.self, forKey: .favorite_count)
        match_count = try values.decodeIfPresent(Int.self, forKey: .match_count)
        compliment_count = try values.decodeIfPresent(Int.self, forKey: .compliment_count)
    }

}
