//
//  ChangeEmailViewController.swift
//  FlirttimeNew
//
//  Two steps on one screen (both laid out in Settings.storyboard): enter the new address,
//  then confirm it with the code we email to it.
//

import UIKit
import Combine

final class ChangeEmailViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.settings
    }

    static let codeLength = 4
    private static let resendDelay = 30

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
    private var pendingEmail: String?
    private var resendTimer: Timer?
    private var resendSecondsLeft = 0

    private var enteredEmail: String {
        emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var enteredCode: String {
        codeTextField.text?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setBinding()
        codeSectionView.isHidden = true
        updateFieldFocus(emailFieldView, focused: false)
        updateFieldFocus(codeFieldView, focused: false)
        updatePrimaryButton()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
        viewModel.loadProfile()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resendTimer?.invalidate()
    }

    private func setBinding() {
        viewModel.$user.receive(on: DispatchQueue.main).sink { [weak self] user in
            guard let self, let user else { return }
            let email = user.email?.trimmingCharacters(in: .whitespaces) ?? ""
            self.currentEmailLabel.text = email.isEmpty ? "No email added yet" : email
        }.store(in: &cancellables)
    }

    private func updatePrimaryButton() {
        let isCodeStep = pendingEmail != nil
        let isValid = isCodeStep ? enteredCode.count == Self.codeLength : enteredEmail.isValidEmail()
        primaryButton.setTitle(isCodeStep ? "Verify & save" : "Send code", for: .normal)
        primaryButton.isEnabled = isValid
        primaryButton.alpha = isValid ? 1 : 0.5
    }

    private func updateFieldFocus(_ field: UIView, focused: Bool) {
        UIView.animate(withDuration: 0.2) {
            field.layer.borderColor = (focused ? AppColor.Punch : AppColor.Iron).cgColor
        }
    }

    private func sendCode(to email: String) {
        setLoading(true)
        viewModel.requestEmailChangeCode(for: email) { [weak self] result in
            guard let self else { return }
            self.setLoading(false)
            switch result {
            case .success:
                self.pendingEmail = email
                self.codeInfoLabel.text = "Enter the \(Self.codeLength)-digit code we sent to \(email)"
                self.emailTextField.isEnabled = false
                UIView.animate(withDuration: 0.25) {
                    self.codeSectionView.isHidden = false
                    self.view.layoutIfNeeded()
                }
                self.codeTextField.becomeFirstResponder()
                self.startResendCountdown()
                self.updatePrimaryButton()
            case .failure(let error):
                self.showNewAlertPopUp(Title: "Error", Msg: error.message, isSuccess: false) { _ in }
            }
        }
    }

    private func verify(email: String) {
        setLoading(true)
        viewModel.verifyEmailChange(email: email, code: enteredCode) { [weak self] result in
            guard let self else { return }
            self.setLoading(false)
            switch result {
            case .success:
                self.view.endEditing(true)
                self.aCustomToastView.show(message: "Your email has been updated")
                self.navigationController?.popViewController(animated: true)
            case .failure(let error):
                self.codeFieldView.layer.borderColor = AppColor.AlertBottomFailure.cgColor
                self.showNewAlertPopUp(Title: "Wrong code", Msg: error.message, isSuccess: false) { _ in }
            }
        }
    }

    private func startResendCountdown() {
        resendSecondsLeft = Self.resendDelay
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
        if let pendingEmail {
            verify(email: pendingEmail)
        } else {
            view.endEditing(true)
            sendCode(to: enteredEmail)
        }
    }

    @IBAction private func resendTapped(_ sender: UIButton) {
        guard let pendingEmail else { return }
        sendCode(to: pendingEmail)
    }

    @IBAction private func changeAddressTapped(_ sender: UIButton) {
        pendingEmail = nil
        resendTimer?.invalidate()
        codeTextField.text = nil
        emailTextField.isEnabled = true
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
