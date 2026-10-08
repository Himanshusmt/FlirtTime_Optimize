//
//  EditProfileModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 03/07/24.
//

import Foundation
import UIKit

enum selectImageType{
    case addSelfImage
    case addCoverImage
}

struct MoreAboutMe {
    var key:String?
    var index:Int?
}

// MARK: - MoreAboutMeQuestionModel
struct MoreAboutMeQuestionModel: Codable {
    let status: Bool?
    let message: String?
    let data: [MoreAboutMeData]?
}

// MARK: - Datum
struct MoreAboutMeData: Codable {
    let id: Int?
    let question: String?
    let type: String?
    let icon: String?
    var options: [MoreAboutOption]?
}

// MARK: - Option
struct MoreAboutOption: Codable {
    let questionID: Int?
    let name: String?
    let icon: String?
    var isSelected:Bool?

    enum CodingKeys: String, CodingKey {
        case questionID = "question_id"
        case name, icon,isSelected
    }
}

struct EditProfileImageModel{
    var image:UIImage?
    var id:Int?
    var status:Int?
    //1 Verified, 2 Pending, 3 Rejected
    var isPrimary:Bool?
}

struct VerifyEmailData: Codable {
    let status: Bool?
    let message: String?
}
