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
        // Preferred shape: `{ data: { isSubscribed, plan, subscription, benefits } }`
        if let nested = c.first(MySubscriptionData.self, "data"), nested.hasSubscriptionContent {
            membership = nested
        } else if let nested = c.first(MySubscriptionData.self, "subscription", "membership"),
                  nested.hasSubscriptionContent {
            membership = nested
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
    let nextRenewalDate: String?
    let transactionId: String?
    let originalTransactionId: String?
    let bonusCoins: Int?
    let remainingValidity: RemainingValidity?
    let benefitTexts: [String]?

    /// Days left from the server countdown (preferred) or computed from `expiresAt`.
    struct RemainingValidity: Decodable, Equatable {
        let days: Int?
        let hours: Int?
        let minutes: Int?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: QMKey.self)
            days = c.int("days")
            hours = c.int("hours")
            minutes = c.int("minutes")
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        let plan = c.first(MySubscriptionPlanInfo.self, "plan")
        let detail = c.first(MySubscriptionDetail.self, "subscription")

        if let detailId = detail?.id {
            id = detailId
        } else if let intId = c.int("id") {
            id = String(intId)
        } else {
            id = c.string("id", "subscriptionId")
        }

        planName = plan?.name
            ?? c.string("planName", "name", "title", "plan_name")
        productId = detail?.productId
            ?? plan?.productId
            ?? c.string("productId", "product_id", "appleProductId", "apple_product_id")
        platform = detail?.platform
            ?? c.string("platform", "store", "paymentGateway", "payment_gateway")
        status = detail?.status ?? c.string("status")

        let topLevelActive = c.bool("isActive", "is_active", "isSubscribed", "is_subscribed")
        let expired = detail?.isExpired ?? c.bool("isExpired", "is_expired")
        if let topLevelActive {
            isActive = topLevelActive
        } else if let expired {
            isActive = !expired
        } else if let status {
            let value = status.lowercased()
            isActive = value == "active" || value == "subscribed" || value == "trialing"
        } else {
            isActive = nil
        }

        autoRenew = detail?.autoRenewing
            ?? c.bool("autoRenew", "auto_renew", "autoRenewing", "auto_renewing",
                      "willAutoRenew", "will_auto_renew", "isRecurring", "is_recurring")

        if let planPrice = plan?.price, !planPrice.isEmpty {
            price = planPrice
        } else if let amount = c.first(Double.self, "price", "paidAmount", "paid_amount", "amount") {
            price = String(amount)
        } else {
            price = c.string("price", "paidAmount", "paid_amount", "amount")
        }
        currency = plan?.currency ?? c.string("currency")
        billingCycle = plan?.billingCycle
            ?? c.string("billingCycle", "billing_cycle", "duration", "period")

        purchasedAt = detail?.startsAt
            ?? c.string("purchasedAt", "purchaseDate", "purchase_date", "startDate", "start_date",
                        "startsAt", "starts_at", "createdAt", "created_at")
        expiresAt = detail?.expiresAt
            ?? c.string("expiresAt", "expirationDate", "expiration_date", "endDate", "end_date",
                        "renewsAt", "renews_at", "nextBillingDate", "next_billing_date")
        nextRenewalDate = detail?.nextRenewalDate
            ?? c.string("nextRenewalDate", "next_renewal_date", "renewsAt", "renews_at")

        transactionId = c.string("transactionId", "transaction_id")
        originalTransactionId = c.string("originalTransactionId", "original_transaction_id")
        bonusCoins = plan?.includedCoins ?? c.int("bonusCoins", "bonus_coins", "includedCoins", "included_coins")
        remainingValidity = detail?.remainingValidity
            ?? c.first(RemainingValidity.self, "remainingValidity", "remaining_validity")
        benefitTexts = (c.first([PlanFeature].self, "benefits") ?? [])
            .compactMap(\.text)
            .filter { !$0.isEmpty }
            .nilIfEmpty
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

    var displayAutoRenewal: String {
        autoRenew == true ? "On" : "Off"
    }

    var formattedExpiry: String? {
        guard let date = Self.parseDate(expiresAt) else { return expiresAt }
        return Self.dateTimeFormatter.string(from: date)
    }

    var formattedPurchaseDate: String? {
        guard let date = Self.parseDate(purchasedAt) else { return purchasedAt }
        return Self.dateTimeFormatter.string(from: date)
    }

    var formattedNextRenewal: String? {
        let raw = nextRenewalDate ?? (autoRenew == true ? expiresAt : nil)
        guard let date = Self.parseDate(raw) else { return raw }
        return Self.dateTimeFormatter.string(from: date)
    }

    /// Whole days until expiry. Prefers server `remainingValidity.days`.
    var daysRemaining: Int? {
        if let days = remainingValidity?.days { return max(days, 0) }
        guard let end = Self.parseDate(expiresAt) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: end)).day
        return days.map { max($0, 0) }
    }

    /// Show the countdown only in the final 5 days before expiry.
    var shouldShowDaysRemaining: Bool {
        guard isCurrentlyActive, let days = daysRemaining else { return false }
        return days <= 5
    }

    var daysRemainingTitle: String? {
        guard shouldShowDaysRemaining else { return nil }
        if let remaining = remainingValidity {
            if let days = remaining.days, days > 0 {
                return "\(days) day\(days == 1 ? "" : "s") left"
            }
            if let hours = remaining.hours, hours > 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s") left"
            }
            if let minutes = remaining.minutes, minutes > 0 {
                return "\(minutes) min\(minutes == 1 ? "" : "s") left"
            }
        }
        guard let days = daysRemaining else { return nil }
        if days == 0 { return "Ends today" }
        return "\(days) day\(days == 1 ? "" : "s") left"
    }

    var daysRemainingSubtitle: String {
        if autoRenew == true { return "Auto-renewal is on — renews before this ends" }
        return isCurrentlyActive ? "Subscription ends soon" : "Subscription ended"
    }

    var priceLine: String? {
        guard let price = displayPrice else { return nil }
        if let cycle = billingCycle?.trimmingCharacters(in: .whitespaces), !cycle.isEmpty {
            return "\(price) / \(cycle.lowercased())"
        }
        return price
    }

    var autoRenewalLine: String {
        if autoRenew == true {
            if let next = formattedNextRenewal {
                return "Auto-renewal On · Next on \(next)"
            }
            return "Auto-renewal On"
        }
        return "Auto-renewal Off"
    }

    var renewalSummary: String {
        if autoRenew == true {
            if let next = formattedNextRenewal {
                return "Renews on \(next)"
            }
            return "Renews automatically"
        }
        guard let expiry = formattedExpiry else { return "Active membership" }
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
    let price: String?
    let currency: String?
    let includedCoins: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        name = c.string("name", "title", "planName")
        productId = c.string("productId", "product_id", "appleProductId", "apple_product_id")
        billingCycle = c.string("billingCycle", "billing_cycle")
        if let amount = c.first(Double.self, "price") {
            price = String(amount)
        } else {
            price = c.string("price")
        }
        currency = c.string("currency")
        includedCoins = c.int("includedCoins", "included_coins", "bonusCoins", "bonus_coins")
    }
}

private struct MySubscriptionDetail: Decodable {
    let id: String?
    let productId: String?
    let platform: String?
    let status: String?
    let autoRenewing: Bool?
    let isExpired: Bool?
    let startsAt: String?
    let expiresAt: String?
    let nextRenewalDate: String?
    let remainingValidity: MySubscriptionData.RemainingValidity?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        if let intId = c.int("id") {
            id = String(intId)
        } else {
            id = c.string("id", "subscriptionId")
        }
        productId = c.string("productId", "product_id")
        platform = c.string("platform")
        status = c.string("status")
        autoRenewing = c.bool("autoRenewing", "auto_renewing", "autoRenew", "auto_renew")
        isExpired = c.bool("isExpired", "is_expired")
        startsAt = c.string("startsAt", "starts_at", "startDate", "start_date")
        expiresAt = c.string("expiresAt", "expires_at", "endDate", "end_date")
        nextRenewalDate = c.string("nextRenewalDate", "next_renewal_date")
        remainingValidity = c.first(MySubscriptionData.RemainingValidity.self,
                                    "remainingValidity", "remaining_validity")
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
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
