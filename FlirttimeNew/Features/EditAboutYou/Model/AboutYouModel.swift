//
//  AboutYouModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 07/05/24.
//

import Foundation
import UIKit


// MARK: - GeneralQuestionsModel
struct GeneralQuestionsModel: Codable {
    let status: Bool?
    let message: String?
    let data: [QuestionData]?
}

// MARK: - Message
struct QuestionData: Codable {
    let id: Int?
    let title, question,icon: String?
    let generalText: String?
    let type: String?
    var options: [GeneralOption]?

    enum CodingKeys: String, CodingKey {
        case id, title, question
        case generalText = "general_text"
        case type, options,icon
    }
}

// MARK: - Option
struct GeneralOption: Codable {
    let questionID: Int?
    let name: String?
    var isSelected : Bool?

    enum CodingKeys: String, CodingKey {
        case questionID = "question_id"
        case name, isSelected
    }
}

// MARK: - UserInterestModel
struct UserInterestModel: Codable {
    let status:Bool?
    let message: String?
    let data: UserInterest?
}

// MARK: - UserInterestModelData
struct UserInterest: Codable {
    let data: UserInterestData?
}

// MARK: - DataClass
struct UserInterestData: Codable {
    let title, question, generalText, type: String?
    let profileIcon, icon: String?
    var options: [InterestOption]?

    enum CodingKeys: String, CodingKey {
        case title, question
        case generalText = "general_text"
        case type, options,icon
        case profileIcon = "profile_icon"
    }
}

// MARK: - Option
struct InterestOption: Codable {
    let name: String?
    let icon: String?
    let id: Int?
    var checked: Bool?
}


struct AboutYouHeaderModel{
    var headerLabel1:String?
    var subHeaderLabel:String?
    var aboutQuestionLabel:String?
}

struct AboutYouModel{
    var title:String?
    var image:String? = nil
    var isSelected:Bool?
}

struct AboutYouImageModel{
    var image:UIImage?
    var isSelected:Bool? = false
}


struct AboutYouPostModel: Codable {
    let questionID: String?
    let answer: String?

    enum CodingKeys: String, CodingKey {
        case questionID = "question_id"
        case answer
    }
}

// MARK: - PostAboutYouResposneModel
struct AboutYouResposneModel: Codable {
    let status: Bool?
    let message: String?
}
