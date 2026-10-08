//
//  TabPlaceholderViewController.swift
//  FlirttimeNew
//

import UIKit

/// Stand-in root for tabs whose feature has not been ported yet (Home, Moments, Messages).
class TabPlaceholderViewController: BaseViewController {

    @objc var screenTitle: String = ""
    @objc var showsLogout: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        setUI()
    }

    private func setUI() {
        let logoImageView = UIImageView(image: UIImage(named: "FlirtTimeTitle"))
        logoImageView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.text = screenTitle
        titleLabel.font = UIFont.fredoka(.bold, size: 28)
        titleLabel.textColor = AppColor.Punch
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Coming soon"
        subtitleLabel.font = UIFont.fredoka(.regular, size: 16)
        subtitleLabel.textColor = AppColor.DoveGray
        subtitleLabel.textAlignment = .center

        let stackView = UIStackView(arrangedSubviews: [logoImageView, titleLabel, subtitleLabel])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        if showsLogout {
            let logoutButton = UIButton(type: .system)
            logoutButton.setTitle("Logout", for: .normal)
            logoutButton.titleLabel?.font = UIFont.fredoka(.medium, size: 16)
            logoutButton.setTitleColor(AppColor.AppWhite, for: .normal)
            logoutButton.backgroundColor = AppColor.Punch
            logoutButton.layer.cornerRadius = 25
            logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
            stackView.setCustomSpacing(40, after: subtitleLabel)
            stackView.addArrangedSubview(logoutButton)
            logoutButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        }

        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            logoImageView.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    @objc private func logoutTapped() {
        self.navigateToLoginScreen()
    }
}
