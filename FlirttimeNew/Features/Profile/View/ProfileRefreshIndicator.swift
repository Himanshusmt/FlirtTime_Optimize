//
//  ProfileRefreshIndicator.swift
//  FlirttimeNew
//
//  Pull-to-refresh spinner for the profile screens. The cover photo stretches over the area where
//  UIRefreshControl draws, so this badge sits above the scroll view, just below the status bar.
//

import UIKit

final class ProfileRefreshIndicator: UIView {

    static let size: CGFloat = 38
    /// Pull distance at which the badge is fully opaque.
    private static let fullPullDistance: CGFloat = 70

    private let spinner = UIActivityIndicatorView(style: .medium)
    private(set) var isRefreshing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor.black.withAlphaComponent(0.45)
        layer.cornerRadius = Self.size / 2
        alpha = 0
        spinner.color = .white
        spinner.hidesWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        isAccessibilityElement = true
        accessibilityLabel = "Refreshing"
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Pins the badge to the top center of `view`, below the safe area.
    func install(in view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: view.centerXAnchor),
            topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size)
        ])
    }

    /// Fades the badge in with the pull; ignored while a refresh is running.
    func update(pullDistance: CGFloat) {
        guard !isRefreshing else { return }
        let progress = min(1, max(0, pullDistance / Self.fullPullDistance))
        alpha = progress
        if progress > 0 {
            if !spinner.isAnimating { spinner.startAnimating() }
        } else {
            spinner.stopAnimating()
        }
    }

    func beginRefreshing() {
        isRefreshing = true
        accessibilityElementsHidden = false
        spinner.startAnimating()
        UIView.animate(withDuration: 0.15) { self.alpha = 1 }
    }

    func endRefreshing() {
        guard isRefreshing else { return }
        isRefreshing = false
        accessibilityElementsHidden = true
        UIView.animate(withDuration: 0.25, animations: { self.alpha = 0 }, completion: { _ in
            if !self.isRefreshing { self.spinner.stopAnimating() }
        })
    }
}
