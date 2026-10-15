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

    /// Shows a red dot at the top-right of the view while there are unread notifications.
    /// `inset` is the dot's distance from the top and trailing edges.
    func bindNotificationBadge(inset: CGFloat = 8) {
        let dot = UIView()
        dot.backgroundColor = AppColor.Punch
        dot.layer.cornerRadius = 4.5
        dot.layer.borderWidth = 1.5
        dot.layer.borderColor = AppColor.AppWhite.cgColor
        dot.isUserInteractionEnabled = false
        dot.isHidden = true
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 9),
            dot.heightAnchor.constraint(equalToConstant: 9),
            dot.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            dot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset)
        ])

        let subscription = NotificationBadgeStore.shared.$unreadCount
            .receive(on: DispatchQueue.main)
            .sink { [weak dot] count in
                dot?.isHidden = count == 0
            }
        objc_setAssociatedObject(self, &Self.notificationBadgeKey, subscription, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
