//
//  SaveUserDetailResponseModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 06/06/24.
//

import Foundation


// MARK: - SaveUserDetailResponseModel
struct UserDetailResponseModel: Codable {
    let status: Bool?
    let message: String?
    let data: userDetailData?
}

// MARK: - DataClass
struct userDetailData: Codable {
    let id: Int?
    let user_id: Int?
    let display_name, fullname : String?
    let gender: Int?
    let avatar: String?

    enum CodingKeys: String, CodingKey {
        case id, user_id, display_name
        case fullname, gender, avatar
    }
}

struct SaveUserDetailModel:Codable{
    var signUpOption:SignUpOption?
    var emailID:String?
    var phoneNumber:String?
    var phoneCode:String?
    var firstName:String?
    var lastName:String?
    var nickName:String?
    var gender:String?
    var dateOfBirth:String?
    var aboutYou:String?
    var genderID: Int?
}

struct DisplayNameCheck: Codable {
    let message: String?
    let status: Bool?
    
    enum CodingKeys: String, CodingKey {
        case status, message
    }
}
