//
//  SceneDelegate.swift
//  FlirttimeNew
//
//  Created by Aasif on 07/10/26.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        showSplashAsRoot()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        ChatSocketSessionCoordinator.shared.handleApplicationWillEnterForeground()
    }

    private func showSplashAsRoot() {
        let splashVC = SplashScreenVC.instantiateFromStoryboard()
        let navController = UINavigationController(rootViewController: splashVC)
        navController.isNavigationBarHidden = true
        setRootViewController(navController, animated: false)
    }

    private func setRootViewController(_ vc: UIViewController, animated: Bool = true) {
        guard let window = self.window else { return }
        window.rootViewController = vc
        window.makeKeyAndVisible()

        if animated {
            UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve, animations: nil, completion: nil)
        }
    }

    func changeRootViewController(_ viewController: UIViewController, animated: Bool = true) {
        let navController = UINavigationController(rootViewController: viewController)
        navController.isNavigationBarHidden = true
        setRootViewController(navController, animated: animated)
    }
}
