//
//  EditAboutViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 30/05/24.
//

import Foundation
import RxSwift
import Swinject

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

    private lazy var sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!
    private let disposeBag = DisposeBag()

    func validation(data:[MoreAboutOption]?) -> Bool? {
        if ((data?.first(where: {$0.isSelected == true})) != nil){
            return true
        }else{
            return false
        }
    }

    /// `filteredData` holds `Attributes.json` option ids keyed by legacy field name (and `interests: [Int]`).
    /// Lifestyle answers go to `users/more-about-me` as option titles; interests go to `onboarding/interests` as catalog UUIDs.
    func callSaveUserDetailsAPI(filteredData:[String:Any]) {
        var requests: [Single<Void>] = []

        var values: [String: String] = [:]
        for field in EditProfileAPIMapper.lifestyleFields {
            if let id = filteredData[field.legacy] as? Int,
               let title = EditProfileAPIMapper.optionTitle(alias: field.alias, id: id) {
                values[field.api] = title
            }
        }
        if !values.isEmpty {
            requests.append(sessionManager.updateMoreAboutMe(values))
        }

        if let ids = filteredData["interests"] as? [Int] {
            let names = ids.compactMap { EditProfileAPIMapper.optionTitle(alias: Constants.QuestionOption.interests, id: $0)?.lowercased() }
            let sessionManager = self.sessionManager
            requests.append(sessionManager.interestsCatalog().flatMap { catalog -> Single<Void> in
                let uuids = names.compactMap { name in catalog.first { $0.name.lowercased() == name }?.id }
                guard !uuids.isEmpty else { return .error(APIError.apiError("These interests aren't available yet")) }
                return sessionManager.updateInterests(ids: uuids)
            })
        }

        guard !requests.isEmpty else {
            aUserDetailResponseModel = .mockSuccess("Profile updated successfully")
            return
        }
        Single.zip(requests)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                self?.aUserDetailResponseModel = .mockSuccess("Profile updated successfully")
            }, onFailure: { [weak self] error in
                self?.errorMessage = parseError(error) ?? "Unable to save your answers"
            })
            .disposed(by: disposeBag)
    }
}
