//
//  OtherUserProfileViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 16/05/24.
//

import UIKit
import RxSwift
import Swinject

// TODO: replace remaining mock responses (moment images / subscription check).
class OtherUserProfileViewModel {

    @Published var statusFalse:String?
    @Published var errorMessage:String?

    @Published var aAttributesModel:AttributesModel?

    @Published var aUserActionModel:ActionData?
    /// `"like"` | `"super_like"` | `"nope"` from the last successful discovery action.
    @Published private(set) var completedDiscoveryAction: String?
    @Published var errorAction:String?
    @Published var quotaBlocked: MomentsActionError?
    @Published var errorState:Bool?

    @Published var agetMomentImages:MomentUser?
    @Published var errorMomentImages:String?

    @Published var aSendCompliment: SentCompliment?
    @Published var errorSendCompliment: (title: String, message: String)?

    @Published var aCheckUserSubscribe:CheckSubscriptionResponse?
    @Published var errorCheckUserSubscribe:String?

    /// First page of the user's moments; `nil` until loaded.
    @Published private(set) var moments: [MomentsPost]?
    private(set) var momentsTotal = 0
    @Published private(set) var quickMoments: [QuickMoment] = []
    @Published private(set) var voiceIntro: MomentsVoiceIntro?
    /// GET `users/:userId/profile`; `nil` until loaded.
    @Published private(set) var profile: OtherUserProfile?
    @Published private(set) var profileError: String?
    @Published private(set) var isLoadingProfile = false
    /// True while any profile, moments, quick moments or voice intro request is in flight (drives pull to refresh).
    @Published private(set) var isFetching = false
    private var pendingRequests = 0
    /// The signed-in user's interests, to find the ones in common when the profile response doesn't list them.
    @Published private(set) var myInterests: [MomentsInterest]?

    /// Moments fetched for the profile grid; the grid itself shows `OtherUserProfileViewController.momentsGridLimit`.
    static let momentsPageSize = 20
    /// Set once `users/:userId/moments` answers, so the moments embedded in the profile response don't overwrite it.
    private var hasLoadedUserMoments = false

    private lazy var sessionManager = Container.appContainer.resolve(AppSessionManager.self)!
    private let disposeBag = DisposeBag()
    private var actionInProgress = false

    var quickMomentFrames: [MomentsStory] {
        quickMoments.enumerated().map { $1.storyMoment(id: $0) }
    }

    let arrayMoments: [UIImage] = ["delete-13", "delete-14", "delete-4", "delete-18", "delete-19", "delete-20", "delete-21"].compactMap { UIImage(named: $0) }

    let arrayInterest: [String] = ["Bowling","Bowling","Bowling","Bowling","8 - ball","Gaming","Cricket","8 - ball","Gaming","Cricket"]

    let arrayMoreAboutMe: [MoreAboutMeModel] = [MoreAboutMeModel(text1:"Height" ,text2: "178cm"),MoreAboutMeModel(text1:"Excersise" ,text2:"Active"),MoreAboutMeModel(text1:"Education" ,text2:"UnderGraduate" ),MoreAboutMeModel(text1:"Drinking" ,text2:"Never" ),MoreAboutMeModel(text1:"Smoking" ,text2:"Never" ),MoreAboutMeModel(text1:"Looking for" ,text2:"Time Pass" ),MoreAboutMeModel(text1:"Kids" ,text2:"Not sure" ),MoreAboutMeModel(text1:"Horoscope" ,text2:"Libra" ),MoreAboutMeModel(text1:"Party",text2:"Moderate" ),MoreAboutMeModel(text1:"Religion" ,text2:"Hindu")]

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    private func beginRequest() {
        pendingRequests += 1
        isFetching = true
    }

    private func endRequest() {
        pendingRequests = max(0, pendingRequests - 1)
        if pendingRequests == 0 { isFetching = false }
    }

    // TODO: GET vibes/?userId=, quick-moments/?userId= and the user's voice intro once the APIs are live.
    func getMoments(userID: Int) {
        beginRequest()
        respond { [weak self] in
            let response = MockMomentsStore.shared.feed(page: 1, limit: Self.momentsPageSize, authorID: String(userID))
            self?.momentsTotal = response.data?.count ?? 0
            self?.moments = response.data?.rows ?? []
            self?.endRequest()
        }
    }

    /// Profile details, moments and voice intro come in one response; any of them may be missing for a user.
    func loadProfile(userID: String) {
        isLoadingProfile = true
        profileError = nil
        beginRequest()
        sessionManager.otherUserProfile(userId: userID)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] profile in
                guard let self else { return }
                self.isLoadingProfile = false
                defer { self.endRequest() }
                self.profile = profile
                self.voiceIntro = profile.voiceIntro?.momentsIntro
                let author = MomentsAuthor(userId: profile.userId ?? userID,
                                           userName: profile.username ?? profile.name,
                                           fullName: profile.fullName ?? profile.name,
                                           profilePicture: profile.profilePhoto,
                                           verified: profile.isVerified,
                                           location: profile.city)
                guard !self.hasLoadedUserMoments else { return }
                let moments = (profile.moments ?? []).compactMap { $0.vibe(author: author) }
                self.momentsTotal = moments.count
                self.moments = moments
            }, onFailure: { [weak self] error in
                guard let self else { return }
                self.isLoadingProfile = false
                if self.moments == nil { self.moments = [] }
                let status = (error as? APIHTTPError)?.statusCode
                if status != 502 && status != 503 && status != 504 {
                    self.profileError = parseError(error) ?? "Unable to load this profile"
                }
                self.endRequest()
            })
            .disposed(by: disposeBag)
        getUserMoments(userID: userID)
        getQuickMoments(userID: userID)
    }

    /// GET `users/:userId/moments`; on failure the grid keeps the moments from the profile response.
    func getUserMoments(userID: String) {
        beginRequest()
        sessionManager.userMoments(userId: userID, page: 1, limit: Self.momentsPageSize)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] page in
                guard let self else { return }
                self.hasLoadedUserMoments = true
                self.momentsTotal = page.total ?? page.vibes.count
                self.moments = page.vibes
                self.endRequest()
            }, onFailure: { [weak self] _ in
                self?.endRequest()
            })
            .disposed(by: disposeBag)
    }

    func getMyInterests() {
        sessionManager.myProfile()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] data in
                self?.myInterests = data.vibeInterests
            }, onFailure: { _ in })
            .disposed(by: disposeBag)
    }

    func getQuickMoments(userID: String) {
        beginRequest()
        sessionManager.userQuickMoments(userId: userID)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] moments in
                // `isViewed` from each story drives the WhatsApp-style ring (gray = viewed, red = unseen).
                self?.quickMoments = moments.sorted {
                    (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast)
                }
                self?.endRequest()
            }, onFailure: { [weak self] _ in
                self?.endRequest()
            })
            .disposed(by: disposeBag)
    }

    /// Marks a Quick Moment seen and greys its ring immediately in the profile row.
    func markQuickMomentViewed(id: String) {
        if let index = quickMoments.firstIndex(where: { $0.id == id }), !quickMoments[index].hasViewed {
            var updated = quickMoments
            updated[index].hasViewed = true
            quickMoments = updated
        }
        sessionManager.markQuickMomentViewed(momentId: id)
            .subscribe(onSuccess: { }, onFailure: { _ in })
            .disposed(by: disposeBag)
    }

    func deleteQuickMoment(id: String, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        sessionManager.deleteQuickMoment(momentId: id)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                self?.quickMoments.removeAll { $0.id == id }
                completion(.success(()))
            }, onFailure: { error in
                completion(.failure(MomentsError(message: parseError(error) ?? "Unable to delete quick moment")))
            })
            .disposed(by: disposeBag)
    }

    /// The signed-in user's own moments, quick moments and voice intro (Edit Profile preview).
    func loadOwnProfile() {
        beginRequest()
        sessionManager.myMoments(page: 1, limit: Self.momentsPageSize)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] page in
                self?.momentsTotal = page.total ?? page.vibes.count
                self?.moments = page.vibes
                self?.endRequest()
            }, onFailure: { [weak self] _ in
                guard let self else { return }
                if self.moments == nil {
                    self.momentsTotal = 0
                    self.moments = []
                }
                self.endRequest()
            })
            .disposed(by: disposeBag)

        beginRequest()
        sessionManager.myQuickMoments()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] moments in
                self?.quickMoments = moments.sorted {
                    (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast)
                }
                self?.endRequest()
            }, onFailure: { [weak self] _ in
                self?.endRequest()
            })
            .disposed(by: disposeBag)

        beginRequest()
        VoiceIntroService.fetch { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let intro) = result {
                    self?.voiceIntro = intro?.playerIntro
                }
                self?.endRequest()
            }
        }
    }

    func getVoiceIntro(userID: Int) {
        beginRequest()
        respond { [weak self] in
            self?.voiceIntro = MockDiscover.shared.voiceIntro(userID: userID)
            self?.endRequest()
        }
    }

    func loadJSON() {
        guard let fileURL = Bundle.main.url(forResource: "Attributes", withExtension: "json") else {
            print("JSON file not found")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let attributes = try decoder.decode(AttributesModel.self, from: data)

            if attributes.status ?? false {
                self.aAttributesModel = attributes
            } else {
                self.statusFalse = attributes.message
            }

        } catch {
            print("Error decoding JSON: \(error)")
            self.errorMessage = error.localizedDescription
        }
    }

    /// Profile X / heart / super-like → `POST discovery/actions` (`nope` / `like` / `super_like`).
    func clickActionAPI(interaction_type: String, targetUserId: String) {
        guard !actionInProgress, !targetUserId.isEmpty else { return }
        let action = Self.discoveryAction(for: interaction_type)
        actionInProgress = true
        sessionManager.discoveryAction(targetUserId: targetUserId, action: action)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] result in
                guard let self else { return }
                self.actionInProgress = false
                if let coins = result.remainingCoins {
                    CoinWallet.shared.update(coins)
                }
                if action == "like" || action == "super_like" {
                    FreeTierLimitsStore.shared.refresh()
                }
                self.completedDiscoveryAction = action
                self.aUserActionModel = ActionData(
                    status: true,
                    message: Self.successMessage(for: action, isMatched: result.isMatched == true),
                    file: nil,
                    exception: nil,
                    data: MyData(
                        membership_required: false,
                        current_balance: result.remainingCoins,
                        match_image: nil,
                        match_display_name: nil,
                        coin_required: false,
                        is_match: result.isMatched,
                        match_user_id: nil
                    )
                )
            }, onFailure: { [weak self] error in
                self?.actionInProgress = false
                if let quota = Self.quotaError(for: action, error: error) {
                    self?.quotaBlocked = quota
                    return
                }
                self?.errorAction = parseError(error).flatMap { $0.isEmpty ? nil : $0 }
                    ?? "Unable to update this profile"
            })
            .disposed(by: disposeBag)
    }

    private static func discoveryAction(for interactionType: String) -> String {
        switch interactionType {
        case Constants.ActionType.like: return "like"
        case Constants.ActionType.favorite: return "super_like"
        default: return "nope"
        }
    }

    private static func quotaError(for action: String, error: Error) -> MomentsActionError? {
        if FreeTierErrorCode.isDailyLikeLimit(error) { return .likeLimitReached }
        if FreeTierErrorCode.matches(error, FreeTierErrorCode.insufficientCoins) { return .insufficientCoins }
        let statusCode = (error as? APIHTTPError)?.statusCode
        if action == "like", statusCode == 429 { return .likeLimitReached }
        if action == "super_like", statusCode == 402 || statusCode == 403 { return .insufficientCoins }
        return nil
    }

    private static func successMessage(for action: String, isMatched: Bool) -> String {
        if isMatched { return "It's a match" }
        switch action {
        case "like": return "You liked this profile"
        case "super_like": return "Super like sent"
        default: return "Not interested"
        }
    }

    func getMomentUserImages(user_ID:Int) {
        respond { [weak self] in
            guard let self = self else { return }
            let moments = MockPeople.person(id: user_ID).map(MockPeople.momentImagesJSON) ?? []
            let payload: [String: Any] = [
                "status": true,
                "message": "",
                "img_base_url": ApiName.imgBaseURL,
                "data": [
                    "current_page": 1,
                    "data": moments,
                    "first_page_url": "",
                    "from": 1,
                    "last_page": 1,
                    "links": [],
                    "per_page": 20,
                    "to": moments.count,
                    "total": moments.count
                ]
            ]
            if let model = MockDataStore.shared.decode(MomentUser.self, from: payload) {
                self.agetMomentImages = model
            } else {
                self.errorMomentImages = "Unable to load moments"
            }
        }
    }

    /// `userID` is the backend UUID of the user receiving the compliment.
    func sendCompliment(userID: String, message: String) {
        sessionManager.sendCompliment(userId: userID, message: message)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] compliment in
                self?.aSendCompliment = compliment
            }, onFailure: { [weak self] error in
                if (error as? APIHTTPError)?.code == "ALREADY_MATCHED" {
                    self?.errorSendCompliment = (Constants.Compliment.alreadyMatchedTitle, Constants.Compliment.alreadyMatched)
                } else {
                    let message = parseError(error).flatMap { $0.isEmpty ? nil : $0 } ?? Constants.Compliment.failed
                    self?.errorSendCompliment = (Constants.Compliment.failedTitle, message)
                }
            })
            .disposed(by: disposeBag)
    }

    func getCheckUserSubscribedAPI() {
        respond { [weak self] in
            let isActive = UserDataManager.shared.isUserSubscriptionDone ?? false
            self?.aCheckUserSubscribe = CheckSubscriptionResponse(status: true, message: "", data: CheckSubscriptionData(isActive: isActive))
        }
    }
}
