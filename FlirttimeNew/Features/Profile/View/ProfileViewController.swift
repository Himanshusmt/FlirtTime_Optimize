//
//  ProfileViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 18/05/24.
//

import UIKit
import Photos
import Combine

class ProfileViewController: BaseViewController,UIScrollViewDelegate,UIGestureRecognizerDelegate{

    @IBOutlet weak var nameLabel:UILabel!
    @IBOutlet weak var verifiedUserIcon:UIImageView!
    @IBOutlet weak var backGroundProfileImage:UIImageView!
    @IBOutlet weak var editProfileImageButton: UIButton!
    @IBOutlet weak var coverImage: UIImageView!
    @IBOutlet weak var rewardCollectionView: UICollectionView!
    @IBOutlet weak var addCoverPhotoButton: UIButton!
    @IBOutlet weak var addCoverPhotoButton2: UIView!
    @IBOutlet weak var premiumCardView: UIView!
    @IBOutlet weak var upgradePremiumPlanButton: UIButton!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var momentCollectionView: UICollectionView!
    @IBOutlet weak var momentCollectionViewHeight: NSLayoutConstraint!
    @IBOutlet weak var noMomentsView: UIView!
    @IBOutlet weak var momentListView: UIView!
    @IBOutlet weak var profileProgressView: CircularProgressView!
    @IBOutlet weak var userAboutLabel: UILabel!
    @IBOutlet weak var userProfileImage: UIImageView!
    @IBOutlet weak var editProfileView: UIView!
    @IBOutlet weak var settingButton: UIButton!
    @IBOutlet weak var addMomentView: UIView!
    @IBOutlet weak var allMomentView: UIView!

    private var aProfileViewModel = ProfileViewModel()
    private var userProfileData:UserDetailsData?
    private var aMyMomentsData:[MomentsDatum]? = []
    private var MyMomentCellWidth = (screen.width - 50)/2
    private var selectedImage:UIImage?
    private var editProfileImage:Bool? = true
    private var desposeBag: Set<AnyCancellable> = []
    private var textDescription:String?
    private var coverImageUrl:String?
    private var ignoreViewWillAppear:Bool? = false
    
    private var aBannerModel = SetBannerModel()
    private var aAvatarModel = SetAvatarModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setUI()
        self.setBinding()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        AppTabBarController.buttonD.isHidden = false
        
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.ignoreViewWillAppear = false
        AppTabBarController.buttonD.isHidden = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.aProfileViewModel.aUserProfileModel == nil && !(self.ignoreViewWillAppear ?? false) {
            self.noMomentsView.isHidden = true
            self.momentListView.isHidden = false
            self.setProfileCompletionProgress()
            self.aProfileViewModel.getProfileDataAPI()
            self.aProfileViewModel.getMyMomentsAPI()
        }
        
        self.checkHideCustomButton(hide: false)
        self.resetData(ignoreViewWillAppear: true)
    }

    func resetData(ignoreViewWillAppear:Bool?){
        self.ignoreViewWillAppear = ignoreViewWillAppear
        self.setProfileCompletionProgress()
        self.aProfileViewModel.aUserProfileModel = nil
        self.aProfileViewModel.getProfileDataAPI()
        self.aProfileViewModel.getMyMomentsAPI()
    }

    func setUI(){
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.editProfileImageButton.layer.cornerRadius = 10
        self.editProfileImageButton.layer.masksToBounds = true
        self.addCoverPhotoButton2.isHidden = true
        self.addCoverPhotoButton.isHidden = true
        self.scrollView.delegate = self
        self.registerCell()

        let labelTapGesture = UITapGestureRecognizer(target: self, action: #selector(self.handleLabelTap(_:)))
        labelTapGesture.cancelsTouchesInView = false
        labelTapGesture.delegate = self // Set the delegate
        self.userAboutLabel.addGestureRecognizer(labelTapGesture)
        self.premiumCardView.addShadow(color: AppColor.AppBlack.withAlphaComponent(0.25), opacity: 1.0, offset: CGSize(width: 0, height: 1.0))
        premiumCardView.backgroundColor = .white // or your card background color
        premiumCardView.layer.cornerRadius = 14.0
       // premiumCardView.layer.borderWidth = 1
       // premiumCardView.layer.borderColor = AppColor.AthensGray.cgColor // your border color
        //premiumCardView.clipsToBounds = false // Important for shadow to show

        // Shadow
       // premiumCardView.layer.shadowColor = UIColor.black.cgColor
       // premiumCardView.layer.shadowOpacity = 0.1
       // premiumCardView.layer.shadowOffset = CGSize(width: 0, height: 4)
       // premiumCardView.layer.shadowRadius = 8
    }

    func setBinding(){
        self.aBannerModel.$aUploadBannerModel.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                //self.coverImageUrl = model?.data?.image_url ?? ""
                self.aActivityIndicator.hide()
               // self.showImageAlertPopUp(TitleMsg: "Picture uploaded successfully", TitleBtn: "Continue")
                
                if let imageUrl = URL(string: model?.data?.image_url ?? "") {
                    self.addCoverPhotoButton.isHidden = true
                    self.addCoverPhotoButton2.isHidden = false
                    self.coverImage.contentMode = .scaleAspectFill
                    self.downloadImage(imageType:self.coverImage, imageUrl: imageUrl, message: model?.message ?? "")
                }
            }
        }.store(in: &desposeBag)

        self.aAvatarModel.$aUploadAvatarModel.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                if let imageUrl = URL(string: model?.data?.image_url ?? "") {
                    DispatchQueue.main.async {
                        self.downloadImage(imageType:self.userProfileImage, imageUrl: imageUrl, message: model?.message ?? "")
                    }
                }
            }
        }.store(in: &desposeBag)

        self.aProfileViewModel.$aUserProfileModel.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.userProfileData = model
                    self.setUserProfileData(model: model)
                    self.momentCollectionView.reloadData()
                }
            }
        }.store(in: &desposeBag)
        
        self.aProfileViewModel.$aMyMomentsModel.receive(on: DispatchQueue.main).sink { model in
            if model?.count ?? 0 > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.aMyMomentsData = model
                    self.setMyMomentsData()
                }
            }else {
                self.noMomentsView.isHidden = false
                self.momentListView.isHidden = true
            }
            self.momentCollectionView.reloadData()
        }.store(in: &desposeBag)

        self.aProfileViewModel.$errorMessage.receive(on: DispatchQueue.main).sink { error in
            if error != nil {
                self.showNewAlertPopUp(Title: "Error", Msg: error ?? "", isSuccess: false, CompletionHandler: {(success) -> Void in
    
                })
            }
        }.store(in: &desposeBag)
        
        self.aBannerModel.$errorBannerMessage.receive(on: DispatchQueue.main).sink { error in
            if error != nil {
                self.aActivityIndicator.hide()
                self.showImageAlertPopUp(TitleMsg: "Picture upload failed", TitleBtn: "Discard")
            }
        }.store(in: &desposeBag)

    }

    func downloadImage(imageType:UIImageView,imageUrl:URL?,message:String?){
        self.aActivityIndicator.show()
        imageType.loadImage(with: imageUrl,placeholder: UIImage(named: "ProfileBlur")) { [weak self] _ in
            self?.aActivityIndicator.hide()
        }
    }
    
//    func downloadImage(imageType:UIImageView,imageUrl:URL?,message:String?){
//        print("url......", imageUrl?.absoluteString ?? "")
//        //self.aActivityIndicator.show()
//        DispatchQueue.main.async {
//            imageType.sd_setImage(with: imageUrl, placeholderImage: UIImage(named: "ProfileBlur"))
//            
//        }
//        //self.aAppAlert.show(message:message ?? "", buttonTitles: [Constants.AlertButtons.okay],isSuccess: true)
//        //imageType.sd_setImage(with: imageUrl, placeholderImage: UIImage(named: "ProfileBlur"))
//        //self.aActivityIndicator.hide()
//    }

    func setUserProfileData(model:UserDetailsData?){
            
            if model?.userInfo?.banner != nil {
                self.coverImageUrl = "\(ApiName.imgBaseURL)"+"\(model?.userInfo?.banner ?? "")"
                if let imageUrl = URL(string: self.coverImageUrl ?? "") {
                    print("img url cover.....", imageUrl)
                    DispatchQueue.main.async {
                        self.addCoverPhotoButton.isHidden = true
                        self.addCoverPhotoButton2.isHidden = false
                        self.coverImage.loadImage(with: imageUrl,placeholder: UIImage(named: "addCoverPhoto"))
                        self.coverImage.contentMode = .scaleAspectFill
                    }
                }
            }
             else {
                self.addCoverPhotoButton.isHidden = false
                self.addCoverPhotoButton2.isHidden = true
            }
            let profileImg = "\(ApiName.imgBaseURL)"+"\(model?.userInfo?.avatar ?? "")"
            print("img url profile.....", profileImg)
            if let imageUrl = URL(string: profileImg) {
                DispatchQueue.main.async {
                    self.userProfileImage.loadImage(with: imageUrl,placeholder: UIImage(named: "ProfileBlur"))
                    self.coverImage.contentMode = .scaleAspectFill
                }
            }
        
        self.nameLabel.text = "\(model?.userInfo?.displayName ?? "")"
        //self.verifiedUserIcon.isHidden = model?.data?.isVerified == 0
        self.profileProgressView.setProgressColor = .red
        let profilePercentage = Float(model?.profile_complete ?? 0) / 100
        self.profileProgressView.setProgressWithAnimation(duration:2.0, value: profilePercentage)
        self.userAboutLabel.isUserInteractionEnabled = true
        self.textDescription = model?.userInfo?.aboutMe
        self.userAboutLabel.text = self.textDescription
        self.userAboutLabel.appendReadmore(after: textDescription ?? "", trailingContent: .readmore)
        self.editProfileImageButton.setTitle("\(model?.profile_complete ?? 0)%", for: .normal)
        if model?.userInfo?.isActive == true {
            self.verifiedUserIcon.isHidden = false
        } else {
            self.verifiedUserIcon.isHidden = true
        }
    }
    
    func setMyMomentsData(){
        self.noMomentsView.isHidden = self.aMyMomentsData?.count ?? 0 > 0
        self.momentListView.isHidden = !(self.aMyMomentsData?.count ?? 0 > 0)
        let momentDataCount = self.aMyMomentsData?.count ?? 0
        let count = momentDataCount % 2 == 0 ? momentDataCount : (momentDataCount + 1)
        self.momentCollectionViewHeight.constant =  CGFloat(count / 2) * (self.MyMomentCellWidth * 1.3048 + 12)
        DispatchQueue.main.async {
            self.momentCollectionView.reloadData()
        }
    }

    func setProfileCompletionProgress(color:UIColor? = .white) {
        self.profileProgressView.startAngle = CGFloat(-1.5 * Double.pi)
        self.profileProgressView.endAngle = CGFloat(0.5 * Double.pi)
        self.profileProgressView.setProgressWithAnimation(duration: 0, value: 0)
        self.profileProgressView.setProgressColor = color ?? .red // Your color
        self.profileProgressView.setTrackColor = UIColor.white // Your track color
        self.profileProgressView.setProgressLineWidth = 6 // Appropriate line width
        self.profileProgressView.setTrackLineWidth = 4 // Appropriate track line width
    }

    func registerCell(){
        self.rewardCollectionView.register(UINib(nibName: RewardCollectionViewCell.identifier, bundle: nil), forCellWithReuseIdentifier: RewardCollectionViewCell.identifier)
        self.rewardCollectionView.delegate = self
        self.rewardCollectionView.dataSource = self
        self.rewardCollectionView.reloadData()

        self.momentCollectionView.register(UINib(nibName: MomentCollectionViewCell.identifier, bundle: nil), forCellWithReuseIdentifier: MomentCollectionViewCell.identifier)
        self.momentCollectionView.isScrollEnabled = false
        self.momentCollectionView.delegate = self
        self.momentCollectionView.dataSource = self
        self.momentCollectionView.reloadData()

    }

    @objc func handleLabelTap(_ sender: UITapGestureRecognizer) {
        guard let text = self.userAboutLabel.text else { return }

        let readmore = (text as NSString).range(of: TrailingContent.readmore.text)
        let readless = (text as NSString).range(of: TrailingContent.readless.text)
        if readmore.length > 0 {
            self.userAboutLabel.appendReadLess(after: textDescription ?? "", trailingContent: .readless)
        } else if readless.length > 0 {
            self.userAboutLabel.appendReadmore(after: textDescription ?? "", trailingContent: .readmore)
        } else { return }
        
//        if sender.didTapAttributedTextInLabel(label: self.userAboutLabel, inRange: readmore) {
//            self.userAboutLabel.appendReadLess(after: textDescription ?? "", trailingContent: .readless)
//        } else if  sender.didTapAttributedTextInLabel(label: self.userAboutLabel, inRange: readless) {
//            self.userAboutLabel.appendReadmore(after: textDescription ?? "", trailingContent: .readmore)
//        } else { return }
    }

    @IBAction func addCoverPhotoButtonTapped(_ sender: UIButton) {
        self.editProfileImage = false
        self.openImageSelectionMethodPopUp()
    }

    @IBAction func addCoverPhotoButton2Tapped(_ sender: UIButton) {
        self.editProfileImage = false
        self.openImageSelectionMethodPopUp()
    }
    
    @IBAction func upgragePremiumPlanButtonTapped(_ sender: UIButton) {
        self.openPremium()
    }

    @IBAction func rewardSeeMoreButtonTapped(_ sender: UIButton) {
        //        sender.isSelected =  !(sender.isSelected)
        //        self.noMomentsView.isHidden = !(sender.isSelected)
        //        self.momentListView.isHidden = sender.isSelected

        self.showComingSoon("Rewards")
    }

    @IBAction func addMomentButtonTapped(_ sender: UIButton) {
        // TODO: restore the verification gating and push AddMomentViewController once Moments is ported.
        self.showComingSoon("Add moment")
    }

    @IBAction func editProfileButtonTapped(_ sender: UIButton) {
//        if UserDataManager.shared.isHomeVerificationDone == false {
//            self.openVerifyUserNonSkipPopUp()
//        } else {
           // if UserDataManager.shared.ProfileStatus == Constants.ProfileStatus.Pending || UserDataManager.shared.AvatarStatus == Constants.AvatarStatus.UnderVerification || UserDataManager.shared.AvatarStatus == Constants.AvatarStatus.NewUpload {
            //Commented by Aasif old comment
//            if UserDataManager.shared.AvatarStatus != Constants.AvatarStatus.Verified {  // Implemented by Aasif new comment
//                self.showWaitAlertPopUp()
//                
//            } else {
                let aEditProfileViewController:EditProfileViewController = EditProfileViewController.instantiateFromStoryboard()
                //aEditProfileViewController.userProfileData = self.userProfileData
                aEditProfileViewController.coverImageUrl = self.coverImageUrl
                aEditProfileViewController.callBackAction = { [weak self] in
                    self?.resetData(ignoreViewWillAppear: true)
                }
                self.navigationController?.pushViewController(aEditProfileViewController, animated: true)
//            }
//        }
        
    }

    @IBAction func settingButtonTapped(_ sender: UIButton) {
        // Settings is not ported yet; it hosts logout until it is.
        self.aDeleteCustomPopUp.show(message: Constants.logOut.logout, button1Text: Constants.AlertButtons.yes, button2Text: Constants.AlertButtons.No, deleteType: .logout) {
            self.navigateToLoginScreen()
        }
    }

    @IBAction func editProfilePhotoButtonTapped(_ sender: UIButton) {
//        self.editProfileImage = true
//        self.openImageSelectionMethodPopUp()
    }
    
    @IBAction func goToProfileTapped(_ sender: UIButton) {
//        if UserDataManager.shared.isHomeVerificationDone == false {
//            self.openVerifyUserNonSkipPopUp()
//        } else {                      //Commented by Aasif
            let aEditProfileViewController:EditProfileViewController = EditProfileViewController.instantiateFromStoryboard()
            //aEditProfileViewController.userProfileData = self.userProfileData
            aEditProfileViewController.coverImageUrl = self.coverImageUrl
            aEditProfileViewController.callBackAction = { [weak self] in
                self?.resetData(ignoreViewWillAppear: true)
            }
            self.navigationController?.pushViewController(aEditProfileViewController, animated: true)
//        }
        
    }
    
    func openImageSelectionMethodPopUp(){
        let aImageSelectionMethodVC:ImageSelectionMethodVC = ImageSelectionMethodVC.instantiateFromStoryboard()
        aImageSelectionMethodVC.callBack = { [weak self] data in
            if data {
                self?.checkCameraAuthorization()
            }else{
                self?.requestPhotoLibraryAccess()
            }
        }
        aImageSelectionMethodVC.modalPresentationStyle = .overCurrentContext
        self.tabBarController?.present(aImageSelectionMethodVC, animated: true, completion: nil)
    }
}

extension ProfileViewController:UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch collectionView{
        case rewardCollectionView:
            return 3
        case momentCollectionView:
            let count = (self.aMyMomentsData?.count ?? 0)
            return count == 1 ? 2 : count
        default :
            return 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch collectionView{
        case rewardCollectionView:
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RewardCollectionViewCell.identifier, for: indexPath) as? RewardCollectionViewCell {
                return cell
            }
        case momentCollectionView:
            if (self.aMyMomentsData?.count ?? 0) == 1 && indexPath.row != 0 {
                if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MomentCollectionViewCell.identifier, for: indexPath) as? MomentCollectionViewCell {
                    cell.isUserInteractionEnabled = false
                    cell.contentView.isHidden = true
                    return cell
                }
            }else {
                if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MomentCollectionViewCell.identifier, for: indexPath) as? MomentCollectionViewCell {
                    cell.setMyMomnetsData(data:self.aMyMomentsData?[indexPath.row].images ?? [])
                    cell.isUserInteractionEnabled = true
                    cell.contentView.isHidden = false
                    return cell
                }
            }
        default :
            return UICollectionViewCell()
        }
        return UICollectionViewCell()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
//        let aOtherUserPhotoGridViewController:OtherUserPhotoGridViewController = OtherUserPhotoGridViewController.instantiateFromStoryboard()
//        self.navigationController?.pushViewController(aOtherUserPhotoGridViewController, animated: true)
        
        guard collectionView == momentCollectionView else { return }
        self.showComingSoon("Moments")
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        switch collectionView{
        case rewardCollectionView:
            return CGSize(width: screen.width - 40 , height: 114)
        case momentCollectionView:
            return CGSize(width: MyMomentCellWidth , height: MyMomentCellWidth * 1.3048)
        default :
            return CGSize(width: 0 , height: 0)
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 10
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 11
    }

    //    func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
    //        if scrollView.panGestureRecognizer.translation(in: scrollView).y < 0{
    //            hideShowTabBar(isHide:true)
    //        }else{
    //            hideShowTabBar(isHide:false)
    //        }
    //    }


    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView != self.rewardCollectionView else {return}
        let translation = scrollView.panGestureRecognizer.translation(in: scrollView).y
        hideShowTabBar(isHide: translation < 0)
    }

}

extension ProfileViewController {

    func uploadSelectedImage(_ selectedImage:UIImage?){
        guard let image = selectedImage else {return}
        let imgPic = image.fixedOrientation()
        self.aActivityIndicator.show()
        if self.editProfileImage ?? false {
            self.aAvatarModel.uploadUserProfileImageAPI(image: imgPic)
        }else{
            self.aBannerModel.uploadCoverPhotoAPI(image: imgPic)
        }
    }
}

// Granted User permission
extension ProfileViewController {
    // Function to request photo library access permission
    func requestPhotoLibraryAccess() {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            if status == .authorized { // Permission granted by the user
                self?.openPhotoLibrary()
            } else { // Permission denied by the user
                // Show alert for photo library access permission
                DispatchQueue.main.async {
                    self?.showPhotoLibraryAccessAlert()
                }
            }
        }
    }

    func checkCameraAuthorization() {
        DispatchQueue.main.async {
            let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if cameraAuthorizationStatus == .denied || cameraAuthorizationStatus == .restricted {
                self.showCameraAccessAlert()
            } else {
                let aFaceVerificationViewController:FaceVerificationViewController = FaceVerificationViewController.instantiateFromStoryboard()
                aFaceVerificationViewController.headerText = Constants.ProfileVerification.startPosing
                aFaceVerificationViewController.isHideScanningImage = true
                aFaceVerificationViewController.callBackAction = { [weak self] image in
                    if let selectedImage = image {
                        self?.uploadSelectedImage(selectedImage)
                    }
                }
                aFaceVerificationViewController.modalPresentationStyle = .overCurrentContext
                self.tabBarController?.present(aFaceVerificationViewController, animated: true, completion: nil)
            }
        }
    }


    // UIImagePickerControllerDelegate method to handle image selection
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let selectedImage = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage) {
            self.selectedImage = selectedImage
        }
        picker.dismiss(animated: true) {
            self.uploadSelectedImage(self.selectedImage)
        }
    }

    // UIImagePickerControllerDelegate method to handle cancel action
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}
