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
    /// `true`/`false` from the API, or `1`/`0` from older payloads.
    let isActive: Bool?
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        coins = try container.decodeIfPresent(Int.self, forKey: .coins)
        price = try container.decodeIfPresent(String.self, forKey: .price)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        bonusCoins = try container.decodeIfPresent(Int.self, forKey: .bonusCoins)
        isActive = Self.decodeActive(from: container)
        appleProductID = try container.decodeIfPresent(String.self, forKey: .appleProductID)
        googleProductID = try container.decodeIfPresent(String.self, forKey: .googleProductID)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
        tag = try container.decodeIfPresent(String.self, forKey: .tag)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(coins, forKey: .coins)
        try container.encodeIfPresent(price, forKey: .price)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(bonusCoins, forKey: .bonusCoins)
        try container.encodeIfPresent(isActive, forKey: .isActive)
        try container.encodeIfPresent(appleProductID, forKey: .appleProductID)
        try container.encodeIfPresent(googleProductID, forKey: .googleProductID)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(tag, forKey: .tag)
    }

    private static func decodeActive(from container: KeyedDecodingContainer<CodingKeys>) -> Bool? {
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: .isActive) { return flag }
        if let flag = try? container.decodeIfPresent(Int.self, forKey: .isActive) { return flag != 0 }
        return nil
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
