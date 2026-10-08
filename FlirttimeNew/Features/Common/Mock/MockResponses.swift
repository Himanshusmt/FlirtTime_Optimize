//
//  MockResponses.swift
//  FlirttimeNew
//
//  Builders for the simple server responses returned by the mock view models.
//

import Foundation

extension UploadProfileImageModel {
    static func mockUpload(fileName: String, imagePayload: [String: Any]? = nil, message: String) -> UploadProfileImageModel? {
        var data: [String: Any] = ["image_url": ApiName.imgBaseURL + fileName]
        if let imagePayload {
            data["image"] = imagePayload
        }
        return MockDataStore.shared.decode(UploadProfileImageModel.self, from: ["status": true, "message": message, "data": data])
    }
}

extension DeleteUserImageResponseModel {
    static func mockSuccess(_ message: String) -> DeleteUserImageResponseModel {
        DeleteUserImageResponseModel(status: true, message: message)
    }
}

extension UserDetailResponseModel {
    static func mockSuccess(_ message: String) -> UserDetailResponseModel {
        UserDetailResponseModel(status: true, message: message, data: nil)
    }
}
