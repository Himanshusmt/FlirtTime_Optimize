//
//  ImageSelectionMethodVC.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 16/05/24.
//

import UIKit

class ImageSelectionMethodVC: BaseViewController,UIGestureRecognizerDelegate,Instantiable {

    @IBOutlet weak var mainView: UIView!
    @IBOutlet weak var stack1: UIStackView!
    @IBOutlet weak var stack2: UIStackView!
    @IBOutlet weak var deletePictureButton: UIButton!
    @IBOutlet weak var takePhotoGalleryButton: UIStackView!
    
    @IBOutlet weak var imgVWProfile: UIImageView!
    @IBOutlet weak var imgVWCover: UIImageView!
    
    var fromEditProfileScreen:Bool? = false
    var selectImageType:selectImageType?
    var isContainImage:Bool? = false
    var callBack:((Bool)-> Void)?
    var deletePictureCallBack:((Bool)->())?
    var isShowImage:Bool? = false
    var strURLImg:UIImage?
    var isShowAvatarImage:Bool? = false
    
    static var storyboardName: StringConvertible {
        return StoryboardName.aboutYou
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setUI()
    }

    func setUI(){
        self.mainView.setRoundedManualTopCorners(cornerRadius: 15)
        self.view.backgroundColor = .black.withAlphaComponent(0.7)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self // Set the delegate
        self.view.addGestureRecognizer(tapGesture)

        // Create a swipe gesture recognizer
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeDown.direction = .down
        self.view.addGestureRecognizer(swipeDown)
        if self.fromEditProfileScreen ?? false && self.selectImageType == .addSelfImage{
            if isContainImage == true {
                self.mainView.isHidden = true
//                self.deletePictureButton.isHidden = (isContainImage ?? false) //!(isContainImage ?? false)
//                self.stack1.isHidden = self.isContainImage ?? false
//                self.stack2.isHidden = (self.isContainImage ?? false) //!(self.isContainImage ?? false)
//                self.takePhotoGalleryButton.isHidden = true
                
            } else {
                self.mainView.isHidden = false
                self.deletePictureButton.isHidden = !(isContainImage ?? false)
                self.stack1.isHidden = self.isContainImage ?? false
                self.stack2.isHidden = !(self.isContainImage ?? false)
            }
            
        } else if self.fromEditProfileScreen ?? false && self.selectImageType == .addCoverImage {
            self.deletePictureButton.isHidden = true
            self.stack1.isHidden = false
            self.stack2.isHidden = true
        } else {
            
            if self.isContainImage == true {
                self.deletePictureButton.isHidden = false
                self.stack1.isHidden = true
                self.stack2.isHidden = false
            } else {
                self.deletePictureButton.isHidden = true
                self.stack1.isHidden = false
                self.stack2.isHidden = true
            }
            
        }
        
        if self.isShowImage == true && self.selectImageType == .addSelfImage{
            self.imgVWCover.isHidden = true
            self.imgVWProfile.isHidden = false
            self.imgVWProfile.cornerRadius = 20
            self.imgVWProfile.contentMode = .scaleAspectFill
            self.imgVWProfile.image = strURLImg
        } else if self.isShowImage == true && self.selectImageType == .addCoverImage {
            self.imgVWProfile.isHidden = true
            self.imgVWCover.isHidden = false
            self.imgVWCover.cornerRadius = 20
            self.imgVWCover.contentMode = .scaleAspectFill
            self.imgVWCover.image = strURLImg
        } else {
            self.imgVWProfile.isHidden = true
        }
        
        if self.isShowAvatarImage == true {
            self.mainView.isHidden = true
        } else {
            self.mainView.isHidden = false
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let view = touch.view, view.isDescendant(of: mainView) {
            return false
        }
        return true
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        self.dismiss(animated: true)
    }

    @objc func handleSwipe(_ gesture: UITapGestureRecognizer) {
        self.dismiss(animated: true)
    }

    @IBAction func takePhotoButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true) {
            guard let action = self.callBack else {return}
            action(true)
        }
    }

    @IBAction func choseFromLibraryButtonTappped(_ sender: UIButton) {
        self.dismiss(animated: true) {
            guard let action = self.callBack else {return}
            action(false)
        }
    }

// *MARK: - Edit profile section

    @IBAction func takePhotoButtonAction(_ sender: UIButton) {
        self.dismiss(animated: true) {
            guard let action = self.callBack else {return}
            action(true)
        }
    }
    
    @IBAction func takePhotoFromGallery(_ sender: UIButton) {
        self.dismiss(animated: true) {
            guard let action = self.callBack else {return}
            action(false)
        }
    }


    @IBAction func deletePictureButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true) {
            guard let action = self.deletePictureCallBack else {return}
            action(true)
        }
    }
}
