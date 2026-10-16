//
//  ChangeEmailViewController.swift
//  FlirttimeNew
//
//  Two steps on one screen (both laid out in Settings.storyboard): enter the new email or phone,
//  then confirm it with the code we send to it.
//

import UIKit
import Combine

final class ChangeEmailViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.settings
    }

    static let codeLength = 6
    private static let resendDelay = 30
    private static let phoneDigits = 6...15

    var kind: SettingsViewModel.ContactKind = .email

    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var heroIconImageView: UIImageView!
    @IBOutlet private weak var heroTitleLabel: UILabel!
    @IBOutlet private weak var heroSubtitleLabel: UILabel!
    @IBOutlet private weak var currentIconImageView: UIImageView!
    @IBOutlet private weak var currentCaptionLabel: UILabel!
    @IBOutlet private weak var newValueCaptionLabel: UILabel!
    @IBOutlet private weak var currentEmailLabel: UILabel!
    @IBOutlet private weak var emailFieldView: UIView!
    @IBOutlet private weak var emailTextField: UITextField!
    @IBOutlet private weak var codeSectionView: UIView!
    @IBOutlet private weak var codeInfoLabel: UILabel!
    @IBOutlet private weak var codeFieldView: UIView!
    @IBOutlet private weak var codeTextField: UITextField!
    @IBOutlet private weak var resendButton: UIButton!
    @IBOutlet private weak var primaryButton: UIButton!

    private let viewModel = SettingsViewModel()
    private var cancellables: Set<AnyCancellable> = []
    private var pendingValue: String?
    private var isAdding = true
    private var resendTimer: Timer?
    private var resendSecondsLeft = 0
    private var countryCode = "+91"
    private var regionCode: String?
    private lazy var countryCodeButton = UIButton(type: .system)

    private var enteredValue: String {
        let text = emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch kind {
        case .email: return text.lowercased()
        case .phone: return text.filter(\.isNumber)
        }
    }

    private var isValueValid: Bool {
        switch kind {
        case .email: return enteredValue.isValidEmail()
        case .phone: return Self.phoneDigits.contains(enteredValue.count)
        }
    }

    /// The new value as shown to the user, e.g. "+91 9876543210".
    private func displayValue(_ value: String) -> String {
        kind == .phone ? "\(countryCode) \(value)" : value
    }

    private var enteredCode: String {
        codeTextField.text?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureForKind()
        applyAddOrChangeCopy()
        setBinding()
        codeSectionView.isHidden = true
        codeTextField.keyboardType = .numberPad
        codeTextField.textContentType = .oneTimeCode
        updateFieldFocus(emailFieldView, focused: false)
        updateFieldFocus(codeFieldView, focused: false)
        updatePrimaryButton()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
        viewModel.loadAccount()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resendTimer?.invalidate()
    }

    private func configureForKind() {
        guard kind == .phone else { return }
        titleLabel.text = "Change phone"
        heroIconImageView.image = UIImage(systemName: "iphone.gen3")
        heroTitleLabel.text = "Want to change your phone number?"
        heroSubtitleLabel.text = "We'll text a verification code to your new number to make sure it's yours."
        currentIconImageView.image = UIImage(systemName: "phone.fill")
        currentCaptionLabel.text = "Current phone"
        newValueCaptionLabel.text = "New phone number"
        emailTextField.placeholder = "Phone number"
        emailTextField.keyboardType = .phonePad
        emailTextField.textContentType = .telephoneNumber
        emailTextField.autocapitalizationType = .none

        if let data = CountryDataManager.shared.filterCountryData, let dialCode = data.dial_code {
            countryCode = dialCode
            regionCode = CountryDataManager.shared.regionCode
        }
        countryCodeButton.setTitleColor(AppColor.AppBlack, for: .normal)
        countryCodeButton.titleLabel?.font = emailTextField.font
        countryCodeButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        countryCodeButton.addTarget(self, action: #selector(countryCodeTapped), for: .touchUpInside)
        updateCountryCodeButton()
        emailTextField.leftView = countryCodeButton
        emailTextField.leftViewMode = .always
    }

    /// This screen is only opened to add a missing email or phone. Copy stays on "add" in that case.
    private func applyAddOrChangeCopy() {
        if kind == .email {
            titleLabel.text = isAdding ? "Add email" : "Change email"
            heroTitleLabel.text = isAdding ? "Add your email" : "Want to change your email?"
            heroSubtitleLabel.text = isAdding
                ? "We'll send a verification code to this address to make sure it's yours."
                : "We'll send a verification code to your new address to make sure it's yours."
            newValueCaptionLabel.text = isAdding ? "Email" : "New email"
        } else {
            titleLabel.text = isAdding ? "Add phone" : "Change phone"
            heroTitleLabel.text = isAdding ? "Add your phone number" : "Want to change your phone number?"
            heroSubtitleLabel.text = isAdding
                ? "We'll text a verification code to this number to make sure it's yours."
                : "We'll text a verification code to your new number to make sure it's yours."
            newValueCaptionLabel.text = isAdding ? "Phone number" : "New phone number"
        }
    }

    private func updateCountryCodeButton() {
        countryCodeButton.setTitle("\(countryCode) ▾", for: .normal)
        countryCodeButton.sizeToFit()
    }

    private func setBinding() {
        viewModel.$appUser.receive(on: DispatchQueue.main).sink { [weak self] user in
            guard let self, let user else { return }
            let current = (self.kind == .email ? user.email : user.phone)?.trimmingCharacters(in: .whitespaces) ?? ""
            let placeholder = self.kind == .email ? "No email added yet" : "No phone number added yet"
            self.isAdding = current.isEmpty
            self.currentEmailLabel.text = current.isEmpty ? placeholder : current
            self.applyAddOrChangeCopy()
        }.store(in: &cancellables)
    }

    private func updatePrimaryButton() {
        let isCodeStep = pendingValue != nil
        let isValid = isCodeStep ? enteredCode.count == Self.codeLength : isValueValid
        primaryButton.setTitle(isCodeStep ? "Verify & save" : "Send code", for: .normal)
        primaryButton.isEnabled = isValid
        primaryButton.alpha = isValid ? 1 : 0.5
    }

    private func updateFieldFocus(_ field: UIView, focused: Bool) {
        UIView.animate(withDuration: 0.2) {
            field.layer.borderColor = (focused ? AppColor.Punch : AppColor.Iron).cgColor
        }
    }

    private func sendCode(to value: String) {
        setLoading(true)
        viewModel.requestContactCode(kind: kind, value: value, countryCode: countryCode) { [weak self] result in
            guard let self else { return }
            self.setLoading(false)
            switch result {
            case .success(let resendAfter):
                self.pendingValue = value
                self.codeInfoLabel.text = "Enter the \(Self.codeLength)-digit code we sent to \(self.displayValue(value))"
                self.emailTextField.isEnabled = false
                self.countryCodeButton.isEnabled = false
                UIView.animate(withDuration: 0.25) {
                    self.codeSectionView.isHidden = false
                    self.view.layoutIfNeeded()
                }
                self.codeTextField.becomeFirstResponder()
                self.startResendCountdown(resendAfter)
                self.updatePrimaryButton()
            case .failure(let error):
                self.emailFieldView.layer.borderColor = AppColor.AlertBottomFailure.cgColor
                self.showNewAlertPopUp(Title: error.title ?? "Couldn't send code", Msg: error.message, isSuccess: false) { _ in }
            }
        }
    }

    private func verify() {
        setLoading(true)
        viewModel.verifyContactCode(kind: kind, code: enteredCode) { [weak self] result in
            guard let self else { return }
            self.setLoading(false)
            switch result {
            case .success:
                self.view.endEditing(true)
                let message: String
                if self.kind == .email {
                    message = self.isAdding ? "Your email has been added" : "Your email has been updated"
                } else {
                    message = self.isAdding ? "Your phone number has been added" : "Your phone number has been updated"
                }
                self.aCustomToastView.show(message: message)
                self.navigationController?.popViewController(animated: true)
            case .failure(let error):
                self.codeFieldView.layer.borderColor = AppColor.AlertBottomFailure.cgColor
                self.showNewAlertPopUp(Title: "Wrong code", Msg: error.message, isSuccess: false) { _ in }
            }
        }
    }

    private func startResendCountdown(_ seconds: Int? = nil) {
        resendSecondsLeft = seconds.flatMap { $0 > 0 ? $0 : nil } ?? Self.resendDelay
        resendTimer?.invalidate()
        updateResendButton()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.resendSecondsLeft -= 1
            if self.resendSecondsLeft <= 0 { timer.invalidate() }
            self.updateResendButton()
        }
    }

    private func updateResendButton() {
        let canResend = resendSecondsLeft <= 0
        resendButton.isEnabled = canResend
        resendButton.setTitle(canResend ? "Resend code" : "Resend code in \(resendSecondsLeft)s", for: .normal)
    }

    // MARK: - Actions

    @objc private func countryCodeTapped() {
        let picker = CountryListViewController.instantiateFromStoryboard()
        picker.regionCode = regionCode
        picker.selectionCallBack = { [weak self] selected in
            guard let self, let dialCode = selected.dial_code else { return }
            self.regionCode = selected.code
            self.countryCode = dialCode
            self.updateCountryCodeButton()
        }
        picker.modalPresentationStyle = .overCurrentContext
        navigationController?.present(picker, animated: true)
    }

    @IBAction private func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction private func textChanged(_ sender: UITextField) {
        if sender === codeTextField, enteredCode.count > Self.codeLength {
            codeTextField.text = String(enteredCode.prefix(Self.codeLength))
        }
        updatePrimaryButton()
    }

    @IBAction private func primaryTapped(_ sender: UIButton) {
        if pendingValue != nil {
            verify()
        } else {
            view.endEditing(true)
            sendCode(to: enteredValue)
        }
    }

    @IBAction private func resendTapped(_ sender: UIButton) {
        guard pendingValue != nil else { return }
        setLoading(true)
        viewModel.resendContactCode(kind: kind) { [weak self] result in
            guard let self else { return }
            self.setLoading(false)
            switch result {
            case .success(let resendAfter):
                self.aCustomToastView.show(message: "A new code is on its way")
                self.startResendCountdown(resendAfter)
            case .failure(let error):
                self.showNewAlertPopUp(Title: "Error", Msg: error.message, isSuccess: false) { _ in }
            }
        }
    }

    @IBAction private func changeAddressTapped(_ sender: UIButton) {
        pendingValue = nil
        resendTimer?.invalidate()
        codeTextField.text = nil
        emailTextField.isEnabled = true
        countryCodeButton.isEnabled = true
        UIView.animate(withDuration: 0.25) {
            self.codeSectionView.isHidden = true
            self.view.layoutIfNeeded()
        }
        emailTextField.becomeFirstResponder()
        updatePrimaryButton()
    }
}

extension ChangeEmailViewController: UITextFieldDelegate {

    func textFieldDidBeginEditing(_ textField: UITextField) {
        updateFieldFocus(textField === emailTextField ? emailFieldView : codeFieldView, focused: true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        updateFieldFocus(textField === emailTextField ? emailFieldView : codeFieldView, focused: false)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if primaryButton.isEnabled {
            primaryTapped(primaryButton)
        } else {
            textField.resignFirstResponder()
        }
        return true
    }
}
