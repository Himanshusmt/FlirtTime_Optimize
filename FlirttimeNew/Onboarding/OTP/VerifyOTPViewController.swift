//
//  VerifyOTPViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 27/04/24.
//

import UIKit
import IQKeyboardManagerSwift

class VerifyOTPViewController: BaseViewController,Instantiable {

    @IBOutlet weak var resendButton: UIButton!
    @IBOutlet weak var acceptPrivacyLabel: UILabel!
    @IBOutlet weak var otpBottomView: UIView!
    @IBOutlet weak var editButton: UIButton!
    @IBOutlet weak var continueButton: UIButton!
    @IBOutlet weak var emailPhoneNumberLabel: UILabel!
    @IBOutlet weak var timerLabel: UILabel!
    @IBOutlet weak var otpTextFieldView: OTPFieldView!
    @IBOutlet weak var wrongOTPPopUp: UIView!
    @IBOutlet weak var otpPopUpInsideView: UIView!
    @IBOutlet weak var otpBottomTipImage: UIImageView!
    @IBOutlet weak var emailVerifyNoteView: UIStackView!
    @IBOutlet weak var topImageHeight: NSLayoutConstraint!
    @IBOutlet weak var topImageBottom: NSLayoutConstraint!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var resendOTPStack: UIStackView!
    @IBOutlet weak var codeSentLabel: UILabel!
    @IBOutlet weak var messageOnLabel: UILabel!
    @IBOutlet weak var lblWrongOTPTitle: UILabel!
    @IBOutlet weak var lblWrongOTPMsg: UILabel!

    var topConstraintEqual: NSLayoutConstraint?
    var topConstraintGreaterThanOrEqual: NSLayoutConstraint?

    let resendAttribute: [NSAttributedString.Key: Any] = [
        .font:UIFont.fredoka(.medium, size: 12),
        .foregroundColor: AppColor.Punch.withAlphaComponent(0.5),
        .underlineStyle: NSUnderlineStyle.single.rawValue
    ]

    let editAttribute:[NSAttributedString.Key: Any] = [
        .font:UIFont.fredoka(.medium, size: 12),
        .foregroundColor: AppColor.Punch,
        .underlineStyle: NSUnderlineStyle.single.rawValue
    ]

    private var enterOtp = ""
    var signUpOption:SignUpOption?
    var emailID:String?
    var phoneNumber:String?
    var phoneCode:String?
    var phoneCountryCode:String?
    var timer: Timer?
    var secondsRemaining = 60
    var isAllOTPEntered:Bool? = false
    var otpTextFieldIndex:Int? = 0
    var isDoneEditing:Bool? = false
    static var storyboardName: StringConvertible {
        return StoryboardName.login
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        IQKeyboardManager.shared.enableAutoToolbar = true
        IQKeyboardManager.shared.resignOnTouchOutside = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setUI()
        IQKeyboardManager.shared.enableAutoToolbar = false
        IQKeyboardManager.shared.resignOnTouchOutside = false
    }

    func setUI(){
        self.startTimer()
        self.otpBottomView.setRoundedManualTopCorners(cornerRadius: 18)
        self.acceptPrivacyLabel.setAttriibutText(text1:Constants.LoginOption.acceptenceText, text2: Constants.LoginOption.privacyPolicy, color: AppColor.AppBlack)
        self.codeSentLabel.text = self.signUpOption == .email ? Constants.VerifiyOTP.codeSentViaEmail : Constants.VerifiyOTP.codeSentViaMesg
        self.messageOnLabel.isHidden = self.signUpOption == .email ? true : false
        self.setBUttonAttribute(resendButton,"Resend", yourAttributes: resendAttribute)
        self.setBUttonAttribute(editButton,"Edit", yourAttributes: editAttribute)
        self.emailPhoneNumberLabel.text = self.signUpOption == .phoneNumber ? self.phoneNumber : self.emailID
        self.continueButton.backgroundColor = AppColor.Punch.withAlphaComponent(0.5)
        self.wrongOTPPopUp.isHidden = true
        self.otpPopUpInsideView.addShadow(color: .darkGray, opacity: 0.3, offset: CGSize(width: 0.5, height: 2.0))
        self.otpBottomTipImage.addShadow(color: .darkGray, opacity: 0.3, offset: CGSize(width: 0.5, height: 3.5))
        self.emailVerifyNoteView.isHidden = self.signUpOption == .phoneNumber
        self.setResendButtonInteration(isHide: true)
        self.setupOtpView()
    }

    private func setResendButtonInteration(isHide:Bool){
        self.resendButton.isUserInteractionEnabled = !(isHide)
        self.resendButton.titleLabel?.textColor = isHide ? AppColor.Punch.withAlphaComponent(0.5) : AppColor.Punch
    }

    private func setupOtpView() {
        self.otpTextFieldView.fieldsCount = 6
        self.otpTextFieldView.fieldBorderWidth = 1
        self.otpTextFieldView.defaultBorderColor = AppColor.Iron
        self.otpTextFieldView.filledBorderColor = AppColor.AppBlack
        self.otpTextFieldView.fieldBorderWidth = 2
        self.otpTextFieldView.cursorColor = AppColor.AppBlack
        self.otpTextFieldView.displayType = .underlinedBottom
        let fieldSize = (UIScreen.main.bounds.width - 48 - 46) / 6.0
        self.otpTextFieldView.fieldSize = CGFloat(fieldSize)
        self.otpTextFieldView.fieldFont = UIFont.fredoka(.medium, size: 40)
        self.otpTextFieldView.separatorSpace = 8
        self.otpTextFieldView.shouldAllowIntermediateEditing = false
        self.otpTextFieldView.delegate = self
        self.otpTextFieldView.initializeUI()
    }

    @IBAction func resendOTPButton(_ sender: UIButton) {
        self.stopTimer()
        self.startTimer()
    }

    @IBAction func editButton(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }

    @IBAction func continueButtonAction(_ sender: UIButton) {
        self.view.endEditing(true)
        UserDataManager.shared.isOTPVerificationDone = true
        self.navigateToNextScreen()
    }
    
    @IBAction func actionLearnMore(_ sender: UIButton) {
        let vc = LearnMoreVC()
        present(vc, animated: true, completion: nil)
        }
    
    @IBAction func actionPrivacyPolicy(_ sender: UIButton) {
            self.loadPrivacyPolicy()
        }


    func setBUttonAttribute(_ button:UIButton,_ text:String,yourAttributes:[NSAttributedString.Key: Any]){
        let attributeString = NSMutableAttributedString(
            string: text,
            attributes: yourAttributes
        )
        button.setAttributedTitle(attributeString, for: .normal)
    }

    func setContinueButtonUI(isEnteredOtp:Bool){
        self.continueButton.backgroundColor = isEnteredOtp ? AppColor.Punch : AppColor.Punch.withAlphaComponent(0.5)
        self.continueButton.isUserInteractionEnabled = isEnteredOtp ? true : false
//        self.wrongOTPPopUp.isHidden = isEnteredOtp ? true : false
    }

    // Timer For Resend OTP
    private func startTimer(){
        self.secondsRemaining = 60
        self.setResendButtonInteration(isHide: true)
        if timer == nil {
            timer =  Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { (Timer) in
                if self.secondsRemaining > 0 {
                    let minutes = self.secondsRemaining / 60
                    let seconds = self.secondsRemaining % 60
                    self.timerLabel.text = String(format: "%02d:%02d", minutes, seconds)
                    self
                        .secondsRemaining -= 1
                } else {
                    self.stopTimer()
                }
            }
        }
    }

    private func stopTimer(){
        timer?.invalidate()
        timer = nil
        self.timerLabel.text = "01:00"
        self.setResendButtonInteration(isHide: false)
    }

    private func navigateToNextScreen(){
        self.stopTimer()
        let aUserDetailsViewController = UserDetailsViewController.instantiateFromStoryboard()
        aUserDetailsViewController.signUpOption = self.signUpOption
        aUserDetailsViewController.emailID = self.emailID
        aUserDetailsViewController.phoneNumber = self.phoneNumber
        aUserDetailsViewController.phoneCode = self.phoneCode
        self.navigationController?.pushViewController(aUserDetailsViewController, animated: true)
    }
}

extension VerifyOTPViewController: OTPFieldViewDelegate {

    func enteredOTP(otp: String, textFieldView: UIView) {
        self.enterOtp = otp
        self.isAllOTPEntered = otp.count == 6 ? true : false
        if otp.count < 6 {
            setContinueButtonUI(isEnteredOtp: false)
        }
        print("OTPString: \(otp)")
    }

    func hasEnteredAllOTP(hasEnteredAll hasEntered: Bool) -> Bool {
        print("Has entered all OTP? \(hasEntered)")
        self.setContinueButtonUI(isEnteredOtp:hasEntered)
        return false
    }

    func shouldBecomeFirstResponderForOTP(otpTextFieldIndex index: Int) -> Bool {
        // Deactivate any active top constraints
        self.wrongOTPPopUp.isHidden = true

        if index == 0 || self.otpTextFieldView.secureEntryData[index] != "" {
            self.topConstraintEqual?.isActive = false
            self.topConstraintGreaterThanOrEqual?.isActive = false

            self.topConstraintEqual = self.acceptPrivacyLabel.topAnchor.constraint(equalTo: self.resendOTPStack.bottomAnchor, constant: 15)
            self.topConstraintEqual?.isActive = true

            UIView.animate(withDuration: 0.3) {
                self.topImageHeight.constant = 0
                self.topImageBottom.constant = 60
                self.scrollView.setContentOffset(CGPoint(x: 0, y: -self.scrollView.contentInset.top), animated: true)
                // Disable vertical scrolling
                self.view.layoutIfNeeded()
            }
        }

        if self.isAllOTPEntered ?? false && self.otpTextFieldIndex != index {
            self.isDoneEditing = false
        }else{
            self.isDoneEditing = true
        }
        self.otpTextFieldIndex = index
        return true
    }

    func didEndEditing(text: String) {
        print("rgrg")
        if !(self.isDoneEditing ?? false) || !(self.isAllOTPEntered ?? false) {
            print("sdgfsfg")
        }else{
            // Deactivate any active top constraints
            self.topConstraintEqual?.isActive = false
            self.topConstraintGreaterThanOrEqual?.isActive = false

            // Create a greater than or equal to constraint
            self.topConstraintGreaterThanOrEqual = self.acceptPrivacyLabel.topAnchor.constraint(greaterThanOrEqualTo: self.resendOTPStack.bottomAnchor, constant: 10)
            self.topConstraintGreaterThanOrEqual?.isActive = true

            // Animate the change if needed
            UIView.animate(withDuration: 0.3) {
                self.topImageHeight.constant = 440.0
                self.topImageBottom.constant = -130
                self.view.layoutIfNeeded()
            }
        }
        self.isDoneEditing = true
    }
}
