//
//  NotificationBadgeStore.swift
//  FlirttimeNew
//

import Combine
import RxSwift
import Swinject
import UIKit

/// Unread notification count (`GET notifications/counts`) shared by every bell button.
final class NotificationBadgeStore {

    static let shared = NotificationBadgeStore()

    @Published private(set) var unreadCount = 0

    private let sessionManager: AppSessionManager
    private var request: Disposable?

    private init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    func refresh() {
        guard sessionManager.isLoggedIn else {
            set(unread: 0)
            return
        }
        request?.dispose()
        request = sessionManager.notificationCounts()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] counts in
                self?.set(unread: counts.unread)
            })
    }

    func set(unread: Int) {
        unreadCount = max(0, unread)
    }
}

extension UIView {

    private static var notificationBadgeKey: UInt8 = 0

    /// Shows the unread notification count ("9+" above 9) at the top-right of the view; hidden at 0.
    /// `inset` positions the badge's center relative to the top and trailing edges.
    func bindNotificationBadge(inset: CGFloat = 8) {
        let badgeSize: CGFloat = 18
        let badge = UILabel()
        badge.backgroundColor = AppColor.Punch
        badge.textColor = .white
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.textAlignment = .center
        badge.layer.cornerRadius = badgeSize / 2
        badge.layer.borderWidth = 1.5
        badge.layer.borderColor = AppColor.AppWhite.cgColor
        badge.clipsToBounds = true
        badge.isUserInteractionEnabled = false
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        NSLayoutConstraint.activate([
            badge.heightAnchor.constraint(equalToConstant: badgeSize),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: badgeSize),
            badge.centerYAnchor.constraint(equalTo: topAnchor, constant: inset),
            badge.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -inset)
        ])

        let subscription = NotificationBadgeStore.shared.$unreadCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak badge] count in
                guard let badge else { return }
                badge.isHidden = count == 0
                badge.text = count > 9 ? " 9+ " : "\(count)"
                badge.accessibilityLabel = "\(count) unread notifications"
                self?.accessibilityValue = count == 0 ? nil : "\(count) unread"
            }
        objc_setAssociatedObject(self, &Self.notificationBadgeKey, subscription, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
