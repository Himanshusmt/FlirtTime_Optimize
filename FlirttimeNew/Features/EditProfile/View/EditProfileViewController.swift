//
//  EditProfileViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 31/05/24.
//

import UIKit
import IQKeyboardManagerSwift
//import Photos
import PhotosUI
import Combine

class EditProfileViewController: BaseViewController, Instantiable {

    @IBOutlet weak var verifyYourselfView: UIView!
    @IBOutlet weak var lastNameTextField: OutlinedTextField!
    @IBOutlet weak var emaiIDTextField: OutlinedTextField!
    @IBOutlet weak var firstNameTextField: OutlinedTextField!
    @IBOutlet weak var cityPlaceTextField: OutlinedTextField!
    @IBOutlet weak var displayNameTextField: OutlinedTextField!
    @IBOutlet weak var verifyMailTextField: OutlinedTextField!
    @IBOutlet weak var verifyButton: UIButton!
    @IBOutlet weak var aboutTextView: UITextView!
    @IBOutlet weak var viewTextView: UIView!
    @IBOutlet weak var labelTextViewTitle: UILabel!
    @IBOutlet weak var interestCollectionView: UICollectionView!
    @IBOutlet weak var interestViewHeight: NSLayoutConstraint!
    @IBOutlet weak var aboutMeTableView: UITableView!
    @IBOutlet weak var moreAboutView: UIView!
    @IBOutlet weak var coverImage: UIImageView!
    @IBOutlet weak var moreAboutMeViewHeight: NSLayoutConstraint!
    @IBOutlet weak var addCoverPhotoButton: UIButton!
    @IBOutlet weak var editCoverView: UIView!
    @IBOutlet weak var connectInstaSelectionImage: UIImageView!
    @IBOutlet weak var connectfacebookSelectionImage: UIImageView!
    @IBOutlet weak var connectThreadSelectionImage: UIImageView!
    @IBOutlet weak var imageCollectionView: UICollectionView!
    @IBOutlet weak var holdAndDragNoteLabel: UILabel!
    @IBOutlet weak var lblVerifyIdentity: UILabel!
    @IBOutlet weak var lblProfileComplete: UILabel!
    @IBOutlet weak var btnPreview: UIButton!
    @IBOutlet weak var btnBack: UIButton!
    @IBOutlet weak var vwIsVerification: UIView!
    @IBOutlet weak var heightVWVeification: NSLayoutConstraint!
    @IBOutlet weak var lblCountAboutMe: UILabel!
    @IBOutlet weak var otpTextFildView: OTPFieldView!
    @IBOutlet weak var vwOTPField: UIView!
    @IBOutlet weak var vwBtnVerify: UIView!
    @IBOutlet weak var prosonalInfoViewHeightConstraint: NSLayoutConstraint!
    
    var getVerifyButton: UIButton!
    var selectedRegionCode:String?
    let countryCodeLabel = UILabel()
    var flagImageView = UIImageView()
    var maxCharacters = 10 // Set max character limit
    var isFromNotificationVC: Bool = false
    //private var editProfileMoreAboutQuestionData:MoreAboutMeQuestionModel?
    private var aEditProfileViewModel = EditProfileViewModel()
    
    var aAttributesViewModel = AttributesViewModel()
    private var editProfileMoreAboutQuestionData:AttributesModel?
    
    private var editProfileQuestionData:[AttributesData] = []
    
    private var moreAboutProfileQuestionData:[AttributesData] = []
    
    private var moreAllInterestData:[AttributesData] = []
    private var moreAllSelectedInterestData:[AttributesData] = []
    
    private var imageSelectedIndex:Int?
    private var selectImageType:selectImageType?
    private var selectedAssetIdentifiers: [String] = []
    private var isSelectingMultipleImage:Bool? = false
    private var desposeBag:Set<AnyCancellable> = []
    var coverImageUrl:String?
    //var userProfileData:UserProfileData?
    var deleteImageID:Int?
    var updatedTextValue:String? = ""
    var callBackAction:(()->())?
    
    var userDetailInfo:UserDetailsData?
    var upLoadedImg: [UIImage] = []
    var arrSwapIndex: [Int] = []
    var isChanged_About_Me:Bool? = false
    var isPreviewClicked:Bool? = false
    var countAboutMe:Int = 0
    var isOTPEntered:Bool? = false
    var strOTP:String?

    static var storyboardName: StringConvertible {
        return StoryboardName.editProfile
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setUpBinding()
       // self.aAttributesViewModel.loadJSON()
        //self.setUserData()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.isPreviewClicked = false
        self.btnPreview.isUserInteractionEnabled = true
        self.btnBack.isUserInteractionEnabled = true
        self.setUI()
        self.interestCollectionView.reloadData()
        self.checkHideCustomButton(hide: true)
        self.prosonalInfoViewHeightConstraint.constant = 0
        self.filterListAlphabetically()
    }
    func setEditAboutYouData(){
        
        if self.editProfileMoreAboutQuestionData != nil && self.userDetailInfo != nil {
            
            
            if self.moreAboutProfileQuestionData.count > 0 {
                self.moreAboutProfileQuestionData.removeAll()
            }
            
            self.editProfileQuestionData = self.filterAttributesBasedOnUserInfo(attributes: self.editProfileMoreAboutQuestionData?.data ?? [], userInfo: self.userDetailInfo?.userInfo)
            
            for val in self.editProfileQuestionData {
                print("\(val)")
                self.moreAboutProfileQuestionData.append(val)
            }
            
            
            var moreQuestions = self.filterAttributesBasedOnUserInfo(attributes: self.editProfileMoreAboutQuestionData?.data ?? [], userInfo: self.userDetailInfo?.userInfo, forNilKeys: false)
            
            for val in moreQuestions {
                print("\(val)")
                self.moreAboutProfileQuestionData.append(val)
            }
            
            self.moreAllInterestData = self.filterIntrestInfo(attributes: self.editProfileMoreAboutQuestionData?.data ?? [], userInfo: self.userDetailInfo?.userInfo)
            
            self.moreAllSelectedInterestData = self.moreAllInterestData.map{ attOpt in
                let atOption = attOpt.aOptions?.filter{ $0.isSelected == true}
                var aOption = attOpt
                aOption.aOptions = atOption
                return aOption
            }
            
            print("This is Interests", self.moreAllInterestData)
            print("These are sel Interests", self.moreAllSelectedInterestData)
            
            
            self.setMoreAboutTableViewHeight()
            self.aboutMeTableView.reloadData()
            
            self.setInterestCollectionViewHeight()
            self.interestCollectionView.reloadData()
            
            self.lblProfileComplete.text = "\(self.userDetailInfo?.profile_complete ?? 0)% complete"
        }
            
    }
    
//    func filterListAlphabetically() {
//        let filledAnswers = moreAboutProfileQuestionData
//            .filter { data in
//                if let selectedOption = data.aOptions?.first(where: { $0.isSelected == true }) {
//                    return selectedOption.title != "Add"
//                }
//                return false
//            }
//            .sorted { ($0.alias ?? "").localizedCaseInsensitiveCompare($1.alias ?? "") == .orderedAscending }
//        let emptyAnswers = moreAboutProfileQuestionData
//            .filter { data in
//                if let selectedOption = data.aOptions?.first(where: { $0.isSelected == true }) {
//                    return selectedOption.title == "Add"
//                }
//                return true
//            }
//        moreAboutProfileQuestionData = filledAnswers + emptyAnswers
//    }
    
    func filterListAlphabetically() {
        let filledAnswers = moreAboutProfileQuestionData
            .filter { data in
                if let selectedOption = data.aOptions?.first(where: { $0.isSelected == true }) {
                    return selectedOption.title != "Add"
                }
                return false
            }
            .sorted { ($0.alias ?? "").localizedCaseInsensitiveCompare($1.alias ?? "") == .orderedAscending }
        
        let emptyAnswers = moreAboutProfileQuestionData
            .filter { data in
                if let selectedOption = data.aOptions?.first(where: { $0.isSelected == true }) {
                    return selectedOption.title == "Add"
                }
                return true
            }
        
        moreAboutProfileQuestionData = filledAnswers + emptyAnswers
        
        // 🔑 Reload table/collection so indexes match new order
        DispatchQueue.main.async {
          //  self.aboutMeTableView.reloadData() // or collectionView.reloadData()
        }
    }



    func setUI(){
        self.verifyYourselfView.addShadow(color: AppColor.AppBlack.withAlphaComponent(0.25), opacity: 1.0, offset: CGSize(width: 0, height: 1.0))
        self.moreAboutView.addShadow(color: AppColor.AppBlack.withAlphaComponent(0.2), opacity: 1.0, offset: CGSize(width: 0, height: 0.5))
        self.holdAndDragNoteLabel.setAttriibutText(text1: Constants.EditProfile.dragAndHold, text2: Constants.EditProfile.note,pattern: false, color: AppColor.AppBlack)
        self.registerCell()
        //self.aEditProfileViewModel.getProfileMoreAboutMeQuestion()
        self.aEditProfileViewModel.callCheckExistingData()
        
    }
    
    func extractNilKeys(from userInfo: UserDetailInfo?, forNilKeys:Bool = true) -> [String:Any] {
        guard let userInfo = userInfo else { return [:] }
        
        var nilKeys: [String:Any] = [:]
        
        let properties: [(String, Any?)] = [
            
            
            ("sexuality", userInfo.sexuality),
            ("height", userInfo.height),
            ("weight", userInfo.weight),
            ("eyecolor", userInfo.eyeColour),
            ("haircolor", userInfo.hairColour),
            ("living", userInfo.living),
            ("children", userInfo.children),
            ("smoking", userInfo.smoking),
            ("drinking", userInfo.drinking),
            ("motherTongue", userInfo.motherTongue),
            ("marital_status", userInfo.maritalStatus),
            ("relationship", userInfo.relationship),
            ("religion", userInfo.religion),
            ("education", userInfo.education),
            ("employedIn", userInfo.employedIn),
            ("interests", userInfo.interests)
        ]
        
        //("interest",userInfo.interests),
//        ("dob", userInfo.dob),
//        ("gender", userInfo.gender),
        
        for (key, value) in properties {
            if forNilKeys == true {
                if value == nil {
                    nilKeys.updateValue(value ?? "", forKey: key)
                }
            } else {
                if value != nil {
                    nilKeys.updateValue(value ?? "", forKey: key)
                }
            }
            
        }
        
        return nilKeys
    }
    
    func filterAttributesBasedOnUserInfo(attributes: [AttributesData], userInfo: UserDetailInfo?, forNilKeys:Bool = true) -> [AttributesData] {
        print("ATTRIBUTES :", attributes)
        let nilKeys = extractNilKeys(from: userInfo, forNilKeys: forNilKeys)
        
        var filteredAttributes = attributes.filter { attribute in
            if let alias = attribute.alias {
                return (nilKeys.index(forKey: alias) != nil)
            }
            return false
        }
        //contains(alias)
        
        if forNilKeys == false {
            
            filteredAttributes = filteredAttributes.map { attributes in
                var updatedAttributes = attributes
                for (key, value) in nilKeys {
                    if key == updatedAttributes.alias {
                        if var options = updatedAttributes.aOptions {
                            options = options.map { option in
                                var updatedOption = option
                                if updatedOption.id == value as? Int {
                                    updatedOption.isSelected = true
                                }
                                return updatedOption
                            }
                            updatedAttributes.aOptions = options
                        }
                    }
                }
                return updatedAttributes
            }
            
            print("new.........",filteredAttributes)
        }
        
        print("questions........",filteredAttributes)
        return filteredAttributes
    }
    
    func extractKeysIntrest(from userInfo: UserDetailInfo?) -> [String:[Int]] {
        guard let userInfo = userInfo else { return [:] }
        
        var nilKeys: [String:[Int]] = [:]
        
        let properties: [(String, Any?)] = [("interest",userInfo.interests)]
        
        //("interest",userInfo.interests),
//        ("dob", userInfo.dob),
//        ("gender", userInfo.gender),
        
        for (key, value) in properties {
            if value != nil {
                nilKeys.updateValue(value as! [Int], forKey: key)
            } else {
                nilKeys.updateValue(value as? [Int] ?? [], forKey: key)
            }
        }
        
        return nilKeys
    }
    
    func filterIntrestInfo(attributes: [AttributesData], userInfo: UserDetailInfo?) -> [AttributesData] {
        print("ATTRIBUTES INTRESET :", attributes)
        
        let nilKeys = extractKeysIntrest(from: userInfo)
        
        var filteredAttributes = attributes.filter { attribute in
            if let alias = attribute.alias {
                return (nilKeys.index(forKey: alias) != nil)
            }
            return false
        }
        
        filteredAttributes = filteredAttributes.map { attributes in
            var updatedAttributes = attributes
            for (key, value) in nilKeys {
                if key == updatedAttributes.alias {
                    for val in value {
                        if var options = updatedAttributes.aOptions {
                            options = options.map { option in
                                var updatedOption = option
                                if updatedOption.id == val {
                                    updatedOption.isSelected = true
                                }
                                return updatedOption
                            }
                            updatedAttributes.aOptions = options
                        }
                        
                    }

                }
            }
            print("MY INTERESET ARRAY :", updatedAttributes)
            return updatedAttributes
        }
        print("MY FOLTERET INTERESET :", filteredAttributes)
        return filteredAttributes
    }

    func setUserData(){
        self.setTextFieldUI()
        self.firstNameTextField.text = self.userDetailInfo?.userInfo?.fullname
        //self.lastNameTextField.text = self.userProfileData?.lastName
        if self.userDetailInfo?.email != nil {
            self.emaiIDTextField.text = self.userDetailInfo?.email
        }
        if self.userDetailInfo?.phone != nil {
            self.emaiIDTextField.text = "+\(self.userDetailInfo?.phoneCode ?? "") \(self.userDetailInfo?.phone ?? "")"
        }
        
        if self.userDetailInfo?.email != nil && self.userDetailInfo?.phone != nil {
            self.emaiIDTextField.text = self.userDetailInfo?.email
            self.verifyMailTextField.text = "+\(self.userDetailInfo?.phoneCode ?? "") \(self.userDetailInfo?.phone ?? "")"
        }
        
        self.displayNameTextField.text = self.userDetailInfo?.userInfo?.displayName?.trimmText()
        
        self.cityPlaceTextField.text = self.userDetailInfo?.userInfo?.location
        
        if self.updatedTextValue != "" {
            self.aboutTextView.text = updatedTextValue
        } else {
            self.aboutTextView.text = self.userDetailInfo?.userInfo?.aboutMe
        }
        self.countAboutMe = self.userDetailInfo?.userInfo?.aboutMe?.count ?? 0
        self.lblCountAboutMe.text = "\(self.countAboutMe)/150"
        
        self.aboutTextView.textColor = AppColor.Punch
        self.coverImage.contentMode = .scaleAspectFill
        //self.aEditProfileViewModel.arrayInterest = self.userProfileData?.interests
        //self.aEditProfileViewModel.arrayMoreAboutMe = self.userProfileData?.detail
        //URL(string: self.coverImageUrl ?? "")
        if self.userDetailInfo?.userInfo?.banner != nil {
            
            self.coverImageUrl = "\(ApiName.imgBaseURL)" + "\((self.userDetailInfo?.userInfo?.banner) ?? "")"
            print("img url .........",self.coverImageUrl ?? "")
            if let imageUrl = URL(string: self.coverImageUrl ?? "") {
                DispatchQueue.main.async {
                    self.addCoverPhotoButton.isHidden = true
                    self.editCoverView.isHidden = false
                    self.coverImage.loadImage(with: imageUrl)
                }
            }
            
        }
        
        lblVerifyIdentity.text = "Verify your identity, \(self.userDetailInfo?.userInfo?.displayName ?? "")"
        self.filterListAlphabetically()
        self.aboutMeTableView.reloadData()
        self.getUIImageFromImageURL()
        //self.setUI()
        
        if self.userDetailInfo?.userInfo?.gestureIsVerified ?? false == true {
            self.vwIsVerification.isHidden = true
            self.heightVWVeification.constant = -149
            self.view.layoutIfNeeded()
        } else {
            self.vwIsVerification.isHidden = false
            self.heightVWVeification.constant = 20
            self.view.layoutIfNeeded()
        }
        
    }

    func getUIImageFromImageURL(){
        var userImg:[UserImage] = []
        var avatarImg:[UserImage] = []
        avatarImg = self.userDetailInfo?.user_images?.filter{ $0.isPrimary == true && $0.filefor == "gallery"} ?? []
        userImg  = self.userDetailInfo?.user_images?.filter{ $0.isPrimary == false && $0.filefor == "gallery"} ?? []
        for (index,item) in (avatarImg).enumerated(){
            guard index < 1 else {return}
            if index == 0 && avatarImg.count > 0 {
                
                let img = ApiName.imgBaseURL+""+(avatarImg[0].filename ?? "")
                if let imageUrl = URL(string: img) {
                    self.downloadImage(from: imageUrl) { image in
                        guard image != nil else {return}
                        let data = EditProfileImageModel(image:image ,id: avatarImg[0].id, status: avatarImg[0].status,isPrimary: avatarImg[0].isPrimary)
                        self.aEditProfileViewModel.images[index] = data
                        self.imageCollectionView.reloadData()
                    }
                }
            }
        }
        
        for (index,item) in (userImg).enumerated(){
            guard index < 5 else {return}

                let img = ApiName.imgBaseURL+""+(item.filename ?? "")
                if let imageUrl = URL(string: img) {
                    self.downloadImage(from: imageUrl) { image in
                        guard image != nil else {return}
                        let data = EditProfileImageModel(image:image ,id: item.id,status: item.status,isPrimary: item.isPrimary)
                        self.aEditProfileViewModel.images[index+1] = data
                        self.imageCollectionView.reloadData()
                    }
                }
            
            
        }
        
    }

    func setTextFieldUI(){
        self.firstNameTextField.delegate = self
        self.lastNameTextField.delegate = self
        self.emaiIDTextField.delegate = self
        self.cityPlaceTextField.delegate = self
        self.aboutTextView.delegate = self
        self.displayNameTextField.delegate = self
        self.verifyMailTextField.delegate = self

        self.firstNameTextField.label.text = "Full Name"
        self.lastNameTextField.label.text = "Last Name"
        
        if self.userDetailInfo?.phone == nil {
            
            maxCharacters = 10
            
            self.verifyMailTextField.label.text = "Phone"
            self.emaiIDTextField.label.text = "Email"
            
            // Create the right-side button
            let button = UIButton(type: .custom)
            //button.setImage(UIImage(systemName: "eye.fill"), for: .normal) // SF Symbol as example
            button.setTitleColor(AppColor.Punch, for: .normal)
            button.setTitle("Get Verify", for: .normal)
            button.backgroundColor = AppColor.verifyPink
            button.frame = CGRect(x: 0, y: 0, width: 76, height: 30)
            button.titleLabel?.font = UIFont(name: "Fredoka-Regular", size: 12)
            button.layer.cornerRadius = 5 // Adjust as needed
            button.layer.masksToBounds = true
            
            button.addTarget(self, action: #selector(getVerified), for: .touchUpInside)
            self.getVerifyButton = button
            self.getVerifyButton.isEnabled = false
            self.getVerifyButton.alpha = 0.5
            
            // Set button as trailing view
            self.verifyMailTextField.trailingView = button
            self.verifyMailTextField.trailingViewMode = .always
            self.verifyMailTextField.trailingView?.contentMode = .scaleAspectFit
            self.verifyMailTextField.trailingView?.contentMode = .center
            
            
            self.verifyMailTextField.keyboardType = .phonePad

            // Create the leading button
            let leadingButton = UIButton(type: .custom)
            leadingButton.frame = CGRect(x: 0, y: 0, width: 96, height: 18) // Set fixed size
            leadingButton.backgroundColor = .clear // Keep it transparent
            leadingButton.contentVerticalAlignment = .center
            
            // Country flag image
            flagImageView = UIImageView(image: UIImage(named: "indiaFlag")) // Replace with your image
            flagImageView.contentMode = .scaleAspectFit
            flagImageView.frame = CGRect(x: 0, y: 0, width: 25, height: 18)
            
            // Country code label
            countryCodeLabel.text = "+91" // Example country code
            countryCodeLabel.font = UIFont(name: "Fredoka-Regular", size: 16)
            countryCodeLabel.textColor = .black
            countryCodeLabel.frame = CGRect(x: 30, y: 0, width: 40, height: 18)
            
            // Down arrow image
            let arrowImageView = UIImageView(image: UIImage(named: "dropDown"))
            arrowImageView.contentMode = .scaleAspectFit
            arrowImageView.frame = CGRect(x: 65, y: 0, width: 16, height: 18)
            
            // Add views to button
            leadingButton.addSubview(flagImageView)
            leadingButton.addSubview(countryCodeLabel)
            leadingButton.addSubview(arrowImageView)

            // Add action to button
            leadingButton.addTarget(self, action: #selector(selectCountry), for: .touchUpInside)
            
            
            if let data = CountryDataManager.shared.filterCountryData {
                self.setCountryCodeUI(data)
                self.selectedRegionCode = CountryDataManager.shared.regionCode
            }

            // Set button as leading view
            self.verifyMailTextField.leadingView = leadingButton
            self.verifyMailTextField.leadingViewMode = .always
            self.verifyMailTextField.leadingView?.contentMode = .scaleAspectFit
            self.verifyMailTextField.leadingView?.contentMode = .center
            
            self.verifyMailTextField.layoutIfNeeded()
            
            self.verifyMailTextField.setNormalLabelColor(AppColor.Bombay, for: .normal)
            self.verifyMailTextField.setTextColor(AppColor.Punch, for: .normal)
            self.verifyMailTextField.setTextColor(AppColor.Punch, for: .editing)
            self.verifyMailTextField.setFloatingLabelColor(AppColor.Punch, for: .editing)
            self.verifyMailTextField.setFloatingLabelColor(AppColor.Bombay, for: .normal)
            self.verifyMailTextField.setOutlineColor(AppColor.Punch, for: .editing)
            self.verifyMailTextField.setOutlineColor(AppColor.Iron, for: .normal)
            self.verifyMailTextField.containerRadius = 10
            
            self.setupOtpView()
            
        } else if self.userDetailInfo?.email == nil {
            
            maxCharacters = 150
            
            self.emaiIDTextField.label.text = "Phone"
            self.verifyMailTextField.label.text = "Email"
            
            // Create the right-side button
            let button = UIButton(type: .custom)
            //button.setImage(UIImage(systemName: "eye.fill"), for: .normal) // SF Symbol as example
            button.setTitleColor(AppColor.Punch, for: .normal)
            button.setTitle("Get Verify", for: .normal)
            button.backgroundColor = AppColor.verifyPink
            button.frame = CGRect(x: 0, y: 0, width: 76, height: 30)
            button.titleLabel?.font = UIFont(name: "Fredoka-Regular", size: 12)
            button.layer.cornerRadius = 5 // Adjust as needed
            button.layer.masksToBounds = true
            button.addTarget(self, action: #selector(getVerified), for: .touchUpInside)
            self.getVerifyButton = button
            self.getVerifyButton.isEnabled = false
            self.getVerifyButton.alpha = 0.5
           
            
            // Set button as trailing view
            self.verifyMailTextField.trailingView = button
            self.verifyMailTextField.trailingViewMode = .always
            self.verifyMailTextField.trailingView?.contentMode = .scaleAspectFit
            self.verifyMailTextField.trailingView?.contentMode = .center
            
            self.verifyMailTextField.layoutIfNeeded()
            
            self.verifyMailTextField.setNormalLabelColor(AppColor.Bombay, for: .normal)
            self.verifyMailTextField.setTextColor(AppColor.Punch, for: .normal)
            self.verifyMailTextField.setTextColor(AppColor.Punch, for: .editing)
            self.verifyMailTextField.setFloatingLabelColor(AppColor.Punch, for: .editing)
            self.verifyMailTextField.setFloatingLabelColor(AppColor.Bombay, for: .normal)
            self.verifyMailTextField.setOutlineColor(AppColor.Punch, for: .editing)
            self.verifyMailTextField.setOutlineColor(AppColor.Iron, for: .normal)
            self.verifyMailTextField.containerRadius = 10
            
            self.setupOtpView()
            
        } else if self.userDetailInfo?.phone != nil && self.userDetailInfo?.email != nil {
            
            self.emaiIDTextField.label.text = "Email"
            self.verifyMailTextField.label.text = "Phone"
        }
    
        self.cityPlaceTextField.label.text = "City, State"
        self.displayNameTextField.label.text = "Display Name"

        self.aboutTextView.text = "A little bit about you..."
        self.aboutTextView.textColor = AppColor.Bombay
        
        if self.userDetailInfo?.phone == nil || self.userDetailInfo?.email == nil {
            
            [firstNameTextField,lastNameTextField,emaiIDTextField,cityPlaceTextField,displayNameTextField].forEach { textField in
                textField?.setNormalLabelColor(AppColor.Bombay, for: .normal)
                textField?.setTextColor(AppColor.Punch, for: .normal)
                textField?.setTextColor(AppColor.Punch, for: .editing)
                textField?.setFloatingLabelColor(AppColor.Punch, for: .editing)
                textField?.setFloatingLabelColor(AppColor.Bombay, for: .normal)
                textField?.setOutlineColor(AppColor.Punch, for: .editing)
                textField?.setOutlineColor(AppColor.Iron, for: .normal)
                textField?.containerRadius = 10
                textField?.isUserInteractionEnabled = false
            }
        } else {
            
            [firstNameTextField,lastNameTextField,emaiIDTextField,cityPlaceTextField,displayNameTextField, verifyMailTextField].forEach { textField in
                textField?.setNormalLabelColor(AppColor.Bombay, for: .normal)
                textField?.setTextColor(AppColor.Punch, for: .normal)
                textField?.setTextColor(AppColor.Punch, for: .editing)
                textField?.setFloatingLabelColor(AppColor.Punch, for: .editing)
                textField?.setFloatingLabelColor(AppColor.Bombay, for: .normal)
                textField?.setOutlineColor(AppColor.Punch, for: .editing)
                textField?.setOutlineColor(AppColor.Iron, for: .normal)
                textField?.containerRadius = 10
                textField?.isUserInteractionEnabled = false
            }
        }



        IQKeyboardManager.shared.enableAutoToolbar = true
        IQKeyboardManager.shared.resignOnTouchOutside = true
        
    }
    
    func setCountryCodeUI(_ data:CountryListModel?){
        self.countryCodeLabel.text = data?.dial_code
        self.flagImageView.image = UIImage(named:data?.code ?? "", in: Bundle.main, with: nil)
    }
    
    @objc func selectCountry() {
        // Open country picker or perform desired action
        
        let aCountryListViewController = CountryListViewController.instantiateFromStoryboard()
        aCountryListViewController.regionCode = self.selectedRegionCode
        aCountryListViewController.selectionCallBack = { [weak self] selectedData in
            self?.selectedRegionCode = selectedData.code
            self?.setCountryCodeUI(selectedData)
        }
        aCountryListViewController.modalPresentationStyle = .overCurrentContext
        self.navigationController?.present(aCountryListViewController, animated: true, completion: nil)
    }
    
    @objc func getVerified(sender: UIButton) {
        getVerifyButton.showLoading()
        if self.userDetailInfo?.email == nil {
            
            let emailText = verifyMailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            if emailText?.isValidEmail() == true {
                self.aEditProfileViewModel.verifyEmailAPI(email: emailText ?? "")
            } else {
                self.getVerifyButton.hideLoading()
                self.showNewAlertPopUp(Title: "Error", Msg: "Please enter valid email", isSuccess: false, CompletionHandler: {(success) -> Void in
                    
                })
            }
            
        } else {
            let phoneText = verifyMailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if phoneText?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0 == 10 {
                let phoneNo = "\(self.countryCodeLabel.text ?? "")\(phoneText ?? "")"
                print("Phone no .............",phoneNo)
                sendVerificationCode(to: phoneNo)
            } else {
                self.getVerifyButton.hideLoading()
                self.showNewAlertPopUp(Title: "Error", Msg: "Please enter valid Phone No", isSuccess: false, CompletionHandler: {(success) -> Void in
                    
                })
            }
            
        }
        
        
    }
    
    @IBAction func getVerifiedOTP(sender: UIButton) {
        self.verifyButton.showLoading()
        if self.userDetailInfo?.email == nil {
            
            let emailText = verifyMailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if self.isOTPEntered == true {
                self.aEditProfileViewModel.verifyEmailOTPAPI(email: emailText, OTP: strOTP ?? "", completion: { success in
                    self.verifyButton.hideLoading()
                    if success {
                        self.aEditProfileViewModel.callCheckExistingData()
                        print("OTP verified successfully")
                    } else {
                        print("OTP verification failed")
                    }
                }
               )
            }
            
        } else {
            
            self.verifyCode(verificationID: UserDataManager.shared.OTPAuth ?? "", verificationCode: strOTP ?? "")
        }
    }

    func registerCell(){
        //self.interestCollectionView.collectionViewLayout = createInterestCollectionLayout()
        self.interestCollectionView.register(UINib(nibName: UserInterestCollectionViewCell.identifier, bundle: nil), forCellWithReuseIdentifier: UserInterestCollectionViewCell.identifier)
        self.interestCollectionView.delegate = self
        self.interestCollectionView.dataSource = self

        self.interestCollectionView.register(UINib(nibName: ImageCollectionViewCell.identifier, bundle: nil), forCellWithReuseIdentifier: ImageCollectionViewCell.identifier)
        self.interestCollectionView.delegate = self
        self.interestCollectionView.dataSource = self
        self.interestCollectionView.reloadData()

        self.setupCollectionViewLayout()

        self.aboutMeTableView.register(UINib(nibName: MoreAboutMeTableViewCell.identifier, bundle: nil), forCellReuseIdentifier: MoreAboutMeTableViewCell.identifier)
        self.aboutMeTableView.delegate = self
        self.aboutMeTableView.dataSource = self

        self.setInterestCollectionViewHeight()
        self.setMoreAboutTableViewHeight()
    }

    func setUpBinding(){
        
        self.aEditProfileViewModel.$aUploadProfilePhotoResponseModel.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                self.aActivityIndicator.hide()
                if let imageUrl = URL(string: model?.data?.image_url ?? "") {
                    DispatchQueue.main.async {
                      //  self.showImageAlertPopUp(TitleMsg: "Picture uploaded successfully", TitleBtn: "Continue")
                        self.addSelectedImage(image: self.upLoadedImg, model: model!)
                        
                    }
                }
            }
        }.store(in: &desposeBag)
        
        self.aEditProfileViewModel.$aUploadCoverPhotoResponseModel.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                if let imageUrl = URL(string: model?.data?.image_url ?? "") {
                    DispatchQueue.main.async {
                        self.addCoverPhotoButton.isHidden = true
                        self.editCoverView.isHidden = false
                        self.aActivityIndicator.hide()
                       // self.showImageAlertPopUp(TitleMsg: "Picture uploaded successfully", TitleBtn: "Continue")
                        self.downloadImage(imageType: self.coverImage, imageUrl: imageUrl, message: model?.message)
                    }
                }
            }
        }.store(in: &desposeBag)
        
        self.aEditProfileViewModel.$aUserDetailDataModel.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                self.userDetailInfo = model?.data
                print("api.......",self.userDetailInfo!)
                self.setUserData()
                self.aAttributesViewModel.loadJSON()
                
                if self.isPreviewClicked == true {
                    let aOtherUserProfileViewController = OtherUserProfileViewController.instantiateFromStoryboard()
                    aOtherUserProfileViewController.isMyProfile = true
                    aOtherUserProfileViewController.userDetails = self.userDetailInfo
                    self.navigationController?.pushViewController(aOtherUserProfileViewController, animated: true)
                }
            }
        }.store(in: &desposeBag)
        
        self.aAttributesViewModel.$aAttributesModel.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                print("cur.......",self.userDetailInfo!)
                self.editProfileMoreAboutQuestionData = model
                self.setEditAboutYouData()
            }
            self.interestCollectionView.reloadData()
        }.store(in: &desposeBag)

//        self.aEditProfileViewModel.$aMoreAboutMeQuestionModel.receive(on: DispatchQueue.main).sink { model in
//            if model != nil {
//                self.editProfileMoreAboutQuestionData = model
//            }
//        }.store(in: &desposeBag)

        self.aEditProfileViewModel.$aDeleteUserImageResponseModel.receive(on:DispatchQueue.main).sink { model in
            if model != nil {
                self.deleteSelectedImage()
            }
        }.store(in: &desposeBag)

        self.aEditProfileViewModel.$errorMessage.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self = self else {return}
            if error != nil {
                self.aActivityIndicator.hide()
                if error == Constants.ImageErrorTypes.errorUserImage || error == Constants.ImageErrorTypes.errorBannerImage {
                    if self.aEditProfileViewModel.showErrorMsg != "" {
                        self.showImageAlertPopUp(TitleMsg: "Nude explicit content is not allowed.", TitleBtn: "Discard")
                    } else {
                        self.showImageAlertPopUp(TitleMsg: "Picture upload failed", TitleBtn: "Discard")
                    }
                } else {
                    self.showNewAlertPopUp(Title: "Error", Msg: error ?? "", isSuccess: false, CompletionHandler: {(success) -> Void in
                        
                    })
                }
                
                
            }
        }.store(in: &desposeBag)
        
        self.aEditProfileViewModel.$aPrimaryImageResponseModel.receive(on:DispatchQueue.main).sink { model in
            if model != nil {
                
                self.swapValues(in: &self.aEditProfileViewModel.images, at: self.arrSwapIndex[0], and: self.arrSwapIndex[1])
                self.imageCollectionView.reloadData()
                
            }
        }.store(in: &desposeBag)
        
        self.aEditProfileViewModel.$errorPrimaryImage.receive(on:DispatchQueue.main).sink { error in
            if error != nil {
                
                self.swapValues(in: &self.aEditProfileViewModel.images, at: self.arrSwapIndex[1], and: self.arrSwapIndex[0])
                self.imageCollectionView.reloadData()
                
            }
        }.store(in: &desposeBag)
        
        self.aEditProfileViewModel.$aUpdateAboutMe.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard let action = self.callBackAction else {return}
                    action()
                    self.view.isUserInteractionEnabled = true
                    self.navigationController?.popViewController(animated: true)
                }
            }
        }.store(in: &desposeBag)
        
        self.aEditProfileViewModel.$errorAboutMe.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard let action = self.callBackAction else {return}
                    action()
                    self.view.isUserInteractionEnabled = true
                    self.navigationController?.popViewController(animated: true)
                }
            }
        }.store(in: &desposeBag)
        
        self.aEditProfileViewModel.$aVerifyEmail.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                self.vwOTPField.isHidden = false
                self.vwBtnVerify.isHidden = false
                self.otpTextFildView.initializeUI()
            }
        }.store(in: &desposeBag)
        
        self.aEditProfileViewModel.$errorVerifyEmail.receive(on: DispatchQueue.main).sink { error in
            if error != nil {
                
                self.showNewAlertPopUp(Title: "Error", Msg: error ?? "", isSuccess: false, CompletionHandler: {(success) -> Void in
                    
                })

            }
        }.store(in: &desposeBag)
        
        self.aEditProfileViewModel.$aVerifyEmailOTP.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                self.vwOTPField.isHidden = true
                self.vwBtnVerify.isHidden = true
                
                self.showNewAlertPopUp(Title: "Success", Msg: "Email Updated Successfully.", isSuccess: true, CompletionHandler: {(success) -> Void in
                    
                })
            }
        }.store(in: &desposeBag)
        
        self.aEditProfileViewModel.$errorVerifyEmailOTP.receive(on: DispatchQueue.main).sink { error in
            if error != nil {
                self.showNewAlertPopUp(Title: "Error", Msg: error ?? "", isSuccess: false, CompletionHandler: {(success) -> Void in
                    
                })

            }
        }.store(in: &desposeBag)
        
        self.aEditProfileViewModel.$aUpdatePhoneNo.receive(on: DispatchQueue.main).sink { model in
            if model != nil {
                if model?.status == true {
                    self.vwOTPField.isHidden = true
                    self.vwBtnVerify.isHidden = true
                    
                    self.showNewAlertPopUp(Title: "Success", Msg: "Phone Updated Successfully.", isSuccess: true, CompletionHandler: {(success) -> Void in
                        
                    })
                } else {
                    self.showNewAlertPopUp(Title: "Alert", Msg: model?.message ?? "", isSuccess: false, CompletionHandler: {(success) -> Void in
                    })
                }
            }
        }.store(in: &desposeBag)
        
        self.aEditProfileViewModel.$errorPhoneUpdate.receive(on: DispatchQueue.main).sink { error in
            if error != nil {
                self.showNewAlertPopUp(Title: "Error", Msg: error ?? "", isSuccess: false, CompletionHandler: {(success) -> Void in
                    
                })

            }
        }.store(in: &desposeBag)
    }
    
    private func setupOtpView() {
        self.otpTextFildView.fieldsCount = 6
        self.otpTextFildView.fieldBorderWidth = 1
        self.otpTextFildView.defaultBorderColor = AppColor.CatskillWhite
        self.otpTextFildView.filledBorderColor = AppColor.Punch
        self.otpTextFildView.cursorColor = AppColor.Punch
        self.otpTextFildView.displayType = .square
        self.otpTextFildView.fieldSize = 48
        self.otpTextFildView.fieldFont = UIFont.fredoka(.regular,size: 24)
        self.otpTextFildView.separatorSpace = 12
        self.otpTextFildView.textFiledCornerRadius = 12
        self.otpTextFildView.shouldAllowIntermediateEditing = false
        self.otpTextFildView.delegate = self
        //self.otpTextFildView.initializeUI()
    }

    func downloadImage(imageType:UIImageView,imageUrl:URL?,message:String?){
        self.aActivityIndicator.show()
        imageType.loadImage(with: imageUrl) { [weak self] _ in
            self?.aActivityIndicator.hide()
        }
    }

    func downloadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        ImageLoader.shared.load(url, completion: completion)
    }

    func createInterestCollectionLayout() -> UICollectionViewLayout {
        let otherItemSize1 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalHeight(1.0))
        let otherItem1 = NSCollectionLayoutItem(layoutSize: otherItemSize1)
        otherItem1.contentInsets = NSDirectionalEdgeInsets(top:4, leading: 4.5, bottom:8, trailing: 7)

        let otherItemSize2 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalHeight(1.0))
        let otherItem2 = NSCollectionLayoutItem(layoutSize: otherItemSize2)
        otherItem2.contentInsets = NSDirectionalEdgeInsets(top:4, leading:7, bottom:8, trailing: 7)

        let otherItemSize3 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalHeight(1.0))
        let otherItem3 = NSCollectionLayoutItem(layoutSize: otherItemSize3)
        otherItem3.contentInsets = NSDirectionalEdgeInsets(top:4, leading:4.5, bottom: 8, trailing:7)

        let itemCount = Double((self.aEditProfileViewModel.arrayInterest?.count ?? 0) + 1)
        let numberOfRow = ceil(Double(itemCount/4))
        let fraction = 1.0/numberOfRow

        let mainGroupSize1 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(fraction))
        let mainGroup1 = NSCollectionLayoutGroup.horizontal(layoutSize: mainGroupSize1, subitems: [otherItem1,otherItem2,otherItem2, otherItem3])
        let section = NSCollectionLayoutSection(group: mainGroup1)
        return UICollectionViewCompositionalLayout(section: section)
    }

    func setInterestCollectionViewHeight(){
        let availableWidth = screen.width - 94
        let itemInEachRow = 4.0
        let itemWidth = availableWidth/itemInEachRow
//        var itemCount = 0.0
//        itemCount = Double((self.moreAllSelectedInterestData[0].aOptions?.count ?? 0) + 1)
//        if itemCount > 0 {
//            itemCount = Double((self.moreAllSelectedInterestData[0].aOptions?.count ?? 0) + 1)
//        }
        let itemCount = Double((moreAllSelectedInterestData.first?.aOptions?.count ?? 0) + 1)
        let numberOfRow = ceil(Double(itemCount/itemInEachRow))
        self.interestViewHeight.constant = ((numberOfRow * itemWidth * 0.83) + ((numberOfRow) * 12) + (numberOfRow * 10))
        
        //self.aEditProfileViewModel.arrayInterest?.count
    }

    func setMoreAboutTableViewHeight(){
//        let count = self.aEditProfileViewModel.arrayMoreAboutMe?.count ?? 0
//        self.moreAboutMeViewHeight.constant = CGFloat(count * 42)
        
        let count = self.moreAboutProfileQuestionData.count
        self.moreAboutMeViewHeight.constant = CGFloat(count * 42)
    }

    private func setupCollectionViewLayout() {
        self.imageCollectionView.collectionViewLayout = createAddImageCollectionLayout()
        self.imageCollectionView.register(UINib(nibName: ImageCollectionViewCell.identifier, bundle: nil), forCellWithReuseIdentifier: ImageCollectionViewCell.identifier)
        self.imageCollectionView.delegate = self
        self.imageCollectionView.dataSource = self
        let gesture = UILongPressGestureRecognizer(target:self , action:#selector(handLongPressGestrue(_:)))
        self.imageCollectionView.addGestureRecognizer(gesture)
        self.imageCollectionView.reloadData()
    }

    func createAddImageCollectionLayout() -> UICollectionViewLayout {
        let firstItemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.7), heightDimension: .fractionalHeight(1.0))
        let firstItem = NSCollectionLayoutItem(layoutSize: firstItemSize)
        firstItem.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 7.5, trailing: 15)

        let otherItemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.5))
        let otherItem = NSCollectionLayoutItem(layoutSize: otherItemSize)
        otherItem.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 7.5, trailing: 0)

        let other1ItemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.5))
        let other1Item = NSCollectionLayoutItem(layoutSize: other1ItemSize)
        other1Item.contentInsets = NSDirectionalEdgeInsets(top: 2.5, leading: 0, bottom:7.5, trailing: 0)

        let otherGroupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.3), heightDimension: .fractionalHeight(1.0))
        let otherGroup = NSCollectionLayoutGroup.vertical(layoutSize: otherGroupSize, subitems: [otherItem,other1Item])


        let otherItemSize1 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1.0))
        let otherItem1 = NSCollectionLayoutItem(layoutSize: otherItemSize1)
        otherItem1.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 15)

        let otherItemSize2 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1.0))
        let otherItem2 = NSCollectionLayoutItem(layoutSize: otherItemSize2)
        otherItem2.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 15)

        let otherItemSize3 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.3), heightDimension: .fractionalHeight(1.0))
        let otherItem3 = NSCollectionLayoutItem(layoutSize: otherItemSize3)
        otherItem3.contentInsets = NSDirectionalEdgeInsets(top: 5, leading:0, bottom: 5, trailing:0)

        let otherGroupSize12 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.7), heightDimension: .fractionalHeight(1))
        let otherGroup12 = NSCollectionLayoutGroup.horizontal(layoutSize: otherGroupSize12, subitems: [otherItem1,otherItem2])

        let otherGroupSize3 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.33))
        let otherGroup3 = NSCollectionLayoutGroup.horizontal(layoutSize: otherGroupSize3, subitems: [otherGroup12,otherItem3])


        let mainGroupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.67))
        let mainGroup = NSCollectionLayoutGroup.horizontal(layoutSize: mainGroupSize, subitems: [firstItem, otherGroup])

        let mainGroupSize1 = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
        let mainGroup1 = NSCollectionLayoutGroup.vertical(layoutSize: mainGroupSize1, subitems: [mainGroup, otherGroup3])

        let section = NSCollectionLayoutSection(group: mainGroup1)

        return UICollectionViewCompositionalLayout(section: section)
    }

    @IBAction func backButtonTapped(_ sender: UIButton) {
        
        if isFromNotificationVC {
            self.navigationController?.popToRootViewController(animated: true)
        } else {
            self.view.isUserInteractionEnabled = false
            self.btnBack.isUserInteractionEnabled = false
            
            if self.isChanged_About_Me == true {
                let param = ["about_me":self.aboutTextView.text]
                self.aEditProfileViewModel.callSaveUserDetailsAPI(filteredData: param as [String : Any])
            } else {
                guard let action = self.callBackAction else {return}
                action()
                self.view.isUserInteractionEnabled = true
                self.navigationController?.popViewController(animated: true)
            }
        }
    }

    @IBAction func addCoverPhotoButtonTapped(_ sender: UIButton) {
        self.selectImageType = .addCoverImage
        self.openImageSelectionMethodPopUp()
    }

    @IBAction func editCoverButtonTapped(_ sender: UIButton) {
        self.selectImageType = .addCoverImage
        self.openImageSelectionMethodPopUp()
    }

    @IBAction func verifyYourself(_ sender: UIButton) {
        
        let aGestureVerificationViewController = GestureVerificationViewController.instantiateFromStoryboard()
        self.navigationController?.pushViewController(aGestureVerificationViewController, animated: true)
        
    }
    
    @IBAction func previewButtonTapped(_ sender: UIButton) {
        self.btnPreview.isUserInteractionEnabled = false
        self.isPreviewClicked = true
        self.aEditProfileViewModel.callCheckExistingData()
    }

    @IBAction func connectInstagramButtonTapped(_ sender: UIButton) {
        self.connectfacebookSelectionImage.isHidden = true
        self.connectInstaSelectionImage.isHidden = false
        self.connectThreadSelectionImage.isHidden = true
    }

    @IBAction func connectFaceBookButtonTapped(_ sender: UIButton) {
        self.connectfacebookSelectionImage.isHidden = false
        self.connectInstaSelectionImage.isHidden = true
        self.connectThreadSelectionImage.isHidden = true
    }

    @IBAction func connectThreadButtonTapped(_ sender: UIButton) {
        self.connectfacebookSelectionImage.isHidden = true
        self.connectInstaSelectionImage.isHidden = true
        self.connectThreadSelectionImage.isHidden = false
    }

    func openImageSelectionMethodPopUp(){
        
        if self.imageSelectedIndex == 0 {
//            self.showNewAlertPopUp(Title: "Message", Msg: "You can only drag and change the image, as it's primary image section", isSuccess: false, CompletionHandler: {(success) -> Void in
//        
//            })
            
            let aImageSelectionMethodVC:ImageSelectionMethodVC = ImageSelectionMethodVC.instantiateFromStoryboard()
            aImageSelectionMethodVC.fromEditProfileScreen = true
            aImageSelectionMethodVC.selectImageType = self.selectImageType

            aImageSelectionMethodVC.isContainImage = self.aEditProfileViewModel.images[self.imageSelectedIndex ?? 0] != nil
            if self.aEditProfileViewModel.images[self.imageSelectedIndex ?? 0] != nil && self.selectImageType == .addSelfImage {
                
                aImageSelectionMethodVC.isShowImage = true
                aImageSelectionMethodVC.isShowAvatarImage = true
                aImageSelectionMethodVC.strURLImg = self.aEditProfileViewModel.images[self.imageSelectedIndex ?? 0]?.image
                
            } else if self.selectImageType == .addCoverImage && self.addCoverPhotoButton.isHidden == true {
                
                aImageSelectionMethodVC.isShowImage = true
                aImageSelectionMethodVC.strURLImg = self.coverImage.image
            }
            
            aImageSelectionMethodVC.modalPresentationStyle = .overCurrentContext
            self.navigationController?.present(aImageSelectionMethodVC, animated: true, completion: nil)

            
            
            
        } else {
            let aImageSelectionMethodVC:ImageSelectionMethodVC = ImageSelectionMethodVC.instantiateFromStoryboard()
            aImageSelectionMethodVC.fromEditProfileScreen = true
            aImageSelectionMethodVC.selectImageType = self.selectImageType

            aImageSelectionMethodVC.isContainImage = self.aEditProfileViewModel.images[self.imageSelectedIndex ?? 0] != nil
            if self.aEditProfileViewModel.images[self.imageSelectedIndex ?? 0] != nil && self.selectImageType == .addSelfImage {
                
                aImageSelectionMethodVC.isShowImage = true
                aImageSelectionMethodVC.strURLImg = self.aEditProfileViewModel.images[self.imageSelectedIndex ?? 0]?.image
                
            } else if self.selectImageType == .addCoverImage && self.addCoverPhotoButton.isHidden == true {
                
                aImageSelectionMethodVC.isShowImage = true
                aImageSelectionMethodVC.strURLImg = self.coverImage.image
            }
            
            aImageSelectionMethodVC.callBack = { [weak self] data in
                if data {
                    self?.checkCameraAuthorization()
                }else{
                    self?.requestPhotoLibraryAccess()
                }
            }
            aImageSelectionMethodVC.deletePictureCallBack = { [weak self] data in
                if let id = self?.deleteImageID {
                    self?.aEditProfileViewModel.deleteImageAPI(id:id)
                }
                
            }
            aImageSelectionMethodVC.modalPresentationStyle = .overCurrentContext
            self.navigationController?.present(aImageSelectionMethodVC, animated: true, completion: nil)

        }
    }
}

extension EditProfileViewController: UITextFieldDelegate {

    func setFilledTextFieldUI(_ textField: OutlinedTextField){
        textField.setTextColor(AppColor.Punch, for: .normal)
        textField.setFloatingLabelColor(AppColor.Punch, for: .normal)
        textField.setOutlineColor(AppColor.Punch, for: .normal)
    }

    func setEmptyTextFieldUI(_ textField: OutlinedTextField){
        textField.setNormalLabelColor(AppColor.Bombay, for: .normal)
        textField.setTextColor(AppColor.Punch, for: .normal)
        textField.setFloatingLabelColor(AppColor.Bombay, for: .normal)
        textField.setOutlineColor(AppColor.Iron, for: .normal)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        self.updatedTextValue = textField.text
        self.updateTextFieldUI(textField)
    }

    func updateTextFieldUI(_ textField: UITextField){
        let text = textField.text?.trimmText()
        if text != "" {
            self.setFilledTextFieldUI(textField as! OutlinedTextField)
        }else{
            self.setEmptyTextFieldUI(textField as! OutlinedTextField)
        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // Get the updated text after typing
        if textField == self.verifyMailTextField {
            let currentText = textField.text ?? ""
            guard let stringRange = Range(range, in: currentText) else { return false }
            let updatedText = currentText.replacingCharacters(in: stringRange, with: string)
            if updatedText.count < maxCharacters {
                self.getVerifyButton.isEnabled = false
                self.getVerifyButton.alpha = 0.5
            } else if updatedText.count == maxCharacters {
                self.getVerifyButton.isEnabled = true
                self.getVerifyButton.alpha = 1.0
            }
            return updatedText.count <= maxCharacters // Restrict input
        }
        
        return true
    }
}

extension EditProfileViewController: UITextViewDelegate {

    func textViewDidBeginEditing(_ textView: UITextView) {
        self.isChanged_About_Me = true
        if textView.textColor == AppColor.Bombay {
            textView.text = nil
            textView.textColor = AppColor.Bombay
        }
        textViewWithValue(borderWidth: 2)
    }

    func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
        let text = textView.text?.trimmText()
        if text != "" {
            textViewWithValue(borderWidth: 1)
        } else {
            textViewWithOutValue()
        }
        return true
    }

    func textViewWithValue(borderWidth:CGFloat) {
        self.viewTextView.borderColor = AppColor.Bombay
        self.viewTextView.borderWidth = borderWidth
        self.labelTextViewTitle.isHidden = false
    }

    func textViewWithOutValue() {
        self.viewTextView.borderColor = AppColor.Bombay
        self.viewTextView.borderWidth = 1
        self.aboutTextView.text = "A little bit about you..."
        self.labelTextViewTitle.isHidden = true
        self.aboutTextView.textColor = AppColor.Bombay
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Get the current text in the textView
            let currentText = textView.text ?? ""
            
            // Calculate the new length of the text after the change
            let updatedText = (currentText as NSString).replacingCharacters(in: range, with: text)
            
            // Allow the change only if the new length is <= 150 characters
            self.countAboutMe = updatedText.count
            if self.countAboutMe <= 150 {
                self.lblCountAboutMe.text = "\(self.countAboutMe)/150"
            }
            self.updatedTextValue = updatedText
            return updatedText.count <= 150
        }
}

extension EditProfileViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView,numberOfItemsInSection section: Int) -> Int {
       // switch collectionView{
        if collectionView == interestCollectionView {
            if self.moreAllSelectedInterestData.isEmpty || (self.moreAllSelectedInterestData[0].aOptions?.isEmpty ?? true) {
                return 1 // Show only the "Add" cell
            } else {
                return (self.moreAllSelectedInterestData[0].aOptions?.count ?? 0) + 1 // Interests + Add cell
            }
        } else {
            return self.aEditProfileViewModel.images.count
        }
      //  case interestCollectionView:
            
           
            
//            if self.moreAllSelectedInterestData.count > 0 {
//                let count = self.moreAllSelectedInterestData[0].aOptions?.count ?? 0
//                return count + 1
//            }
//            return 1
            //self.aEditProfileViewModel.arrayInterest?.count ?? 0
//        case imageCollectionView:
//            return self.aEditProfileViewModel.images.count
//        default:
//            return 0
//        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch collectionView {
        case interestCollectionView:

           var count = 0
            
            if self.moreAllSelectedInterestData.count > 0 {
                count = self.moreAllSelectedInterestData[0].aOptions?.count ?? 0
            }
            //self.aEditProfileViewModel.arrayInterest?.count ?? 0
            print("item.......", indexPath.row, count)
            if count == indexPath.row{
                if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ImageCollectionViewCell.identifier, for: indexPath) as? ImageCollectionViewCell {
                    let availableWidth = screen.width - 100
                    let itemWidth = availableWidth / 4
                    cell.setAddInterestPlaceholderImageUI(width: availableWidth, height: itemWidth * 0.83,noOfitemsInRow:4)
                    cell.imageDeleButton.isHidden = true
                    return cell
                }
            }else{
                if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UserInterestCollectionViewCell.identifier, for: indexPath) as? UserInterestCollectionViewCell {
//                    cell.setData(data: self.aEditProfileViewModel.arrayInterest?[indexPath.row])
                    //self.moreAllSelectedInterestData[0].aOptions
                    cell.setData(data: self.moreAllSelectedInterestData[0].aOptions?[indexPath.row])
                    return cell
                }
            }
        case imageCollectionView:
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ImageCollectionViewCell.identifier, for: indexPath) as? ImageCollectionViewCell {
                cell.setAddImageUI(image: self.aEditProfileViewModel.images[indexPath.item] ?? nil, index: indexPath.item)
                cell.completion = { [weak self] id in
                    print(indexPath.item,id as Any)
                    self?.deleteImageID = id
                    
                    self?.aDeleteCustomPopUp.show(message:Constants.AddMoment.deleteImage + "?",
                                                 button1Text:Constants.AlertButtons.cancel,
                                                 button2Text: Constants.AlertButtons.yesDelete) {
                       // ✅ Call delete API with correct ID
                        self?.aEditProfileViewModel.deleteImageAPI(id: id ?? 0)
                    }
//                    self?.imageSelectedIndex = indexPath.item
//                    self?.selectImageType = .addSelfImage
//                    self?.openImageSelectionMethodPopUp()
                }
                return cell
            }
        default:
            return UICollectionViewCell()
        }
        return UICollectionViewCell()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch collectionView{
        case interestCollectionView:
            //let count = self.moreAllSelectedInterestData[0].aOptions?.count
            let itemCount = self.moreAllSelectedInterestData.first?.aOptions?.count ?? 0
            //self.aEditProfileViewModel.arrayInterest?.count ?? 0
            if itemCount == indexPath.row {
//                let aAboutYouViewController:AboutYouViewController = AboutYouViewController.instantiateFromStoryboard()
//                //aAboutYouViewController.selectedIndex = 3
//                aAboutYouViewController.fromEditProfile = true
//                aAboutYouViewController.callBackCompletion = { [weak self] data in
//                    guard let self = self else { return }
//                    self.aEditProfileViewModel.arrayInterest = data
////                    self.interestCollectionView.collectionViewLayout = createInterestCollectionLayout()
//                    self.interestCollectionView.reloadData()
//                    self.setInterestCollectionViewHeight()
//                }
                let aEditAboutYouViewController:EditAboutYouViewController = EditAboutYouViewController.instantiateFromStoryboard()
                aEditAboutYouViewController.aMoreAboutMeQuestionData = self.moreAllInterestData
//                aEditAboutYouViewController.aMoreAboutMeQuestionData = self.editProfileQuestionData
                aEditAboutYouViewController.fromEditProfile = true
                aEditAboutYouViewController.isInterest = true
                self.navigationController?.pushViewController(aEditAboutYouViewController, animated:true)
            }
        case imageCollectionView:
            if self.aEditProfileViewModel.images[indexPath.item] == nil {
                self.imageSelectedIndex = indexPath.item
                self.selectImageType = .addSelfImage
                self.openImageSelectionMethodPopUp()
            } else {
                self.deleteImageID = self.aEditProfileViewModel.images[indexPath.item]?.id
                self.imageSelectedIndex = indexPath.item
                self.selectImageType = .addSelfImage
                self.openImageSelectionMethodPopUp()
                
            }
        default:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return self.aEditProfileViewModel.images[indexPath.item] != nil
    }

    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        
        if self.aEditProfileViewModel.images[destinationIndexPath.item] != nil {
            
            print("Index dest", self.aEditProfileViewModel.images[destinationIndexPath.row]?.status ?? 0)
            print("Index source", self.aEditProfileViewModel.images[sourceIndexPath.row]?.status ?? 0)
            //|| destinationIndexPath.row == 0
            //|| (self.aEditProfileViewModel.images[sourceIndexPath.row]?.status == 2 || self.aEditProfileViewModel.images[sourceIndexPath.row]?.status == 3)
            if sourceIndexPath.row == 0 || destinationIndexPath.row == 0 {
                //make image primary
                
                if sourceIndexPath.row == 0 {
                    
                    if (self.aEditProfileViewModel.images[destinationIndexPath.row]?.status == 2 || self.aEditProfileViewModel.images[destinationIndexPath.row]?.status == 3) {
                        //error image is not verified
                        self.showNewAlertPopUp(Title: "Error", Msg: "Image is not verified", isSuccess: false, CompletionHandler: {(success) -> Void in
                    
                        })
                    } else {
                        //make image primary
                        self.arrSwapIndex = [sourceIndexPath.row,destinationIndexPath.row]
                        aEditProfileViewModel.getProfileImagePrimary(id: self.aEditProfileViewModel.images[destinationIndexPath.row]?.id ?? 0)
                    }
                    
                    
                } else if destinationIndexPath.row == 0 {
                    
                    if (self.aEditProfileViewModel.images[sourceIndexPath.row]?.status == 2 || self.aEditProfileViewModel.images[sourceIndexPath.row]?.status == 3) {
                        //error image is not verified
                        self.showNewAlertPopUp(Title: "Error", Msg: "Image is not verified", isSuccess: false, CompletionHandler: {(success) -> Void in
                    
                        })
                    } else {
                        //make image primary
                        
                        self.arrSwapIndex = [sourceIndexPath.row,destinationIndexPath.row]
                        aEditProfileViewModel.getProfileImagePrimary(id: self.aEditProfileViewModel.images[sourceIndexPath.row]?.id ?? 0)
                        
                    }
                }
                
            } else {
                
//                let item = self.aEditProfileViewModel.images.remove(at: sourceIndexPath.row)
//                self.aEditProfileViewModel.images.insert(item, at: destinationIndexPath.row)
                
                self.swapValues(in: &self.aEditProfileViewModel.images, at: sourceIndexPath.row, and: destinationIndexPath.row)
                
            }
            
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 ) {
            self.imageCollectionView.reloadData()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 ) {
            self.imageCollectionView.reloadData()
        }
        
    }
    
    func swapValues<T>(in array: inout [T], at index1: Int, and index2: Int) {
        guard index1 >= 0, index1 < array.count, index2 >= 0, index2 < array.count else {
            print("Invalid indices")
            return
        }
        array.swapAt(index1, index2) // Swift built-in method for swapping
    }

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        // Provide the item to drag
        let item = self.aEditProfileViewModel.images[indexPath.item]?.image
        guard let image = item else { return [] }
        let itemProvider = NSItemProvider(object: image)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = item
        return [dragItem]
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        // Specify the drop operation
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    @objc func handLongPressGestrue(_ gesture :UILongPressGestureRecognizer){
        guard let collection = self.imageCollectionView else {return}
        switch gesture.state {
        case .began:
            guard self.aEditProfileViewModel.images.filter({$0 != nil}).count > 1 else{return}
            guard let targetIndexPath = collection.indexPathForItem(at: gesture.location(in: collection))else {
                return
            }
            print("begin")
            guard self.aEditProfileViewModel.images[targetIndexPath.item] != nil else{return}
            collection.beginInteractiveMovementForItem(at: targetIndexPath)
        case .changed:
            guard let targetIndexPath = collection.indexPathForItem(at: gesture.location(in: collection)) else {return}
            print("changed")
            if self.aEditProfileViewModel.images[targetIndexPath.item] != nil {
                collection.updateInteractiveMovementTargetPosition(gesture.location(in: self.imageCollectionView))
            }else{
                DispatchQueue.main.async {
                    self.imageCollectionView.reloadData()
                }
            }
        case .ended:
            collection.endInteractiveMovement()
        default:
            collection.cancelInteractiveMovement()
        }
    }
    
//    // MARK: - UICollectionViewDelegateFlowLayout
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        switch collectionView{
        case interestCollectionView:

                let numberOfItemsPerRow: CGFloat = 4 // Adjust for desired layout
                let spacing: CGFloat = 2//10 // Spacing between cells
                
                // Calculate total spacing
                let totalSpacing = (numberOfItemsPerRow - 1) * spacing //-1
                
                // Get the collection view width
                let width = screen.width - 100
            
                //collectionView.bounds.width - 94
                
                // Calculate the cell width
                let itemWidth = (width) / numberOfItemsPerRow
                //(width - totalSpacing ) / numberOfItemsPerRow
       
                
            if indexPath.row == self.moreAllSelectedInterestData.count {
                let availableWidth = screen.width - 100
                let itemW = availableWidth / 4
                
                return CGSize(width: itemW, height: 94)
            } else {
                return CGSize(width: itemWidth, height: 94)
            }
                // Return the size for each cell
                
            
             // Adjust height if needed
        default:
            return CGSize(width: self.imageCollectionView.frame.width, height: self.imageCollectionView.frame.height)
        }
        
        }
    
}


extension EditProfileViewController: UITableViewDelegate, UITableViewDataSource{

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.filterListAlphabetically()
        return  self.moreAboutProfileQuestionData.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: MoreAboutMeTableViewCell.identifier, for: indexPath)as? MoreAboutMeTableViewCell{
            
            let item = moreAboutProfileQuestionData[indexPath.row] // This is AttributesData
            cell.setUI(data: item, hideForwardImage: false)
            return cell
        }
        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedItem = moreAboutProfileQuestionData[indexPath.row]
        print("Tapped on:", selectedItem)
        let aEditAboutYouViewController: EditAboutYouViewController = EditAboutYouViewController.instantiateFromStoryboard()
        aEditAboutYouViewController.aMoreAboutMeQuestionData = [selectedItem]
        aEditAboutYouViewController.fromEditProfile = true
        if let originalIndex = editProfileQuestionData.firstIndex(where: { $0.alias == selectedItem.alias }) {
            aEditAboutYouViewController.selectedIndex = originalIndex
        }
        self.navigationController?.pushViewController(aEditAboutYouViewController, animated: false)
    }
}

extension EditProfileViewController:PHPickerViewControllerDelegate{

    // Function to request photo library access permission
    func requestPhotoLibraryAccess() {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            if status == .authorized { // Permission granted by the user
                self?.openMultipleSelectionLibrary()
            } else {
                // Permission denied by the user
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
                self.navigationController?.present(aFaceVerificationViewController, animated: true, completion: nil)
            }
        }
    }
}

extension EditProfileViewController {

    func uploadSelectedImage(_ selectedImage:UIImage?){
        guard let image = selectedImage else {return}
        let imgPic = image.fixedOrientation()
        self.aActivityIndicator.show()
        if self.selectImageType == .addCoverImage{
            self.aEditProfileViewModel.uploadCoverPhotoAPI(image: imgPic)
        }else{
            upLoadedImg = [imgPic]
            self.aEditProfileViewModel.uploadProfilePhotoAPI(image: imgPic)
        }
    }
}

// For multiple selection from Photolibrary
extension EditProfileViewController {
    func openMultipleSelectionLibrary(){
        self.isSelectingMultipleImage = true
        DispatchQueue.main.async {
            var config = PHPickerConfiguration()
            config.filter = .images
            //            if self.aEditProfileViewModel.images[self.imageSelectedIndex ?? 0] == nil {
            //                let nilItems = self.aEditProfileViewModel.images.filter({$0 == nil})
            //                print(nilItems)
            //                config.selectionLimit = nilItems.count
            //            }else{
            config.selectionLimit = 1
            //            }
            let phPicker = PHPickerViewController(configuration: config)
            phPicker.delegate = self
            self.present(phPicker, animated: true)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        let dispatchGroup = DispatchGroup()
        var selectedImage:[UIImage] = []
        for result in results {
            dispatchGroup.enter()
            self.aActivityIndicator.show()
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    print(image)
                    selectedImage.append(image)
                }
                dispatchGroup.leave()
            }
        }
        dispatchGroup.notify(queue: .main) {
            print(selectedImage)
            if self.isSelectingMultipleImage ?? false {
                self.aActivityIndicator.hide()
            }
            self.isSelectingMultipleImage = false
            if !(selectedImage.isEmpty){
                self.uploadSelectedImage(selectedImage[0])
            }
        }
    }

    func addSelectedImage(image:[UIImage], model:UploadProfileImageModel){
        if self.aEditProfileViewModel.images[imageSelectedIndex ?? 0] != nil {
            self.aEditProfileViewModel.images[imageSelectedIndex ?? 0]?.image = image.first
        }else{
            for image in image {
                for (index,item) in self.aEditProfileViewModel.images.enumerated(){
                    if item == nil {
                        let data:EditProfileImageModel? = EditProfileImageModel(image: image, id: model.data?.uploadImg?.id, status: model.data?.uploadImg?.status)
                        self.aEditProfileViewModel.images[index] = data
                        break
                    }
                }
            }
        }
        DispatchQueue.main.async{
            self.imageCollectionView.reloadData()
        }
    }

    func deleteSelectedImage(){
        self.aEditProfileViewModel.images[self.imageSelectedIndex ?? 0] = nil
        let imageData:[EditProfileImageModel?] = self.aEditProfileViewModel.images.filter({$0?.image != nil})
        self.aEditProfileViewModel.images = Array(repeating: nil, count: 6)
        for image in imageData {
            for (index,item) in self.aEditProfileViewModel.images.enumerated(){
                if item == nil {
                    self.aEditProfileViewModel.images[index] = image
                    //self.
                    break
                }
            }
        }
        DispatchQueue.main.async{
            self.aEditProfileViewModel.callCheckExistingData()
            //self.imageCollectionView.reloadData()
        }
    }
}

extension EditProfileViewController:OTPFieldViewDelegate {
    func didEndEditing(text: String) {
        print(text as Any)
        strOTP = text
    }

    func enteredOTP(otp: String, textFieldView: UIView) {
        if otp.count < 6 {
            isOTPEntered = false
        } else {
            isOTPEntered = true
            strOTP = otp
        }
        print("OTPString: \(otp)")
    }

    func hasEnteredAllOTP(hasEnteredAll hasEntered: Bool) -> Bool {
        print("Has entered all OTP? \(hasEntered)")
        isOTPEntered = hasEntered
        return false
    }

    func shouldBecomeFirstResponderForOTP(otpTextFieldIndex index: Int) -> Bool {
        return true
    }
}
extension EditProfileViewController {

    // TODO: replace with Firebase PhoneAuthProvider verification once Firebase is integrated.
    // Mock: any 6-digit code is accepted.
    func verifyCode(verificationID: String, verificationCode: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) {
            self.verifyButton.hideLoading()
            guard verificationCode.count == 6, verificationCode.allSatisfy(\.isNumber) else {
                self.showNewAlertPopUp(Title: "Got some trouble!!", Msg: "Please enter valid OTP.", isSuccess: false, CompletionHandler: {(success) -> Void in

                })
                return
            }
            let strCountryCode = "\(self.countryCodeLabel.text?.dropFirst() ?? "")"
            let strPhoneNo = self.verifyMailTextField.text?.trimmText()
            self.aEditProfileViewModel.addPhoneNo(countryCode: strCountryCode, number: strPhoneNo ?? "")
        }
    }

    // TODO: replace with Firebase PhoneAuthProvider.verifyPhoneNumber once Firebase is integrated.
    func sendVerificationCode(to phoneNumber: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) {
            self.getVerifyButton.hideLoading(originalTitle: "Get Verify")
            self.vwOTPField.isHidden = false
            self.vwBtnVerify.isHidden = false
            self.otpTextFildView.initializeUI()
            UserDataManager.shared.OTPAuth = "mock-verification-id"
        }
    }
}
