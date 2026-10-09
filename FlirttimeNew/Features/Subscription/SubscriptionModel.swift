//
//  SubscriptionModel.swift
//  FlirttimeNew
//
//  Server models for the `subscriptions`, `subscription/create` and `subscription/check` endpoints.
//

import Foundation

/// Payload sent to `subscription/create` after a successful App Store purchase.
struct Subscription {
    var title: String
    var description: String
    var productID: String
    var transactionID: String
    var paidAmount: Double
    var currency: String
    var startDate: String
    var endDate: String
    var paymentGateway: String

    var parameters: [String: Any] {
        ["title": title,
         "description": description,
         "product_id": productID,
         "transaction_id": transactionID,
         "paid_amount": paidAmount,
         "currency": currency,
         "start_date": startDate,
         "end_date": endDate,
         "payment_gateway": paymentGateway]
    }
}

struct SubscriptionResponse: Codable {
    let status: Bool
    let message: String
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
