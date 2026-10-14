//
//  SetBannerModel.swift
//  FlirtTime
//
//  Created by Smt MacMini on 12/12/24.
//

import UIKit
import RxSwift
import Swinject

class SetBannerModel: NSObject {

    @Published var aUploadBannerModel:UploadProfileImageModel?
    @Published var errorBannerMessage:String?

    private lazy var sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!
    private let disposeBag = DisposeBag()

    private static let maxImageBytes = 5 * 1024 * 1024

    func uploadCoverPhotoAPI(image:UIImage) {
        guard let imageData = image.jpegData(maxBytes: Self.maxImageBytes) else {
            errorBannerMessage = "Picture upload failed"
            return
        }
        sessionManager.updateCoverPicture(imageData: imageData)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] url in
                let payload: [String: Any] = ["status": true, "message": "Cover photo updated successfully",
                                              "data": ["image_url": url]]
                self?.aUploadBannerModel = EditProfileAPIMapper.decode(UploadProfileImageModel.self, from: payload)
            }, onFailure: { [weak self] error in
                self?.errorBannerMessage = parseError(error) ?? "Picture upload failed"
            })
            .disposed(by: disposeBag)
    }
}
