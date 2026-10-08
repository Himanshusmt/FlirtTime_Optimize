import UIKit

// MARK: - Selection Header Bar

final class ChatSelectionHeaderBar: UIView {

    private let countLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont(name: "Fredoka-SemiBold", size: 17) ?? UIFont.chat(.bold, size: 17)
        lbl.textColor = ChatTheme.textPrimary
        lbl.textAlignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "xmark"), for: .normal)
        btn.tintColor = ChatTheme.textPrimary
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        btn.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let separator: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.gray.withAlphaComponent(0.2)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    var onCancel: (() -> Void)?
    var onSelectAll: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = .white
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(cancelButton)
        addSubview(countLabel)
        addSubview(separator)

        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 32),
            cancelButton.heightAnchor.constraint(equalToConstant: 32),

            countLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            heightAnchor.constraint(equalToConstant: 52),
        ])

        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        enforceRTLIfNeeded()
    }

    func configure(count: Int) {
        countLabel.text = String(format: ChatStrings.chat_selectedCountFormat.localizedString(), count)
    }

    @objc private func cancelTapped() {
        onCancel?()
    }
}

// MARK: - Selection Action Bar

final class ChatSelectionActionBar: UIView {

    private let topSeparator: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.gray.withAlphaComponent(0.2)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let stackView: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.distribution = .fillProportionally
        s.alignment = .center
        s.spacing = 4
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    var onForward: (() -> Void)?
    var onDeleteForMe: (() -> Void)?
    var onDeleteForEveryone: (() -> Void)?

    private var canDeleteForEveryone: Bool = false
    private var canForward: Bool = true
    private var hasSelection: Bool = false
    private var isChannel: Bool = false

    // Button containers for enabling/disabling
    private var forwardContainer: UIView?
    private var deleteForMeContainer: UIView?
    private var deleteForEveryoneContainer: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = .systemBackground
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(topSeparator)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            topSeparator.topAnchor.constraint(equalTo: topAnchor),
            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(safeAreaBottom() + 8)),
        ])
        enforceRTLIfNeeded()
    }

    func configure(hasSelection: Bool, canDeleteForEveryone: Bool, canForward: Bool = true, isChannel: Bool = false) {
        self.hasSelection = hasSelection
        self.canDeleteForEveryone = canDeleteForEveryone
        self.canForward = canForward
        self.isChannel = isChannel
        rebuildButtons()
    }

    private func rebuildButtons() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        forwardContainer = nil
        deleteForMeContainer = nil
        deleteForEveryoneContainer = nil


        // Delete for me — DMs and channels (scope=me)
        let delMe = makeActionItem(
            icon: "trash",
            title: ChatStrings.chat_deleteForMe.localizedString(),
            color: .systemRed,
            action: { [weak self] in self?.onDeleteForMe?() }
        )
        deleteForMeContainer = delMe
        stackView.addArrangedSubview(delMe)

        // Delete for everyone
        if canDeleteForEveryone {
            stackView.addArrangedSubview(makeVerticalSeparator())
            let delAll = makeActionItem(
                icon: "trash.fill",
                title: ChatStrings.chat_deleteForEveryone.localizedString(),
                color: .systemRed.withAlphaComponent(0.8),
                action: { [weak self] in self?.onDeleteForEveryone?() }
            )
            deleteForEveryoneContainer = delAll
            stackView.addArrangedSubview(delAll)
        }

        applyEnabledState()
    }

    private func applyEnabledState() {
        let enabled = hasSelection
        let alpha: CGFloat = enabled ? 1.0 : 0.35

        // Forward button respects both hasSelection and canForward
        let forwardEnabled = enabled && canForward
        forwardContainer?.alpha = forwardEnabled ? 1.0 : 0.35
        forwardContainer?.isUserInteractionEnabled = forwardEnabled

        // Delete buttons only respect hasSelection
        [deleteForMeContainer, deleteForEveryoneContainer].forEach { container in
            container?.alpha = alpha
            container?.isUserInteractionEnabled = enabled
        }
    }

    private func makeActionItem(
        icon: String,
        title: String,
        color: UIColor,
        action: @escaping () -> Void
    ) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        let baseIcon = UIImage(systemName: icon)
        let isRTL = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
        iconView.image = isRTL ? baseIcon?.withHorizontallyFlippedOrientation() : baseIcon
        iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        iconView.preferredSymbolConfiguration = config
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = title
        label.font = UIFont(name: "Fredoka-Medium", size: 11) ?? UIFont.chat(.medium, size: 11)
        label.textColor = color
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -2),
            label.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),

            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])

        let btn = UIButton(type: .system)
        btn.backgroundColor = .clear
        btn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: container.topAnchor),
            btn.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            btn.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)

        return container
    }

    private func makeVerticalSeparator() -> UIView {
        let sep = UIView()
        sep.backgroundColor = UIColor.gray.withAlphaComponent(0.2)
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.widthAnchor.constraint(equalToConstant: 0.5).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return sep
    }

    private func safeAreaBottom() -> CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first(where: { $0.isKeyWindow })
        return window?.safeAreaInsets.bottom ?? 0
    }
}
