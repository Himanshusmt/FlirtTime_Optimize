//
//  VerificationDoneViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 06/05/24.
//

import UIKit

class VerificationDoneViewController: BaseViewController, Instantiable {
    
    static var storyboardName: StringConvertible {
        return StoryboardName.signUp
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }


    @IBAction func continueButtonTapped(_ sender: UIButton) {
        UserDataManager.shared.isHomePageRedirect = true
        guard let sceneDelegate = self.view.window?.windowScene?.delegate as? SceneDelegate else { return }
        sceneDelegate.changeRootViewController(AppTabBarController.instantiateFromStoryboard())
    }

}
