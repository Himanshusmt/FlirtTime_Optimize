//
//  GestureVerificationViewModel.swift
//  FlirttimeNew
//

import UIKit
import RxSwift
import Swinject

final class GestureVerificationViewModel {

    private let sessionManager: AppSessionManager
    private let disposeBag = DisposeBag()

    var onLoading: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onUploaded: (() -> Void)?
    var onFaceNotDetected: ((String) -> Void)?

    /// Backend limit for `selfie_image`.
    private static let maxImageBytes = 5 * 1024 * 1024

    init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    func uploadGesture(image: UIImage) {
        guard let imageData = Self.jpegData(for: image.fixedOrientation()) else {
            onError?("Unable to process the photo. Please try again.")
            return
        }

        onLoading?(true)
        sessionManager.uploadGestureSelfie(imageData: imageData)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] verification in
                self?.onLoading?(false)
                guard verification.isApproved else {
                    if verification.faceDetected == false {
                        self?.onFaceNotDetected?(verification.reasonMessage
                                                 ?? "No face detected. Please take a clear photo showing your face.")
                    } else {
                        self?.onError?(verification.reasonMessage ?? "Verification failed. Please try again.")
                    }
                    return
                }
                self?.onUploaded?()
            }, onFailure: { [weak self] error in
                self?.onLoading?(false)
                self?.onError?(parseError(error) ?? "Something went wrong")
            })
            .disposed(by: disposeBag)
    }

    private static func jpegData(for image: UIImage) -> Data? {
        var quality: CGFloat = 0.8
        var data = image.jpegData(compressionQuality: quality)
        while let current = data, current.count > maxImageBytes, quality > 0.1 {
            quality -= 0.1
            data = image.jpegData(compressionQuality: quality)
        }
        guard let data, data.count <= maxImageBytes else { return nil }
        return data
    }
}
