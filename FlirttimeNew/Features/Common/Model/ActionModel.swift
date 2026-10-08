//
//  ActionModel.swift
//  FlirtTime
//
//  Created by Smt MacMini on 03/12/24.
//

import Foundation

struct ActionData: Decodable {
    let status: Bool?
    let message: String?
    let file:String?
    let exception:String?
    let data: MyData?
    //let data: [MyData]?
}

struct MyData: Decodable {
    // Define properties of the object inside "data"
//    let id: Int
//    let name: String
    
    let membership_required: Bool?
    let current_balance: Int?
    let match_image: String?
    let match_display_name: String?
    let coin_required: Bool?
    let is_match: Bool?
    let match_user_id: Int?
    
    
}
