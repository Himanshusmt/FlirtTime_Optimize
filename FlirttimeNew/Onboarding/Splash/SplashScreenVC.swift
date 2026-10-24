//
//  SplashScreenVC.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 04/04/24.
//


import UIKit
import RxSwift
import Swinject

class SplashScreenVC: UIViewController,Instantiable {
    
    @IBOutlet weak var constraintCircle: NSLayoutConstraint!
    @IBOutlet weak var constraintFTlogo: NSLayoutConstraint!
    static var storyboardName: StringConvertible {
        return StoryboardName.splash
    }
    
    var window: UIWindow?
    private let disposeBag = DisposeBag()
    
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
    
    func navigateToNextScreen() {
        Task { @MainActor in
            self.continueSplashNavigationIfAllowed()
        }
    }

    @MainActor
    private func continueSplashNavigationIfAllowed() {
        // Kill/background CallKit answer presents on this splash window. Replacing the
        // root here would tear down the live audio/video call UI.
        if AgoraCallService.shared.hasActiveCallSession || CallKitManager.shared.hasReportedIncomingCall {
            AppLogger.killCall("Splash hold — incoming/active call phase=\(AgoraCallService.shared.phase)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.navigateToNextScreen()
            }
            return
        }

        let sessionManager = Container.appContainer.resolve(AppSessionManager.self)!
        guard UserDataManager.shared.isOTPVerificationDone == true else {
            routeByLocalState()
            return
        }
        guard sessionManager.isLoggedIn else {
            sessionManager.logout()
            routeByLocalState()
            return
        }
        UserDefaults.standard.set(true, forKey: "isUserLogIn")
        sessionManager.getMe()
            .subscribe(onSuccess: { [weak self] _ in
                DeviceTokenManager.shared.registerIfNeeded(force: true)
                Task { @MainActor in
                    self?.routeByLocalStateIfNoCall()
                }
            }, onFailure: { [weak self] error in
                if httpStatusCode(from: error) == 401 {
                    sessionManager.logout()
                }
                Task { @MainActor in
                    self?.routeByLocalStateIfNoCall()
                }
            })
            .disposed(by: disposeBag)
    }

    @MainActor
    private func routeByLocalStateIfNoCall() {
        if AgoraCallService.shared.hasActiveCallSession || CallKitManager.shared.hasReportedIncomingCall {
            AppLogger.killCall("Splash defer root swap — call still live")
            navigateToNextScreen()
            return
        }
        routeByLocalState()
    }

    private func routeByLocalState() {
        if UserDataManager.shared.isOTPVerificationDone == true {
            if UserDataManager.shared.isHomePageRedirect == true
                || UserDataManager.shared.appUser?.isProfileComplete == true {
                UserDataManager.shared.isHomePageRedirect = true
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

