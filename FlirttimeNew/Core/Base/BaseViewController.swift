//
//  BaseViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 04/04/24.
//


import UIKit
import SafariServices
import RxSwift
import Swinject

class BaseViewController: UIViewController {
    
    typealias CompletionHandler = (_ success:Bool) -> Void
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .darkContent
    }
    
    var aFlirtCustomPopUp =  FlirtCustomPopUp()
    var aDeleteCustomPopUp = DeleteCustomPopUp()
    var aCustomToastView = CustomToastView()
    var aActivityIndicator = ActivityIndicator()
    private let onboardingDisposeBag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let window = UIApplication.shared.windows.first {
            aFlirtCustomPopUp = FlirtCustomPopUp(frame: window.bounds)
            aDeleteCustomPopUp = DeleteCustomPopUp(frame: window.bounds)
            aCustomToastView = CustomToastView(frame: window.bounds)
            aActivityIndicator = ActivityIndicator(frame: window.bounds)
        }
    }
    
    /// `ActivityIndicator.show()` finishes asynchronously, so `hide()` is queued after it
    /// to avoid a stuck loader when an API fails synchronously (e.g. no internet).
    func setLoading(_ isLoading: Bool) {
        if isLoading {
            aActivityIndicator.show()
        } else {
            DispatchQueue.main.async { self.aActivityIndicator.hide() }
        }
    }

    /// Completed profiles go home. Everyone else resumes at `currentStep` from onboarding progress.
    func routeAfterLogin(isProfileComplete: Bool, signUpOption: SignUpOption) {
        UserDataManager.shared.isOTPVerificationDone = true
        if isProfileComplete {
            showOnboardingStep(.completed, signUpOption: signUpOption)
            return
        }
        let sessionManager = Container.appContainer.resolve(AppSessionManager.self)!
        setLoading(true)
        sessionManager.onboardingProgress()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] progress in
                self?.setLoading(false)
                self?.showOnboardingStep(progress.resolvedStep, signUpOption: signUpOption)
            }, onFailure: { [weak self] _ in
                self?.setLoading(false)
                self?.showOnboardingStep(.basicInfo, signUpOption: signUpOption)
            })
            .disposed(by: onboardingDisposeBag)
    }

    private func showOnboardingStep(_ step: OnboardingStep, signUpOption: SignUpOption) {
        UserDataManager.shared.isHomePageRedirect = step == .completed
        if step == .completed {
            guard let sceneDelegate = view.window?.windowScene?.delegate as? SceneDelegate else { return }
            sceneDelegate.changeRootViewController(AppTabBarController.instantiateFromStoryboard())
            return
        }
        let viewController = OnboardingFlow.viewController(for: step, signUpOption: signUpOption)
        if let navigationController {
            navigationController.pushViewController(viewController, animated: true)
        } else if let sceneDelegate = view.window?.windowScene?.delegate as? SceneDelegate {
            sceneDelegate.changeRootViewController(viewController)
        }
    }

    func showNewAlertPopUp(Title:String, Msg:String, isSuccess:Bool, CompletionHandler:@escaping CompletionHandler) {
        let customView = CustomAlertVW(frame: CGRect(x: 0, y: 44, width: self.view.frame.width , height: 82))
        customView.setView(Title: Title, Msg: Msg, isSuccess: isSuccess)
        let window = UIApplication.shared.windows.first
        window?.addSubview(customView)
        customView.callBackAction = {
            CompletionHandler(true)
        }
    }

    func showImageAlertPopUp(TitleMsg:String, TitleBtn:String) {
        let customView = CustomImagePopUpVC(frame: CGRect(x: 0, y: 0, width: self.view.frame.width , height: self.view.frame.height))
        customView.showMessage(btnTitle: TitleBtn, msg: TitleMsg)
        let window = UIApplication.shared.windows.first
        window?.addSubview(customView)
    }

    func showSubscriptionPopUp(isToChatView:Bool? = false, chatUserID:Int? = nil, isToHomeView:Bool? = false, subscriptionPopUpType: SubscriptionPopUpType?) {
        // Server `isSubscribed` is the source of truth — don't upsell Premium members.
        guard !FreeTierLimitsStore.shared.isPremium else { return }

        let customView = SubscriptionPopUp(frame: CGRect(x: 0, y: 0, width: self.view.frame.width , height: self.view.frame.height))
        if isToHomeView == true {
            customView.isToHome = true
        }
        if subscriptionPopUpType != nil {
            customView.configurePopupView(subcriptionType: subscriptionPopUpType ?? .compliment)
        }

        let window = UIApplication.shared.windows.first
        window?.addSubview(customView)
        customView.subsUpdateAction = { [weak self] in
            // TODO: open ChatViewController for `chatUserID` after purchase when `isToChatView` once chat is ported.
            self?.openPremium(source: subscriptionPopUpType)
        }
    }

    func openPremium(source: SubscriptionPopUpType? = nil, onPurchased: (() -> Void)? = nil) {
        let premiumVC = PremiumViewController(source: source)
        premiumVC.onPurchased = onPurchased
        if let navigationController {
            navigationController.pushViewController(premiumVC, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: premiumVC)
            nav.isNavigationBarHidden = true
            nav.modalPresentationStyle = .fullScreen
            present(nav, animated: true)
        }
    }

    func openCoinShop(onPurchased: (() -> Void)? = nil) {
        let coinsVC = CoinsViewController()
        coinsVC.onPurchased = onPurchased
        if let navigationController {
            navigationController.pushViewController(coinsVC, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: coinsVC)
            nav.isNavigationBarHidden = true
            nav.modalPresentationStyle = .fullScreen
            present(nav, animated: true)
        }
    }

    /// Placeholder for destinations whose module has not been ported yet.
    func showComingSoon(_ feature: String) {
        self.aCustomToastView.show(message: "\(feature) is coming soon")
    }

    func checkHideCustomButton(hide:Bool? = true) {
        guard let appTabBarController = self.tabBarController as? AppTabBarController else { return }
        appTabBarController.setCustomButtonHidden(hide ?? true)
    }

    func hideShowTabBar(isHide: Bool) {
        guard let tabBar = self.tabBarController?.tabBar else { return }

        if let appTabBarController = self.tabBarController as? AppTabBarController {
            AppTabBarController.buttonD.isHidden = isHide
            appTabBarController.setCustomButtonHidden(isHide)
        }

        let tabBarHeight = tabBar.frame.size.height
        let screenHeight = self.view.frame.size.height
        var newFrame = tabBar.frame

        newFrame.origin.y = isHide ? screenHeight + tabBarHeight : screenHeight - tabBarHeight

        UIView.animate(withDuration: 0.5) {
            tabBar.frame = newFrame
        }
    }
    
    func loadPrivacyPolicy() {
        guard let url = URL(string: "https://flirttime.in/page/privacy-policy") else { return }
        let safariVC = SFSafariViewController(url: url)
        safariVC.modalPresentationStyle = .pageSheet // Optional, for iPad compatibility
        present(safariVC, animated: true, completion: nil)
    }

    func loadTermsAndConditions() {
        guard let url = URL(string: "https://flirttime.in/page/terms") else { return }
        let safariVC = SFSafariViewController(url: url)
        safariVC.modalPresentationStyle = .pageSheet
        present(safariVC, animated: true, completion: nil)
    }
}

extension UIViewController {
    func presentSubscriptionPopUp(_ type: SubscriptionPopUpType) {
        guard !FreeTierLimitsStore.shared.isPremium else { return }
        let customView = SubscriptionPopUp(frame: UIScreen.main.bounds)
        customView.configurePopupView(subcriptionType: type)
        UIApplication.shared.windows.first?.addSubview(customView)
        customView.subsUpdateAction = { [weak self] in
            let premiumVC = PremiumViewController(source: type)
            if let navigationController = self?.navigationController {
                navigationController.pushViewController(premiumVC, animated: true)
            } else if let self {
                let nav = UINavigationController(rootViewController: premiumVC)
                nav.isNavigationBarHidden = true
                nav.modalPresentationStyle = .fullScreen
                self.present(nav, animated: true)
            }
        }
    }
}
