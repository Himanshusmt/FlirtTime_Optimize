//
//  DiscoverViewModel.swift
//  FlirttimeNew
//

import Foundation
import Combine
import RxSwift
import Swinject

final class DiscoverViewModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    static let fallbackReason = "You may discover something new about each other."

    @Published private(set) var loadState: LoadState = .idle
    /// Remaining profiles after the interest filter; `deck[0]` is the active card.
    @Published private(set) var deck: [MomentsProfile] = []
    @Published private(set) var interestFilter: MomentsInterest?
    /// Saved filter-sheet preferences; the deck comes from `discovery/search` with these.
    @Published private(set) var preferences: FilterModel = .saved
    /// Choices for the filter sheet from GET `discovery/filters/options`; `nil` until loaded.
    @Published private(set) var filterOptions: DiscoveryFilterOptions?
    /// Quick Moments story tray for the Moments tab; `nil` until loaded.
    @Published private(set) var quickMomentTray: QuickMomentTray?
    /// Interests tab tiles from GET `interests`.
    @Published private(set) var interestCatalog: [InterestCatalogItem] = []
    /// People for the selected interest tile; `profiles` is `nil` while loading.
    @Published private(set) var interestPeople: (interestId: String, profiles: [MomentsProfile]?)?

    /// Set while an action is being sent; further gestures are ignored until it completes or fails.
    private(set) var actionInProgress = false

    /// Remaining profiles before the interest filter is applied.
    private var queue: [MomentsProfile] = []

    /// Everyone still available, ignoring the interest filter (Moments and Interests tabs).
    var everyone: [MomentsProfile] { queue }
    var currentProfile: MomentsProfile? { deck.first }
    var nextProfile: MomentsProfile? { deck.dropFirst().first }

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    private static let pageSize = 10
    /// The next page is fetched once this few cards are left.
    private static let prefetchThreshold = 3
    private var nextPage = 1
    private var hasMorePages = true
    private var isFetchingPage = false
    /// Everyone already shown or acted on, so a later page never repeats a card.
    private var seenUserIDs = Set<String>()
    private var isLoadingInterestCatalog = false
    /// Bumped when filters change, so pages requested with the old filters are dropped.
    private var deckGeneration = 0
    private var didLoadSavedFilters = false
    private var isLoadingFilterOptions = false

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    // MARK: - Loading

    /// The first call loads the saved filters from GET `discovery/filters` before the deck.
    func loadRecommendations() {
        guard loadState != .loading else { return }
        loadState = .loading
        nextPage = 1
        hasMorePages = true
        loadFilterOptions()
        guard didLoadSavedFilters else {
            sessionManager.discoveryFilters()
                .observe(on: MainScheduler.instance)
                .subscribe(onSuccess: { [weak self] saved in
                    guard let self else { return }
                    self.didLoadSavedFilters = true
                    self.storePreferences(FilterModel(preferences: saved))
                    self.fetchNextPage(replacing: true)
                }, onFailure: { [weak self] _ in
                    guard let self else { return }
                    self.didLoadSavedFilters = true
                    self.fetchNextPage(replacing: true)
                })
                .disposed(by: disposeBag)
            return
        }
        fetchNextPage(replacing: true)
    }

    func loadFilterOptions() {
        guard filterOptions == nil, !isLoadingFilterOptions else { return }
        isLoadingFilterOptions = true
        sessionManager.discoveryFilterOptions()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] options in
                self?.isLoadingFilterOptions = false
                self?.filterOptions = options
            }, onFailure: { [weak self] _ in
                self?.isLoadingFilterOptions = false
            })
            .disposed(by: disposeBag)
    }

    func exploreAgain() {
        seenUserIDs.removeAll()
        interestFilter = nil
        loadRecommendations()
    }

    private func fetchNextPage(replacing: Bool = false) {
        guard !isFetchingPage, hasMorePages else { return }
        isFetchingPage = true
        let page = nextPage
        let generation = deckGeneration

        sessionManager.discoverySearch(filters: preferences.preferences, page: page, limit: Self.pageSize)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] response in
                guard let self, generation == self.deckGeneration else { return }
                self.isFetchingPage = false
                self.nextPage = page + 1
                let users = response.profiles ?? []
                self.hasMorePages = response.pagination?.hasMore ?? (users.count >= Self.pageSize)

                let existing = replacing ? Set<String>() : Set(self.queue.compactMap(\.remoteUserId))
                let profiles = users
                    .compactMap(DiscoverViewModel.makeProfile(from:))
                    .filter { profile in
                        guard let userID = profile.remoteUserId else { return false }
                        return !existing.contains(userID) && (replacing || !self.seenUserIDs.contains(userID))
                    }
                profiles.compactMap(\.remoteUserId).forEach { self.seenUserIDs.insert($0) }

                if replacing {
                    self.queue = profiles
                } else {
                    self.queue += profiles
                }
                self.rebuildDeck()
                if self.loadState != .loaded { self.loadState = .loaded }
                self.prefetchIfNeeded()
            }, onFailure: { [weak self] error in
                guard let self, generation == self.deckGeneration else { return }
                self.isFetchingPage = false
                if replacing || self.queue.isEmpty {
                    self.loadState = .failed(parseError(error) ?? "Couldn't load new people right now")
                }
            })
            .disposed(by: disposeBag)
    }

    private func prefetchIfNeeded() {
        guard loadState == .loaded, queue.count <= Self.prefetchThreshold else { return }
        fetchNextPage()
    }

    // MARK: - Interest discovery

    /// Narrows the deck to people who share `interest`. Returns `false` when nobody else matches.
    @discardableResult
    func filter(by interest: MomentsInterest) -> Bool {
        guard queue.contains(where: { $0.interests.contains(interest) }) else { return false }
        interestFilter = interest
        rebuildDeck()
        return true
    }

    func clearFilter() {
        interestFilter = nil
        rebuildDeck()
    }

    // MARK: - Filters

    /// How many people match `filters`, from `discovery/search` with `countOnly`; `nil` when the request fails.
    func matchCount(for filters: FilterModel, completion: @escaping (Int?) -> Void) {
        sessionManager.discoverySearch(filters: filters.preferences, page: 1, limit: 1, countOnly: true)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { data in
                completion(data.totalCount ?? data.pagination?.totalCount)
            }, onFailure: { _ in
                completion(nil)
            })
            .disposed(by: disposeBag)
    }

    /// Whether the deck is empty while filters are narrowing the search.
    var isEmptyBecauseOfFilters: Bool {
        deck.isEmpty && loadState == .loaded && preferences.activeCount > 0
    }

    /// Saves `filters` with PUT `discovery/filters`, then reloads the deck. Completes with an error message on failure.
    func apply(_ filters: FilterModel, completion: @escaping (String?) -> Void) {
        sessionManager.updateDiscoveryFilters(filters.preferences)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] saved in
                guard let self else { return }
                let applied = FilterModel(preferences: saved)
                self.storePreferences(applied)
                MomentsAnalytics.track(.discoverFiltersApplied, properties: ["active_count": applied.activeCount])
                self.reloadDeck()
                completion(nil)
            }, onFailure: { error in
                completion(parseError(error) ?? "Couldn't save your filters")
            })
            .disposed(by: disposeBag)
    }

    /// Server defaults from POST `discovery/filters/reset`; `nil` when the request fails.
    func resetFilters(completion: @escaping (FilterModel?) -> Void) {
        sessionManager.resetDiscoveryFilters()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] saved in
                guard let self else { return }
                let defaults = FilterModel(preferences: saved)
                self.storePreferences(defaults)
                self.reloadDeck()
                completion(defaults)
            }, onFailure: { _ in
                completion(nil)
            })
            .disposed(by: disposeBag)
    }

    private func storePreferences(_ filters: FilterModel) {
        UserDataManager.shared.filterDataModel = filters
        preferences = filters
    }

    /// Starts the deck over from page 1 with the current preferences.
    private func reloadDeck() {
        deckGeneration += 1
        seenUserIDs.removeAll()
        interestFilter = nil
        queue = []
        hasMorePages = true
        isFetchingPage = false
        loadState = .idle
        loadRecommendations()
    }

    // MARK: - Actions

    /// Sends `action` for `profile`, removing it from the deck straight away so the next card is ready.
    /// `viaConnectSheet`: an Interested from the "Connect because…" sheet goes to `connections/request` with the reason.
    /// Returns `false` (and does nothing) while another action is still in flight.
    @discardableResult
    func perform(_ action: MomentsAction,
                 on profile: MomentsProfile,
                 reasons: [ConnectReason] = [],
                 reaction: MomentsReaction? = nil,
                 viaConnectSheet: Bool = false,
                 completion: @escaping (Result<MomentsActionOutcome, MomentsActionError>) -> Void) -> Bool {
        guard !actionInProgress else { return false }
        if let blocked = FreeTierLimitsStore.shared.blockReason(for: action) {
            DispatchQueue.main.async { completion(.failure(blocked)) }
            return true
        }
        actionInProgress = true
        remove(profileID: profile.id)
        MomentsAnalytics.track(action.analyticsEvent, profileID: profile.id)
        if let reaction {
            MomentsAnalytics.track(.vibeReactionSent, profileID: profile.id, properties: ["target": reaction.analyticsValue])
        }

        guard let targetUserID = profile.remoteUserId else {
            actionInProgress = false
            DispatchQueue.main.async { completion(.failure(.network)) }
            return true
        }

        let request: Single<Bool>
        if viaConnectSheet, action == .interested {
            request = sessionManager.sendConnectionRequest(targetUserId: targetUserID, reason: reasons.first?.rawValue)
                .map(\.didMatch)
        } else {
            request = sessionManager.discoveryAction(targetUserId: targetUserID, action: action.apiAction)
                .do(onSuccess: { result in
                    if let coins = result.remainingCoins {
                        CoinWallet.shared.update(coins)
                    }
                })
                .map { $0.isMatched == true }
        }

        request
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] isMatch in
                if action == .interested || action == .superVibe {
                    FreeTierLimitsStore.shared.refresh()
                }
                self?.finish(action, on: profile, reasons: reasons, reaction: reaction,
                             isMatch: isMatch, completion: completion)
            }, onFailure: { [weak self] error in
                self?.actionInProgress = false
                completion(.failure(Self.actionError(for: action, error: error)))
            })
            .disposed(by: disposeBag)
        return true
    }

    private static func actionError(for action: MomentsAction, error: Error) -> MomentsActionError {
        if let quota = quotaError(for: action, error: error) { return quota }
        let statusCode = (error as? APIHTTPError)?.statusCode ?? error.statusCode
        if statusCode == 502 || statusCode == 503 || statusCode == 504 {
            return .serverBusy
        }
        return .network
    }

    private static func quotaError(for action: MomentsAction, error: Error) -> MomentsActionError? {
        if FreeTierErrorCode.isDailyLikeLimit(error) {
            return .likeLimitReached
        }
        if FreeTierErrorCode.matches(error, FreeTierErrorCode.insufficientCoins) {
            return .insufficientCoins
        }
        let statusCode = (error as? APIHTTPError)?.statusCode
        if action == .interested, statusCode == 429 {
            return .likeLimitReached
        }
        if action == .superVibe, statusCode == 402 || statusCode == 403 {
            return .insufficientCoins
        }
        return nil
    }

    private func finish(_ action: MomentsAction,
                        on profile: MomentsProfile,
                        reasons: [ConnectReason],
                        reaction: MomentsReaction?,
                        isMatch: Bool,
                        completion: @escaping (Result<MomentsActionOutcome, MomentsActionError>) -> Void) {
        if action.sendsConnection {
            MomentsAnalytics.track(.connectionRequestSent, profileID: profile.id,
                                properties: ["reasons": reasons.map(\.rawValue),
                                             "super": action == .superVibe,
                                             "reaction": reaction?.analyticsValue ?? ""])
        }
        if isMatch {
            MomentsAnalytics.track(.connectionCreated, profileID: profile.id)
        }
        actionInProgress = false
        completion(.success(MomentsActionOutcome(action: action, profile: profile, isMatch: isMatch, reaction: reaction)))
    }

    /// Puts a profile back on top of the deck (e.g. after a failed action the user wants to keep).
    func restore(_ profile: MomentsProfile) {
        guard !queue.contains(profile) else { return }
        queue.insert(profile, at: 0)
        rebuildDeck()
    }

    /// Reports or blocks `profile`; on success it leaves Discover. Fails with a message for the user.
    func apply(_ safetyAction: MomentsSafetyAction, to profile: MomentsProfile,
               completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userID = profile.remoteUserId else {
            completion(.failure(APIError.apiError("This profile can't be reported right now")))
            return
        }
        let request: Single<Void>
        switch safetyAction {
        case .report(let reason):
            request = sessionManager.reportUser(userId: userID, reason: reason.rawValue, description: reason.title)
        case .block:
            request = sessionManager.blockUser(userId: userID, reason: "Blocked from Discover").map { _ in () }
        }
        request
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                self?.remove(profileID: profile.id)
                completion(.success(()))
            }, onFailure: { error in
                completion(.failure(error))
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Interests catalog

    func loadInterestCatalog() {
        guard interestCatalog.isEmpty, !isLoadingInterestCatalog else { return }
        isLoadingInterestCatalog = true
        sessionManager.interestsCatalog()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] items in
                self?.isLoadingInterestCatalog = false
                self?.interestCatalog = items
            }, onFailure: { [weak self] _ in
                self?.isLoadingInterestCatalog = false
            })
            .disposed(by: disposeBag)
    }

    func loadPeople(for item: InterestCatalogItem) {
        if interestPeople?.interestId == item.id, interestPeople?.profiles != nil { return }
        interestPeople = (item.id, nil)
        sessionManager.discoveryPeople(page: 1, limit: 20, interestId: item.id)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] response in
                guard let self, self.interestPeople?.interestId == item.id else { return }
                let profiles = (response.users ?? []).compactMap(DiscoverViewModel.makeProfile(from:))
                self.interestPeople = (item.id, profiles)
            }, onFailure: { [weak self] _ in
                guard let self, self.interestPeople?.interestId == item.id else { return }
                self.interestPeople = (item.id, [])
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Quick Moments

    func loadQuickMomentTray() {
        sessionManager.quickMomentsTray()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] tray in
                self?.quickMomentTray = tray
            }, onFailure: { _ in })
            .disposed(by: disposeBag)
    }

    /// A user's active stories, newest first; falls back to the tray's copy when the request fails or is empty.
    /// Own stories come from `quick-moments/me`, since the tray copy has no reaction or reply counts.
    func quickMoments(of item: QuickMomentTrayItem, isMine: Bool = false, completion: @escaping ([QuickMoment]) -> Void) {
        let request: Single<[QuickMoment]>
        if isMine {
            request = sessionManager.myQuickMoments()
        } else if let userId = item.user?.id {
            request = sessionManager.userQuickMoments(userId: userId)
        } else {
            completion(item.stories)
            return
        }
        request
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { moments in
                let sorted = moments.sorted {
                    (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast)
                }
                completion(sorted.isEmpty ? item.stories : sorted)
            }, onFailure: { _ in
                completion(item.stories)
            })
            .disposed(by: disposeBag)
    }

    func markQuickMomentViewed(id: String) {
        sessionManager.markQuickMomentViewed(momentId: id)
            .subscribe(onSuccess: { }, onFailure: { _ in })
            .disposed(by: disposeBag)
    }

    func deleteQuickMoment(id: String, completion: @escaping (String?) -> Void) {
        sessionManager.deleteQuickMoment(momentId: id)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                self?.loadQuickMomentTray()
                completion(nil)
            }, onFailure: { error in
                completion(parseError(error) ?? "Couldn't delete your quick moment")
            })
            .disposed(by: disposeBag)
    }

    func reactToQuickMoment(id: String, emoji: String, onFailure: @escaping (String) -> Void) {
        sessionManager.reactToQuickMoment(momentId: id, emoji: emoji)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { _ in }, onFailure: { error in
                onFailure(parseError(error) ?? "Couldn't send your reaction")
            })
            .disposed(by: disposeBag)
    }

    func replyToQuickMoment(id: String, message: String, onFailure: @escaping (String) -> Void) {
        sessionManager.replyToQuickMoment(momentId: id, message: message)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { _ in }, onFailure: { error in
                onFailure(parseError(error) ?? "Couldn't send your reply")
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Deck

    private func remove(profileID: Int) {
        queue.removeAll { $0.id == profileID }
        rebuildDeck()
        prefetchIfNeeded()
    }

    private func rebuildDeck() {
        let matching = queue
        if let interestFilter {
            let filtered = matching.filter { $0.interests.contains(interestFilter) }
            if filtered.isEmpty {
                self.interestFilter = nil
                deck = matching
            } else {
                deck = filtered
            }
        } else {
            deck = matching
        }
        preloadUpcoming()
    }

    private func preloadUpcoming() {
        for profile in deck.prefix(3) {
            let paths = Array(profile.photos.prefix(1)) + profile.moments.prefix(3).map(\.imagePath)
            for path in paths {
                guard let url = URL(string: path.hasPrefix("http") ? path : ApiName.imgBaseURL + path) else { continue }
                ImageLoader.shared.load(url) { _ in }
            }
        }
    }

    // MARK: - Mapping

    /// Usernames are shown exactly as registered; `name` (the nickname) is only a fallback.
    static func displayName(username: String?, name: String?) -> String {
        let handle = username?.trimmingCharacters(in: .whitespaces) ?? ""
        if !handle.isEmpty { return handle }
        return (name ?? "").trimmingCharacters(in: .whitespaces).firstLetterCapitalized
    }

    static func makeProfile(from person: DiscoveryPerson) -> MomentsProfile? {
        guard let userID = person.userId, !userID.isEmpty else { return nil }

        let interests = uniqueInterests(person.interestTags ?? [])
        let shared = uniqueInterests(person.sharedInterests ?? [])
        let photos = [person.profilePhoto].compactMap { $0 }.filter { !$0.isEmpty }
        let locationLabel = person.location ?? person.city
        let matchScore = person.profileMatchPercentage ?? person.vibeScore

        var profile = MomentsProfile(id: userID.stableID,
                                  displayName: displayName(username: person.username, name: person.name),
                                  age: person.age,
                                  isVerified: person.isVerified == true,
                                  gender: nil,
                                  city: cityName(from: locationLabel),
                                  distanceKm: person.distanceKm,
                                  isOnline: person.isOnline,
                                  datingIntent: nil,
                                  photos: photos,
                                  about: person.about?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                                  interests: interests,
                                  sharedInterests: shared,
                                  reasons: reasons(shared: shared, sameCity: nil),
                                  voiceIntro: nil,
                                  moments: [],
                                  vibeScore: matchScore)
        profile.commonInterestsCount = person.commonInterestsCount
        profile.momentsCount = person.totalMoments ?? 0
        profile.remoteUserId = userID
        return profile
    }

    static func makeProfile(from person: DiscoverySearchProfile) -> MomentsProfile? {
        guard let userID = person.userId ?? person.id, !userID.isEmpty else { return nil }

        let interests = uniqueInterests(person.interests ?? [])
        let shared = uniqueInterests(person.sharedInterests ?? [])
        let gallery = (person.photos ?? [])
            .sorted { ($0.isPrimary == true ? 0 : 1, $0.displayOrder ?? .max) < ($1.isPrimary == true ? 0 : 1, $1.displayOrder ?? .max) }
            .compactMap { $0.url ?? $0.thumbnailUrl }
        var photos: [String] = []
        for path in [person.primaryPhotoUrl ?? person.profilePhotoUrl].compactMap({ $0 }) + gallery where !path.isEmpty && !photos.contains(path) {
            photos.append(path)
        }
        let gender: Int?
        switch person.gender?.lowercased() {
        case "female": gender = 2
        case "male": gender = 1
        case "non_binary", "non-binary", "nonbinary": gender = 3
        default: gender = nil
        }
        let intent = FilterModel.datingIntents.first { $0.apiValue == person.lookingFor }?.title
        let locationLabel = person.location ?? person.city
        let matchScore = person.profileMatchPercentage ?? person.vibeScore

        var profile = MomentsProfile(id: userID.stableID,
                                  displayName: displayName(username: person.username, name: person.name),
                                  age: person.age,
                                  isVerified: (person.isFaceVerified ?? person.isVerified) == true,
                                  gender: gender,
                                  city: cityName(from: locationLabel),
                                  distanceKm: person.distanceKm,
                                  isOnline: person.isOnline,
                                  datingIntent: intent,
                                  photos: photos,
                                  about: (person.bio ?? person.about)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                                  interests: interests,
                                  sharedInterests: shared,
                                  reasons: reasons(shared: shared, sameCity: nil),
                                  voiceIntro: nil,
                                  moments: [],
                                  vibeScore: matchScore)
        profile.commonInterestsCount = person.commonInterestsCount
        profile.momentsCount = person.totalMoments ?? 0
        profile.remoteUserId = userID
        return profile
    }

    /// Starting card for an Explore tab person; `CardDetailViewController` loads the rest.
    static func makeProfile(from card: InteractionCard) -> MomentsProfile? {
        guard let userID = card.userId, !userID.isEmpty else { return nil }
        var profile = MomentsProfile(id: userID.stableID,
                                  displayName: displayName(username: card.name, name: nil),
                                  age: card.age,
                                  isVerified: card.isVerified == true,
                                  gender: nil,
                                  city: cityName(from: card.city),
                                  distanceKm: card.distanceKm,
                                  isOnline: card.isOnline,
                                  datingIntent: nil,
                                  photos: [card.photo].compactMap { $0 }.filter { !$0.isEmpty },
                                  about: "",
                                  interests: [],
                                  sharedInterests: [],
                                  reasons: [],
                                  voiceIntro: nil,
                                  moments: [],
                                  vibeScore: nil)
        profile.remoteUserId = userID
        return profile
    }

    /// Full profile from `users/:userId/profile`; anything the API leaves empty keeps the card's value.
    static func makeProfile(from detail: OtherUserProfile, merging base: MomentsProfile) -> MomentsProfile {
        let photo = detail.profilePhoto ?? ""
        let photos = photo.isEmpty ? base.photos : [photo]

        let interests = uniqueInterests(detail.interests ?? [])
        let shared = detail.sharedInterests.map(uniqueInterests) ?? base.sharedInterests
        let explanation = detail.vibeExplanation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let apiReasons = explanation.isEmpty ? [] : [explanation]
        let name = displayName(username: detail.username, name: detail.name)
        let about = detail.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let voice = detail.voiceIntro?.momentsIntro

        let moments = (detail.moments ?? []).compactMap { moment -> MomentsStory? in
            let path = moment.thumbnailUrl ?? moment.mediaUrl ?? ""
            let caption = moment.caption?.isEmpty == false ? moment.caption : nil
            guard !path.isEmpty || caption != nil else { return nil }
            return MomentsStory(id: (moment.momentId ?? moment.id ?? path).stableID,
                              imagePath: path,
                              isVideo: moment.mediaType == "video",
                              caption: caption,
                              postedAt: moment.createdAt.flatMap(date(fromISO:)))
        }

        var profile = MomentsProfile(id: base.id,
                                  displayName: name.isEmpty ? base.displayName : name,
                                  age: detail.age ?? base.age,
                                  isVerified: detail.isVerified ?? base.isVerified,
                                  gender: base.gender,
                                  city: cityName(from: detail.city) ?? base.city,
                                  distanceKm: detail.distanceKm ?? base.distanceKm,
                                  isOnline: detail.isOnline ?? base.isOnline,
                                  datingIntent: base.datingIntent,
                                  photos: photos,
                                  about: about.isEmpty ? base.about : about,
                                  interests: interests.isEmpty ? base.interests : interests,
                                  sharedInterests: shared,
                                  reasons: apiReasons.isEmpty ? reasons(shared: shared, sameCity: nil) : apiReasons,
                                  voiceIntro: voice ?? base.voiceIntro,
                                  moments: moments.isEmpty ? base.moments : moments,
                                  vibeScore: detail.vibeScore ?? base.vibeScore)
        profile.commonInterestsCount = base.commonInterestsCount
        profile.momentsCount = max(base.momentsCount, moments.count)
        profile.remoteUserId = base.remoteUserId
        return profile
    }

    /// "2026-10-12T10:14:35.577Z", with or without fractional seconds.
    private static func date(fromISO string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func uniqueInterests(_ tags: [DiscoveryTag]) -> [MomentsInterest] {
        var seen = Set<Int>()
        return tags.compactMap { MomentsInterestCatalog.interest(named: $0.name, emoji: $0.emoji) }
            .filter { seen.insert($0.id).inserted }
    }

    /// Only real overlap is used; with nothing in common the honest fallback is shown instead.
    static func reasons(shared: [MomentsInterest], sameCity: String?) -> [String] {
        var reasons: [String] = []
        if let first = shared.first {
            reasons.append("You both love \(first.title.lowercased())")
        }
        if shared.count > 1 {
            reasons.append("You both selected \(shared[1].title.lowercased())")
        }
        if shared.count > 2 {
            let more = shared.count - 2
            reasons.append(more == 1 ? "1 more interest in common" : "\(more) more interests in common")
        }
        if let sameCity {
            reasons.append("You're both in \(sameCity)")
        }
        return reasons.isEmpty ? [fallbackReason] : reasons
    }

    static func cityName(from location: String?) -> String? {
        guard let city = location?.split(separator: ",").first?.trimmingCharacters(in: .whitespaces), !city.isEmpty else { return nil }
        return city
    }

    static func age(from dob: String?) -> Int? {
        guard let dob else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(dob.prefix(10))) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: Date()).year
    }
}
