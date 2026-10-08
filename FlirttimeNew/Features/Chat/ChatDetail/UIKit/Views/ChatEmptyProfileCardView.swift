//
//  ChatEmptyProfileCardView.swift
//  FlirttimeNew
//
//  Profile summary shown in place of the message list while a 1:1 conversation has no messages.
//

import UIKit
import Kingfisher

final class ChatEmptyProfileCardView: UIView {

    struct Profile {
        let name: String
        var age: Int?
        var avatarURL: String?
        var distanceMiles: Int?
        var interests: [String] = []
    }

    var onProfile: (() -> Void)?
    var onReport: (() -> Void)?

    private let avatarSize: CGFloat = 96

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.borderWidth = 3
        iv.layer.borderColor = ChatTheme.primary.cgColor
        iv.backgroundColor = ChatTheme.surface
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.semibold, size: 20)
        lbl.textColor = ChatTheme.textPrimary
        lbl.textAlignment = .center
        return lbl
    }()

    private let distanceLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(size: 13)
        lbl.textColor = ChatTheme.textSecondary
        lbl.textAlignment = .center
        return lbl
    }()

    private let chipsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }()

    private lazy var profileButton = makeActionButton(icon: ChatAssets.profile, title: ChatStrings.viewProfile.localizedString()) { [weak self] in
        self?.onProfile?()
    }

    private lazy var reportButton = makeActionButton(icon: ChatAssets.reportFlag, title: ChatStrings.chat_report.localizedString()) { [weak self] in
        self?.onReport?()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with profile: Profile) {
        if let age = profile.age {
            nameLabel.text = "\(profile.name), \(age)"
        } else {
            nameLabel.text = profile.name
        }

        distanceLabel.text = profile.distanceMiles.map { "\($0) miles away" }
        distanceLabel.isHidden = profile.distanceMiles == nil

        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        profile.interests.prefix(4).forEach { chipsStack.addArrangedSubview(makeChip($0)) }
        chipsStack.isHidden = profile.interests.isEmpty

        let placeholder = UIImage(named: ChatAssets.avatarPlaceholder)
        if let urlString = profile.avatarURL, let url = URL(string: urlString) {
            avatarImageView.kf.setImage(with: url, placeholder: placeholder)
        } else {
            avatarImageView.image = placeholder
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        let actions = UIStackView(arrangedSubviews: [profileButton, reportButton])
        actions.axis = .horizontal
        actions.spacing = 40
        actions.alignment = .top

        let stack = UIStackView(arrangedSubviews: [avatarImageView, nameLabel, distanceLabel, chipsStack, actions])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(14, after: avatarImageView)
        stack.setCustomSpacing(14, after: distanceLabel)
        stack.setCustomSpacing(24, after: chipsStack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        avatarImageView.layer.cornerRadius = avatarSize / 2
        NSLayoutConstraint.activate([
            avatarImageView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: avatarSize),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    private func makeChip(_ text: String) -> UIView {
        let label = PaddedLabel(insets: UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12))
        label.text = text
        label.font = UIFont.chat(.medium, size: 12)
        label.textColor = ChatTheme.primary
        label.backgroundColor = ChatTheme.primarySoft
        label.layer.cornerRadius = 14
        label.clipsToBounds = true
        return label
    }

    private func makeActionButton(icon: String, title: String, action: @escaping () -> Void) -> UIView {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: icon)?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = .white
        button.backgroundColor = ChatTheme.primary
        button.layer.cornerRadius = 26
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)

        let label = UILabel()
        label.text = title
        label.font = UIFont.chat(size: 12)
        label.textColor = ChatTheme.textPrimary
        label.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [button, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 52),
            button.heightAnchor.constraint(equalToConstant: 52),
        ])
        return stack
    }
}

private final class PaddedLabel: UILabel {
    private let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
