//
//  MockStore.swift
//  FlirttimeNew
//
//  Local stand-in for the `subscriptions`, `subscription/create`, `subscription/check`,
//  `coin-packages` and coin purchase endpoints. Product ids match App Store Connect and
//  `FlirttimeStore.storekit`, so StoreKit purchases work against these responses unchanged.
//

import Foundation

final class MockStore {

    static let shared = MockStore()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let coinBalance = "mock_coin_balance"
        static let subscription = "mock_subscription"
        static let creditedTransactions = "mock_credited_coin_transactions"
    }
    private static let startingBalance = 40

    private init() {}

    // MARK: - Subscription plans

    func subscriptionPlansJSON() -> [String: Any] {
        let commonFeatures: [[String: Any]] = [
            ["id": 1, "text": "Unlimited Vibes every day", "image": "infinity"],
            ["id": 2, "text": "Chat without waiting for a match", "image": "bubble.left.and.bubble.right.fill"],
            ["id": 3, "text": "See who already liked you", "image": "eye.fill"]
        ]
        let plusFeatures: [[String: Any]] = [
            ["id": 4, "text": "5 Super Vibes every week", "image": "star.fill"],
            ["id": 5, "text": "Priority placement in Discover", "image": "bolt.fill"]
        ]
        let topFeatures: [[String: Any]] = [
            ["id": 6, "text": "Send unlimited compliments", "image": "gift.fill"],
            ["id": 7, "text": "Incognito browsing", "image": "eyeglasses"]
        ]
        let plans: [[String: Any]] = [
            plan(id: 1, name: "Weekly", price: "199.00", days: 7, cycle: "weekly", bonus: 0,
                 productID: "com.flirttime.weekly", sort: 1, popular: false,
                 description: "Try Premium for a week", features: commonFeatures),
            plan(id: 2, name: "Monthly", price: "499.00", days: 30, cycle: "monthly", bonus: 100,
                 productID: "com.flirttime.monthly", sort: 2, popular: true,
                 description: "Our most loved plan", features: commonFeatures + plusFeatures),
            plan(id: 3, name: "6 Months", price: "1999.00", days: 180, cycle: "half_yearly", bonus: 400,
                 productID: "com.flirttime.halfyearly", sort: 3, popular: false,
                 description: "Settle in and save", features: commonFeatures + plusFeatures + topFeatures),
            plan(id: 4, name: "Yearly", price: "2999.00", days: 365, cycle: "yearly", bonus: 1000,
                 productID: "com.flirttime.annual", sort: 4, popular: false,
                 description: "Best value for serious daters", features: commonFeatures + plusFeatures + topFeatures)
        ]
        return ["status": true, "message": "Subscriptions fetched successfully", "img_base_url": ApiName.imgBaseURL, "data": plans]
    }

    /// Mirrors `subscription/create`: activates the plan and credits its bonus coins.
    func createSubscriptionJSON(_ params: [String: Any], plan: SubscriptionPlanData) -> [String: Any] {
        guard let transactionID = params["transaction_id"] as? String, !transactionID.isEmpty else {
            return ["status": false, "message": "Missing transaction id"]
        }
        defaults.set(["plan_id": plan.id ?? 0, "end_date": params["end_date"] ?? "", "transaction_id": transactionID],
                     forKey: Key.subscription)
        if creditOnce(transactionID: transactionID) {
            coinBalance += plan.bonusCoins ?? 0
        }
        return ["status": true, "message": "Welcome to Flirttime Premium! Your \(plan.name ?? "") plan is active."]
    }

    func checkSubscriptionJSON() -> [String: Any] {
        guard let stored = defaults.dictionary(forKey: Key.subscription),
              let endDate = stored["end_date"] as? String,
              let end = MockStore.dayFormatter.date(from: endDate),
              end >= Calendar.current.startOfDay(for: Date()) else {
            return ["status": true, "message": "No active subscription", "data": ["is_active": false]]
        }
        return ["status": true, "message": "Subscription active",
                "data": ["is_active": true, "plan_id": stored["plan_id"] ?? 0, "end_date": endDate]]
    }

    // MARK: - Coins

    func coinPackagesJSON() -> [String: Any] {
        let packs: [(String, String, Int, String, Int, String?)] = [
            ("Starter", "starter_pack", 50, "49.00", 0, nil),
            ("Basic", "basic_pack", 100, "89.00", 0, nil),
            ("Bronze", "bronze_pack", 200, "169.00", 10, nil),
            ("Silver", "silver_pack", 350, "279.00", 25, nil),
            ("Gold", "gold_pack", 500, "399.00", 50, "popular"),
            ("Platinum", "platinum_pack", 800, "599.00", 100, nil),
            ("Diamond", "diamond_pack", 1200, "849.00", 200, nil),
            ("Elite", "elite_pack", 2000, "1299.00", 400, nil),
            ("Mega", "mega_pack", 3500, "1999.00", 800, nil),
            ("Royal", "royal_pack", 6000, "2999.00", 1500, "best_value")
        ]
        let data: [[String: Any]] = packs.enumerated().map { index, pack in
            var json: [String: Any] = [
                "id": index + 1,
                "name": pack.0,
                "coins": pack.2,
                "price": pack.3,
                "currency": "INR",
                "bonus_coins": pack.4,
                "is_active": 1,
                "apple_product_id": pack.1,
                "google_product_id": pack.1,
                "sort_order": index + 1
            ]
            json["tag"] = pack.5
            return json
        }
        return ["status": true, "message": "Coin packages fetched successfully", "data": data]
    }

    /// Mirrors the coin purchase endpoint; a transaction is only ever credited once.
    func purchaseCoinsJSON(package: CoinData, transactionID: String) -> [String: Any] {
        if creditOnce(transactionID: transactionID) {
            coinBalance += package.totalCoins
        }
        return ["status": true, "message": "\(package.totalCoins) coins added to your wallet",
                "data": ["balance": coinBalance]]
    }

    var coinBalance: Int {
        get { defaults.object(forKey: Key.coinBalance) as? Int ?? MockStore.startingBalance }
        set { defaults.set(max(0, newValue), forKey: Key.coinBalance) }
    }

    func reset() {
        [Key.coinBalance, Key.subscription, Key.creditedTransactions].forEach(defaults.removeObject)
    }

    // MARK: - Helpers

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func creditOnce(transactionID: String) -> Bool {
        var credited = Set(defaults.stringArray(forKey: Key.creditedTransactions) ?? [])
        guard credited.insert(transactionID).inserted else { return false }
        defaults.set(Array(credited), forKey: Key.creditedTransactions)
        return true
    }

    private func plan(id: Int, name: String, price: String, days: Int, cycle: String, bonus: Int,
                      productID: String, sort: Int, popular: Bool,
                      description: String, features: [[String: Any]]) -> [String: Any] {
        ["id": id, "name": name, "price": price, "currency": "INR", "duration_days": days,
         "is_active": true, "description": description, "bonus_coins": bonus, "is_recurring": true,
         "billing_cycle": cycle, "features": features, "google_product_id": productID,
         "apple_product_id": productID, "sort_order": sort, "is_popular": popular]
    }
}
