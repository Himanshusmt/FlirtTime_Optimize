import UIKit
import Kingfisher

final class ChatInAppNotificationBanner: UIView {

    private let data: InAppChatBannerData
    private let onTap: (InAppChatBannerData) -> Void

    private let containerView: UIView = {
        let v = UIView()
        v.backgroundColor = .systemBackground
        v.layer.cornerRadius = 16
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.15
        v.layer.shadowOffset = CGSize(width: 0, height: 4)
        v.layer.shadowRadius = 12
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let avatarView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.layer.cornerRadius = 22
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let avatarPlaceholder: UIView = {
        let v = UIView()
        v.backgroundColor = ChatTheme.primary.withAlphaComponent(0.15)
        v.layer.cornerRadius = 22
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let initialLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.bold, size: 18)
        lbl.textColor = ChatTheme.primary
        lbl.textAlignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.semibold, size: 15)
        lbl.textColor = .label
        lbl.lineBreakMode = .byTruncatingTail
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let subtitleLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(size: 13)
        lbl.textColor = .secondaryLabel
        lbl.numberOfLines = 2
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let timeLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(size: 11)
        lbl.textColor = .secondaryLabel
        lbl.text = ChatStrings.chat_now.localizedString()
        lbl.setContentHuggingPriority(.required, for: .horizontal)
        lbl.setContentCompressionResistancePriority(.required, for: .horizontal)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private var dismissTimer: Timer?
    private var hideConstraint: NSLayoutConstraint?
    private var showConstraint: NSLayoutConstraint?

    init(data: InAppChatBannerData, onTap: @escaping (InAppChatBannerData) -> Void) {
        self.data = data
        self.onTap = onTap
        super.init(frame: .zero)
        setupViews()
        configure()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        dismissTimer?.invalidate()
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = true

        containerView.addSubview(avatarView)
        containerView.addSubview(avatarPlaceholder)
        avatarPlaceholder.addSubview(initialLabel)
        containerView.addSubview(titleLabel)
        containerView.addSubview(subtitleLabel)
        containerView.addSubview(timeLabel)
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            avatarView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),

            avatarPlaceholder.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            avatarPlaceholder.widthAnchor.constraint(equalToConstant: 44),
            avatarPlaceholder.heightAnchor.constraint(equalToConstant: 44),

            initialLabel.centerXAnchor.constraint(equalTo: avatarPlaceholder.centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: avatarPlaceholder.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),

            timeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            timeLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:))))
        enforceRTLIfNeeded()
    }

    private func configure() {
        titleLabel.text = bannerTitle
        subtitleLabel.text = bannerSubtitle
        let initial = String(avatarInitial.prefix(1)).uppercased()
        initialLabel.text = initial

        if let url = data.senderAvatarURL {
            avatarView.isHidden = false
            avatarPlaceholder.isHidden = true
            avatarView.kf.setImage(with: url, placeholder: placeholderImage(initial: initial))
        } else {
            avatarView.isHidden = true
            avatarPlaceholder.isHidden = false
        }
    }

    private func placeholderImage(initial: String) -> UIImage {
        let size = CGSize(width: 44, height: 44)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            ChatTheme.primary.withAlphaComponent(0.15).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.chat(.bold, size: 18),
                .foregroundColor: ChatTheme.primary
            ]
            let textSize = initial.size(withAttributes: attrs)
            let point = CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2)
            initial.draw(at: point, withAttributes: attrs)
        }
    }

    func show(in parentView: UIView, below sibling: UIView? = nil) {
        guard superview == nil else { return }
        parentView.addSubview(self)

        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
        ])

        hideConstraint = topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor, constant: -80)
        showConstraint = topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor, constant: 4)

        hideConstraint?.isActive = true
        showConstraint?.isActive = false
        parentView.layoutIfNeeded()

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: []) {
            self.hideConstraint?.isActive = false
            self.showConstraint?.isActive = true
            parentView.layoutIfNeeded()
        }

        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss(completion: (() -> Void)? = nil) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard superview != nil else {
            completion?()
            return
        }

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            self.showConstraint?.isActive = false
            self.hideConstraint?.isActive = true
            self.superview?.layoutIfNeeded()
        }) { _ in
            self.removeFromSuperview()
            completion?()
        }
    }

    func forceRemove() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        showConstraint?.isActive = false
        hideConstraint?.isActive = false
        removeFromSuperview()
    }

    @objc private func handleTap() {
        let bannerData = data
        forceRemove()
        onTap(bannerData)
    }

    @objc private func handleSwipe(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        if gesture.state == .changed {
            if translation.y < 0 {
                transform = CGAffineTransform(translationX: 0, y: translation.y)
            }
        } else if gesture.state == .ended {
            if translation.y < -30 {
                dismiss()
            } else {
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
                    self.transform = .identity
                }
            }
        }
    }

    // MARK: - Display helpers

    private var bannerTitle: String {
        switch data.chatType {
        case "channel": return "\(ChatStrings.chat_channelLabel.localizedString()): \(data.groupName ?? "")"
        case "group": return data.groupName ?? data.senderName
        default: return data.senderName
        }
    }

    private var bannerSubtitle: String {
        switch data.chatType {
        case "group": return "\(data.senderName): \(data.messagePreview)"
        default: return data.messagePreview
        }
    }

    private var avatarInitial: String {
        switch data.chatType {
        case "group", "channel": return data.groupName ?? data.senderName
        default: return data.senderName
        }
    }
}
