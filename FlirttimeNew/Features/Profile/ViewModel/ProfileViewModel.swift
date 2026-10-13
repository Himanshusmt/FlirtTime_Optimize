//
//  ProfileViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 19/05/24.
//

import Foundation
import UIKit

// TODO: replace the MockDataStore / MockQuickMomentStore calls with ApiName.getUserDataInfo and the Quick Moments endpoints.
class ProfileViewModel {

    @Published var aUserProfileModel:UserDetailsData?
    /// The signed-in user's Quick Moments, newest first.
    @Published private(set) var quickMoments: [QuickMoment] = []
    @Published var errorMessage:String?
    /// The latest few of the signed-in user's moments (Moments), newest first; `nil` until loaded.
    @Published private(set) var myMoments: [MomentsPost]?
    private(set) var myMomentsTotal = 0

    static let myMomentsPreviewLimit = 6

    private let quickMomentStore = MockQuickMomentStore.shared

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

    func getQuickMoments() {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) { [weak self] in
            guard let self else { return }
            let response = self.quickMomentStore.list(userID: MockMomentsStore.shared.currentUserID)
            self.quickMoments = response.data ?? []
        }
    }

    func getMyMoments() {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) { [weak self] in
            guard let self else { return }
            let store = MockMomentsStore.shared
            let response = store.feed(page: 1, limit: Self.myMomentsPreviewLimit, authorID: store.currentUserID)
            self.myMomentsTotal = response.data?.count ?? 0
            self.myMoments = response.data?.rows ?? []
        }
    }

    func createQuickMoment(text: String?, background: Int?, image: UIImage?, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) { [weak self] in
            guard let self else { return }
            let response = self.quickMomentStore.create(text: text, background: background, image: image)
            guard response.success == true, let moment = response.data else {
                completion(.failure(MomentsError(message: response.message ?? "Unable to share quick moment")))
                return
            }
            self.quickMoments.insert(moment, at: 0)
            completion(.success(()))
        }
    }

    func deleteQuickMoment(id: String, completion: @escaping (Result<Void, MomentsError>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) { [weak self] in
            guard let self else { return }
            let response = self.quickMomentStore.delete(id: id)
            guard response.success == true else {
                completion(.failure(MomentsError(message: response.message ?? "Unable to delete quick moment")))
                return
            }
            self.quickMoments.removeAll { $0.id == id }
            completion(.success(()))
        }
    }
}
