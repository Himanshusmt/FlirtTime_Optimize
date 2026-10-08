//
//  ProfileViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 19/05/24.
//

import Foundation
import UIKit

// TODO: replace the MockDataStore calls with ApiName.getUserDataInfo / ApiName.myMoments requests.
class ProfileViewModel {

    @Published var aUserProfileModel:UserDetailsData?
    @Published var aMyMomentsModel:[MomentsDatum]? = []
    @Published var errorMessage:String?

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

    func getMyMomentsAPI() {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) { [weak self] in
            self?.aMyMomentsModel = MockDataStore.shared.myMoments()
        }
    }
}
