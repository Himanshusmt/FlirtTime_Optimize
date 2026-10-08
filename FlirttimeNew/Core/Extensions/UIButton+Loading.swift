//
//  UIButton+Loading.swift
//  FlirttimeNew
//

import UIKit

extension UIButton {

    private var activityIndicatorTag: Int { return 999 }

    func showLoading(title: String? = nil) {
        self.isUserInteractionEnabled = false
        self.setTitle("", for: .normal)

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        spinner.tag = activityIndicatorTag

        self.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }

    func hideLoading(originalTitle: String = "Get Verify") {
        self.isUserInteractionEnabled = true
        self.setTitle(originalTitle, for: .normal)

        if let spinner = self.viewWithTag(activityIndicatorTag) as? UIActivityIndicatorView {
            spinner.stopAnimating()
            spinner.removeFromSuperview()
        }
    }
}
