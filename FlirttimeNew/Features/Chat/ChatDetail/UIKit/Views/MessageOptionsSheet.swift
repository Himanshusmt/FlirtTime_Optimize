import UIKit

final class MessageOptionsSheet: UIView {

    // MARK: - Config

    private let sheetCornerRadius: CGFloat = 24
//    private let reactions = ["👍", "🔥", "💥", "🍀", "😍", "🙏", "😊", "🤗"]
    private var reactions: [String] {
        RecentReactionsManager.shared.reactions
    }

    // MARK: - Subviews

    private let dimmingView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.alpha = 0
        return v
    }()

    private let containerView: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius = 24
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.1
        v.layer.shadowRadius = 10
        v.layer.shadowOffset = CGSize(width: 0, height: -5)
        v.clipsToBounds = true
        return v
    }()

    private let scrollView = UIScrollView()
    private let contentStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 0
        s.alignment = .fill
        return s
    }()

    // MARK: - State

    private var sheetTopConstraint: NSLayoutConstraint?
    private var dimmingTap: UITapGestureRecognizer?
    private var panGesture: UIPanGestureRecognizer?
    private var panStartY: CGFloat = 0
    // MARK: - Callbacks

    var onDismiss: (() -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupViews() {
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        addSubview(dimmingView)
        addSubview(containerView)

        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        containerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: bottomAnchor),

            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        sheetTopConstraint = containerView.topAnchor.constraint(equalTo: topAnchor)
        sheetTopConstraint?.priority = .required
        sheetTopConstraint?.isActive = true

        // Scroll view inside container
        containerView.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        scrollView.showsVerticalScrollIndicator = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDimmingTap))
        dimmingTap = tap
        dimmingView.addGestureRecognizer(tap)
    }

    // MARK: - Public

    func present(in parent: UIView) {
        parent.addSubview(self)
        frame = parent.bounds

        let screenHeight = parent.bounds.height
        let targetHeight = min(contentSize(), screenHeight * 0.8)
        sheetTopConstraint?.constant = screenHeight

        layoutIfNeeded()

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            self.dimmingView.alpha = 0.4
        }
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: .curveEaseOut
        ) {
            self.sheetTopConstraint?.constant = screenHeight - targetHeight
            parent.layoutIfNeeded()
        }

        // Pan gesture for drag-to-dismiss
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        containerView.addGestureRecognizer(pan)
        panGesture = pan
    }

    func dismiss() {
        let screenHeight = bounds.height

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: .curveEaseOut, animations: {
            self.dimmingView.alpha = 0
            self.sheetTopConstraint?.constant = screenHeight
            self.superview?.layoutIfNeeded()
        }) { _ in
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }

    // MARK: - Build Content

    func configure(
        message: ConversationMessage,
        displayContent: String = "",
        canCopy: Bool,
        canTranslate: Bool,
        translateTitle: String?,
        canEdit: Bool,
        canDelete: Bool,
        canDeleteForEveryone: Bool,
        canPin: Bool,
        canForward: Bool,
        canReply: Bool,
        canRetry: Bool = false,
        canMessageInfo: Bool = false,
        isPinned: Bool,
        onReact: @escaping (String) -> Void,
        onCopy: @escaping () -> Void,
        onReply: @escaping () -> Void,
        onForward: @escaping () -> Void,
        onSelect: @escaping () -> Void,
        onTranslate: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onPin: @escaping () -> Void,
        onMessageInfo: @escaping () -> Void,
        onRetry: @escaping () -> Void = {},
        onDeleteForMe: @escaping () -> Void,
        onDeleteForEveryone: @escaping () -> Void,
        onPlusReaction: @escaping () -> Void
    ) {
        // Clear previous content
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Drag handle
        let handle = UIView()
        handle.backgroundColor = UIColor.gray.withAlphaComponent(0.4)
        handle.layer.cornerRadius = 3
        handle.translatesAutoresizingMaskIntoConstraints = false
        let handleWrapper = UIView()
        handleWrapper.translatesAutoresizingMaskIntoConstraints = false
        handleWrapper.addSubview(handle)
        NSLayoutConstraint.activate([
            handle.widthAnchor.constraint(equalToConstant: 48),
            handle.heightAnchor.constraint(equalToConstant: 5),
            handle.centerXAnchor.constraint(equalTo: handleWrapper.centerXAnchor),
            handle.topAnchor.constraint(equalTo: handleWrapper.topAnchor, constant: 10),
            handleWrapper.heightAnchor.constraint(equalToConstant: 26),
        ])
        contentStack.addArrangedSubview(handleWrapper)

        // Message preview: text messages show content, others show the type label
        let msgType = (message.messageType ?? message.type ?? "").lowercased()
        let isTextMessage = msgType == "text" || msgType.isEmpty
        let previewText: String
        if isTextMessage {
            previewText = displayContent.isEmpty
                ? (message.content ?? message.originalContentForDisplay ?? ChatStrings.chat_message.localizedString())
                : displayContent
        } else {
            previewText = previewFor(message: message)
        }
        let previewLabel = UILabel()
        previewLabel.text = previewText
        previewLabel.font = UIFont(name: "Fredoka-Regular", size: 15) ?? UIFont.chat(size: 15)
        previewLabel.textColor = ChatTheme.textPrimary
        previewLabel.numberOfLines = 1
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        let previewBg = UIView()
        previewBg.backgroundColor = UIColor.gray.withAlphaComponent(0.1)
        previewBg.layer.cornerRadius = 12
        previewBg.translatesAutoresizingMaskIntoConstraints = false
        previewBg.addSubview(previewLabel)
        NSLayoutConstraint.activate([
            previewLabel.topAnchor.constraint(equalTo: previewBg.topAnchor, constant: 12),
            previewLabel.leadingAnchor.constraint(equalTo: previewBg.leadingAnchor, constant: 14),
            previewLabel.trailingAnchor.constraint(equalTo: previewBg.trailingAnchor, constant: -14),
            previewLabel.bottomAnchor.constraint(equalTo: previewBg.bottomAnchor, constant: -12),
        ])

        let previewWrapper = UIView()
        previewWrapper.translatesAutoresizingMaskIntoConstraints = false
        previewBg.translatesAutoresizingMaskIntoConstraints = false
        previewWrapper.addSubview(previewBg)
        NSLayoutConstraint.activate([
            previewBg.topAnchor.constraint(equalTo: previewWrapper.topAnchor),
            previewBg.leadingAnchor.constraint(equalTo: previewWrapper.leadingAnchor, constant: 16),
            previewBg.trailingAnchor.constraint(equalTo: previewWrapper.trailingAnchor, constant: -16),
            previewBg.bottomAnchor.constraint(equalTo: previewWrapper.bottomAnchor),
        ])
        contentStack.addArrangedSubview(previewWrapper)
        addSpacer(height: 12)

        // Pending/failed messages show a minimal sheet (only delete + retry)
        let isMinimal = !canCopy && !canReply && !canForward && !canEdit && !canPin && !canTranslate

        // Reactions section — hidden for pending/failed messages
        if !isMinimal {
            let reactLabel = UILabel()
            reactLabel.text = ChatStrings.chat_react.localizedString()
            reactLabel.font = UIFont(name: "Fredoka-SemiBold", size: 20) ?? UIFont.chat(.bold, size: 20)
            reactLabel.textColor = ChatTheme.textPrimary
            reactLabel.translatesAutoresizingMaskIntoConstraints = false

            let reactionScrollView = UIScrollView()
            reactionScrollView.showsHorizontalScrollIndicator = false
            reactionScrollView.translatesAutoresizingMaskIntoConstraints = false

            let reactionStack = UIStackView()
            reactionStack.axis = .horizontal
            reactionStack.spacing = 18
            reactionStack.alignment = .center
            reactionStack.translatesAutoresizingMaskIntoConstraints = false
            reactionScrollView.addSubview(reactionStack)

            NSLayoutConstraint.activate([
                reactionStack.leadingAnchor.constraint(equalTo: reactionScrollView.leadingAnchor, constant: 16),
                reactionStack.trailingAnchor.constraint(equalTo: reactionScrollView.trailingAnchor),
                reactionStack.centerYAnchor.constraint(equalTo: reactionScrollView.centerYAnchor),
            ])

            for emoji in reactions {
                let btn = UIButton(type: .system)
                btn.setTitle(emoji, for: .normal)
                btn.titleLabel?.font = UIFont.chat(size: 32)
                btn.tag = reactions.firstIndex(of: emoji) ?? 0
                btn.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    btn.widthAnchor.constraint(equalToConstant: 44),
                    btn.heightAnchor.constraint(equalToConstant: 44),
                ])
                btn.addTarget(self, action: #selector(reactionTapped(_:)), for: .touchUpInside)
                reactionStack.addArrangedSubview(btn)
            }
            
            let plusButton = UIButton(type: .system)
            plusButton.setTitle("+", for: .normal)
            plusButton.titleLabel?.font = UIFont.chat(.bold, size: 28)
            plusButton.backgroundColor = UIColor.systemGray6
            plusButton.layer.cornerRadius = 22
            plusButton.setTitleColor(ChatTheme.primary, for: .normal)
            NSLayoutConstraint.activate([
                plusButton.widthAnchor.constraint(equalToConstant: 44),
                plusButton.heightAnchor.constraint(equalToConstant: 44),
            ])
            plusButton.addAction(UIAction { _ in
                self.dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onPlusReaction()
                }
            }, for: .touchUpInside)
            reactionStack.addArrangedSubview(plusButton)

            let reactSection = UIView()
            reactSection.translatesAutoresizingMaskIntoConstraints = false
            reactSection.addSubview(reactLabel)
            reactSection.addSubview(reactionScrollView)
            NSLayoutConstraint.activate([
                reactLabel.topAnchor.constraint(equalTo: reactSection.topAnchor, constant: 4),
                reactLabel.leadingAnchor.constraint(equalTo: reactSection.leadingAnchor, constant: 16),
                reactionScrollView.topAnchor.constraint(equalTo: reactLabel.bottomAnchor, constant: 12),
                reactionScrollView.leadingAnchor.constraint(equalTo: reactSection.leadingAnchor),
                reactionScrollView.trailingAnchor.constraint(equalTo: reactSection.trailingAnchor),
                reactionScrollView.bottomAnchor.constraint(equalTo: reactSection.bottomAnchor),
                reactionScrollView.heightAnchor.constraint(equalToConstant: 48),
            ])
            contentStack.addArrangedSubview(reactSection)
        }

        // Divider
        addDivider(top: 16, bottom: 4)

        // Action rows
        let actionWrapper = UIStackView()
        actionWrapper.axis = .vertical
        actionWrapper.spacing = 0
        actionWrapper.alignment = .fill

        if canCopy {
            actionWrapper.addArrangedSubview(makeActionRow(
                title: ChatStrings.chat_copy.localizedString(),
                systemImage: "doc.on.doc",
                isDestructive: false
            ) { onCopy(); self.dismiss() })
        }
        if canReply {
            actionWrapper.addArrangedSubview(makeActionRow(
                title: ChatStrings.chat_reply.localizedString(),
                systemImage: "arrowshape.turn.up.left",
                isDestructive: false
            ) { onReply(); self.dismiss() })
        }
        
        if canMessageInfo {
            actionWrapper.addArrangedSubview(makeActionRow(
                title: ChatStrings.chat_messageInfo.localizedString(),
                systemImage: "info.circle",
                isDestructive: false
            ) {
                onMessageInfo()
                self.dismiss()
            })
        }
        
        
        if canEdit {
            actionWrapper.addArrangedSubview(makeActionRow(
                title: ChatStrings.chat_edit.localizedString(),
                systemImage: "pencil",
                isDestructive: false
            ) { onEdit(); self.dismiss() })
        }
        // Show Pin/Unpin before Select/Delete so pinned messages clearly expose Unpin
        if canPin {
            actionWrapper.addArrangedSubview(makeActionRow(
                title: isPinned ? ChatStrings.chat_unpin.localizedString() : ChatStrings.chat_pin.localizedString(),
                systemImage: isPinned ? "pin.slash" : "pin",
                isDestructive: false,
                rotation: 45
            ) { onPin(); self.dismiss() })
        }
        if !isMinimal {
            actionWrapper.addArrangedSubview(makeActionRow(
                title: ChatStrings.chat_select.localizedString(),
                systemImage: "checkmark.circle",
                isDestructive: false
            ) { onSelect(); self.dismiss() })
        }
        if canTranslate {
            actionWrapper.addArrangedSubview(makeActionRow(
                title: translateTitle ?? ChatStrings.chat_translate.localizedString(),
                systemImage: "character.bubble",
                isDestructive: false
            ) { onTranslate(); self.dismiss() })
        }
        if canRetry {
            actionWrapper.addArrangedSubview(makeActionRow(
                title: ChatStrings.chat_retry.localizedString(),
                systemImage: "arrow.clockwise",
                isDestructive: false
            ) { onRetry(); self.dismiss() })
        }
        if canDelete {
            actionWrapper.addArrangedSubview(makeActionRow(
                title: ChatStrings.chat_deleteForMe.localizedString(),
                systemImage: "trash",
                isDestructive: true
            ) { onDeleteForMe(); self.dismiss() })
        }
        if canDelete && canDeleteForEveryone {
            actionWrapper.addArrangedSubview(makeActionRow(
                title: ChatStrings.chat_deleteForEveryone.localizedString(),
                systemImage: "trash.fill",
                isDestructive: true
            ) { onDeleteForEveryone(); self.dismiss() })
        }

        contentStack.addArrangedSubview(actionWrapper)

        // Bottom safe area
        let safeBottom = safeAreaBottom()
        let bottomSpacer = UIView()
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = true
        bottomSpacer.frame.size.height = safeBottom
        let constraint = bottomSpacer.heightAnchor.constraint(equalToConstant: safeBottom)
        constraint.priority = .defaultHigh
        constraint.isActive = true
        contentStack.addArrangedSubview(bottomSpacer)

        // Store reaction callback
        reactionCallback = onReact
        enforceRTLIfNeeded()
    }

    private var reactionCallback: ((String) -> Void)?

    // MARK: - Helpers

    private func addSpacer(height: CGFloat) {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        contentStack.addArrangedSubview(spacer)
    }

    private func addDivider(top: CGFloat, bottom: CGFloat) {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        let line = UIView()
        line.backgroundColor = UIColor.separator
        line.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(line)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: top + 0.5 + bottom),
            line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            line.heightAnchor.constraint(equalToConstant: 0.5),
            line.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        ])
        contentStack.addArrangedSubview(wrapper)
    }

    private func makeActionRow(
        title: String,
        systemImage: String,
        isDestructive: Bool,
        rotation: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isUserInteractionEnabled = true

        let icon = UIImageView()
        let baseIcon = UIImage(systemName: systemImage)
        let isRTL = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
        icon.image = isRTL ? baseIcon?.withHorizontallyFlippedOrientation() : baseIcon
        icon.tintColor = isDestructive ? .red : ChatTheme.textPrimary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        if let rotation {
            icon.transform = CGAffineTransform(rotationAngle: rotation * .pi / 180)
        }

        let label = UILabel()
        label.text = title
        label.font = UIFont(name: "Fredoka-Regular", size: 17) ?? UIFont.chat(size: 17)
        label.textColor = isDestructive ? .red : ChatTheme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(icon)
        row.addSubview(label)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 44),

            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -16),
        ])

        let btn = UIButton(type: .system)
        btn.backgroundColor = .clear
        btn.addTarget(self, action: #selector(actionRowTapped(_:)), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: row.topAnchor),
            btn.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            btn.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        btn.addAction(UIAction { _ in action() }, for: .touchUpInside)

        return row
    }

    private func contentSize() -> CGFloat {
        let safeBottom = safeAreaBottom()
        layoutIfNeeded()
        return contentStack.frame.height + safeBottom
    }

    private func safeAreaBottom() -> CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first(where: { $0.isKeyWindow })
        return window?.safeAreaInsets.bottom ?? 0
    }

    private func previewFor(message: ConversationMessage) -> String {
        let msgType = (message.messageType ?? message.type ?? "").lowercased()
        let typeName = ConversationMessage.messageTypeDisplayName(msgType)
        if typeName.isEmpty || typeName == ChatStrings.chat_message.localizedString() {
            return message.content ?? message.originalContentForDisplay
        }
        return typeName
    }

    // MARK: - Actions

    @objc private func handleDimmingTap() {
        dismiss()
    }

    @objc private func reactionTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index < reactions.count else { return }
        let emoji = reactions[index]
        RecentReactionsManager.shared.addReaction(emoji)
        // Scale animation matching SwiftUI ReactionButtonStyle
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0,
            options: .curveEaseOut
        ) {
            sender.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        } completion: { _ in
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                usingSpringWithDamping: 0.6,
                initialSpringVelocity: 0,
                options: .curveEaseOut
            ) {
                sender.transform = .identity
            }
        }
        reactionCallback?(emoji)
        dismiss()
    }

    @objc private func actionRowTapped(_ sender: UIButton) {
        // handled via UIAction closure
    }

    // MARK: - Pan gesture

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: containerView)
        let screenHeight = bounds.height

        switch gesture.state {
        case .changed:
            let newY = max(0, translation.y)
            sheetTopConstraint?.constant = (screenHeight - containerView.frame.height) + newY
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: containerView)
            let shouldDismiss = translation.y > 140 || velocity.y > 500
            if shouldDismiss {
                dismiss()
            } else {
                let targetHeight = min(contentSize(), screenHeight * 0.8)
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0,
                    options: .curveEaseOut
                ) {
                    self.sheetTopConstraint?.constant = screenHeight - targetHeight
                    self.superview?.layoutIfNeeded()
                }
            }
            gesture.setTranslation(.zero, in: containerView)
        default:
            break
        }
    }
}


final class RecentReactionsManager {

    static let shared = RecentReactionsManager()

    private let key = "recent_reactions"

    private let defaultReactions = ["👍", "🔥", "💥", "🍀", "😍", "🙏", "😊", "🤗"]

    var reactions: [String] {
            let saved = ChatUserDefaultsStore.shared.recentReactions
            if saved.isEmpty {
                return Array(defaultReactions.prefix(15))
            }
            let merged = saved + defaultReactions.filter { !saved.contains($0) }
            return Array(merged.prefix(15))
        }

    func addReaction(_ emoji: String) {
        var recent = ChatUserDefaultsStore.shared.recentReactions

        recent.removeAll { $0 == emoji }
        recent.insert(emoji, at: 0)

        recent = Array(recent.prefix(8))

        ChatUserDefaultsStore.shared.recentReactions = recent
    }
}
