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
    var interests:[Int]?
    var intents:[String]?
    /// Interest UUIDs from `discovery/filters/options`.
    var interestIds:[String]?
}
