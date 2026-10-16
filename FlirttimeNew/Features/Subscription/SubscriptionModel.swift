//
//  SubscriptionModel.swift
//  FlirttimeNew
//
//  Server models for the `subscriptions` and subscription purchase verify endpoints.
//

import Foundation

struct SubscriptionPurchaseResponse: Codable {
    let status: Bool?
    let success: Bool?
    let message: String
    let data: SubscriptionPurchaseData?

    /// Backend may set either `status` or `success`.
    var isSuccessful: Bool { status == true || success == true }
}

struct SubscriptionPurchaseData: Codable {
    let alreadyProcessed: Bool?
    let isActive: Bool?
    let productId: String?
    let transactionId: String?
    let expiresAt: String?
    let bonusCoins: Int?
    let previousBalance: Int?
    let currentBalance: Int?
    let status: String?

    var walletBalance: Int? { currentBalance }
}

// MARK: - My subscription (`GET /api/v1/subscriptions/my`)

struct MySubscriptionResponse: Decodable {
    let status: Bool?
    let success: Bool?
    let message: String?
    /// Present when the user has (or had) a subscription record.
    let membership: MySubscriptionData?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        status = c.bool("status")
        success = c.bool("success")
        message = c.string("message")
        if let nested = c.first(MySubscriptionData.self, "data", "subscription", "membership") {
            membership = nested.hasSubscriptionContent ? nested : nil
        } else if let direct = try? MySubscriptionData(from: decoder), direct.hasSubscriptionContent {
            membership = direct
        } else {
            membership = nil
        }
    }
}

/// Active (or recent) Premium membership for the signed-in user.
struct MySubscriptionData: Decodable, Equatable {
    let id: String?
    let planName: String?
    let productId: String?
    let platform: String?
    let status: String?
    let isActive: Bool?
    let autoRenew: Bool?
    let price: String?
    let currency: String?
    let billingCycle: String?
    let purchasedAt: String?
    let expiresAt: String?
    let transactionId: String?
    let originalTransactionId: String?
    let bonusCoins: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        if let intId = c.int("id") {
            id = String(intId)
        } else {
            id = c.string("id", "subscriptionId")
        }
        planName = c.string("planName", "name", "title", "plan", "plan_name")
            ?? c.first(MySubscriptionPlanInfo.self, "plan")?.name
        productId = c.string("productId", "product_id", "appleProductId", "apple_product_id")
            ?? c.first(MySubscriptionPlanInfo.self, "plan")?.productId
        platform = c.string("platform", "store", "paymentGateway", "payment_gateway")
        status = c.string("status")
        isActive = c.bool("isActive", "is_active", "isSubscribed", "is_subscribed")
            ?? status.map { $0.lowercased() == "active" || $0.lowercased() == "subscribed" }
        autoRenew = c.bool("autoRenew", "auto_renew", "willAutoRenew", "will_auto_renew", "isRecurring", "is_recurring")
        if let amount = c.first(Double.self, "price", "paidAmount", "paid_amount", "amount") {
            price = String(amount)
        } else {
            price = c.string("price", "paidAmount", "paid_amount", "amount")
        }
        currency = c.string("currency")
        billingCycle = c.string("billingCycle", "billing_cycle", "duration", "period")
            ?? c.first(MySubscriptionPlanInfo.self, "plan")?.billingCycle
        purchasedAt = c.string("purchasedAt", "purchaseDate", "purchase_date", "startDate", "start_date",
                               "startsAt", "starts_at", "createdAt", "created_at")
        expiresAt = c.string("expiresAt", "expirationDate", "expiration_date", "endDate", "end_date",
                             "renewsAt", "renews_at", "nextBillingDate", "next_billing_date")
        transactionId = c.string("transactionId", "transaction_id")
        originalTransactionId = c.string("originalTransactionId", "original_transaction_id")
        bonusCoins = c.int("bonusCoins", "bonus_coins")
    }

    /// Enough fields to treat this as a real membership payload (vs an empty `{}`).
    var hasSubscriptionContent: Bool {
        planName != nil || productId != nil || status != nil || isActive != nil || expiresAt != nil || id != nil
    }

    var isCurrentlyActive: Bool {
        if let isActive { return isActive }
        if let status {
            let value = status.lowercased()
            return value == "active" || value == "subscribed" || value == "trialing"
        }
        guard let end = Self.parseDate(expiresAt) else { return false }
        return end > Date()
    }

    var displayPlanName: String {
        if let planName, !planName.isEmpty { return planName }
        if let billingCycle, !billingCycle.isEmpty { return billingCycle.capitalized }
        return "Premium"
    }

    var displayPrice: String? {
        guard let price, !price.isEmpty else { return nil }
        if let decimal = Decimal(string: price) {
            return PremiumViewModel.format(decimal, currency: currency)
        }
        if let currency, !currency.isEmpty { return "\(currency) \(price)" }
        return price
    }

    var displayPlatform: String {
        switch platform?.lowercased() {
        case "ios", "apple", "appstore", "app_store", "applepay": return "App Store"
        case "android", "google", "play", "playstore", "play_store": return "Google Play"
        case let value? where !value.isEmpty: return value.capitalized
        default: return "App Store"
        }
    }

    var displayStatus: String {
        if isCurrentlyActive { return "Active" }
        if let status, !status.isEmpty { return status.capitalized }
        return "Inactive"
    }

    var formattedExpiry: String? {
        guard let date = Self.parseDate(expiresAt) else { return expiresAt }
        return Self.dateTimeFormatter.string(from: date)
    }

    var formattedPurchaseDate: String? {
        guard let date = Self.parseDate(purchasedAt) else { return purchasedAt }
        return Self.dateTimeFormatter.string(from: date)
    }

    /// Whole days until `expiresAt`. `nil` when the end date is unknown.
    var daysRemaining: Int? {
        guard let end = Self.parseDate(expiresAt) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: end)).day
        return days.map { max($0, 0) }
    }

    var daysRemainingTitle: String? {
        guard let days = daysRemaining else { return nil }
        if days == 0 { return "Ends today" }
        return "\(days) day\(days == 1 ? "" : "s") left"
    }

    var daysRemainingSubtitle: String {
        if autoRenew == true { return "Renews automatically before this ends" }
        return isCurrentlyActive ? "Subscription ends soon" : "Subscription ended"
    }

    var priceLine: String? {
        guard let price = displayPrice else { return nil }
        if let cycle = billingCycle?.trimmingCharacters(in: .whitespaces), !cycle.isEmpty {
            return "\(price) / \(cycle.lowercased())"
        }
        return price
    }

    var renewalSummary: String {
        guard let expiry = formattedExpiry else {
            return autoRenew == true ? "Renews automatically" : "Active membership"
        }
        if autoRenew == true {
            return "Renews on \(expiry)"
        }
        return isCurrentlyActive ? "Expires on \(expiry)" : "Ended on \(expiry)"
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return MomentsDate.date(from: string) ?? dayFormatter.date(from: String(string.prefix(10)))
    }
}

private struct MySubscriptionPlanInfo: Decodable {
    let name: String?
    let productId: String?
    let billingCycle: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        name = c.string("name", "title", "planName")
        productId = c.string("productId", "product_id", "appleProductId", "apple_product_id")
        billingCycle = c.string("billingCycle", "billing_cycle")
    }
}

struct SubscriptionModel: Codable {
    let status: Bool?
    let message: String?
    let data: [SubscriptionPlanData]?
    let imgBaseURL: String?

    enum CodingKeys: String, CodingKey {
        case status, message, data
        case imgBaseURL = "img_base_url"
    }
}

struct PlanFeature: Codable, Hashable {
    let id: Int?
    let text: String?
    let image: String?
}

struct SubscriptionPlanData: Codable, Hashable {
    let id: Int?
    let name: String?
    let price: String?
    let currency: String?
    let durationDays: Int?
    let isActive: Bool?
    let description: String?
    let bonusCoins: Int?
    let isRecurring: Bool?
    let billingCycle: String?
    let trialPeriod: String?
    let features: [PlanFeature]?
    let googleProductID: String?
    let appleProductID: String?
    let icon: String?
    let sortOrder: Int?
    let isPopular: Bool?
    let iconURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name, price, currency, description, features, icon
        case durationDays = "duration_days"
        case isActive = "is_active"
        case bonusCoins = "bonus_coins"
        case isRecurring = "is_recurring"
        case billingCycle = "billing_cycle"
        case trialPeriod = "trial_period"
        case googleProductID = "google_product_id"
        case appleProductID = "apple_product_id"
        case sortOrder = "sort_order"
        case isPopular = "is_popular"
        case iconURL = "icon_url"
    }
}

extension SubscriptionPlanData {

    /// "1 Week", "6 Months", "1 Year"…
    var durationTitle: String {
        guard let days = durationDays, days > 0 else { return billingCycle?.capitalized ?? "" }
        switch days {
        case ..<28: return days % 7 == 0 ? plural(days / 7, "Week") : plural(days, "Day")
        case ..<360: return plural(Int((Double(days) / 30).rounded()), "Month")
        default: return plural(Int((Double(days) / 365).rounded()), "Year")
        }
    }

    /// "week", "month", "6 months", "year" for "₹499 every month".
    var renewalPeriod: String {
        let title = durationTitle.lowercased()
        return title.hasPrefix("1 ") ? String(title.dropFirst(2)) : title
    }

    var weeks: Double {
        Double(max(durationDays ?? 7, 1)) / 7
    }

    private func plural(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }
}
