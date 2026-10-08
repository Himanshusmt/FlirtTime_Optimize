//
//  SetBannerModel.swift
//  FlirtTime
//
//  Created by Smt MacMini on 12/12/24.
//

import UIKit

// TODO: replace with the ApiName.uploadBannerImage multipart request.
class SetBannerModel: NSObject {

    @Published var aUploadBannerModel:UploadProfileImageModel?
    @Published var errorBannerMessage:String?

    func uploadCoverPhotoAPI(image:UIImage) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) { [weak self] in
            guard let self = self else { return }
            guard let name = MockDataStore.shared.setBanner(image) else {
                self.errorBannerMessage = "Picture upload failed"
                return
            }
            self.aUploadBannerModel = UploadProfileImageModel.mockUpload(fileName: name, message: "Cover photo updated successfully")
        }
    }
}
