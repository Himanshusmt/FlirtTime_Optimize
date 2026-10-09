//
//  StoreManager.swift
//  FlirttimeNew
//
//  StoreKit 2 wrapper used by Premium (auto-renewable subscriptions) and the Coin Shop (consumables).
//

import Foundation
import StoreKit

enum StorePurchaseResult {
    case purchased(Transaction)
    case cancelled
    /// Waiting on Ask to Buy or SCA; the transaction arrives later through `Transaction.updates`.
    case pending
}

enum StoreError: LocalizedError {
    case productUnavailable
    case failedVerification
    case cannotMakePayments

    var errorDescription: String? {
        switch self {
        case .productUnavailable: return "This item isn't available on the App Store right now."
        case .failedVerification: return "We couldn't verify this purchase with the App Store."
        case .cannotMakePayments: return "Purchases are disabled on this device."
        }
    }
}

final class StoreManager {

    static let shared = StoreManager()

    /// Posted on the main queue when the active subscription changes outside a purchase flow
    /// (renewal, refund, Ask to Buy approval, purchase on another device).
    static let entitlementsDidChange = Notification.Name("StoreManager.entitlementsDidChange")

    private var productCache: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    private init() {}

    /// Call once at launch so transactions completed outside the app are not missed.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard let self, let transaction = try? self.verified(update) else { continue }
                await transaction.finish()
                await MainActor.run {
                    NotificationCenter.default.post(name: StoreManager.entitlementsDidChange, object: transaction)
                }
            }
        }
    }

    // MARK: - Products

    /// Products are returned in the order of `ids`; ids unknown to the App Store are skipped.
    @MainActor
    func products(for ids: [String]) async throws -> [Product] {
        let missing = Set(ids).subtracting(productCache.keys)
        if !missing.isEmpty {
            for product in try await Product.products(for: missing) {
                productCache[product.id] = product
            }
        }
        return ids.compactMap { productCache[$0] }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> StorePurchaseResult {
        guard AppStore.canMakePayments else { throw StoreError.cannotMakePayments }
        var options: Set<Product.PurchaseOption> = []
        if let userID = UserDataManager.shared.userID {
            options.insert(.appAccountToken(Self.accountToken(for: userID)))
        }
        switch try await product.purchase(options: options) {
        case .success(let verification):
            let transaction = try verified(verification)
            await transaction.finish()
            return .purchased(transaction)
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    /// Syncs with the App Store and returns the active subscription, if any.
    func restorePurchases() async throws -> Transaction? {
        try await AppStore.sync()
        return await activeSubscription()
    }

    // MARK: - Entitlements

    /// The latest active auto-renewable subscription, if any.
    func activeSubscription() async -> Transaction? {
        var latest: Transaction?
        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? verified(entitlement),
                  transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil,
                  (transaction.expirationDate ?? .distantFuture) > Date() else { continue }
            if latest == nil || transaction.purchaseDate > latest!.purchaseDate {
                latest = transaction
            }
        }
        return latest
    }

    func hasActiveSubscription() async -> Bool {
        await activeSubscription() != nil
    }

    // MARK: - Helpers

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw StoreError.failedVerification
        }
    }

    /// Stable per-user UUID so the server can tie App Store notifications back to the account.
    private static func accountToken(for userID: Int) -> UUID {
        let hex = String(repeating: "0", count: 32) + String(UInt64(bitPattern: Int64(userID)), radix: 16)
        let digits = Array(hex.suffix(32))
        let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(digits[$0]) }
        return UUID(uuidString: groups.joined(separator: "-")) ?? UUID()
    }
}
