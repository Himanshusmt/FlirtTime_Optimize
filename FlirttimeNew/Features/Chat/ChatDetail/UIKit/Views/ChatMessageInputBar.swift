import UIKit
import Combine

protocol ChatMessageInputBarDelegate: AnyObject {
    func inputBarDidSend(_ inputBar: ChatMessageInputBar)
    func inputBar(_ inputBar: ChatMessageInputBar, didEditText text: String)
    func inputBarDidChangeHeight(_ inputBar: ChatMessageInputBar, height: CGFloat)
    func inputBarDidToggleAttachment(_ inputBar: ChatMessageInputBar)
    func inputBarDidTapCamera(_ inputBar: ChatMessageInputBar)
    func inputBarDidTapMicrophone(_ inputBar: ChatMessageInputBar)
    func inputBarDidCloseAttachment(_ inputBar: ChatMessageInputBar)
    func inputBar(_ inputBar: ChatMessageInputBar, mentionQueryChanged query: String?, range: Range<String.Index>?)
    func inputBar(_ inputBar: ChatMessageInputBar, didSelectMention participant: GroupParticipant)
    func inputBarTextDidChange(_ inputBar: ChatMessageInputBar, text: String)
}

// MARK: - Auto-growing text view

final class ChatInputTextView: UITextView {

    var onContentSizeChanged: ((CGFloat) -> Void)?
    var onTextChanged: (() -> Void)?

    private lazy var placeholderLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = font
        lbl.textColor = ChatTheme.textPrimary.withAlphaComponent(0.6)
        lbl.text = ChatStrings.chat_message.localizedString()
        lbl.isUserInteractionEnabled = false
        lbl.numberOfLines = 1
        lbl.textAlignment = .natural
        return lbl
    }()

    private let minHeight: CGFloat = 40
    private let maxHeight: CGFloat = 100

    fileprivate var buttonSideInset: CGFloat { 52 }
    fileprivate var actionSideInset: CGFloat { 50 }
    fileprivate var textSideInset: CGFloat { 12 }

    /// Set once by the parent bar — single source of truth for RTL direction.
    fileprivate var isRTLLayout: Bool = false

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        font = UIFont.chat(size: 16)
        textColor = ChatTheme.textPrimary
        backgroundColor = .clear
        isScrollEnabled = false
        isEditable = true
        isSelectable = true
        textContainerInset = UIEdgeInsets(
            top: 16,
            left: buttonSideInset,
            bottom: 16,
            right: actionSideInset
        )
        textContainer.lineFragmentPadding = 4

        returnKeyType = .next
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        addSubview(placeholderLabel)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleTextDidChange),
            name: UITextView.textDidChangeNotification, object: self
        )
    }

    override var contentSize: CGSize {
        didSet {
            guard oldValue.height != contentSize.height else { return }
            notifyHeightChanged()
        }
    }

    override var text: String? {
        didSet {
            placeholderLabel.isHidden = !(text ?? "").isEmpty
            onTextChanged?()
        }
    }

    @objc private func handleTextDidChange() {
        placeholderLabel.isHidden = !(text ?? "").isEmpty
        onTextChanged?()
        invalidateIntrinsicContentSize()
        notifyHeightChanged()
    }

    private func notifyHeightChanged() {
        guard frame.width > 0 else { return }
        let size = sizeThatFits(CGSize(width: frame.width, height: .greatestFiniteMagnitude))
        let capped = min(max(size.height, minHeight), maxHeight)
        isScrollEnabled = size.height >= maxHeight
        onContentSizeChanged?(capped)
    }

    /// Called by parent to set RTL mode — adjusts text alignment and container insets.
    func configureRTL(_ rtl: Bool) {
        isRTLLayout = rtl
        textAlignment = rtl ? .right : .natural
        placeholderLabel.textAlignment = rtl ? .right : .natural
        placeholderLabel.text = ChatStrings.chat_message.localizedString()
        setTextInsets(hasText: !(text ?? "").isEmpty)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutPlaceholder()
    }

    /// Frame-based placeholder positioning — avoids UITextView's RTL Auto Layout override.
    private func layoutPlaceholder() {
        guard placeholderLabel.superview != nil, bounds.width > 0 else { return }

        let top = textContainerInset.top
        let padding = textContainer.lineFragmentPadding

        let cursorInset: CGFloat
        let oppositeInset: CGFloat
        if isRTLLayout {
            cursorInset = textContainerInset.right + padding
            oppositeInset = textContainerInset.left
        } else {
            cursorInset = textContainerInset.left + padding
            oppositeInset = textContainerInset.right
        }

        let availableWidth = bounds.width - cursorInset - oppositeInset
        guard availableWidth > 0 else { return }

        let labelSize = placeholderLabel.sizeThatFits(
            CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        )

        let x: CGFloat
        if isRTLLayout {
            x = bounds.width - cursorInset - ceil(labelSize.width)
        } else {
            x = cursorInset
        }

        placeholderLabel.frame = CGRect(
            x: x,
            y: top,
            width: ceil(labelSize.width),
            height: ceil(labelSize.height)
        )
    }

    func setTextInsets(hasText: Bool) {
        let buttonInset: CGFloat = hasText ? textSideInset : buttonSideInset
        let actionInset: CGFloat = hasText ? textSideInset : actionSideInset

        if isRTLLayout {
            textContainerInset = UIEdgeInsets(top: 16, left: actionInset, bottom: 16, right: buttonInset)
        } else {
            textContainerInset = UIEdgeInsets(top: 16, left: buttonInset, bottom: 16, right: actionInset)
        }
        setNeedsLayout()
    }
}

// MARK: - ChatMessageInputBar

final class ChatMessageInputBar: UIView {

    weak var delegate: ChatMessageInputBarDelegate?

    var isEditing: Bool = false
    var showingAttachmentSheet: Bool = false

    var messageText: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            updateButtonStates()
        }
    }

    // MARK: - Subviews

    private let composerBackground: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.gray.withAlphaComponent(0.12)
        v.layer.cornerRadius = 26
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    let textView: ChatInputTextView = {
        let tv = ChatInputTextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let attachmentButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: ChatAssets.plus)?.withRenderingMode(.alwaysTemplate), for: .normal)
        btn.tintColor = ChatTheme.primary
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let micButton: UIButton = {
        let btn = makeCircleIconButton(customImage: ChatAssets.microphone)
        return btn
    }()

    private let sendButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.setImage(UIImage(named: ChatAssets.send)?.withRenderingMode(.alwaysTemplate), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = ChatTheme.primary
        btn.layer.cornerRadius = 28
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    // MARK: - Character limit

    private static let maxCharacters = 4096
    private static let counterThreshold = 3600

    private let charCountLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        lbl.textColor = .secondaryLabel
        lbl.textAlignment = .trailing
        lbl.isHidden = true
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    // MARK: - Layout constants (matching original SwiftUI)

    private let composerMinHeight: CGFloat = 52
    private let composerMaxHeight: CGFloat = 120
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 8
    private let mainSpacing: CGFloat = 12
    private let innerSpacing: CGFloat = 10

    // MARK: - Computed

    private var barMinHeight: CGFloat {
        return max(composerMinHeight + verticalPadding * 2, 56 + verticalPadding * 2)
    }

    // MARK: - Constraints

    private var barHeightConstraint: NSLayoutConstraint?
    private var composerHeightConstraint: NSLayoutConstraint?

    private var sendLTRLeading: NSLayoutConstraint?
    private var sendLTRTrailing: NSLayoutConstraint?
    private var sendRTLLeading: NSLayoutConstraint?
    private var sendRTLTrailing: NSLayoutConstraint?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white

        let rtl = UIApplication.isRTL()

        addSubview(composerBackground)
        composerHeightConstraint = composerBackground.heightAnchor.constraint(equalToConstant: composerMinHeight)
        composerHeightConstraint?.isActive = true
        NSLayoutConstraint.activate([
            composerBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            composerBackground.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),
            composerBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPadding),
        ])

        composerBackground.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: composerBackground.leadingAnchor, constant: 4),
            textView.topAnchor.constraint(equalTo: composerBackground.topAnchor),
            textView.bottomAnchor.constraint(equalTo: composerBackground.bottomAnchor),
            textView.trailingAnchor.constraint(equalTo: composerBackground.trailingAnchor, constant: -4),
        ])

        composerBackground.addSubview(charCountLabel)
        NSLayoutConstraint.activate([
            charCountLabel.trailingAnchor.constraint(equalTo: composerBackground.trailingAnchor, constant: -14),
            charCountLabel.bottomAnchor.constraint(equalTo: composerBackground.bottomAnchor, constant: -4),
        ])

        composerBackground.addSubview(attachmentButton)
        NSLayoutConstraint.activate([
            attachmentButton.leadingAnchor.constraint(equalTo: composerBackground.leadingAnchor, constant: 6),
            attachmentButton.centerYAnchor.constraint(equalTo: composerBackground.centerYAnchor),
            attachmentButton.widthAnchor.constraint(equalToConstant: 40),
            attachmentButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        composerBackground.addSubview(micButton)
        NSLayoutConstraint.activate([
            micButton.trailingAnchor.constraint(equalTo: composerBackground.trailingAnchor, constant: -10),
            micButton.centerYAnchor.constraint(equalTo: composerBackground.centerYAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 32),
            micButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        addSubview(sendButton)

        sendLTRLeading = sendButton.leftAnchor.constraint(equalTo: composerBackground.rightAnchor, constant: mainSpacing)
        sendLTRTrailing = sendButton.rightAnchor.constraint(equalTo: rightAnchor, constant: -horizontalPadding)

        // RTL: |left| ←16→ [send] ←12→ [composer]
        sendRTLLeading = sendButton.leftAnchor.constraint(equalTo: leftAnchor, constant: horizontalPadding)
        sendRTLTrailing = sendButton.rightAnchor.constraint(equalTo: composerBackground.leftAnchor, constant: -mainSpacing)

        if rtl {
            sendRTLLeading?.isActive = true
            sendRTLTrailing?.isActive = true
        } else {
            sendLTRLeading?.isActive = true
            sendLTRTrailing?.isActive = true
        }

        NSLayoutConstraint.activate([
            sendButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 56),
            sendButton.heightAnchor.constraint(equalToConstant: 56),
        ])

        // Bar height
        barHeightConstraint = heightAnchor.constraint(equalToConstant: barMinHeight)
        barHeightConstraint?.isActive = true

        // Delegates and actions
        textView.delegate = self
        attachmentButton.addTarget(self, action: #selector(attachmentTapped), for: .touchUpInside)
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        // Auto-grow
        textView.onContentSizeChanged = { [weak self] newHeight in
            guard let self else { return }
            self.updateHeight(for: newHeight)
        }

        enforceRTLIfNeeded()

        textView.configureRTL(rtl)
        updateButtonStates()
    }

    // MARK: - Height Management

    private func updateHeight(for textHeight: CGFloat) {
        let composerHeight = max(composerMinHeight, min(textHeight, composerMaxHeight))
        let newBarHeight = composerHeight + verticalPadding * 2

        composerHeightConstraint?.constant = composerHeight
        barHeightConstraint?.constant = max(barMinHeight, newBarHeight)

        delegate?.inputBarDidChangeHeight(self, height: barHeightConstraint?.constant ?? barMinHeight)
    }

    func resetHeight() {
        composerHeightConstraint?.constant = composerMinHeight
        barHeightConstraint?.constant = barMinHeight
    }

    // MARK: - Button State

    private func updateButtonStates() {
        let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        UIView.animate(withDuration: 0.15) {
            self.attachmentButton.alpha = hasText ? 0 : 1
            self.micButton.alpha = hasText ? 0 : 1
        }
        attachmentButton.isHidden = hasText
        micButton.isHidden = hasText

        textView.setTextInsets(hasText: hasText)

        // Send button
        sendButton.isEnabled = hasText
        sendButton.alpha = hasText ? 1.0 : 0.4
        UIView.animate(withDuration: 0.15) {
            self.sendButton.transform = hasText ? .identity : CGAffineTransform(scaleX: 0.85, y: 0.85)
        }
    }

    // MARK: - Focus

    func becomeFirstResponderInput() {
        textView.becomeFirstResponder()
    }

    func resignFirstResponderInput() {
        textView.resignFirstResponder()
    }

    // MARK: - Actions

    @objc private func attachmentTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showingAttachmentSheet.toggle()

        let targetTransform: CGAffineTransform = showingAttachmentSheet
            ? CGAffineTransform(rotationAngle: .pi / 4)
            : .identity

        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.4,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.attachmentButton.transform = targetTransform
        }
        delegate?.inputBarDidToggleAttachment(self)
    }

    @objc private func micTapped() {
        delegate?.inputBarDidTapMicrophone(self)
    }

    @objc private func sendTapped() {
        if isEditing {
            delegate?.inputBar(self, didEditText: messageText)
        } else {
            delegate?.inputBarDidSend(self)
        }
    }

    // MARK: - Helpers

    private static func makeCircleIconButton(systemName: String, pointSize: CGFloat) -> UIButton {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        btn.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        btn.tintColor = ChatTheme.textPrimary
        btn.backgroundColor = UIColor.gray.withAlphaComponent(0.2)
        btn.layer.cornerRadius = 16
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }

    private static func makeCircleIconButton(customImage: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: customImage)?.withRenderingMode(.alwaysTemplate), for: .normal)
        btn.tintColor = ChatTheme.primary
        btn.backgroundColor = UIColor.gray.withAlphaComponent(0.2)
        btn.layer.cornerRadius = 16
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }

    func resetAttachmentButton() {
        guard showingAttachmentSheet else { return }
        showingAttachmentSheet = false
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.4,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.attachmentButton.transform = .identity
        }
    }

    private func updateCharCounter() {
        let count = (textView.text ?? "").count
        if count >= Self.counterThreshold {
            charCountLabel.isHidden = false
            charCountLabel.text = "\(count)/\(Self.maxCharacters)"
        } else {
            charCountLabel.isHidden = true
        }
    }
}

// MARK: - UITextViewDelegate

extension ChatMessageInputBar: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        updateButtonStates()
        updateCharCounter()
        delegate?.inputBarTextDidChange(self, text: textView.text ?? "")

        // Close attachment sheet on text change
        if showingAttachmentSheet {
            resetAttachmentButton()
            delegate?.inputBarDidCloseAttachment(self)
        }

        // Mention query detection
        if let selectedRange = textView.selectedTextRange,
           let position = textView.position(from: selectedRange.start, offset: 0) {
            let cursorOffset = textView.offset(from: textView.beginningOfDocument, to: position)
            if let result = MentionTextAttributes.extractMentionQuery(text: textView.text, cursorPosition: cursorOffset) {
                delegate?.inputBar(self, mentionQueryChanged: result.query, range: result.range)
            } else {
                delegate?.inputBar(self, mentionQueryChanged: nil, range: nil)
            }
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let currentText = textView.text ?? ""
        let proposed = (currentText as NSString).replacingCharacters(in: range, with: text)
        return proposed.count <= Self.maxCharacters
    }
}
