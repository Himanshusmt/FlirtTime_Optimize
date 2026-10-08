//
//  MomentModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 20/05/24.
//

import Foundation

// MARK: - MomentsModel
struct MomentsModel: Codable {
    let status: Bool?
    let message: String?
    let data: MomentsData?
    let imgBaseURL: String?

    enum CodingKeys: String, CodingKey {
        case status, message, data
        case imgBaseURL = "img_base_url"
    }
}

// MARK: - DataClass
struct MomentsData: Codable {
    let currentPage: Int?
    var data: [MomentsDatum]?
    let firstPageURL: String?
    let from, lastPage: Int?
    let lastPageURL: String?
    let links: [Link]?
    let nextPageURL, path: String?
    let perPage: Int?
    let prevPageURL: String?
    let to, total: Int?

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
        case to, total
    }
}

// MARK: - Datum
struct MomentsDatum: Codable {
    let id, userID: Int?
    let title: String?
    let body: String?
    let tags: String?
    let images: [String]?
    var likeCount, commentCount, shareCount, status: Int?
    let createdAt, updatedAt: String?
    let deletedAt: String?
    let userInfo: UserDetailInfo?
    var isLiked: Bool?
    let postImages: [PostImage]?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title, body, tags
        case images
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case shareCount = "share_count"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case userInfo = "user_info"
        case isLiked = "is_like"
        case postImages = "post_images"

    }
}

// MARK: - UserInfo
struct UserInfos: Codable {
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

// MARK: - PostImage
struct PostImage: Codable {
    let id, postID, userID: Int?
    let filename, filetype: String?
    let status: Int?
    let createdAt, updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case userID = "user_id"
        case filename, filetype, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}


// MARK: - Link
struct Link: Codable {
    let url: String?
    let label: String?
    let active: Bool?
}

// MARK: - LimeUnlikeModel
struct LikeUnlikeModel: Codable {
    let status: Bool?
    let message: String?
    let data: LikeUnlikeData?
}

// MARK: - DataClass
struct LikeUnlikeData: Codable {
    let id, userID,commentID: Int?
    let createdAt, updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
//        case postID = "post_id"
        case userID = "user_id"
        case commentID = "comment_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}


// MARK: - BlockAndReportModel
struct BlockAndReportModel: Codable {
    let status: Bool?
    let message: String?
    var postID:Int?
}

// MARK: - MomentShareModel
struct MomentShareModel: Codable {
    let status: Bool?
    let message: String?
    let data: MomentShareData?
}

struct SuccessModel: Codable {
    let status: Bool?
    let message: String?
}


// MARK: - MomentShareData
struct MomentShareData: Codable {
    let userID: Int?
    //let postID, updatedAt, createdAt: String?
    let id: Int?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
//        case postID = "post_id"
//        case updatedAt = "updated_at"
//        case createdAt = "created_at"
        case id
    }
}
