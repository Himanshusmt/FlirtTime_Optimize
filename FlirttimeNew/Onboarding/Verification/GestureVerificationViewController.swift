//
//  GestureVerificationViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 06/05/24.
//

import UIKit
import AVFoundation


class GestureVerificationViewController: BaseViewController,Instantiable {
    @IBOutlet weak var gesturePoseImage: UIImageView!
    @IBOutlet weak var labelPrivacy: UILabel!
    @IBOutlet weak var lablePose: UILabel!
    @IBOutlet weak var btnBack: UIButton!
    var directRedirection:Bool? = false
    private let viewModel = GestureVerificationViewModel()
    static var storyboardName: StringConvertible {
        return StoryboardName.signUp
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.bindViewModel()
        viewModel.reportScreenOpened()
        self.lablePose.setAttriibutText(text1: Constants.gesture.pose, text2: Constants.gesture.photo, color: AppColor.Punch, multipleLine: false)
//        self.labelPrivacy.setAttriibutText(text1: Constants.gesture.moreInfo, text2: Constants.gesture.privacyPolicy, color: AppColor.Punch, multipleLine: true)
        self.labelPrivacy.setAttributedTextWithLink(
            text1: Constants.gesture.moreInfo,
            text2: Constants.gesture.privacyPolicy,
            color: AppColor.Punch,
            multipleLine: true
        ) {
            print("Privacy Policy tapped!")
            self.loadPrivacyPolicy()
        }
    }

    private func bindViewModel() {
        viewModel.onLoading = { [weak self] isLoading in
            self?.setLoading(isLoading)
        }
        viewModel.onError = { [weak self] message in
            self?.aCustomToastView.show(message: message)
        }
        viewModel.onUploaded = { [weak self] in
            self?.navigateToNextScreen()
        }
        viewModel.onFaceNotDetected = { [weak self] message in
            self?.aFlirtCustomPopUp.show(text: message,
                                         buttonTitle: [Constants.AlertButtons.cancel],
                                         popUpType: .picUploadingFailed)
        }
    }

    @IBAction func backButton(_ sender: UIButton) {
        if self.directRedirection ?? false{
            guard let navigationController = self.navigationController else {return }
            let controllers = navigationController.viewControllers
            for vc in controllers {
                if vc.isKind(of: LoginViewController.self) {
                    let viewController = vc as! LoginViewController
                    self.navigationController?.popToViewController(viewController, animated: true)
                }
            }
        }else{
            self.navigationController?.popViewController(animated: true)
        }
    }

    @IBAction func takeaPhotoButtonTapped(_ sender: UIButton) {
        self.checkCameraAuthorization()

    }
}

extension GestureVerificationViewController {
    func checkCameraAuthorization() {
        DispatchQueue.main.async {
            let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if cameraAuthorizationStatus == .denied || cameraAuthorizationStatus == .restricted {
                self.showCameraAccessAlert()
                return
            }else{
                let aFaceVerificationViewController:FaceVerificationViewController = FaceVerificationViewController.instantiateFromStoryboard()
                aFaceVerificationViewController.headerText = Constants.ProfileVerification.startPosing
                aFaceVerificationViewController.callBackAction = { [weak self] image in
                    guard let image else { return }
                    self?.viewModel.uploadGesture(image: image)
                }
                aFaceVerificationViewController.modalPresentationStyle = .overCurrentContext
                self.navigationController?.present(aFaceVerificationViewController, animated: true, completion: nil)
            }
        }
    }

    func navigateToNextScreen(){
        let aVerificationDoneViewController:VerificationDoneViewController = VerificationDoneViewController.instantiateFromStoryboard()
        self.navigationController?.pushViewController(aVerificationDoneViewController, animated: true)
    }
}

