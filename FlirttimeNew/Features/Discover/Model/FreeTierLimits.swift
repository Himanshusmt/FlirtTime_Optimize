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
        matchRefreshWork.disposed(by: disposeBag)
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
        // Server `isSubscribed` wins once limits have loaded so a stale local flag
        // cannot keep a free account unlocked.
        if let subscribed = limits?.isSubscribed {
            return subscribed
        }
        return UserDataManager.shared.isUserSubscriptionDone == true
    }

    /// Free users with no matches cannot open the Messages tab at all.
    var canAccessChatModule: Bool {
        isPremium || hasMatches
    }

    /// Audio / video calling is Premium-only. Free users see the subscription sheet.
    var canMakeCall: Bool {
        isPremium
    }

    /// At least one mutual match. Persisted so the Messages tab can gate immediately.
    @Published private(set) var hasMatches: Bool = FreeTierLimitsStore.loadPersistedHasMatches()
    @Published private(set) var matchedUserIds: Set<String> = FreeTierLimitsStore.loadPersistedMatchedIds()

    private static let hasMatchesKey = "ft.freeTier.hasMatches"
    private static let matchedIdsKey = "ft.freeTier.matchedUserIds"
    private static let dailyQuickMomentViews = 3
    private static let dailyQuickMomentAdds = 1
    private let matchRefreshWork = SerialDisposable()

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

    /// Free users may only open a 1:1 chat with that specific matched person.
    /// Having any match does not unlock every conversation. Groups stay Premium-only.
    func canStartChat(withUserId userId: String?, isMatchedHint: Bool = false, isGroupOrChannel: Bool = false) -> Bool {
        canStartChat(withUserIds: [userId], isMatchedHint: isMatchedHint, isGroupOrChannel: isGroupOrChannel)
    }

    func canStartChat(withUserIds userIds: [String?], isMatchedHint: Bool = false, isGroupOrChannel: Bool = false) -> Bool {
        if isPremium { return true }
        if isGroupOrChannel { return false }
        if isMatchedHint { return true }
        if userIds.contains(where: { isMatched(with: $0) }) { return true }
        return canStartChat(isMatched: false)
    }

    func isMatched(with userId: String?) -> Bool {
        possibleIds(from: userId).contains(where: { matchedUserIds.contains($0) })
    }

    func markHasMatch(userId: String? = nil) {
        recordMatchedIds([userId])
        hasMatches = true
        persistHasMatches(true)
    }

    func recordMatchedIds(_ ids: [String?]) {
        var next = matchedUserIds
        for id in ids {
            possibleIds(from: id).forEach { next.insert($0) }
        }
        guard next != matchedUserIds else { return }
        matchedUserIds = next
        persistMatchedIds(next)
        if !next.isEmpty {
            hasMatches = true
            persistHasMatches(true)
        }
    }

    func canViewOthersQuickMoments(userId: String?) -> Bool {
        if isPremium { return true }
        let id = normalizedId(userId) ?? ""
        if !id.isEmpty, viewedQuickMomentUserIdsToday().contains(id) { return true }
        return viewedQuickMomentUserIdsToday().count < Self.dailyQuickMomentViews
    }

    func consumeQuickMomentView(userId: String?) {
        guard !isPremium, let userId = normalizedId(userId) else { return }
        var ids = viewedQuickMomentUserIdsToday()
        guard ids.insert(userId).inserted else { return }
        UserDefaults.standard.set(Array(ids), forKey: quickMomentViewsKey())
    }

    func canAddQuickMoment(existingCreatedToday: Int = 0) -> Bool {
        if isPremium { return true }
        return max(addedQuickMomentsToday(), existingCreatedToday) < Self.dailyQuickMomentAdds
    }

    func consumeQuickMomentAdd() {
        guard !isPremium else { return }
        UserDefaults.standard.set(max(addedQuickMomentsToday() + 1, 1), forKey: quickMomentAddsKey())
    }

    /// Keeps the local daily add counter in sync with moments already on the server / tray.
    func syncAddedQuickMoments(from moments: [QuickMoment]) {
        let today = createdTodayCount(in: moments)
        guard today > addedQuickMomentsToday() else { return }
        UserDefaults.standard.set(today, forKey: quickMomentAddsKey())
    }

    func createdTodayCount(in moments: [QuickMoment]) -> Int {
        moments.filter { moment in
            guard let date = MomentsDate.date(from: moment.createdAt) else { return false }
            return Calendar.current.isDateInToday(date)
        }.count
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
            hasMatches = false
            matchedUserIds = []
            persistHasMatches(false)
            persistMatchedIds([])
            return
        }
        refreshMatchStatus()
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

    func refreshMatchStatus() {
        guard sessionManager.isLoggedIn else { return }
        let counts = sessionManager.interactionCounts()
        let matches = sessionManager.interactions(type: "matches", limit: 50)
        matchRefreshWork.disposable = Single.zip(counts, matches)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] counts, page in
                guard let self else { return }
                self.recordMatchedIds(page.items.flatMap { [$0.userId, $0.id] })
                let matched = counts.matches > 0 || (page.totalCount ?? 0) > 0 || !self.matchedUserIds.isEmpty
                self.hasMatches = matched
                self.persistHasMatches(matched)
            }, onFailure: { error in
                AppLogger.debug("[Limits] match status failed: \(parseError(error) ?? error.localizedDescription)")
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

    private func normalizedId(_ userId: String?) -> String? {
        possibleIds(from: userId).first
    }

    private func possibleIds(from userId: String?) -> [String] {
        guard let raw = userId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return []
        }
        var ids = [raw.lowercased()]
        if let intValue = Int(raw) {
            ids.append(String(intValue))
        }
        return Array(Set(ids))
    }

    private func persistHasMatches(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Self.hasMatchesKey)
    }

    private func persistMatchedIds(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: Self.matchedIdsKey)
    }

    private static func loadPersistedHasMatches() -> Bool {
        UserDefaults.standard.bool(forKey: hasMatchesKey)
    }

    private static func loadPersistedMatchedIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: matchedIdsKey) ?? [])
    }

    private func currentUserScope() -> String {
        UserDataManager.shared.appUser?.id
            ?? UserDataManager.shared.userID.map(String.init)
            ?? "anon"
    }

    private func todayStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func quickMomentViewsKey() -> String {
        "ft.qm.views.\(currentUserScope()).\(todayStamp())"
    }

    private func quickMomentAddsKey() -> String {
        "ft.qm.adds.\(currentUserScope()).\(todayStamp())"
    }

    private func viewedQuickMomentUserIdsToday() -> Set<String> {
        Set((UserDefaults.standard.stringArray(forKey: quickMomentViewsKey()) ?? []).compactMap(normalizedId))
    }

    private func addedQuickMomentsToday() -> Int {
        UserDefaults.standard.integer(forKey: quickMomentAddsKey())
    }
}
