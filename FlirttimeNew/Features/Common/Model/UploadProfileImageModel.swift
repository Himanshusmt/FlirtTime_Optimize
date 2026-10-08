//
//  UploadProfileImageModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 06/05/24.
//

import Foundation


struct UploadProfileImageModel:Codable{
    let status : Bool?
    let message: String?
    let data: UploadProfileImageData?
    }

    // MARK: - DataClass
    struct UploadProfileImageData: Codable {
        let image_url: String?
        let uploadImg: UploadImg?
        //let original, thumbnail, the200X200: String?

        enum CodingKeys: String, CodingKey {
            case image_url
            case uploadImg = "image"
//            case original, thumbnail
//            case the200X200 = "200X200"
        }
    }

struct UploadImg: Codable {
    let userId: Int?
    let filename: String?
    let filetype: String?
    let filefor: String?
    let status: Int?
    let updatedAt: String?
    let createdAt: String?
    let id: Int?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case filename
        case filetype
        case filefor
        case status
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case id
    }
}
