//
//  ProfilePhotoViewModel.swift
//  FlirttimeNew
//

import UIKit
import RxSwift
import Swinject

final class ProfilePhotoViewModel {

    private let sessionManager: AppSessionManager
    private var uploadDisposable: Disposable?

    var onUploaded: (() -> Void)?
    var onError: ((String) -> Void)?

    /// Backend limit for uploaded photos.
    private static let maxImageBytes = 5 * 1024 * 1024

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    deinit {
        uploadDisposable?.dispose()
    }

    func upload(image: UIImage) {
        cancel()
        guard let imageData = image.fixedOrientation().jpegData(maxBytes: Self.maxImageBytes) else {
            onError?("Unable to process the photo. Please try again.")
            return
        }

        let sessionManager = self.sessionManager
        uploadDisposable = sessionManager.uploadImageToS3(imageData, folder: "photos")
            .flatMap { upload -> Single<Void> in
                guard let key = upload.resolvedKey else { return .error(APIError.apiError("Picture upload failed")) }
                return sessionManager.setProfilePhoto(imageKey: key)
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                self?.onUploaded?()
            }, onFailure: { [weak self] error in
                self?.onError?(parseError(error) ?? "Picture upload failed")
            })
    }

    func cancel() {
        uploadDisposable?.dispose()
        uploadDisposable = nil
    }
}
