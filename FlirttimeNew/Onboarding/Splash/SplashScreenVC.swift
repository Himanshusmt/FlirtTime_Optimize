//
//  SplashScreenVC.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 04/04/24.
//


import UIKit

class SplashScreenVC: UIViewController,Instantiable {
    
    @IBOutlet weak var constraintCircle: NSLayoutConstraint!
    @IBOutlet weak var constraintFTlogo: NSLayoutConstraint!
    static var storyboardName: StringConvertible {
        return StoryboardName.splash
    }
    
    var window: UIWindow?
    
    override func viewDidLoad() {
        super.viewDidLoad()
       
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.animateView()
            self.animationImageView()
            
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }
    
    func animationImageView(){
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
            self.navigateToNextScreen()
        }
    }
    
    func animateView() {
        UIView.animate(withDuration: 1.0) {
            self.constraintCircle.constant = 300.0
            self.view.layoutIfNeeded()
        } completion: { _ in
            UIView.animate(withDuration: 1.0) {
                self.constraintCircle.constant = 250.0
                self.view.layoutIfNeeded()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.animateFT()
        }
    }
    
   
    
    
    func animateFT() {
        UIView.animate(withDuration: 1.0) {
            self.constraintFTlogo.constant = 130.0
            self.view.layoutIfNeeded()
        }
    }
    
    func navigateToNextScreen(){
        if UserDataManager.shared.isOTPVerificationDone == true {
            if UserDataManager.shared.isHomePageRedirect == true {
                navigateToViewController(AppTabBarController.instantiateFromStoryboard())
            } else {
                let aUserDetailsViewController = UserDetailsViewController.instantiateFromStoryboard()
                navigateToViewController(aUserDetailsViewController)
            }
        } else if UserDataManager.shared.firstTime ?? false {
            let aLoginOptionsViewController = LoginOptionsViewController.instantiateFromStoryboard()
            self.navigationController?.pushViewController(aLoginOptionsViewController, animated: true)
        } else {
            let aIntroduction1VC = Introduction1VC.instantiateFromStoryboard()
            self.navigationController?.pushViewController(aIntroduction1VC, animated: true)
        }
    }
    
    func navigateToViewController(_ viewController: UIViewController, animated: Bool = true) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let sceneDelegate = windowScene.delegate as? SceneDelegate {
            let navController = UINavigationController(rootViewController: viewController)
            navController.isNavigationBarHidden = true
            
            sceneDelegate.window?.rootViewController = navController
            sceneDelegate.window?.makeKeyAndVisible()
        }
    }
}

