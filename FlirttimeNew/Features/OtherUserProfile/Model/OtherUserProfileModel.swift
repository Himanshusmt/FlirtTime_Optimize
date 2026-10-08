//
//  OtherUserProfileModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 17/05/24.
//

import Foundation

enum TrailingContent {
    case readmore
    case readless

    var text: String {
        switch self {
        case .readmore: return " More"
        case .readless: return " Less"
        }
    }
}

struct MoreAboutMeModel{
    var text1:String?
    var text2:String?
}
