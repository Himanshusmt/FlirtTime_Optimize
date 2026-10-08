//
//  SetAvatarModel.swift
//  FlirtTime
//
//  Created by Smt MacMini on 12/12/24.
//

import UIKit

// TODO: replace with the ApiName.uploadAvatarImage multipart request.
class SetAvatarModel: NSObject {

    @Published var aUploadAvatarModel:UploadProfileImageModel?
    @Published var errorMessage:String?

    func uploadUserProfileImageAPI(image:UIImage) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) { [weak self] in
            guard let self = self else { return }
            guard let name = MockDataStore.shared.setAvatar(image) else {
                self.errorMessage = "Picture upload failed"
                return
            }
            self.aUploadAvatarModel = UploadProfileImageModel.mockUpload(fileName: name, message: "Profile photo updated successfully")
        }
    }
}
