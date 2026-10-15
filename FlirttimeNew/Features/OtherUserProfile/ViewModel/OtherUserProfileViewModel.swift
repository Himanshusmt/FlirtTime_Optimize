//
//  OtherUserProfileViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 16/05/24.
//

import UIKit
import RxSwift
import Swinject

// TODO: replace the mock responses with ApiName.getAction / getMomentUserImages /
// sendCompliments / checkSubscription requests.
class OtherUserProfileViewModel {

    @Published var statusFalse:String?
    @Published var errorMessage:String?

    @Published var aAttributesModel:AttributesModel?

    @Published var aUserActionModel:ActionData?
    @Published var errorAction:String?
    @Published var errorState:Bool?

    @Published var agetMomentImages:MomentUser?
    @Published var errorMomentImages:String?

    @Published var aSendCompliment:Complement?
    @Published var errorSendCompliment:String?

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

    static let momentsPreviewLimit = 5

    private lazy var sessionManager = Container.appContainer.resolve(AppSessionManager.self)!
    private let disposeBag = DisposeBag()

    var quickMomentFrames: [MomentsStory] {
        quickMoments.enumerated().map { $1.storyMoment(id: $0) }
    }

    let arrayMoments: [UIImage] = ["delete-13", "delete-14", "delete-4", "delete-18", "delete-19", "delete-20", "delete-21"].compactMap { UIImage(named: $0) }

    let arrayInterest: [String] = ["Bowling","Bowling","Bowling","Bowling","8 - ball","Gaming","Cricket","8 - ball","Gaming","Cricket"]

    let arrayMoreAboutMe: [MoreAboutMeModel] = [MoreAboutMeModel(text1:"Height" ,text2: "178cm"),MoreAboutMeModel(text1:"Excersise" ,text2:"Active"),MoreAboutMeModel(text1:"Education" ,text2:"UnderGraduate" ),MoreAboutMeModel(text1:"Drinking" ,text2:"Never" ),MoreAboutMeModel(text1:"Smoking" ,text2:"Never" ),MoreAboutMeModel(text1:"Looking for" ,text2:"Time Pass" ),MoreAboutMeModel(text1:"Kids" ,text2:"Not sure" ),MoreAboutMeModel(text1:"Horoscope" ,text2:"Libra" ),MoreAboutMeModel(text1:"Party",text2:"Moderate" ),MoreAboutMeModel(text1:"Religion" ,text2:"Hindu")]

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    // TODO: GET vibes/?userId=, quick-moments/?userId= and the user's voice intro once the APIs are live.
    func getMoments(userID: Int) {
        respond { [weak self] in
            let response = MockMomentsStore.shared.feed(page: 1, limit: Self.momentsPreviewLimit, authorID: String(userID))
            self?.momentsTotal = response.data?.count ?? 0
            self?.moments = response.data?.rows ?? []
        }
    }

    /// Profile details, moments and voice intro come in one response; any of them may be missing for a user.
    func loadProfile(userID: String) {
        isLoadingProfile = true
        profileError = nil
        sessionManager.otherUserProfile(userId: userID)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] profile in
                guard let self else { return }
                self.isLoadingProfile = false
                self.profile = profile
                self.voiceIntro = profile.voiceIntro?.momentsIntro
                let author = MomentsAuthor(userId: profile.userId ?? userID,
                                           userName: profile.username ?? profile.name,
                                           fullName: profile.fullName ?? profile.name,
                                           profilePicture: profile.profilePhoto,
                                           verified: profile.isVerified,
                                           location: profile.city)
                let moments = (profile.moments ?? []).compactMap { $0.vibe(author: author) }
                self.momentsTotal = moments.count
                self.moments = moments
            }, onFailure: { [weak self] error in
                self?.isLoadingProfile = false
                self?.moments = []
                self?.profileError = error.localizedDescription
            })
            .disposed(by: disposeBag)
        getQuickMoments(userID: userID)
    }

    func getQuickMoments(userID: String) {
        sessionManager.userQuickMoments(userId: userID)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] moments in
                self?.quickMoments = moments.sorted {
                    (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast)
                }
            })
            .disposed(by: disposeBag)
    }

    /// The signed-in user's own moments, quick moments and voice intro (Edit Profile preview).
    func loadOwnProfile() {
        sessionManager.myMoments(page: 1, limit: Self.momentsPreviewLimit)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] page in
                self?.momentsTotal = page.total ?? page.vibes.count
                self?.moments = Array(page.vibes.prefix(Self.momentsPreviewLimit))
            }, onFailure: { [weak self] _ in
                self?.momentsTotal = 0
                self?.moments = []
            })
            .disposed(by: disposeBag)

        sessionManager.myQuickMoments()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] moments in
                self?.quickMoments = moments.sorted {
                    (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast)
                }
            })
            .disposed(by: disposeBag)

        VoiceIntroService.fetch { [weak self] result in
            if case .success(let intro) = result {
                self?.voiceIntro = intro?.playerIntro
            }
        }
    }

    func getVoiceIntro(userID: Int) {
        respond { [weak self] in
            self?.voiceIntro = MockDiscover.shared.voiceIntro(userID: userID)
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

    func clickActionAPI(interaction_type:String, user_ID:Int) {
        respond { [weak self] in
            let message: String
            switch interaction_type {
            case "1": message = "You liked this profile"
            case "2": message = "You disliked this profile"
            case "3": message = "Super like sent"
            default: message = "Done"
            }
            self?.aUserActionModel = MockDataStore.shared.decode(ActionData.self, from: [
                "status": true,
                "message": message,
                "data": ["membership_required": false, "coin_required": false, "is_match": false]
            ])
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

    func sendCompliments(userID:Int, msg:String) {
        respond { [weak self] in
            self?.aSendCompliment = Complement(status: true, message: "Compliment sent successfully")
        }
    }

    func getCheckUserSubscribedAPI() {
        respond { [weak self] in
            let isActive = UserDataManager.shared.isUserSubscriptionDone ?? false
            self?.aCheckUserSubscribe = CheckSubscriptionResponse(status: true, message: "", data: CheckSubscriptionData(isActive: isActive))
        }
    }
}
