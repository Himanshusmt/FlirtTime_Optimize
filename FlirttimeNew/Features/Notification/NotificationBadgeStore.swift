//
//  NotificationBadgeStore.swift
//  FlirttimeNew
//

import Combine
import RxSwift
import Swinject
import UIKit

/// Unread notification count shared by every bell button.
/// Source of truth is `GET notifications/counts`, kept live by `notification:count`.
final class NotificationBadgeStore {

    static let shared = NotificationBadgeStore()

    @Published private(set) var unreadCount = 0

    private let sessionManager: AppSessionManager
    private var request: Disposable?
    private var listenerIds: [UUID] = []
    private var areListenersConfigured = false

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
        let next = max(0, unread)
        if Thread.isMainThread {
            unreadCount = next
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.unreadCount = next
            }
        }
    }

    func setupSocketListeners() {
        guard !areListenersConfigured else { return }
        areListenersConfigured = true

        let id = ChatSocketManager.shared.listenToEvent(SocketEvent.notificationCount.rawValue) { [weak self] data in
            self?.applySocketPayload(data)
        }
        listenerIds.append(id)
        refresh()
    }

    func invalidateSocketListeners() {
        for id in listenerIds {
            ChatSocketManager.shared.offEventById(id)
        }
        listenerIds.removeAll()
        areListenersConfigured = false
        request?.dispose()
        request = nil
    }

    private func applySocketPayload(_ data: [Any]) {
        let parsed = Self.parseCount(from: data)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let parsed {
                AppLogger.debug("[NotificationBadge] notification:count unread=\(parsed)")
                self.set(unread: parsed)
            } else {
                AppLogger.debug("[NotificationBadge] notification:count missing total — bump + REST confirm")
                self.set(unread: self.unreadCount + 1)
                self.refresh()
            }
        }
    }

    private static func parseCount(from data: [Any]) -> Int? {
        if let number = data.first as? NSNumber { return number.intValue }
        if let value = data.first as? Int { return value }
        if let string = data.first as? String, let value = Int(string) { return value }

        let root: [String: Any]
        if let dict = data.first as? [String: Any] {
            root = dict
        } else if let array = data.first as? [Any], let dict = array.first as? [String: Any] {
            root = dict
        } else {
            return nil
        }
        return NotificationCounts.unread(from: root)
    }
}

extension UIView {

    private static var notificationBadgeKey: UInt8 = 0

    /// Shows the unread notification count ("9+" above 9) at the top-right of the view; hidden at 0.
    /// `inset` positions the badge's center relative to the top and trailing edges.
    func bindNotificationBadge(inset: CGFloat = 8) {
        // The badge sits on the corner and must be allowed to draw outside this view.
        clipsToBounds = false
        let badgeSize: CGFloat = 18
        let badge = NotificationCountBadgeLabel()
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
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(badge)
        let overflow = badgeSize / 2 - inset
        NSLayoutConstraint.activate([
            badge.heightAnchor.constraint(equalToConstant: badgeSize),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: badgeSize),
            badge.topAnchor.constraint(equalTo: topAnchor, constant: -overflow),
            // Grow left so "9+" stays on-screen instead of clipping past the trailing edge.
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: overflow)
        ])

        let subscription = NotificationBadgeStore.shared.$unreadCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak badge] count in
                guard let badge else { return }
                badge.isHidden = count == 0
                badge.text = count > 9 ? "9+" : "\(count)"
                badge.invalidateIntrinsicContentSize()
                badge.accessibilityLabel = "\(count) unread notifications"
                self?.accessibilityValue = count == 0 ? nil : "\(count) unread"
            }
        objc_setAssociatedObject(self, &Self.notificationBadgeKey, subscription, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

private final class NotificationCountBadgeLabel: UILabel {
    private let insets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height)
    }
}
