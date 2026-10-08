//
//  UserDetailsViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 02/05/24.
//

import UIKit
import IQKeyboardManagerSwift

class UserDetailsViewController: BaseViewController,Instantiable{

    @IBOutlet weak var lastNameTextField: OutlinedTextField!
    @IBOutlet weak var nickNameTextField: OutlinedTextField!
    @IBOutlet weak var firstNameTextField: OutlinedTextField!
    @IBOutlet weak var genderTextField: OutlinedTextField!
    @IBOutlet weak var birthDateTextField: OutlinedTextField!
    @IBOutlet weak var errorLabel: UILabel!
    @IBOutlet weak var aboutTextView: UITextView!
    @IBOutlet weak var viewTextView: UIView!
    @IBOutlet weak var labelTextViewTitle: UILabel!
    @IBOutlet weak var calenderImage: UIImageView!
    @IBOutlet weak var continueButton: UIButton!
    @IBOutlet weak var genderNoteLabel: UILabel!
    @IBOutlet weak var dateOfBirthNoteLabel: UILabel!
    @IBOutlet weak var yourStoryNoteLabel: UILabel!
    @IBOutlet weak var lblCountAboutMe: UILabel!
    
    var selectedDOB:Date?
    var apiCallWorkItem: DispatchWorkItem?

//    To save prefill data

    var signUpOption:SignUpOption?
    var emailID:String?
    var phoneNumber:String?
    var phoneCode:String?
    
    var genderID:Int?
    var validNickName:Bool = false
    var countAboutMe:Int = 0

    static var storyboardName: StringConvertible {
        return StoryboardName.signUp
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.dateOfBirthNoteLabel.setAttriibutText(text1: Constants.UserDetails.dateOfBirthNote, text2: Constants.UserDetails.note,pattern: false, color: AppColor.AppBlack)
        self.genderNoteLabel.setAttriibutText(text1: Constants.UserDetails.genderNote, text2: Constants.UserDetails.note,pattern: false, color: AppColor.AppBlack)
        self.yourStoryNoteLabel.setAttriibutText(text1: Constants.UserDetails.tellYourStoryNote, text2: Constants.UserDetails.note,pattern: false, color: AppColor.AppBlack)
        self.setTextFieldUI()
        
        self.firstNameTextField.maxLength = 50
        self.nickNameTextField.maxLength = 50
    }

    func setTextFieldUI(){
        self.firstNameTextField.delegate = self
        self.lastNameTextField.delegate = self
        self.nickNameTextField.delegate = self
        self.genderTextField.delegate = self
        self.birthDateTextField.delegate = self
        self.aboutTextView.delegate = self

        self.firstNameTextField.label.text = Constants.UserDetails.firstName
        self.lastNameTextField.label.text = Constants.UserDetails.lastName
        self.nickNameTextField.label.text = Constants.UserDetails.nickName
        self.birthDateTextField.label.text = Constants.UserDetails.dob
        self.genderTextField.label.text = Constants.UserDetails.gender
        self.aboutTextView.text = Constants.UserDetails.aboutYouPlaceHolder
        self.aboutTextView.textColor = AppColor.Bombay
        
        self.nickNameTextField.keyboardType = .default
        
        self.nickNameTextField.autocorrectionType = .no
        self.nickNameTextField.spellCheckingType = .no
        self.nickNameTextField.smartQuotesType = .no
        self.nickNameTextField.smartDashesType = .no
        self.nickNameTextField.smartInsertDeleteType = .no
        
        self.nickNameTextField.textContentType = .oneTimeCode

//        [firstNameTextField,lastNameTextField,nickNameTextField,genderTextField,birthDateTextField].forEach { textField in
//            textField.autocorrectionType = .no
//        }

        [firstNameTextField,lastNameTextField,nickNameTextField,genderTextField,birthDateTextField].forEach { textField in
            textField.setNormalLabelColor(AppColor.Bombay, for: .normal)
            textField.setTextColor(AppColor.Punch, for: .normal)
            textField.setTextColor(AppColor.Punch, for: .editing)
            textField.setFloatingLabelColor(AppColor.Punch, for: .editing)
            textField.setFloatingLabelColor(AppColor.Bombay, for: .normal)
            textField.setOutlineColor(AppColor.Punch, for: .editing)
            textField.setOutlineColor(AppColor.Iron, for: .normal)
        }
        IQKeyboardManager.shared.enableAutoToolbar = true
        IQKeyboardManager.shared.resignOnTouchOutside = true
        //self.setPrefillData()
    }

    func setContinueButtonUI(){
        let result = self.validation()
        self.continueButton.isUserInteractionEnabled = result
        self.continueButton.backgroundColor = result ? AppColor.Punch : AppColor.Punch.withAlphaComponent(0.5)
    }

    func validation() -> Bool {
        let aboutText = self.aboutTextView.text
        guard self.firstNameTextField.text?.trimmText() != "",
              self.nickNameTextField.text?.trimmText() != "",
              self.birthDateTextField.text?.trimmText() != "",
              self.genderTextField.text?.trimmText() != "",
              aboutText?.trimmText() != "",
              aboutText != Constants.UserDetails.aboutYouPlaceHolder else {
            return false
        }
        return self.validNickName
    }

    func navigateToNextScreen(){
        //UserDataManager.shared.removeUserPrefillIntroData() -- code comment by Abhishek Tiwari
        let aStartProfileVerificationVC = StartProfileVerificationViewController.instantiateFromStoryboard()
        self.navigationController?.pushViewController(aStartProfileVerificationVC, animated: true)
    }
    
    @IBAction func calenderButtonTapped(_ sender: UIButton) {
        view.endEditing(true)
        self.aFlirtCustomPopUp.show(text:Constants.CustomPopUp.birthDayText,buttonTitle: [Constants.AlertButtons.save], popUpType: .birthdayDate, completion1: { date in
            let selectedDOB = date as? Date
            self.birthDateTextField.text = selectedDOB?.convertDateToddMMYYYY()
//            self.calenderImage.tintColor = self.birthDateTextField.text != "" ? AppColor.Punch :  AppColor.Bombay
            self.selectedDOB = selectedDOB
            self.updateTextFieldUI(self.birthDateTextField)
            self.setContinueButtonUI()
        })
    }

    @IBAction func genderButtonTapped(_ sender: UIButton) {
        view.endEditing(true)
        self.aFlirtCustomPopUp.show(text:Constants.CustomPopUp.genderText,buttonTitle: [Constants.AlertButtons.save], popUpType: .gender,completion3: { gender, genderId in
            let selectedGender = gender
            self.genderTextField.text = selectedGender
            self.genderID = genderId
            self.updateTextFieldUI(self.genderTextField)
            self.setContinueButtonUI()
        })
        
//        ,completion1: { data in
//            print(data)
//        }
    }

    @IBAction func continueButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        UserDataManager.shared.displayName = self.nickNameTextField.text?.trimmText()
        self.navigateToNextScreen()
    }

    @IBAction func backButtonTapped(_ sender: UIButton) {
        print("Apple..........")
        guard let navigationController = self.navigationController else {return }
        if signUpOption == .apple
        {
            print("Apple..........")
            navigationController.popViewController(animated: true)
        } else {
            let controllers = navigationController.viewControllers
            let vc = controllers.filter({$0.isKind(of: LoginViewController.self)})
            let vc1 = controllers.filter({$0.isKind(of: LoginOptionsViewController.self)})
            if vc.count > 0{
                let viewController = vc.first as! LoginViewController
                self.navigationController?.popToViewController(viewController, animated: true)
            }else if vc1.count > 0{
                let viewController = vc1.first as! LoginOptionsViewController
                self.navigationController?.popToViewController(viewController, animated: true)
            }
        }
        
    }
}

extension UserDetailsViewController: UITextFieldDelegate {

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
    
        if textField == firstNameTextField || textField == lastNameTextField{
            let allowedCharacters = CharacterSet.letters
            let characterSet = CharacterSet(charactersIn: string)
            if string == " " {
                return true
            }
            return allowedCharacters.isSuperset(of: characterSet)
        }
        self.setContinueButtonUI()
        let updatedText = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) ?? ""
        if textField == nickNameTextField {
            self.validateNickName(nickName:updatedText.trimmText())
        }
        return true
    }

    func setFilledTextFieldUI(_ textField: OutlinedTextField){
        
        print("TEXT FIELD TAG :", textField.tag)
        if textField.tag != 2 {
            textField.setNormalLabelColor(AppColor.Bombay, for: .normal)
            textField.setTextColor(AppColor.Bombay, for: .normal)
            textField.setFloatingLabelColor(AppColor.Bombay, for: .normal)
            textField.setOutlineColor(AppColor.Iron, for: .normal)
//            if textField == birthDateTextField {
//                self.calenderImage.tintColor = AppColor.Bombay
//            }
        } else {
           
            if errorLabel.isHidden == true {
                textField.setNormalLabelColor(AppColor.Bombay, for: .normal)
                textField.setTextColor(AppColor.Bombay, for: .normal)
                textField.setFloatingLabelColor(AppColor.Bombay, for: .normal)
                textField.setOutlineColor(AppColor.Iron, for: .normal)
            } else {
                textField.setTextColor(AppColor.Punch, for: .normal)
                textField.setFloatingLabelColor(AppColor.Punch, for: .normal)
                textField.setOutlineColor(AppColor.Punch, for: .normal)
            }
        }
    }

    func setEmptyTextFieldUI(_ textField: OutlinedTextField){
        textField.setNormalLabelColor(AppColor.Bombay, for: .normal)
        textField.setTextColor(AppColor.Punch, for: .normal)
        textField.setFloatingLabelColor(AppColor.Bombay, for: .normal)
        textField.setOutlineColor(AppColor.Iron, for: .normal)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        self.updateTextFieldUI(textField)
        self.setContinueButtonUI()
    }

    func updateTextFieldUI(_ textField: UITextField){
        let text = textField.text?.trimmText()
        if text != "" {
            self.setFilledTextFieldUI(textField as! OutlinedTextField)
        }else{
            self.setEmptyTextFieldUI(textField as! OutlinedTextField)
        }
    }

    func validateNickName(nickName:String){
        apiCallWorkItem?.cancel()
        let newWorkItem = DispatchWorkItem { [weak self] in
            self?.validNickName = !nickName.isEmpty
            self?.errorLabel.isHidden = true
            self?.setContinueButtonUI()
            
        }
        apiCallWorkItem = newWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: newWorkItem)
    }
}

extension UserDetailsViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == AppColor.Bombay {
            textView.text = nil
            textView.textColor = AppColor.Punch
            self.lblCountAboutMe.textColor = AppColor.Punch
            self.labelTextViewTitle.textColor = AppColor.Punch
            self.countAboutMe = 0
            self.lblCountAboutMe.text = "\(self.countAboutMe)/150"
            
        }
        textViewWithValue(borderWidth: 2)
        self.setContinueButtonUI()
    }

    func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
        let text = textView.text?.trimmText()
        if text != "" {
            //self.textViewWithValue(borderWidth: 1)
            self.updateTextViewStyle(showPlaceHolder: false)
        } else {
            //self.textViewWithOutValue()
            self.updateTextViewStyle(showPlaceHolder: true)
        }
        self.setContinueButtonUI()
        return true
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Get the current text in the textView
            let currentText = textView.text ?? ""
            
            // Calculate the new length of the text after the change
            let updatedText = (currentText as NSString).replacingCharacters(in: range, with: text)
            
            // Allow the change only if the new length is <= 150 characters
            self.setContinueButtonUI()
        
            self.countAboutMe = updatedText.count
            if self.countAboutMe <= 150 {
                self.lblCountAboutMe.text = "\(self.countAboutMe)/150"
            }
        
            return updatedText.count <= 150
        }

//    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
//        self.setContinueButtonUI()
//        return true
//    }

    func textViewWithValue(borderWidth:CGFloat) {
        self.viewTextView.borderColor = AppColor.Punch
        self.viewTextView.borderWidth = borderWidth
        self.labelTextViewTitle.isHidden = false
    }

//    func textViewWithOutValue(showPlaceHolder: bool) {
//        self.viewTextView.borderColor = AppColor.Bombay
//        self.viewTextView.borderWidth = 1
//        self.aboutTextView.text = Constants.UserDetails.aboutYouPlaceHolder
//        self.labelTextViewTitle.isHidden = true
//        self.aboutTextView.textColor = AppColor.Bombay
//    }
    
    func updateTextViewStyle(showPlaceHolder: Bool) {
        if showPlaceHolder {
            self.viewTextView.borderColor = AppColor.Bombay
            self.viewTextView.borderWidth = 1
            self.aboutTextView.text = Constants.UserDetails.aboutYouPlaceHolder
            self.labelTextViewTitle.isHidden = true
            self.aboutTextView.textColor = AppColor.Bombay
            self.lblCountAboutMe.textColor = AppColor.Bombay
            self.countAboutMe = 0
            self.lblCountAboutMe.text = "\(self.countAboutMe)/150"
        } else {
            self.viewTextView.borderColor = AppColor.Bombay
            self.viewTextView.borderWidth = 1
            self.labelTextViewTitle.isHidden = false
            self.labelTextViewTitle.textColor = AppColor.Bombay
            self.aboutTextView.textColor = AppColor.Bombay
            self.lblCountAboutMe.textColor = AppColor.Bombay
        }
    }
}
