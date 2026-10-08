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

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    @IBAction func loginWithEmailButton(_ sender: UIButton) {
        self.navigateToNextScreen(.email)
    }

    @IBAction func loginWithPhoneNumberButton(_ sender: UIButton) {
        self.navigateToNextScreen(.phoneNumber)
    }

    @IBAction func loginWithAppleID(_ sender: UIButton) {
        UserDataManager.shared.isOTPVerificationDone = true
        let aUserDetailsViewController = UserDetailsViewController.instantiateFromStoryboard()
        aUserDetailsViewController.signUpOption = .apple
        self.navigationController?.pushViewController(aUserDetailsViewController, animated: true)
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
