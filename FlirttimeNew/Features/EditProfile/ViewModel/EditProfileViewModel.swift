//
//  EditProfileViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 31/05/24.
//

import Foundation
import UIKit

// TODO: replace the MockDataStore calls with the matching ApiName requests
// (uploadBannerImage, uploadUserProfileImage, removeProfileImage, makePrimaryImage,
// getUserDataInfo, saveIntroduction, verifyEmail, verificationEmailOTP).
class EditProfileViewModel{

    var aAMoreAboutMe:[MoreAboutMe] = [MoreAboutMe(key:"height",index: 6),MoreAboutMe(key: "exercise",index:7),MoreAboutMe(key:"education" ,index: 0),MoreAboutMe(key:"drinking" ,index:1),MoreAboutMe(key:"smoking",index: 2),MoreAboutMe(key:"looking-for" ,index: 5),MoreAboutMe(key: "kids",index: 3),MoreAboutMe(key:"horoscope" ,index: 9),MoreAboutMe(key:"party" ,index: 8),MoreAboutMe(key:"religion" ,index: 4)]

    @Published var errorMessage:String?
    @Published var aUploadCoverPhotoResponseModel:UploadProfileImageModel?
    @Published var aUploadProfilePhotoResponseModel:UploadProfileImageModel?
    @Published var aMoreAboutMeQuestionModel:MoreAboutMeQuestionModel?
    @Published var aDeleteUserImageResponseModel:DeleteUserImageResponseModel?
    @Published var aUserDetailDataModel:UserResponse?
    @Published var aPrimaryImageResponseModel:DeleteUserImageResponseModel?
    @Published var errorPrimaryImage:String?
    @Published var aUpdateAboutMe:UserDetailResponseModel?
    @Published var errorAboutMe:String?

    @Published var aVerifyEmail:VerifyEmailData?
    @Published var errorVerifyEmail:String?

    @Published var aVerifyEmailOTP:VerifyEmailData?
    @Published var errorVerifyEmailOTP:String?

    @Published var aUpdatePhoneNo:UserDetailResponseModel?
    @Published var errorPhoneUpdate:String?
    @Published var showErrorMsg: String?

    var arrayInterest: [Interest]? = []
    var arrayMoreAboutMe: [Detail]? = []
    var images: [EditProfileImageModel?] = Array(repeating: nil, count: 6)

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    func uploadCoverPhotoAPI(image:UIImage) {
        respond { [weak self] in
            guard let self = self else { return }
            guard let name = MockDataStore.shared.setBanner(image) else {
                self.errorMessage = Constants.ImageErrorTypes.errorUserImage
                return
            }
            self.aUploadCoverPhotoResponseModel = UploadProfileImageModel.mockUpload(fileName: name, message: "Cover photo updated successfully")
        }
    }

    func getProfileMoreAboutMeQuestion() {
        respond { [weak self] in
            self?.aMoreAboutMeQuestionModel = MoreAboutMeQuestionModel(status: true, message: "", data: [])
        }
    }

    func deleteImageAPI(id:Int) {
        respond { [weak self] in
            guard let self = self else { return }
            if MockDataStore.shared.deleteImage(id: id) {
                self.aDeleteUserImageResponseModel = .mockSuccess("Image deleted successfully")
            } else {
                self.errorMessage = "Image not found"
            }
        }
    }

    func callCheckExistingData() {
        respond { [weak self] in
            guard let self = self else { return }
            guard let data = MockDataStore.shared.currentUserResponse() else {
                self.errorMessage = "Unable to load profile"
                return
            }
            self.aUserDetailDataModel = data
            UserDataManager.shared.saveUserInfo = data
            UserDataManager.shared.userAvtarImage = data.data?.userInfo?.avatar
            UserDataManager.shared.displayName = data.data?.userInfo?.displayName
        }
    }

    func uploadProfilePhotoAPI(image:UIImage) {
        respond { [weak self] in
            guard let self = self else { return }
            guard let entry = MockDataStore.shared.addGalleryImage(image),
                  let name = entry["filename"] as? String else {
                self.errorMessage = Constants.ImageErrorTypes.errorBannerImage
                return
            }
            self.aUploadProfilePhotoResponseModel = UploadProfileImageModel.mockUpload(fileName: name, imagePayload: entry, message: "Image uploaded successfully")
        }
    }

    func getProfileImagePrimary(id:Int) {
        respond { [weak self] in
            guard let self = self else { return }
            if MockDataStore.shared.makePrimary(id: id) {
                self.aPrimaryImageResponseModel = .mockSuccess("Primary image updated")
            } else {
                self.errorPrimaryImage = "Image not found"
            }
        }
    }

    func callSaveUserDetailsAPI(filteredData:[String:Any]) {
        respond { [weak self] in
            MockDataStore.shared.updateUser(with: filteredData)
            self?.aUpdateAboutMe = .mockSuccess("Profile updated successfully")
        }
    }

    func verifyEmailAPI(email:String) {
        respond { [weak self] in
            guard let self = self else { return }
            if email.isValidEmail() {
                self.aVerifyEmail = VerifyEmailData(status: true, message: "OTP sent to \(email)")
            } else {
                self.errorVerifyEmail = "Please enter a valid email"
            }
        }
    }

    /// Mock: any 6-digit code is accepted.
    func verifyEmailOTPAPI(email: String, OTP: String, completion: @escaping (Bool) -> Void) {
        respond { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            if OTP.count == 6, OTP.allSatisfy(\.isNumber) {
                MockDataStore.shared.updateUser(with: ["email": email])
                self.aVerifyEmailOTP = VerifyEmailData(status: true, message: "Email verified successfully")
                completion(true)
            } else {
                self.errorVerifyEmailOTP = "Invalid OTP"
                completion(false)
            }
        }
    }

    func addPhoneNo(countryCode: String, number: String) {
        respond { [weak self] in
            MockDataStore.shared.updateUser(with: ["phone_code": countryCode, "phone": number])
            self?.aUpdatePhoneNo = .mockSuccess("Phone number updated successfully")
        }
    }
}
