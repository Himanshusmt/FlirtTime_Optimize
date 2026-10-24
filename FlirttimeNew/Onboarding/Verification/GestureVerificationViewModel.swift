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

    /// Screen is open and the gesture is not saved yet.
    func reportScreenOpened() {
        sessionManager.reportOnboardingScreen(.gesture)
            .subscribe(onSuccess: { _ in }, onFailure: { _ in })
            .disposed(by: disposeBag)
    }

    func uploadGesture(image: UIImage) {
        guard let imageData = image.fixedOrientation().jpegData(maxBytes: Self.maxImageBytes) else {
            onError?("Unable to process the photo. Please try again.")
            return
        }

        onLoading?(true)
        sessionManager.uploadGestureSelfie(imageData: imageData)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] verification in
                self?.onLoading?(false)
                let step = OnboardingStep.resolve(currentStep: verification.currentStep,
                                                  isProfileComplete: nil,
                                                  fallback: verification.isApproved ? .completed : .gesture)
                guard step == .completed else {
                    if verification.faceDetected == false {
                        self?.onFaceNotDetected?(verification.reasonMessage
                                                 ?? verification.rejectionReason
                                                 ?? "No face detected. Please take a clear photo showing your face.")
                    } else {
                        self?.onError?(verification.reasonMessage
                                       ?? verification.rejectionReason
                                       ?? "Verification failed. Please try again.")
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
}
