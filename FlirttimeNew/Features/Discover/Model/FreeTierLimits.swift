//
//  FreeTierLimits.swift
//  FlirttimeNew
//
//  GET /api/v1/users/limits — daily like quota, Super Like coins, Explore tab locks.
//

import Foundation
import Combine
import RxSwift
import Swinject

// MARK: - Models

struct UserLimits: Codable {
    let isSubscribed: Bool?
    let likes: LikeQuota?
    let nopes: NopeQuota?
    let superLikes: SuperLikeQuota?
    let tabs: TabLocks?
    let chat: ChatAccess?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        isSubscribed = c.bool("isSubscribed", "is_subscribed")
        likes = c.first(LikeQuota.self, "likes")
        nopes = c.first(NopeQuota.self, "nopes")
        superLikes = c.first(SuperLikeQuota.self, "superLikes", "super_likes")
        tabs = c.first(TabLocks.self, "tabs")
        chat = c.first(ChatAccess.self, "chat")
    }
}

struct LikeQuota: Codable {
    let limit: Int?
    let used: Int?
    let remaining: Int?
    let resetsAt: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        limit = c.int("limit")
        used = c.int("used")
        remaining = c.int("remaining")
        resetsAt = c.string("resetsAt", "resets_at")
    }
}

struct NopeQuota: Codable {
    let isUnlimited: Bool?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        isUnlimited = c.bool("isUnlimited", "is_unlimited")
    }
}

struct SuperLikeQuota: Codable {
    let hasFree: Bool?
    let freeRemaining: Int?
    let costInCoins: Int?
    let userCoins: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        hasFree = c.bool("hasFree", "has_free")
        freeRemaining = c.int("freeRemaining", "free_remaining")
        costInCoins = c.int("costInCoins", "cost_in_coins")
        userCoins = c.int("userCoins", "user_coins", "userCoinBalance")
    }
}

struct TabLocks: Codable {
    let likesTabLocked: Bool?
    let complimentsTabLocked: Bool?
    let youLikedTabLocked: Bool?
    let matchesTabLocked: Bool?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        likesTabLocked = c.bool("likesTabLocked", "likes_tab_locked")
        complimentsTabLocked = c.bool("complimentsTabLocked", "compliments_tab_locked")
        youLikedTabLocked = c.bool("youLikedTabLocked", "you_liked_tab_locked")
        matchesTabLocked = c.bool("matchesTabLocked", "matches_tab_locked")
    }
}

struct ChatAccess: Codable {
    let canChatWithoutMatch: Bool?
    let requiresMatch: Bool?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: QMKey.self)
        canChatWithoutMatch = c.bool("canChatWithoutMatch", "can_chat_without_match")
        requiresMatch = c.bool("requiresMatch", "requires_match")
    }
}

enum FreeTierErrorCode {
    static let dailyLikeLimit = "DAILY_LIKE_LIMIT_REACHED"
    static let dailySwipeLimit = "DAILY_SWIPE_LIMIT_REACHED"
    static let insufficientCoins = "INSUFFICIENT_COINS"
    static let matchRequired = "MATCH_REQUIRED_TO_CHAT"

    static func matches(_ error: Error, _ code: String) -> Bool {
        let http = error as? APIHTTPError
        let tokens = [http?.code, http?.message, error.localizedDescription]
            .compactMap { $0?.uppercased().replacingOccurrences(of: " ", with: "_") }
        return tokens.contains { $0.contains(code) }
    }

    static func isDailyLikeLimit(_ error: Error) -> Bool {
        matches(error, dailyLikeLimit) || matches(error, dailySwipeLimit)
    }
}

// MARK: - Store

final class FreeTierLimitsStore {

    static let shared = FreeTierLimitsStore()

    @Published private(set) var limits: UserLimits?

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()
    private let refreshWork = SerialDisposable()
    private var skipRefreshUntil: Date?

    private init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
        refreshWork.disposed(by: disposeBag)
        NotificationCenter.default.addObserver(
            forName: .userSubscriptionStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    var isPremium: Bool {
        limits?.isSubscribed == true || UserDataManager.shared.isUserSubscriptionDone == true
    }

    var canLike: Bool {
        if isPremium { return true }
        guard let remaining = limits?.likes?.remaining else { return true }
        return remaining > 0
    }

    var canSuperLike: Bool {
        if hasFreeSuperLike { return true }
        let cost = limits?.superLikes?.costInCoins ?? 20
        let coins = limits?.superLikes?.userCoins ?? CoinWallet.shared.balance
        return coins >= cost
    }

    var hasFreeSuperLike: Bool {
        if limits?.superLikes?.hasFree == true { return true }
        return (limits?.superLikes?.freeRemaining ?? 0) > 0
    }

    func isTabLocked(_ tab: ExploreTab) -> Bool {
        switch tab {
        case .likes:
            return limits?.tabs?.likesTabLocked ?? !isPremium
        case .compliments:
            return limits?.tabs?.complimentsTabLocked ?? !isPremium
        case .youLiked:
            return limits?.tabs?.youLikedTabLocked ?? false
        case .matches:
            return limits?.tabs?.matchesTabLocked ?? false
        }
    }

    func canStartChat(isMatched: Bool) -> Bool {
        if isMatched || isPremium { return true }
        if limits?.chat?.canChatWithoutMatch == true { return true }
        if limits?.chat?.requiresMatch == false { return true }
        return false
    }

    func blockReason(for action: MomentsAction) -> MomentsActionError? {
        switch action {
        case .interested:
            return canLike ? nil : .likeLimitReached
        case .superVibe:
            return canSuperLike ? nil : .insufficientCoins
        case .notMyVibe, .nope:
            return nil
        }
    }

    func refresh() {
        guard sessionManager.isLoggedIn else {
            limits = nil
            return
        }
        if let skipRefreshUntil, skipRefreshUntil > Date() { return }
        refreshWork.disposable = sessionManager.userLimits()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] limits in
                self?.skipRefreshUntil = nil
                self?.apply(limits)
            }, onFailure: { [weak self] error in
                let status = (error as? APIHTTPError)?.statusCode ?? 0
                if status == 0 || status == 400 || status == 404 {
                    self?.skipRefreshUntil = Date().addingTimeInterval(120)
                }
                AppLogger.debug("[Limits] fetch failed: \(parseError(error) ?? error.localizedDescription)")
            })
    }

    func apply(_ limits: UserLimits) {
        self.limits = limits
        if let subscribed = limits.isSubscribed {
            UserDataManager.shared.applySubscriptionStatus(subscribed)
        }
        if let coins = limits.superLikes?.userCoins {
            CoinWallet.shared.update(coins)
        }
    }
}
