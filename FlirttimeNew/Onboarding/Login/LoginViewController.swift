//
//  LoginViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 04/04/24.
//

import UIKit
import IQKeyboardManagerSwift

class LoginViewController: BaseViewController,Instantiable {
    
    @IBOutlet weak var loginBottomView: UIView!
    @IBOutlet weak var emailView: UIView!
    @IBOutlet weak var phoneView: UIView!
    @IBOutlet weak var emailTextFieldView: UIView!
    @IBOutlet weak var phoneTextFieldView: UIView!
    @IBOutlet weak var emailPhoneToggleIcon: UIImageView!
    @IBOutlet weak var acceptPrivacyLabel: UILabel!
    @IBOutlet weak var countryCodeLabel: UILabel!
    @IBOutlet weak var countryLogoImage: UIImageView!
    @IBOutlet weak var phoneNumberTextField: UITextField!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var continueButton: UIButton!
    @IBOutlet weak var wrongPhoneNumberPopUp: UIView!
    @IBOutlet weak var phoneNumberPopUpInsideView: UIView!
    @IBOutlet weak var phoneNumberBottomTipImage: UIImageView!
    @IBOutlet weak var wrongEmailPopUp: UIView!
    @IBOutlet weak var emailPopUpInsideView: UIView!
    @IBOutlet weak var emailBottomTipImage: UIImageView!
    @IBOutlet weak var topImageHeight: NSLayoutConstraint!
    @IBOutlet weak var topImageBottom: NSLayoutConstraint!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var emailPhoneStackView: UIStackView!
    var signUpOption:SignUpOption = .phoneNumber
    var lastSignUpOption:SignUpOption = .phoneNumber
    var selectedRegionCode:String?
    var topConstraintEqual: NSLayoutConstraint?
    var topConstraintGreaterThanOrEqual: NSLayoutConstraint?
    private let viewModel = LoginViewModel()
    
    static var storyboardName: StringConvertible {
        return StoryboardName.login
    }
    
    override func viewWillAppear(_ animated: Bool) {
        print("last.....",lastSignUpOption)
        if signUpOption == .apple {
            signUpOption = lastSignUpOption
        }
        super.viewWillAppear(animated)
        IQKeyboardManager.shared.resignOnTouchOutside = true
    }
    
    override func viewDidLoad() {
        self.setUI()
        super.viewDidLoad()
        lastSignUpOption = signUpOption
        self.bindViewModel()
    }

    private func bindViewModel() {
        viewModel.onLoading = { [weak self] isLoading in
            self?.setLoading(isLoading)
        }
        viewModel.onError = { [weak self] message in
            self?.aCustomToastView.show(message: message)
        }
        viewModel.onOTPSent = { [weak self] otp in
            self?.navigateToOTPScreen(otp: otp)
        }
    }
    
    func setUI(){
        scrollView.contentInsetAdjustmentBehavior = .never
        self.phoneNumberTextField.delegate = self
        self.emailTextField.delegate = self
        self.wrongPhoneNumberPopUp.isHidden = true
        self.wrongEmailPopUp.isHidden = true
        self.loginBottomView.setRoundedManualTopCorners(cornerRadius: 18)
        self.emailView.isHidden = self.signUpOption == .email ? false : true
        self.phoneView.isHidden = self.signUpOption == .phoneNumber ? false : true
        self.emailPhoneToggleIcon.image = self.signUpOption == .phoneNumber ?  UIImage(named:"redEmail") : UIImage(named:"redPhone")
        self.acceptPrivacyLabel.setAttriibutText(text1: Constants.LoginOption.acceptenceText, text2: Constants.LoginOption.privacyPolicy, color: AppColor.AppBlack)
        self.continueButton.backgroundColor = AppColor.Punch.withAlphaComponent(0.5)
        if let data = CountryDataManager.shared.filterCountryData {
            self.setCountryCodeUI(data)
            self.selectedRegionCode = CountryDataManager.shared.regionCode
        }
        [self.phoneNumberPopUpInsideView,emailPopUpInsideView].forEach({ view in
            view.addShadow(color: .darkGray, opacity: 0.3, offset: CGSize(width: 0.5, height: 2.0))
        })
        [self.phoneNumberBottomTipImage,emailBottomTipImage].forEach({ view in
            view.addShadow(color: .darkGray, opacity: 0.3, offset: CGSize(width: 0.5, height: 3.5))
        })
    }
    
    func setCountryCodeUI(_ data:CountryListModel?){
        self.countryCodeLabel.text = data?.dial_code
        self.countryLogoImage.image = UIImage(named:data?.code ?? "", in: Bundle.main, with: nil)
    }
    
    @IBAction func phoneNumberTextDidChange(_ sender: UITextField) {
        let trimmText = self.phoneNumberTextField.removeWhitespace()
        self.setContinueButtonUI(text: trimmText)
        self.showHideWrongPhoneNumerPopUp()
    }
    
    @IBAction func emailTextFieldDidChange(_ sender: UITextField) {
        let trimmText = self.emailTextField.removeWhitespace()
        self.showHideWrongEmailPopUp()
        self.setContinueButtonUI(text: trimmText)
    }
    
    @IBAction func emailSignUpButtonAction(_ sender: UIButton) {
        view.endEditing(true)
        self.phoneView.isHidden.toggle()
        self.emailView.isHidden.toggle()
        self.signUpOption = self.phoneView.isHidden ? .email : .phoneNumber
        self.emailPhoneToggleIcon.image = self.signUpOption == .email ? UIImage(named:"redPhone") : UIImage(named:"redEmail")
        self.setContinueButtonUI(text: self.signUpOption == .phoneNumber ? self.phoneNumberTextField.text ?? "" : self.emailTextField.text ?? "")
    }
    
    @IBAction func appleSignUpButtonAction(_ sender: UIButton) {
        self.signUpOption = .apple
        UserDataManager.shared.isOTPVerificationDone = true
        self.navigateToUserDetails()
    }
    
    @IBAction func phoneCodeSelectionButton(_ sender: UIButton) {
        let aCountryListViewController = CountryListViewController.instantiateFromStoryboard()
        aCountryListViewController.regionCode = self.selectedRegionCode
        aCountryListViewController.selectionCallBack = { [weak self] selectedData in
            self?.selectedRegionCode = selectedData.code
            self?.setCountryCodeUI(selectedData)
        }
        aCountryListViewController.modalPresentationStyle = .overCurrentContext
        self.navigationController?.present(aCountryListViewController, animated: true, completion: nil)
    }
    
    
    @IBAction func continueButton(_ sender: UIButton) {
        self.view.endEditing(true)
        viewModel.requestOTP(signUpOption: signUpOption,
                             email: emailTextField.text,
                             countryCode: countryCodeLabel.text,
                             phone: phoneNumberTextField.text)
    }
    
    @IBAction func actionPrivacyPolicy(_ sender: UIButton) {
            self.loadPrivacyPolicy()
        }
    
    @IBAction func actionLEarnMore(_ sender: UIButton) {
        let vc = LearnMoreVC()
        present(vc, animated: true, completion: nil)
        }

    func setContinueButtonUI(text:String){
        let validate = self.validation(text: text, signUpOption: self.signUpOption)
        self.continueButton.backgroundColor = validate ? AppColor.Punch : AppColor.Punch.withAlphaComponent(0.5)
        self.continueButton.isUserInteractionEnabled = validate
    }
    
    func validation(text: String?, signUpOption: SignUpOption) -> Bool {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if signUpOption == .phoneNumber {
            return trimmed.count == 10
        }
        return trimmed.isValidEmail()
    }
    
    func showHideWrongPhoneNumerPopUp(){
//        if let validate = aLoginViewModel.validation(text:phoneNumberTextField.text,singUpOption: self.signUpOption){
//            self.wrongPhoneNumberPopUp.isHidden = validate
//        }
    }
    
    func showHideWrongEmailPopUp(){
//        if let validate = aLoginViewModel.validation(text:emailTextField.text,singUpOption: self.signUpOption){
//            self.wrongEmailPopUp.isHidden = validate
//        }
    }
    
    func navigateToOTPScreen(otp: OTPResponse) {
        let aVerifyOTPViewController = VerifyOTPViewController.instantiateFromStoryboard()
        let countryCode = self.countryCodeLabel.text?.dropFirst()
        aVerifyOTPViewController.verificationId = otp.verificationId
        aVerifyOTPViewController.resendAfter = otp.resendAfter
        aVerifyOTPViewController.signUpOption = self.signUpOption
        aVerifyOTPViewController.phoneCode = String(countryCode ?? "")
        aVerifyOTPViewController.phoneNumber = self.phoneNumberTextField.text
        aVerifyOTPViewController.emailID = self.emailTextField.text
        aVerifyOTPViewController.phoneCountryCode = self.countryCodeLabel.text
        self.navigationController?.pushViewController(aVerifyOTPViewController, animated: true)
    }
    
}

extension LoginViewController: UITextFieldDelegate {
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if phoneNumberTextField == textField {
            let currentText = textField.text ?? ""
            // attempt to read the range they are trying to change, or exit if we can't
            guard let stringRange = Range(range, in: currentText) else { return false }
            // add their new text to the existing text
            let updatedText = currentText.replacingCharacters(in: stringRange, with: string)
            // make sure the result is under 16 characters
            return updatedText.count <= 10
        }
        return true
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        
        // Deactivate any active top constraints
        self.wrongPhoneNumberPopUp.isHidden = true
        self.wrongEmailPopUp.isHidden = true
        self.topConstraintEqual?.isActive = false
        self.topConstraintGreaterThanOrEqual?.isActive = false
        
        self.topConstraintEqual = self.acceptPrivacyLabel.topAnchor.constraint(equalTo: self.emailPhoneStackView.bottomAnchor, constant: 15)
        self.topConstraintEqual?.isActive = true
        UIView.animate(withDuration: 0.3) {
            self.topImageHeight.constant = 0
            self.topImageBottom.constant = 60
            self.scrollView.setContentOffset(CGPoint(x: 0, y: -self.scrollView.contentInset.top), animated: true)
            // Disable vertical scrolling
            self.view.layoutIfNeeded()
        }
        
        switch textField {
        case phoneNumberTextField:
            self.showHideWrongPhoneNumerPopUp()
            self.setPhoneViewUI()
        case emailTextField:
            self.showHideWrongEmailPopUp()
            self.setEmailViewUI()
        default:
            break
        }
    }
    
    func setEmailViewUI(){
        self.phoneTextFieldView.layer.borderColor = AppColor.Iron.cgColor
        self.emailTextFieldView.layer.borderColor = AppColor.Punch.cgColor
    }
    
    func setPhoneViewUI(){
        self.phoneTextFieldView.layer.borderColor = AppColor.Punch.cgColor
        self.emailTextFieldView.layer.borderColor = AppColor.Iron.cgColor
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        switch textField {
        case phoneNumberTextField:
            self.phoneTextFieldView.layer.borderColor = AppColor.Iron.cgColor
        case emailTextField:
            self.emailTextFieldView.layer.borderColor = AppColor.Iron.cgColor
        default:
            break
        }
        
        // Deactivate any active top constraints
        self.topConstraintEqual?.isActive = false
        self.topConstraintGreaterThanOrEqual?.isActive = false
        
        // Create a greater than or equal to constraint
        self.topConstraintGreaterThanOrEqual = self.acceptPrivacyLabel.topAnchor.constraint(greaterThanOrEqualTo: self.emailPhoneStackView.bottomAnchor, constant: 10)
        self.topConstraintGreaterThanOrEqual?.isActive = true
        
        // Animate the change if needed
        UIView.animate(withDuration: 0.3) {
            self.topImageHeight.constant = 440.0
            self.topImageBottom.constant = -130
            //        self.scrollView.isScrollEnabled = true
            self.view.layoutIfNeeded()
        }
        
    }
    
    func navigateToUserDetails(){
        let aUserDetailsViewController = UserDetailsViewController.instantiateFromStoryboard()
        aUserDetailsViewController.signUpOption = self.signUpOption
        aUserDetailsViewController.emailID = self.emailTextField.text
        self.navigationController?.pushViewController(aUserDetailsViewController, animated: true)
    }
}
