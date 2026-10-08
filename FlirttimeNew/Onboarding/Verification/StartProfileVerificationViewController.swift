//
//  StartProfileVerificationViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 03/05/24.
//

import UIKit
import AVFoundation
import Photos

class StartProfileVerificationViewController: BaseViewController,Instantiable {

    @IBOutlet weak var makeYourIdentityView: UIView!
    @IBOutlet weak var labelMakeYourIdentity: UILabel!
    @IBOutlet weak var imageViewGif: UIImageView!
    var userImage:UIImage?
    var methodSelection:PhotoSelectionType?
    var directRedirection:Bool? = false

    static var storyboardName: StringConvertible {
        return StoryboardName.signUp
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.imageViewGif.setGifImage(name:"pablita-face-id")
        self.labelMakeYourIdentity.setAttriibutText(text1: "Mark your identity\nwith a ", text2: "profile picture.", color: AppColor.Punch, multipleLine: false)
    }

    @IBAction func backButton(_ sender: UIButton) {
        if directRedirection ?? false {
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
    

    @IBAction func takePhotoButtonTapped(_ sender: UIButton) {
        self.methodSelection = .camera
        self.checkCameraAuthorization()
    }

    @IBAction func openPhotosLibraryButton(_ sender: UIButton) {
        self.methodSelection = .photoLibrary
        self.requestPhotoLibraryAccess()
    }

}

// Granted User permission
extension StartProfileVerificationViewController {
    func checkCameraAuthorization() {
        DispatchQueue.main.async {
            let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if cameraAuthorizationStatus == .denied || cameraAuthorizationStatus == .restricted {
                self.showCameraAccessAlert()
                return
            }else{
                let aFaceVerificationViewController:FaceVerificationViewController = FaceVerificationViewController.instantiateFromStoryboard()
                aFaceVerificationViewController.headerText = Constants.ProfileVerification.focusOnFace
                aFaceVerificationViewController.callBackAction = { [weak self] image in
                    if image != nil {
                        //                        guard let image = image else { return }
                        guard let self = self else { return }
                        self.showUploadPopUp(selectedImage: image)
                    }
                }
                aFaceVerificationViewController.modalPresentationStyle = .overCurrentContext
                self.navigationController?.present(aFaceVerificationViewController, animated: true, completion: nil)
            }
        }
    }

    // Function to request photo library access permission
    func requestPhotoLibraryAccess() {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized { // Permission granted by the user
                self.openPhotoLibrary()
            } else { // Permission denied by the user
                // Show alert for photo library access permission
                DispatchQueue.main.async {
                    self.showPhotoLibraryAccessAlert()
                }
            }
        }
    }

    // UIImagePickerControllerDelegate method to handle image selection
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let selectedImage = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage) {
            self.userImage = selectedImage
        }
        picker.dismiss(animated: true) {
            self.showUploadPopUp(selectedImage: self.userImage)
        }
    }

    // UIImagePickerControllerDelegate method to handle cancel action
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }

    func navigateToNextScreen(){
        let aEndProfileVerificationViewController:EndProfileVerificationViewController = EndProfileVerificationViewController.instantiateFromStoryboard()
        aEndProfileVerificationViewController.userImage = self.userImage
        self.navigationController?.pushViewController(aEndProfileVerificationViewController, animated: true)
    }
}

extension StartProfileVerificationViewController {

    func showUploadPopUp(selectedImage:UIImage?){
        guard let image = selectedImage else {return}
        let imgPic = image.fixedOrientation()
        self.userImage = imgPic
        self.aFlirtCustomPopUp.show(text:Constants.CustomPopUp.uploadingPicture, buttonTitle: [Constants.AlertButtons.discard], popUpType: .pictureUploading,image:imgPic, completion2: { data in
            if data == .pictureUploading {
                self.navigateToNextScreen()
            }
        })
    }
}
