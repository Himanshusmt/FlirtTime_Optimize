//
//  CoinsModel.swift
//  FlirttimeNew
//
//  Server models for the `coin-packages` and coin purchase endpoints.
//

import Foundation

struct CoinsModel: Codable {
    let status: Bool?
    let message: String?
    let data: [CoinData]?
}

struct CoinData: Codable, Hashable {
    let id: Int?
    let name: String?
    let coins: Int?
    var price: String?
    let currency: String?
    let bonusCoins: Int?
    let isActive: Int?
    let appleProductID: String?
    let googleProductID: String?
    let sortOrder: Int?
    let tag: String?

    enum CodingKeys: String, CodingKey {
        case id, name, coins, price, currency, tag
        case bonusCoins = "bonus_coins"
        case isActive = "is_active"
        case appleProductID = "apple_product_id"
        case googleProductID = "google_product_id"
        case sortOrder = "sort_order"
    }

    /// The App Store product id; older packages only carry the shared Play Store id.
    var storeProductID: String? {
        let apple = appleProductID?.trimmingCharacters(in: .whitespaces)
        return (apple?.isEmpty == false) ? apple : googleProductID
    }

    var totalCoins: Int {
        (coins ?? 0) + (bonusCoins ?? 0)
    }
}

struct CoinPurchaseResponse: Codable {
    let status: Bool
    let message: String
    let data: CoinBalanceData?
}

struct CoinBalanceData: Codable {
    let balance: Int?
}
