//
//  DiscoverViewModel.swift
//  FlirttimeNew
//

import Foundation
import Combine

// TODO: replace the MockDiscover responses with the recommendations and getAction requests.
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
    @Published private(set) var deck: [VibeProfile] = []
    @Published private(set) var interestFilter: VibeInterest?
    /// Saved filter-sheet preferences, applied before the interest filter.
    @Published private(set) var preferences: FilterModel = .saved

    /// Set while an action is being sent; further gestures are ignored until it completes or fails.
    private(set) var actionInProgress = false

    /// Remaining profiles before the interest filter is applied.
    private var queue: [VibeProfile] = []

    /// Everyone still available, ignoring the interest filter (Moments and Interests tabs).
    var everyone: [VibeProfile] { queue }
    var currentProfile: VibeProfile? { deck.first }
    var nextProfile: VibeProfile? { deck.dropFirst().first }

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    // MARK: - Loading

    func loadRecommendations() {
        guard loadState != .loading else { return }
        loadState = .loading
        respond { [weak self] in
            guard let self else { return }
            guard let response = MockDataStore.shared.decode(DiscoverResponse.self, from: MockDiscover.shared.recommendationsJSON()),
                  response.status == true else {
                self.loadState = .failed("Couldn't load new people right now")
                return
            }
            let me = MockDataStore.shared.currentUserResponse()?.data?.userInfo
            self.queue = (response.data ?? []).compactMap { DiscoverViewModel.makeProfile(from: $0, currentUser: me) }
            self.rebuildDeck()
            self.loadState = .loaded
        }
    }

    func exploreAgain() {
        MockDiscover.shared.resetSeen()
        interestFilter = nil
        loadRecommendations()
    }

    // MARK: - Interest discovery

    /// Narrows the deck to people who share `interest`. Returns `false` when nobody else matches.
    @discardableResult
    func filter(by interest: VibeInterest) -> Bool {
        guard queue.contains(where: { preferences.matches($0) && $0.interests.contains(interest) }) else { return false }
        interestFilter = interest
        rebuildDeck()
        return true
    }

    func clearFilter() {
        interestFilter = nil
        rebuildDeck()
    }

    // MARK: - Filters

    /// People left in the deck if `filters` were applied (ignores the interest filter).
    func matchCount(for filters: FilterModel) -> Int {
        queue.filter(filters.matches).count
    }

    /// Whether the deck is empty only because of the saved filters.
    var isEmptyBecauseOfFilters: Bool {
        deck.isEmpty && !queue.isEmpty && preferences.activeCount > 0
    }

    func apply(_ filters: FilterModel) {
        UserDataManager.shared.filterDataModel = filters
        preferences = filters
        VibeAnalytics.track(.discoverFiltersApplied, properties: ["active_count": filters.activeCount])
        rebuildDeck()
    }

    // MARK: - Actions

    /// Sends `action` for `profile`, removing it from the deck straight away so the next card is ready.
    /// Returns `false` (and does nothing) while another action is still in flight.
    @discardableResult
    func perform(_ action: VibeAction,
                 on profile: VibeProfile,
                 reasons: [ConnectReason] = [],
                 reaction: VibeReaction? = nil,
                 completion: @escaping (Result<VibeActionOutcome, VibeActionError>) -> Void) -> Bool {
        guard !actionInProgress else { return false }
        actionInProgress = true
        remove(profileID: profile.id)
        VibeAnalytics.track(action.analyticsEvent, profileID: profile.id)
        if let reaction {
            VibeAnalytics.track(.vibeReactionSent, profileID: profile.id, properties: ["target": reaction.analyticsValue])
        }

        respond { [weak self] in
            guard let self else { return }
            let json = MockDiscover.shared.actionJSON(interactionType: action.interactionType, userID: profile.id)
            guard let json, let model = MockDataStore.shared.decode(ActionData.self, from: json), model.status == true else {
                self.actionInProgress = false
                completion(.failure(.network))
                return
            }
            if action == .superVibe, model.data?.membership_required == true || model.data?.coin_required == true {
                MockDiscover.shared.unmarkSeen(profile.id)
                self.actionInProgress = false
                completion(.failure(.membershipRequired))
                return
            }
            let isMatch = model.data?.is_match == true
            if action.sendsConnection {
                VibeAnalytics.track(.connectionRequestSent, profileID: profile.id,
                                    properties: ["reasons": reasons.map(\.rawValue),
                                                 "super": action == .superVibe,
                                                 "reaction": reaction?.analyticsValue ?? ""])
            }
            if isMatch {
                VibeAnalytics.track(.connectionCreated, profileID: profile.id)
            }
            self.actionInProgress = false
            completion(.success(VibeActionOutcome(action: action, profile: profile, isMatch: isMatch, reaction: reaction)))
        }
        return true
    }

    /// Puts a profile back on top of the deck (e.g. after a failed action the user wants to keep).
    func restore(_ profile: VibeProfile) {
        guard !queue.contains(profile) else { return }
        queue.insert(profile, at: 0)
        rebuildDeck()
    }

    /// Report / block: the profile leaves Discover without sending an interaction.
    func hide(_ profile: VibeProfile, block: Bool) {
        if block {
            MockDiscover.shared.block(userID: profile.id)
        } else {
            MockDiscover.shared.markSeen(profile.id)
        }
        remove(profileID: profile.id)
    }

    // MARK: - Deck

    private func remove(profileID: Int) {
        queue.removeAll { $0.id == profileID }
        rebuildDeck()
    }

    private func rebuildDeck() {
        let matching = queue.filter(preferences.matches)
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

    static func makeProfile(from user: DiscoverUser, currentUser: UserDetailInfo?) -> VibeProfile? {
        guard let info = user.userInfo, let id = info.userID ?? info.id else { return nil }

        let gallery = (info.images ?? [])
            .sorted { ($0.is_primary ?? false) && !($1.is_primary ?? false) }
            .compactMap(\.image)
            .filter { !$0.isEmpty }
        let photos = gallery.isEmpty ? [info.avatar].compactMap { $0 } : gallery

        let interests = VibeInterestCatalog.interests(for: info.interests ?? [])
        let myInterestIDs = Set(currentUser?.interests ?? [])
        let shared = interests.filter { myInterestIDs.contains($0.id) }

        let city = info.locationShow == false ? nil : cityName(from: info.location)
        let myCity = cityName(from: currentUser?.location)
        let sameCity = (city != nil && city?.lowercased() == myCity?.lowercased()) ? city : nil

        let voice: VibeVoiceIntro? = user.voiceIntro.flatMap { intro in
            guard let transcript = intro.transcript, !transcript.isEmpty else { return nil }
            return VibeVoiceIntro(transcript: transcript,
                                  duration: intro.duration ?? 0,
                                  audioURL: intro.audioURL.flatMap(URL.init(string:)))
        }

        let moments = (user.moments ?? []).compactMap { moment -> VibeMoment? in
            guard let id = moment.id, let image = moment.image, !image.isEmpty else { return nil }
            return VibeMoment(id: id, imagePath: image, isVideo: moment.type == "video",
                              caption: moment.caption?.isEmpty == false ? moment.caption : nil,
                              postedAt: moment.createdAt.flatMap { ISO8601DateFormatter().date(from: $0) })
        }

        return VibeProfile(id: id,
                           displayName: (info.displayName ?? info.fullname ?? "").firstLetterCapitalized,
                           age: info.ageShow == false ? nil : age(from: info.dob),
                           isVerified: info.gestureIsVerified == true || info.videoIsVerified == true,
                           gender: info.gender,
                           city: city,
                           distanceKm: info.distanceShow == false ? nil : user.distance,
                           isOnline: info.onlineShow == false ? nil : info.isOnline,
                           datingIntent: user.datingIntent,
                           photos: photos,
                           about: info.aboutMe ?? "",
                           interests: interests,
                           sharedInterests: shared,
                           reasons: reasons(shared: shared, sameCity: sameCity),
                           voiceIntro: voice,
                           moments: moments,
                           vibeScore: vibeScore(shared: shared.count, mine: myInterestIDs.count,
                                                theirs: interests.count, sameCity: sameCity != nil))
    }

    static func vibeScore(shared: Int, mine: Int, theirs: Int, sameCity: Bool) -> Int? {
        guard shared > 0 else { return nil }
        let overlap = Double(shared) / Double(max(1, min(mine, theirs)))
        return min(99, 60 + Int((overlap * 34).rounded()) + (sameCity ? 5 : 0))
    }

    /// Only real overlap is used; with nothing in common the honest fallback is shown instead.
    static func reasons(shared: [VibeInterest], sameCity: String?) -> [String] {
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

    private static func cityName(from location: String?) -> String? {
        guard let city = location?.split(separator: ",").first?.trimmingCharacters(in: .whitespaces), !city.isEmpty else { return nil }
        return city
    }

    private static func age(from dob: String?) -> Int? {
        guard let dob else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(dob.prefix(10))) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: Date()).year
    }
}
