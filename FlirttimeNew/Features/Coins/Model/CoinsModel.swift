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

struct CoinPurchaseResponse: Decodable {
    let status: Bool?
    let success: Bool?
    let message: String?
    let data: CoinPurchaseData?

    /// Backend may set either `status` or `success`.
    var isSuccessful: Bool { status == true || success == true }
}

struct CoinPurchaseData: Decodable {
    let alreadyProcessed: Bool?
    let purchaseId: String?
    let package: CoinPurchasePackageInfo?
    let coinsCredited: Int?
    let baseCoins: Int?
    let bonusCoins: Int?
    let previousBalance: Int?
    let currentBalance: Int?
    let status: String?
    let acknowledged: Bool?
    /// Legacy mock field; prefer `currentBalance`.
    let balance: Int?

    var walletBalance: Int? { currentBalance ?? balance }

    enum CodingKeys: String, CodingKey {
        case alreadyProcessed, purchaseId, package, coinsCredited, baseCoins, bonusCoins
        case previousBalance, currentBalance, status, acknowledged, balance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alreadyProcessed = try? c.decodeIfPresent(Bool.self, forKey: .alreadyProcessed)
        purchaseId = try? c.decodeIfPresent(String.self, forKey: .purchaseId)
        package = try? c.decodeIfPresent(CoinPurchasePackageInfo.self, forKey: .package)
        coinsCredited = Self.decodeInt(c, .coinsCredited)
        baseCoins = Self.decodeInt(c, .baseCoins)
        bonusCoins = Self.decodeInt(c, .bonusCoins)
        previousBalance = Self.decodeInt(c, .previousBalance)
        currentBalance = Self.decodeInt(c, .currentBalance)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        acknowledged = try? c.decodeIfPresent(Bool.self, forKey: .acknowledged)
        balance = Self.decodeInt(c, .balance)
    }

    private static func decodeInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        return nil
    }
}

struct CoinPurchasePackageInfo: Decodable {
    let id: Int?
    let name: String?
    let productId: String?
}

// MARK: - Wallet balance (`GET /api/v1/wallet/balance`)

struct WalletBalanceResponse: Decodable {
    let status: Bool?
    let success: Bool?
    let message: String?
    let data: WalletBalanceData?

    var isSuccessful: Bool { status == true || success == true }
}

struct WalletBalanceData: Decodable {
    let userId: String?
    let coins: Int?
    let recentTransactions: [WalletTransaction]?

    enum CodingKeys: String, CodingKey {
        case userId, coins, recentTransactions
        case user_id, coin_balance, balance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decodeIfPresent(String.self, forKey: .userId) {
            userId = s
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .user_id) {
            userId = s
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .userId) {
            userId = String(i)
        } else {
            userId = nil
        }
        // Prefer `coins`; accept common aliases so a schema tweak doesn't leave the UI on stale/mock values.
        coins = Self.decodeInt(c, keys: [.coins, .coin_balance, .balance])
        recentTransactions = (try? c.decodeIfPresent([WalletTransaction].self, forKey: .recentTransactions)) ?? nil
    }

    private static func decodeInt(_ c: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> Int? {
        for key in keys {
            if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
            if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
            if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        }
        return nil
    }
}

struct WalletTransaction: Decodable {
    let id: String?
    let type: String?
    let amount: Int?
    let balanceBefore: Int?
    let balanceAfter: Int?
    let description: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, type, amount, description, createdAt
        case balanceBefore, balanceAfter
        case balance_before, balance_after, created_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decodeIfPresent(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .id) {
            id = String(i)
        } else {
            id = nil
        }
        type = try? c.decodeIfPresent(String.self, forKey: .type)
        amount = Self.decodeInt(c, key: .amount)
        balanceBefore = Self.decodeInt(c, key: .balanceBefore) ?? Self.decodeInt(c, key: .balance_before)
        balanceAfter = Self.decodeInt(c, key: .balanceAfter) ?? Self.decodeInt(c, key: .balance_after)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt))
            ?? (try? c.decodeIfPresent(String.self, forKey: .created_at))
    }

    private static func decodeInt(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        return nil
    }
}
