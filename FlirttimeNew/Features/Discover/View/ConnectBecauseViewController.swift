//
//  ConnectBecauseViewController.swift
//  FlirttimeNew
//
//  Optional reasons attached to a connection from the full Vibe Profile.
//

import UIKit

final class ConnectBecauseViewController: UIViewController {

    var onSend: (([ConnectReason]) -> Void)?

    private let profile: VibeProfile
    private var selected: [ConnectReason] = []
    private var buttons: [(reason: ConnectReason, button: UIButton)] = []

    init(profile: VibeProfile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Reasons that would be untrue for this profile are not offered.
    private var availableReasons: [ConnectReason] {
        ConnectReason.allCases.filter { reason in
            switch reason {
            case .sameInterests: return !profile.sharedInterests.isEmpty
            case .likedMoment: return !profile.moments.isEmpty
            default: return true
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite

        let titleLabel = UILabel.vibeLabel(.bold, 22, style: .title2, color: AppColor.AppBlack, lines: 0)
        titleLabel.text = "Connect because…"
        titleLabel.accessibilityTraits = .header
        let subtitleLabel = UILabel.vibeLabel(.regular, 15, color: AppColor.DoveGray, lines: 0)
        subtitleLabel.text = "Optional: let \(profile.displayName) know what caught your eye."

        let reasonsStack = UIStackView()
        reasonsStack.axis = .vertical
        reasonsStack.spacing = 10
        for reason in availableReasons {
            let button = UIButton(configuration: reasonConfiguration(reason, isSelected: false))
            button.contentHorizontalAlignment = .leading
            button.accessibilityLabel = reason.rawValue
            button.addAction(UIAction { [weak self] _ in self?.toggle(reason) }, for: .touchUpInside)
            reasonsStack.addArrangedSubview(button)
            buttons.append((reason, button))
        }

        var sendConfig = UIButton.Configuration.filled()
        sendConfig.cornerStyle = .capsule
        sendConfig.baseBackgroundColor = AppColor.Punch
        sendConfig.image = UIImage(systemName: "heart.fill")
        sendConfig.imagePadding = 8
        sendConfig.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        sendConfig.attributedTitle = AttributedString("Send Connection", attributes: AttributeContainer([.font: VibeFont.scaled(.medium, 17)]))
        let sendButton = UIButton(configuration: sendConfig)
        sendButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onSend?(self.selected)
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, reasonsStack, sendButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(20, after: subtitleLabel)
        stack.setCustomSpacing(24, after: reasonsStack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private func reasonConfiguration(_ reason: ConnectReason, isSelected: Bool) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .large
        config.baseBackgroundColor = isSelected ? AppColor.Lavenderblush : AppColor.AthensGray
        config.baseForegroundColor = isSelected ? AppColor.Punch : AppColor.MineShaft
        config.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        config.imagePadding = 10
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        config.attributedTitle = AttributedString(reason.rawValue, attributes: AttributeContainer([.font: VibeFont.scaled(.medium, 16)]))
        return config
    }

    private func toggle(_ reason: ConnectReason) {
        if let index = selected.firstIndex(of: reason) {
            selected.remove(at: index)
        } else {
            selected.append(reason)
        }
        for entry in buttons {
            let isSelected = selected.contains(entry.reason)
            entry.button.configuration = reasonConfiguration(entry.reason, isSelected: isSelected)
            entry.button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }
}
