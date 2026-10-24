//
//  EditProfileViewModel.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 31/05/24.
//

import Foundation
import UIKit
import RxSwift
import Swinject

// TODO: email OTP and phone still use MockDataStore — no backend API yet.
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

    private lazy var sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!
    private let disposeBag = DisposeBag()
    /// The screen keys photos by `Int`; the backend uses UUIDs.
    private var photoUUIDs: [Int: String] = [:]
    /// S3 object keys for PUT `/users/photos` (full gallery, 3–6 keys).
    private var photoKeys: [Int: String] = [:]
    private var nextTempPhotoID = -1
    private var profileFullName: String?
    private var profileNickName: String?
    private var profileDateOfBirth: String?
    private var profileGender: String?

    private static let maxImageBytes = 5 * 1024 * 1024

    private func respond(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay, execute: block)
    }

    func uploadCoverPhotoAPI(image:UIImage) {
        guard let imageData = image.jpegData(maxBytes: Self.maxImageBytes) else {
            errorMessage = Constants.ImageErrorTypes.errorUserImage
            return
        }
        sessionManager.updateCoverPicture(imageData: imageData)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] url in
                let payload: [String: Any] = ["status": true, "message": "Cover photo updated",
                                              "data": ["image_url": url]]
                self?.aUploadCoverPhotoResponseModel = EditProfileAPIMapper.decode(UploadProfileImageModel.self, from: payload)
            }, onFailure: { [weak self] error in
                self?.errorMessage = parseError(error) ?? "Cover photo upload failed"
            })
            .disposed(by: disposeBag)
    }

    func getProfileMoreAboutMeQuestion() {
        respond { [weak self] in
            self?.aMoreAboutMeQuestionModel = MoreAboutMeQuestionModel(status: true, message: "", data: [])
        }
    }

    func deleteImageAPI(id:Int) {
        guard var keys = galleryKeys(),
              let oldKey = photoKeys[id],
              let index = keys.firstIndex(of: oldKey) else {
            errorMessage = "Unable to delete the photo"
            return
        }
        keys.remove(at: index)
        if keys.count < 3 {
            errorMessage = "Keep at least 3 photos"
            return
        }
        saveGalleryKeys(keys)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                self?.photoUUIDs[id] = nil
                self?.photoKeys[id] = nil
                self?.aDeleteUserImageResponseModel = .mockSuccess("Image deleted successfully")
            }, onFailure: { [weak self] error in
                self?.errorMessage = parseError(error) ?? "Unable to delete the photo"
            })
            .disposed(by: disposeBag)
    }

    func callCheckExistingData() {
        let catalog = sessionManager.interestsCatalog().catchAndReturn([])
        Single.zip(sessionManager.myProfileJSON(), catalog)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] json, catalog in
                guard let self = self else { return }
                if !catalog.isEmpty {
                    EditProfileAPIMapper.interestCatalog = catalog
                }
                guard let data = self.legacyResponse(from: json) else {
                    self.errorMessage = "Unable to load profile"
                    return
                }
                self.aUserDetailDataModel = data
                UserDataManager.shared.displayName = data.data?.userInfo?.displayName
            }, onFailure: { [weak self] error in
                self?.errorMessage = parseError(error) ?? "Unable to load profile"
            })
            .disposed(by: disposeBag)
    }

    /// `replacing` is the photo in the tapped slot; it is removed once the new one is saved.
    func uploadProfilePhotoAPI(image:UIImage, replacing: Int? = nil, asPrimary: Bool = false) {
        guard let imageData = image.jpegData(maxBytes: Self.maxImageBytes) else {
            errorMessage = Constants.ImageErrorTypes.errorUserImage
            return
        }
        let filled = images.compactMap { $0 }.count
        if replacing == nil && filled >= 6 {
            errorMessage = "You can add up to 6 photos"
            return
        }

        sessionManager.uploadImageToS3(imageData, folder: "photos")
            .flatMap { [weak self] upload -> Single<String> in
                guard let self, let key = upload.resolvedKey else {
                    return .error(APIError.apiError("Couldn't start the photo upload"))
                }
                guard var keys = self.galleryKeys() else {
                    return .error(APIError.apiError("Unable to update photos. Please try again."))
                }
                if let replacing, let oldKey = self.photoKeys[replacing], let index = keys.firstIndex(of: oldKey) {
                    keys[index] = key
                } else {
                    keys.append(key)
                }
//                guard (3...6).contains(keys.count) else {
//                    return .error(APIError.apiError("You must have between 3 and 6 photos"))
//                }
                return self.saveGalleryKeys(keys).map { key }
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] key in
                guard let self else { return }
                self.applyUploadedPhoto(image: image, key: key, replacing: replacing, asPrimary: asPrimary)
                let payload: [String: Any] = [
                    "status": true,
                    "message": "Image uploaded successfully",
                    "data": ["image_url": "uploaded", "image": ["status": 1, "filefor": "gallery", "is_primary": asPrimary]]
                ]
                self.aUploadProfilePhotoResponseModel = EditProfileAPIMapper.decode(UploadProfileImageModel.self, from: payload)
                self.callCheckExistingData()
            }, onFailure: { [weak self] error in
                self?.showErrorMsg = ""
                self?.errorMessage = parseError(error) ?? Constants.ImageErrorTypes.errorUserImage
            })
            .disposed(by: disposeBag)
    }

    private func applyUploadedPhoto(image: UIImage, key: String, replacing: Int?, asPrimary: Bool) {
        let tempID = nextTempPhotoID
        nextTempPhotoID -= 1
        if let replacing, let slot = images.firstIndex(where: { $0?.id == replacing }) {
            photoUUIDs[replacing] = nil
            photoKeys[replacing] = nil
            images[slot] = EditProfileImageModel(image: image, id: tempID, status: 1, isPrimary: asPrimary || slot == 0)
        } else if let slot = images.firstIndex(where: { $0 == nil }) {
            images[slot] = EditProfileImageModel(image: image, id: tempID, status: 1, isPrimary: slot == 0)
        }
        photoKeys[tempID] = key
    }

    private func galleryKeys() -> [String]? {
        var keys: [String] = []
        for image in images {
            guard let image, let id = image.id else { continue }
            guard let key = photoKeys[id] else { return nil }
            keys.append(key)
        }
        return keys
    }

    /// Backend PUT allows 3–5 keys. A 6th slot is the profile photo, saved separately.
    private func saveGalleryKeys(_ keys: [String]) -> Single<Void> {
        let persist: Single<Void>
        if keys.count <= 5 {
            persist = sessionManager.setGalleryPhotos(imageKeys: keys)
        } else {
            let extras = Array(keys.dropFirst())
            let primary = keys[0]
            persist = sessionManager.setGalleryPhotos(imageKeys: extras)
                .flatMap { [weak self] _ -> Single<Void> in
                    guard let self else { return .error(APIError.apiError("Unable to update photos. Please try again.")) }
                    return self.sessionManager.setProfilePhoto(imageKey: primary).map { _ in () }
                }
        }
        return persist.do(onSuccess: {
            if let primary = keys.first {
                UserDataManager.shared.storeAvatarPath(primary)
            }
        })
    }

    func getProfileImagePrimary(id:Int) {
        guard let uuid = photoUUIDs[id] else {
            errorPrimaryImage = "Image not found"
            return
        }
        sessionManager.setPrimaryGalleryPhoto(id: uuid)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                self?.aPrimaryImageResponseModel = .mockSuccess("Primary image updated")
            }, onFailure: { [weak self] error in
                self?.errorPrimaryImage = parseError(error) ?? "Unable to update the primary photo"
            })
            .disposed(by: disposeBag)
    }

    /// Only `about_me` changes from this screen; the backend requires the full body
    /// (`fullName`, `username`, `dateOfBirth`, `gender`) on every PATCH, so the loaded values are sent back as-is.
    func callSaveUserDetailsAPI(filteredData:[String:Any]) {
        let appUser = UserDataManager.shared.appUser
        var params: [String: Any] = [
            "fullName": profileFullName ?? appUser?.fullName ?? "",
            "username": profileNickName ?? appUser?.username ?? appUser?.nickName ?? ""
        ]
        if let dateOfBirth = profileDateOfBirth ?? appUser?.dateOfBirth {
            params["dateOfBirth"] = dateOfBirth
        }
        if let gender = profileGender ?? appUser?.gender {
            params["gender"] = gender
        }
        if let about = filteredData["about_me"] as? String {
            params["about"] = about
        }
        sessionManager.updateProfileFields(params)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                self?.aUpdateAboutMe = .mockSuccess("Profile updated successfully")
            }, onFailure: { [weak self] error in
                self?.errorAboutMe = parseError(error) ?? "Unable to save your bio"
            })
            .disposed(by: disposeBag)
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

    // MARK: - users/profile → legacy UserResponse

    private func legacyResponse(from json: [String: Any]) -> UserResponse? {
        let data = json["data"] as? [String: Any] ?? json
        let profile = data["profile"] as? [String: Any] ?? data
        let more = (data["moreAboutMe"] as? [String: Any]) ?? (profile["moreAboutMe"] as? [String: Any]) ?? profile
        let appUser = UserDataManager.shared.appUser

        let nameParts = [profile["firstName"], profile["lastName"]].compactMap { Self.text($0) }
        profileFullName = Self.text(profile["fullName"]) ?? (nameParts.isEmpty ? nil : nameParts.joined(separator: " ")) ?? appUser?.fullName
        profileNickName = Self.text(profile["nickName"]) ?? Self.text(profile["displayName"]) ?? appUser?.nickName

        var info: [String: Any] = [
            "gesture_is_verified": (profile["isVerified"] as? Bool) ?? false
        ]
        info["fullname"] = profileFullName
        info["display_name"] = profileNickName
        profileDateOfBirth = (Self.text(profile["dateOfBirth"]) ?? appUser?.dateOfBirth).map { String($0.prefix(10)) }
        profileGender = Self.text(profile["gender"]) ?? appUser?.gender
        info["dob"] = profileDateOfBirth
        info["gender"] = EditProfileAPIMapper.genderID(profileGender)
        info["about_me"] = Self.text(profile["bio"]) ?? Self.text(profile["about"])
        info["location"] = Self.locationText(profile["location"]) ?? Self.text(profile["city"]) ?? appUser?.city
        info["avatar"] = Self.photoURL(profile["profilePhoto"])
        info["banner"] = Self.photoURL(profile["coverPhoto"])

        for field in EditProfileAPIMapper.lifestyleFields {
            let value = Self.text(more[field.api]) ?? Self.itemValue(more["items"], key: field.api)
            if let value, let id = EditProfileAPIMapper.optionID(alias: field.alias, title: value) {
                info[field.legacy] = id
            }
        }

        let interests = (data["interests"] as? [[String: Any]]) ?? (profile["interests"] as? [[String: Any]]) ?? []
        info["interests"] = interests.compactMap { item -> Int? in
            let nested = item["interest"] as? [String: Any]
            let uuid = Self.text(item["interestId"]) ?? Self.text(nested?["id"]) ?? Self.text(item["id"])
            let name = Self.text(item["name"]) ?? Self.text(nested?["name"])
            return EditProfileAPIMapper.interestOptionID(uuid: uuid, name: name)
        }

        photoUUIDs = [:]
        photoKeys = [:]
        var gallery: [[String: Any]] = []
        let photos = ((profile["photos"] as? [[String: Any]]) ?? (data["photos"] as? [[String: Any]]) ?? [])
            .sorted { ($0["displayOrder"] as? Int ?? .max) < ($1["displayOrder"] as? Int ?? .max) }
        for photo in photos {
            guard let uuid = Self.text(photo["id"]), let url = Self.text(photo["url"]) ?? Self.text(photo["thumbnailUrl"]) else { continue }
            let id = EditProfileAPIMapper.photoID(uuid)
            photoUUIDs[id] = uuid
            if let key = Self.photoKey(from: photo, url: url) {
                photoKeys[id] = key
            }
            gallery.append(["id": id, "filename": url, "filefor": "gallery", "status": 1,
                            "is_primary": (photo["isPrimary"] as? Bool) ?? false])
        }
        if !gallery.isEmpty, !gallery.contains(where: { $0["is_primary"] as? Bool == true }) {
            gallery[0]["is_primary"] = true
        }
        if let primary = gallery.first(where: { $0["is_primary"] as? Bool == true })?["filename"] as? String {
            info["avatar"] = primary
        } else if let avatar = info["avatar"] as? String {
            gallery.insert(["id": 0, "filename": avatar, "filefor": "gallery", "status": 1, "is_primary": true], at: 0)
            if photoKeys[0] == nil {
                photoKeys[0] = Self.s3PhotoKey(from: avatar)
            }
        }
        info["images"] = gallery.map { ["image": $0["filename"] ?? "", "type": "gallery", "is_primary": $0["is_primary"] ?? false] }
        info["is_active"] = info["gesture_is_verified"]

        var details: [String: Any] = [
            "user_images": gallery,
            "user_info": info,
            "profile_complete": (profile["completionPercentage"] as? Int) ?? 0
        ]
        details["username"] = appUser?.username
        details["email"] = appUser?.email
        details["phone"] = appUser?.phone

        let payload: [String: Any] = ["status": true, "message": "", "data": details]
        return EditProfileAPIMapper.decode(UserResponse.self, from: payload)
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func photoURL(_ value: Any?) -> String? {
        if let dict = value as? [String: Any] {
            return text(dict["url"]) ?? text(dict["thumbnailUrl"])
        }
        return text(value)
    }

    private static func photoKey(from photo: [String: Any], url: String) -> String? {
        if let key = text(photo["key"]) ?? text(photo["imageKey"]) {
            return key
        }
        return s3PhotoKey(from: url)
    }

    private static func s3PhotoKey(from url: String) -> String? {
        let path = url.split(separator: "?").first.map(String.init) ?? url
        if let range = path.range(of: "photos/") {
            return String(path[range.lowerBound...])
        }
        return path.hasPrefix("photos/") ? path : nil
    }

    private static func locationText(_ value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return text(value) }
        let parts = [dict["city"], dict["state"]].compactMap { text($0) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func itemValue(_ items: Any?, key: String) -> String? {
        (items as? [[String: Any]])?.first { ($0["key"] as? String) == key }.flatMap { text($0["value"]) }
    }
}

/// Bridges the backend's text answers to the option ids in the bundled `Attributes.json`.
enum EditProfileAPIMapper {

    /// Backend key, legacy `user_info` key, `Attributes.json` alias. Children has no backend field yet.
    static let lifestyleFields: [(api: String, legacy: String, alias: String)] = [
        ("drinking", "drinking", Constants.QuestionOption.drinking),
        ("education", "education", Constants.QuestionOption.education),
        ("height", "height", Constants.QuestionOption.height),
        ("religion", "religion", Constants.QuestionOption.religion),
        ("sexuality", "sexuality", Constants.QuestionOption.sexuality),
        ("smoking", "smoking", Constants.QuestionOption.smoking),
        ("weight", "weight", Constants.QuestionOption.weight),
        ("eyeColor", "eye_colour", Constants.QuestionOption.eye_colour),
        ("hairColor", "hair_colour", Constants.QuestionOption.hair_colour),
        ("living", "living", Constants.QuestionOption.living),
        ("relationship", "relationship", Constants.QuestionOption.relationship)
    ]

    static let attributes: [AttributesData] = {
        guard let url = Bundle.main.url(forResource: "Attributes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let model = try? JSONDecoder().decode(AttributesModel.self, from: data) else { return [] }
        return model.data ?? []
    }()

    static func optionID(alias: String, title: String) -> Int? {
        let wanted = normalized(title)
        return attributes.first { $0.alias == alias }?
            .aOptions?.first { normalized($0.title ?? "") == wanted }?.id
    }

    static func optionTitle(alias: String, id: Int) -> String? {
        attributes.first { $0.alias == alias }?
            .aOptions?.first { $0.id == id }?.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `GET interests`; when loaded, the interest picker uses these instead of `Attributes.json`.
    static var interestCatalog: [InterestCatalogItem] = []

    /// Swaps the bundled interest options for the backend catalog (ids hashed from the UUIDs).
    static func withCatalogInterests(_ model: AttributesModel?) -> AttributesModel? {
        guard let model, !interestCatalog.isEmpty, var data = model.data,
              let index = data.firstIndex(where: { $0.alias == Constants.QuestionOption.interests }) else { return model }
        data[index].aOptions = interestCatalog.map {
            attOptions(id: photoID($0.id), attribute_id: nil, title: $0.name, isSelected: nil, photo: $0.vibeInterest?.emoji)
        }
        return AttributesModel(status: model.status, message: model.message, data: data)
    }

    /// Picker option id for a saved interest: the catalog entry by UUID, then by name, then `Attributes.json`.
    static func interestOptionID(uuid: String?, name: String?) -> Int? {
        if !interestCatalog.isEmpty {
            if let uuid, interestCatalog.contains(where: { $0.id == uuid }) {
                return photoID(uuid)
            }
            if let name, let match = interestCatalog.first(where: { normalized($0.name) == normalized(name) }) {
                return photoID(match.id)
            }
            return nil
        }
        guard let name else { return nil }
        return optionID(alias: Constants.QuestionOption.interests, title: name)
    }

    /// Chips for the given picker option ids, using the catalog names and emoji.
    static func momentsInterests(for ids: [Int]) -> [MomentsInterest] {
        guard !interestCatalog.isEmpty else { return MomentsInterestCatalog.interests(for: ids) }
        return ids.compactMap { id in
            interestCatalog.first { photoID($0.id) == id }?.vibeInterest
        }
    }

    static func interestUUID(optionID: Int) -> String? {
        interestCatalog.first { photoID($0.id) == optionID }?.id
    }

    static func genderID(_ gender: String?) -> Int? {
        switch gender?.lowercased() {
        case "male": return 1
        case "female": return 2
        case nil: return nil
        default: return 3
        }
    }

    /// Stable positive `Int` derived from a UUID.
    static func photoID(_ uuid: String) -> Int {
        let hex = uuid.replacingOccurrences(of: "-", with: "").prefix(15)
        return Int(hex, radix: 16) ?? abs(uuid.hashValue)
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
