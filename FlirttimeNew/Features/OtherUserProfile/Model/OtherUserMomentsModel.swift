//
//  OtherUserMomentsModel.swift
//  FlirtTime
//
//  Created by Smt MacMini on 08/01/25.
//

import Foundation

struct MomentUser: Codable {
    let status: Bool?
    let message: String?
    let data: MomentUserData
    let imgBaseURL: String?
    
    enum CodingKeys: String, CodingKey {
        case status
        case message
        case data
        case imgBaseURL = "img_base_url"
    }
}

struct MomentUserData: Codable {
    let currentPage: Int
    let data: [MomentImages] // Assuming data is an array of strings. Change type if necessary.
    let firstPageURL: String
    let from: Int?
    let lastPage: Int?
    let lastPageURL: String?
    let links: [LinkData]
    let nextPageURL: String?
    let path: String?
    let perPage: Int?
    let prevPageURL: String?
    let to: Int?
    let total: Int?
    
    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case data
        case firstPageURL = "first_page_url"
        case from
        case lastPage = "last_page"
        case lastPageURL = "last_page_url"
        case links
        case nextPageURL = "next_page_url"
        case path
        case perPage = "per_page"
        case prevPageURL = "prev_page_url"
        case to
        case total
    }
}

struct LinkData: Codable {
    let url: String?
    let label: String?
    let active: Bool?
}

struct MomentImages: Codable {
    let id: Int?
    let userID: Int
    let title: String?
    let body: String?
    let tags: String?
    let images: [String]
    var likeCount: Int?
    let commentCount: Int?
    var shareCount: Int?
    let status: Int?
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
    var isLike: Bool?
    let userInfo: UserInformation
    
    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case body
        case tags
        case images
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case shareCount = "share_count"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case isLike = "is_like"
        case userInfo = "user_info"
    }
}
struct UserInformation: Codable {
    let userID: Int?
    let fullname: String?
    let displayName: String?
    let avatar: String?
    
    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case fullname
        case displayName = "display_name"
        case avatar
    }
}
