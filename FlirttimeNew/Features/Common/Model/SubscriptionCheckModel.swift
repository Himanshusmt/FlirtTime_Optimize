//
//  SubscriptionCheckModel.swift
//  FlirttimeNew
//

import Foundation

struct CheckSubscriptionResponse: Codable {
    let status: Bool
    let message: String
    let data: CheckSubscriptionData?
}

struct CheckSubscriptionData: Codable {
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
    }
}

struct Complement: Codable {
    let status: Bool?
    let message: String?
}
