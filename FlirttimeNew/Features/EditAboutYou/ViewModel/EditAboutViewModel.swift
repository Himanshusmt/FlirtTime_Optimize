//
//  EditAboutViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 30/05/24.
//

import Foundation

// TODO: replace the MockDataStore call with the ApiName.saveIntroduction request.
class EditAboutViewModel {

    var educationalBackGroundArray:MoreAboutMeData?

    var drinkAlcoholArray:MoreAboutMeData?

    var smokingPreferenceArray:MoreAboutMeData?

    var childrenPlanArray:MoreAboutMeData?

    var religionChoiceArray:MoreAboutMeData?

    var lookingForRelationshipArray:MoreAboutMeData?

    var exerciseArray:MoreAboutMeData?

    var partyPreferenceArray:MoreAboutMeData?

    var zodiacArray:MoreAboutMeData?

    var preferHeightArray:MoreAboutMeData?

    @Published var errorMessage:String?
    @Published var aUserDetailResponseModel:UserDetailResponseModel?

    func validation(data:[MoreAboutOption]?) -> Bool? {
        if ((data?.first(where: {$0.isSelected == true})) != nil){
            return true
        }else{
            return false
        }
    }

    func callSaveUserDetailsAPI(filteredData:[String:Any]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) { [weak self] in
            MockDataStore.shared.updateUser(with: filteredData)
            self?.aUserDetailResponseModel = .mockSuccess("Profile updated successfully")
        }
    }
}
