//
//  AppTabBarController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 08/05/24.
//

import UIKit

class AppTabBarController: UITabBarController, Instantiable {

    /// Tab order matches `Dashboard.storyboard`.
    private enum AppTab: Int {
        case moments = 0
        case explore = 1
        case discover = 2
        case messages = 3
        case profile = 4
    }

    static let buttonD = UIButton.init(type: .custom)

    static var buttonBottomConstraint: NSLayoutConstraint?

    static let customButton: UIButton = {
        let button = UIButton()
        button.layer.cornerRadius = 30
        return button
    }()

    static var storyboardName: StringConvertible {
        return StoryboardName.dashboard
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        UITabBar.appearance().unselectedItemTintColor = AppColor.Punch
        self.tabBar.tintColor = AppColor.Punch
        UITabBarItem.appearance().setTitleTextAttributes([NSAttributedString.Key.foregroundColor: AppColor.Punch], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([NSAttributedString.Key.font: UIFont.fredoka(.regular, size: 13)], for: .selected)
        self.selectedIndex = AppTab.moments.rawValue
        self.delegate = self
        setButton()
        buttonAction()
        SubscriptionPlanStore.shared.preloadIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupCustomButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NotificationManager.shared.consumePendingNotification()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if self.tabBar.isHidden == false {
            setupCustomButton()
        } else {
            setCustomButtonHidden(true)
        }
    }

    func setButton() {
        AppTabBarController.buttonD.frame  = CGRect(x: 100, y: 50, width: 100, height: 100)
        AppTabBarController.buttonD.backgroundColor = .clear
        self.view.insertSubview(AppTabBarController.buttonD, aboveSubview: self.tabBar)
    }

    func buttonAction() {
        AppTabBarController.buttonD.addTarget(self, action: #selector(self.setMyButton), for: .touchUpInside)
        NotificationCenter.default.post(name: Notification.Name("tabClicked"), object: nil, userInfo: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        AppTabBarController.buttonD.frame = CGRect.init(x: self.tabBar.center.x - 45, y: self.view.bounds.height - 115, width: 90, height: 90)
        AppTabBarController.buttonD.layer.cornerRadius = 45
    }

    private func setupCustomButton() {
        guard AppTabBarController.customButton.superview != view else { return }
        AppTabBarController.customButton.removeFromSuperview()
        let bottomConstraint = AppTabBarController.customButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        AppTabBarController.buttonBottomConstraint = bottomConstraint

        AppTabBarController.customButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(AppTabBarController.customButton)

        NSLayoutConstraint.activate([
            AppTabBarController.customButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomConstraint,
            AppTabBarController.customButton.widthAnchor.constraint(equalToConstant: 80),
            AppTabBarController.customButton.heightAnchor.constraint(equalToConstant: 70)
        ])

        AppTabBarController.customButton.addTarget(self, action: #selector(customButtonTapped), for: .touchUpInside)
    }

    @objc func customButtonTapped() {
        self.selectedIndex = AppTab.discover.rawValue
    }

    func setToHome() {
        DispatchQueue.main.async {
            self.selectedIndex = AppTab.discover.rawValue
        }
    }

    /// Hides both center tap targets; `buttonD` sits above pushed screens and would otherwise
    /// still switch to Discover when their bottom center is tapped.
    func setCustomButtonHidden(_ hidden: Bool) {
        AppTabBarController.buttonD.isHidden = hidden
        AppTabBarController.customButton.isHidden = hidden
        AppTabBarController.buttonBottomConstraint?.constant = hidden ? -40 : -20
        AppTabBarController.customButton.superview?.layoutIfNeeded()
    }

    @objc func setMyButton() {
        self.selectedIndex = AppTab.discover.rawValue
    }
}

// Tbbar didselect
extension AppTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        // TODO: restore the profile-verification gating from FlirtTime once the verification API is integrated.
        return true
    }
}
