//
//  LoginOptionsViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 04/04/24.
//

import UIKit

class LoginOptionsViewController: BaseViewController,Instantiable {

    @IBOutlet weak var mainView: UIView!
    @IBOutlet weak var serviceTermsLabel: UILabel!

    static var storyboardName: StringConvertible {
        return StoryboardName.login
    }

    private let appleLoginViewModel = AppleLoginViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        bindAppleLogin()
    }

    private func bindAppleLogin() {
        appleLoginViewModel.onLoading = { [weak self] isLoading in
            self?.setLoading(isLoading)
        }
        appleLoginViewModel.onError = { [weak self] message in
            self?.aCustomToastView.show(message: message)
        }
        appleLoginViewModel.onLoggedIn = { [weak self] isProfileComplete in
            self?.routeAfterLogin(isProfileComplete: isProfileComplete, signUpOption: .apple)
        }
    }

    @IBAction func loginWithEmailButton(_ sender: UIButton) {
        self.navigateToNextScreen(.email)
    }

    @IBAction func loginWithPhoneNumberButton(_ sender: UIButton) {
        self.navigateToNextScreen(.phoneNumber)
    }

    @IBAction func loginWithAppleID(_ sender: UIButton) {
        appleLoginViewModel.signIn(from: view.window)
    }
    
    @IBAction func actionPrivacyPolicy(_ sender: UIButton) {
        self.loadPrivacyPolicy()
    }

    func navigateToNextScreen(_ selectedOption:SignUpOption){
        let aLoginViewController = LoginViewController.instantiateFromStoryboard()
        aLoginViewController.signUpOption = selectedOption
        self.navigationController?.pushViewController(aLoginViewController, animated: true)
    }
}
