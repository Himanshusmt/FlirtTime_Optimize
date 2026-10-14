//
//  ProfileViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 19/05/24.
//

import Foundation
import UIKit
import RxSwift
import Swinject

// TODO: replace the MockDataStore profile call with ApiName.getUserDataInfo.
class ProfileViewModel {

    @Published var aUserProfileModel:UserDetailsData?
    /// Header, about, interests, photos and voice intro from GET `users/profile`.
    @Published private(set) var myProfile: MyProfileData?
    /// The signed-in user's Quick Moments, newest first.
    @Published private(set) var quickMoments: [QuickMoment] = []
    @Published var errorMessage:String?
    /// The latest few of the signed-in user's moments (Moments), newest first; `nil` until loaded.
    @Published private(set) var myMoments: [MomentsPost]?
    private(set) var myMomentsTotal = 0

    static let myMomentsPreviewLimit = 4

    private lazy var sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!
    private let disposeBag = DisposeBag()

    /// Story frames for the bubbles and the viewer, in the same order as `quickMoments`.
    var quickMomentFrames: [MomentsStory] {
        quickMoments.enumerated().map { $1.storyMoment(id: $0) }
    }

    func getProfileDataAPI() {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) { [weak self] in
            guard let self = self else { return }
            guard let data = MockDataStore.shared.currentUserResponse() else {
                self.errorMessage = "Unable to load profile"
                return
            }
            self.aUserProfileModel = data.data
            UserDataManager.shared.saveUserInfo = data
            UserDataManager.shared.userAvtarImage = data.data?.userInfo?.avatar
            UserDataManager.shared.displayName = data.data?.userInfo?.displayName
        }
    }

    func getMyProfile() {
        sessionManager.myProfile()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] profile in
                self?.myProfile = profile
            }, onFailure: { [weak self] error in
                self?.errorMessage = parseError(error) ?? "Unable to load profile"
            })
            .disposed(by: disposeBag)
    }

    func getQuickMoments() {
        sessionManager.myQuickMoments()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] moments in
                self?.quickMoments = moments.sorted {
                    (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast)
                }
            }, onFailure: { [weak self] _ in
                self?.quickMoments = []
            })
            .disposed(by: disposeBag)
    }

    func getMyMoments() {
        sessionManager
            .myMoments(page: 1, limit: Self.myMomentsPreviewLimit)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] page in
                self?.myMomentsTotal = page.total ?? page.vibes.count
                self?.myMoments = Array(page.vibes.prefix(Self.myMomentsPreviewLimit))
            }, onFailure: { [weak self] _ in
                self?.myMomentsTotal = 0
                self?.myMoments = []
            })
            .disposed(by: disposeBag)
    }

    /// A text Quick Moment when `image` is `nil`, otherwise a photo uploaded to S3 with `text` as its caption.
    func createQuickMoment(text: String?, background: Int?, image: UIImage?, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        let body = text?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(QuickMoment.maxTextLength)
        let caption = body.map(String.init) ?? ""

        let request: Single<QuickMoment?>
        if let image {
            request = Single<Data>.create { single in
                DispatchQueue.global(qos: .userInitiated).async {
                    if let data = Self.jpegData(for: image) {
                        single(.success(data))
                    } else {
                        single(.failure(APIError.apiError("Couldn't prepare your photo.")))
                    }
                }
                return Disposables.create()
            }
            .flatMap { [sessionManager] data in sessionManager.uploadQuickMomentImage(data) }
            .flatMap { [sessionManager] upload -> Single<QuickMoment?> in
                guard let key = upload.resolvedKey else { return .error(APIError.apiError("Photo upload failed")) }
                return sessionManager.createImageQuickMoment(imageKey: key, caption: caption)
            }
        } else {
            guard !caption.isEmpty else {
                completion(.failure(MomentsError(message: "Add a photo or write something")))
                return
            }
            request = sessionManager.createTextQuickMoment(text: caption,
                                                           backgroundColor: QuickMomentColors.hex(forBackground: background ?? 0),
                                                           textColor: QuickMomentColors.textColor)
        }

        request
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] moment in
                guard let self else { return }
                if let moment {
                    self.quickMoments.removeAll { $0.id == moment.id }
                    self.quickMoments.insert(moment, at: 0)
                } else {
                    self.getQuickMoments()
                }
                completion(.success(()))
            }, onFailure: { error in
                completion(.failure(MomentsError(message: parseError(error) ?? "Unable to share quick moment")))
            })
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

    /// JPEG under the backend's 10 MB Quick Moment limit.
    private static func jpegData(for image: UIImage) -> Data? {
        let maxBytes = 10 * 1024 * 1024
        for quality in [0.8, 0.6, 0.4, 0.2] as [CGFloat] {
            if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes { return data }
        }
        return nil
    }
}
