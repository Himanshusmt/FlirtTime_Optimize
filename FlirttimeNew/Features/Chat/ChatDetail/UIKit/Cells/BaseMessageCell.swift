import UIKit
import Kingfisher

// MARK: - Cell Actions Protocol

protocol MessageCellActionsDelegate: AnyObject {
    func cellDidTapMessage(_ cell: BaseMessageCell, model: MessageCellModel)
    func cellDidTapAvatar(_ cell: BaseMessageCell, model: MessageCellModel)
    func cellDidLongPress(_ cell: BaseMessageCell, model: MessageCellModel)
    func cellDidSwipeToReply(_ cell: BaseMessageCell, model: MessageCellModel)
    func cellDidTapReaction(_ cell: BaseMessageCell, model: MessageCellModel, reaction: MessageReaction)
    func cellDidTapReplyPreview(_ cell: BaseMessageCell, messageId: String)
    func cellDidTapMedia(_ cell: BaseMessageCell, model: MessageCellModel, mediaIndex: Int)
    func cellDidToggleSelection(_ cell: BaseMessageCell, messageId: String)
    func cellDidTapPollOption(_ cell: BaseMessageCell, model: MessageCellModel, optionIndex: Int)
    func cellDidChangeAudioSpeed(_ cell: BaseMessageCell, speed: Float)
    func cellDidTapLink(_ cell: BaseMessageCell, url: URL)
    func cellDidTapViewVotes(_ cell: BaseMessageCell, model: MessageCellModel)
    func cellDidTapLocation(_ cell: BaseMessageCell, model: MessageCellModel)
    func cellDidToggleExpand(_ cell: BaseMessageCell)
    func cellDidTapMention(_ cell: BaseMessageCell, username: String)
}

// Default empty implementations
extension MessageCellActionsDelegate {
    func cellDidTapMessage(_ cell: BaseMessageCell, model: MessageCellModel) {}
    func cellDidTapAvatar(_ cell: BaseMessageCell, model: MessageCellModel) {}
    func cellDidLongPress(_ cell: BaseMessageCell, model: MessageCellModel) {}
    func cellDidSwipeToReply(_ cell: BaseMessageCell, model: MessageCellModel) {}
    func cellDidTapReaction(_ cell: BaseMessageCell, model: MessageCellModel, reaction: MessageReaction) {}
    func cellDidToggleSelection(_ cell: BaseMessageCell, messageId: String) {}
    func cellDidTapPollOption(_ cell: BaseMessageCell, model: MessageCellModel, optionIndex: Int) {}
    func cellDidChangeAudioSpeed(_ cell: BaseMessageCell, speed: Float) {}
    func cellDidTapLink(_ cell: BaseMessageCell, url: URL) {}
    func cellDidTapViewVotes(_ cell: BaseMessageCell, model: MessageCellModel) {}
    func cellDidTapLocation(_ cell: BaseMessageCell, model: MessageCellModel) {}
    func cellDidToggleExpand(_ cell: BaseMessageCell) {}
    func cellDidTapMention(_ cell: BaseMessageCell, username: String) {}
}

// MARK: - Base Message Cell

class BaseMessageCell: UICollectionViewCell {

    // MARK: - Static brand colors
    static let brandOrange  = ChatTheme.primary
    static let replyGold    = ChatTheme.primaryLight

    // MARK: - Properties

    weak var actionsDelegate: MessageCellActionsDelegate?
    private(set) var cellModel: MessageCellModel?
    private var wasPreviouslyEdited = false

    // MARK: - Subviews

    let containerStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.alignment = .top
        sv.spacing = 0
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    let bubbleContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let contentStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = MessageCellMetrics.contentStackSpacing
        sv.semanticContentAttribute = .forceLeftToRight
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // Forwarded tag
    private let forwardedContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.secondaryLabel.withAlphaComponent(0.08)
        v.layer.cornerRadius = 10
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let forwardedIconView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "arrowshape.turn.up.right")
        iv.tintColor = .secondaryLabel
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let forwardedLabel: UILabel = {
        let label = UILabel()
        label.text = ChatStrings.chat_forwarded.localizedString()
        label.font = UIFont.chat(size: 11)
        label.textColor = .secondaryLabel
        return label
    }()

    // Pinned indicator
    private let pinnedContainer: UIView = {
        let v = UIView()
        v.backgroundColor = ChatTheme.primary.withAlphaComponent(0.08)
        v.layer.cornerRadius = 10
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let pinnedIcon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "pin.fill")
        iv.tintColor = ChatTheme.primary
        iv.contentMode = .scaleAspectFit
        iv.transform = CGAffineTransform(rotationAngle: .pi / 4)
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let pinnedLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = ChatStrings.chat_pinned.localizedString()
        lbl.font = UIFont.chat(size: 10)
        lbl.textColor = ChatTheme.primary
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    // Sender name
    let senderNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.chat(.semibold, size: 12)
        label.textColor = ChatTheme.primary
        label.isHidden = true
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var senderHeaderStack: UIStackView = {
        let sv = UIStackView(arrangedSubviews: [senderNameLabel])
        sv.axis = .horizontal
        sv.alignment = .center
        sv.spacing = 0
        sv.isHidden = true
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // Reply preview
    let replyPreviewContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 8
        view.backgroundColor = UIColor.black.withAlphaComponent(0.06)
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let replyAccentBar: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 1.5
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let replySenderLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.chat(.semibold, size: 11)
        return label
    }()

    private let replyContentLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.chat(size: 11)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    private let replyThumbnailView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.layer.cornerRadius = 8
        iv.clipsToBounds = true
        iv.isHidden = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    /// Small SF-symbol icon shown in the body row for non-text message types
    private let replyTypeIconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.isHidden = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    // Content area — subclasses add their views here
    let contentArea: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // Footer (time + status)
    private let footerStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = MessageCellMetrics.footerInternalSpacing
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let editedLabel: UILabel = {
        let label = UILabel()
        label.text = ChatStrings.chat_edited.localizedString()
        label.font = UIFont.chat(size: 9)
        label.textColor = .secondaryLabel
        label.isHidden = true
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.chat(size: 11)
        label.textColor = .secondaryLabel
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()

    private let statusImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .vertical)
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    // Reactions strip
    private let reactionsStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 2
        sv.alignment = .leading
        sv.isHidden = true
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private var reactionPills: [ReactionPillView] = []

    // Selection checkbox
    private let selectionCheckbox: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 13
        view.layer.borderWidth = 1.5
        view.layer.borderColor = UIColor.gray.withAlphaComponent(0.4).cgColor
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let checkmarkImageView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "checkmark")
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.isHidden = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    let deletedOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.secondarySystemBackground
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let highlightOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = ChatTheme.primaryLight.withAlphaComponent(0.35)
        view.alpha = 0
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let deletedLabel: UILabel = {
        let label = UILabel()
        label.font = .italicSystemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // Swipe-to-reply
    private var panGestureRecognizer: UIPanGestureRecognizer?
    private let swipeThreshold: CGFloat = 60
    private var swipeStartPoint: CGPoint = .zero
    private var isSwipeActive = false
    private var hasPassedThreshold = false

    // Reply indicator shown during swipe
    private let swipeReplyIcon: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true
        container.alpha = 0

        let iv = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left"))
        iv.tintColor = ChatTheme.primary
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 20),
            iv.heightAnchor.constraint(equalToConstant: 20),
        ])
        return container
    }()

    // Layout constraints — incoming pair (left equality) vs outgoing pair (right equality).
    // Uses physical left/right so bubbles stay incoming=LEFT, outgoing=RIGHT in all languages.
    private var contentLeadingConstraint: NSLayoutConstraint?   // = left + 12 (incoming)
    private var contentTrailingConstraint: NSLayoutConstraint?  // ≤ right - 40 (incoming max)
    private var outgoingLeadingConstraint: NSLayoutConstraint?  // ≥ left + 40 (outgoing min)
    private var outgoingTrailingConstraint: NSLayoutConstraint? // = right - 12 (outgoing pin)
    private var selectionIncomingLeading: NSLayoutConstraint?  // = checkbox.right + 6 (incoming selection)
    private var selectionOutgoingLeading: NSLayoutConstraint?  // ≥ checkbox.right + 6 (outgoing selection)

    // RTL alternative constraints (selection + swipe only)
    private var selectionCheckboxLeft: NSLayoutConstraint?     // LTR: left = contentView.left + 6
    private var selectionCheckboxRight: NSLayoutConstraint?    // RTL: right = contentView.right - 6
    private var selectionIncomingRTL: NSLayoutConstraint?      // RTL: right = checkbox.left - 6 (incoming)
    private var selectionOutgoingRTL: NSLayoutConstraint?      // RTL: right ≤ checkbox.left - 6 (outgoing)
    private var swipeReplyIconTrailingLTR: NSLayoutConstraint? // LTR: right of containerStack left
    private var swipeReplyIconLeadingRTL: NSLayoutConstraint?  // RTL: left of containerStack right
    private var bubbleWidthConstraint: NSLayoutConstraint?
    private var maxBubbleWidth: CGFloat { (window?.windowScene?.screen.bounds.width ?? UIScreen.main.bounds.width) * MessageCellMetrics.maxBubbleWidthRatio }

    // Bubble content padding — subclasses with self-contained containers call setBubbleContentInsets(0, 0, 0)
    private var csTop: NSLayoutConstraint?
    private var csLeading: NSLayoutConstraint?
    private var csTrailing: NSLayoutConstraint?
    private var csBottom: NSLayoutConstraint?


    private var overlayTopCS: NSLayoutConstraint?
    private var overlayBottomCS: NSLayoutConstraint?
    private var overlayLeadingCS: NSLayoutConstraint?
    private var overlayTrailingCS: NSLayoutConstraint?

    // Vertical column holding bubble + reactions + footer (mirrors SwiftUI's outer VStack)
    private let messageColumnStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = MessageCellMetrics.columnSpacing
        sv.alignment = .leading
        sv.clipsToBounds = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupGestures()
        setupReactionPills()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
        setupGestures()
        setupReactionPills()
    }

    // MARK: - Setup

    private func setupViews() {
        contentView.addSubview(containerStackView)
        // messageColumnStack holds: senderHeader → pinned → bubble → reactions → footer
        containerStackView.addArrangedSubview(messageColumnStack)
        messageColumnStack.addArrangedSubview(senderHeaderStack)
        messageColumnStack.addArrangedSubview(pinnedContainer)
        messageColumnStack.addArrangedSubview(forwardedContainer)
        messageColumnStack.addArrangedSubview(bubbleContainer)
        messageColumnStack.addArrangedSubview(reactionsStackView)
        messageColumnStack.addArrangedSubview(footerStackView)

        // Bubble content
        bubbleContainer.addSubview(contentStackView)

        // Build content stack: reply preview → content area
        contentStackView.addArrangedSubview(replyPreviewContainer)
        contentStackView.addArrangedSubview(contentArea)

        bubbleContainer.addSubview(deletedOverlay)
        deletedOverlay.addSubview(deletedLabel)

        bubbleContainer.addSubview(highlightOverlay)
        NSLayoutConstraint.activate([
            highlightOverlay.topAnchor.constraint(equalTo: bubbleContainer.topAnchor),
            highlightOverlay.bottomAnchor.constraint(equalTo: bubbleContainer.bottomAnchor),
            highlightOverlay.leadingAnchor.constraint(equalTo: bubbleContainer.leadingAnchor),
            highlightOverlay.trailingAnchor.constraint(equalTo: bubbleContainer.trailingAnchor),
        ])

        NSLayoutConstraint.activate([
            deletedLabel.topAnchor.constraint(equalTo: deletedOverlay.topAnchor, constant: MessageCellMetrics.textProfilePadTop),
            deletedLabel.leadingAnchor.constraint(equalTo: deletedOverlay.leadingAnchor, constant: MessageCellMetrics.textProfilePadH),
            deletedLabel.trailingAnchor.constraint(equalTo: deletedOverlay.trailingAnchor, constant: -MessageCellMetrics.textProfilePadH),
            deletedLabel.bottomAnchor.constraint(equalTo: deletedOverlay.bottomAnchor, constant: -MessageCellMetrics.textProfilePadBottom),
        ])

        overlayTopCS = deletedOverlay.topAnchor.constraint(equalTo: bubbleContainer.topAnchor)
        overlayBottomCS = deletedOverlay.bottomAnchor.constraint(equalTo: bubbleContainer.bottomAnchor)
        overlayLeadingCS = deletedOverlay.leadingAnchor.constraint(equalTo: bubbleContainer.leadingAnchor)
        overlayTrailingCS = deletedOverlay.trailingAnchor.constraint(equalTo: bubbleContainer.trailingAnchor)
        overlayTopCS?.isActive = false
        overlayBottomCS?.isActive = false
        overlayLeadingCS?.isActive = false
        overlayTrailingCS?.isActive = false

        // Forwarded capsule internals
        let forwardedStack = UIStackView(arrangedSubviews: [forwardedIconView, forwardedLabel])
        forwardedStack.axis = .horizontal
        forwardedStack.spacing = 4
        forwardedStack.alignment = .center
        forwardedStack.translatesAutoresizingMaskIntoConstraints = false
        forwardedContainer.addSubview(forwardedStack)
        NSLayoutConstraint.activate([
            forwardedStack.topAnchor.constraint(equalTo: forwardedContainer.topAnchor, constant: MessageCellMetrics.forwardedCapsulePadV),
            forwardedStack.leftAnchor.constraint(equalTo: forwardedContainer.leftAnchor, constant: MessageCellMetrics.forwardedCapsulePadH),
            forwardedStack.rightAnchor.constraint(equalTo: forwardedContainer.rightAnchor, constant: -MessageCellMetrics.forwardedCapsulePadH),
            forwardedStack.bottomAnchor.constraint(equalTo: forwardedContainer.bottomAnchor, constant: -MessageCellMetrics.forwardedCapsulePadV),
            forwardedIconView.widthAnchor.constraint(equalToConstant: MessageCellMetrics.forwardedIconSize),
            forwardedIconView.heightAnchor.constraint(equalToConstant: MessageCellMetrics.forwardedIconSize),
        ])

        // Reply preview internals
        setupReplyPreview()

        // Footer — compact row, outside bubble (no spacer; alignment handled by messageColumnStack)
        footerStackView.addArrangedSubview(editedLabel)
        footerStackView.addArrangedSubview(timeLabel)
        footerStackView.addArrangedSubview(statusImageView)

        // Pinned capsule internals (lives in messageColumnStack, above bubble)
        let pinnedStack = UIStackView(arrangedSubviews: [pinnedIcon, pinnedLabel])
        pinnedStack.axis = .horizontal
        pinnedStack.spacing = 3
        pinnedStack.alignment = .center
        pinnedStack.translatesAutoresizingMaskIntoConstraints = false
        pinnedContainer.addSubview(pinnedStack)
        NSLayoutConstraint.activate([
            pinnedStack.topAnchor.constraint(equalTo: pinnedContainer.topAnchor, constant: MessageCellMetrics.pinnedCapsulePadV),
            pinnedStack.leftAnchor.constraint(equalTo: pinnedContainer.leftAnchor, constant: MessageCellMetrics.pinnedCapsulePadH),
            pinnedStack.rightAnchor.constraint(equalTo: pinnedContainer.rightAnchor, constant: -MessageCellMetrics.pinnedCapsulePadH),
            pinnedStack.bottomAnchor.constraint(equalTo: pinnedContainer.bottomAnchor, constant: -MessageCellMetrics.pinnedCapsulePadV),
            pinnedIcon.widthAnchor.constraint(equalToConstant: MessageCellMetrics.pinnedIconSize),
            pinnedIcon.heightAnchor.constraint(equalToConstant: MessageCellMetrics.pinnedIconSize),
        ])

        // Reactions (between bubble and footer in messageColumnStack)

        // Selection checkbox (left side, hidden by default)
        contentView.addSubview(selectionCheckbox)
        selectionCheckbox.addSubview(checkmarkImageView)

        // Swipe-to-reply indicator (left of bubble in LTR, right in RTL)
        contentView.insertSubview(swipeReplyIcon, belowSubview: containerStackView)
        let swipeIconTrailingLTR = swipeReplyIcon.rightAnchor.constraint(equalTo: containerStackView.leftAnchor, constant: -4)
        let swipeIconCenterY = swipeReplyIcon.centerYAnchor.constraint(equalTo: containerStackView.centerYAnchor)
        let swipeIconW = swipeReplyIcon.widthAnchor.constraint(equalToConstant: 32)
        let swipeIconH = swipeReplyIcon.heightAnchor.constraint(equalToConstant: 32)
        swipeReplyIconTrailingLTR = swipeIconTrailingLTR
        swipeReplyIconLeadingRTL = swipeReplyIcon.leftAnchor.constraint(equalTo: containerStackView.rightAnchor, constant: 4)
        swipeReplyIconLeadingRTL?.isActive = false
        NSLayoutConstraint.activate([swipeIconTrailingLTR, swipeIconCenterY, swipeIconW, swipeIconH])

        contentLeadingConstraint = containerStackView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: MessageCellMetrics.cellHorizontalInset)
        contentTrailingConstraint = containerStackView.rightAnchor.constraint(lessThanOrEqualTo: contentView.rightAnchor, constant: -MessageCellMetrics.cellHorizontalInset)
        outgoingLeadingConstraint = containerStackView.leftAnchor.constraint(greaterThanOrEqualTo: contentView.leftAnchor, constant: MessageCellMetrics.outgoingLeadingMin)
        outgoingTrailingConstraint = containerStackView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -MessageCellMetrics.cellHorizontalInset)

        selectionIncomingLeading = containerStackView.leftAnchor.constraint(equalTo: selectionCheckbox.rightAnchor, constant: 6)
        selectionOutgoingLeading = containerStackView.leftAnchor.constraint(greaterThanOrEqualTo: selectionCheckbox.rightAnchor, constant: 6)

        // Selection checkbox: LTR = left side, RTL = right side
        selectionCheckboxLeft = selectionCheckbox.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 6)
        selectionCheckboxRight = selectionCheckbox.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -6)
        selectionCheckboxRight?.isActive = false

        // RTL selection constraints: container anchors to checkbox left instead of right
        // Incoming: limit max width (lessThanOrEqualTo); Outgoing: pin right edge (equalTo)
        selectionIncomingRTL = containerStackView.rightAnchor.constraint(lessThanOrEqualTo: selectionCheckbox.leftAnchor, constant: -6)
        selectionOutgoingRTL = containerStackView.rightAnchor.constraint(equalTo: selectionCheckbox.leftAnchor, constant: -6)
        selectionIncomingRTL?.isActive = false
        selectionOutgoingRTL?.isActive = false

        // Activate incoming pair by default; configureLayout toggles per message
        bubbleWidthConstraint = bubbleContainer.widthAnchor.constraint(equalToConstant: maxBubbleWidth)
        bubbleWidthConstraint?.priority = .required

        csTop    = contentStackView.topAnchor.constraint(equalTo: bubbleContainer.topAnchor, constant: MessageCellMetrics.textProfilePadTop)
        csLeading  = contentStackView.leftAnchor.constraint(equalTo: bubbleContainer.leftAnchor, constant: MessageCellMetrics.textProfilePadH)
        csTrailing = contentStackView.rightAnchor.constraint(equalTo: bubbleContainer.rightAnchor, constant: -MessageCellMetrics.textProfilePadH)
        csBottom   = contentStackView.bottomAnchor.constraint(equalTo: bubbleContainer.bottomAnchor, constant: -MessageCellMetrics.textProfilePadBottom)

        contentLeadingConstraint?.isActive = true
        contentTrailingConstraint?.isActive = true
        bubbleWidthConstraint?.isActive = true
        csTop?.isActive = true
        csLeading?.isActive = true
        csTrailing?.isActive = true
        csBottom?.isActive = true
        selectionCheckboxLeft?.isActive = true

        NSLayoutConstraint.activate([
            containerStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: MessageCellMetrics.cellPadTop),
            containerStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -MessageCellMetrics.cellPadBottom),

            statusImageView.widthAnchor.constraint(equalToConstant: MessageCellMetrics.statusIconWidth),
            statusImageView.heightAnchor.constraint(equalToConstant: MessageCellMetrics.statusIconSize),

            selectionCheckbox.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectionCheckbox.widthAnchor.constraint(equalToConstant: 26),
            selectionCheckbox.heightAnchor.constraint(equalToConstant: 26),
            checkmarkImageView.centerXAnchor.constraint(equalTo: selectionCheckbox.centerXAnchor),
            checkmarkImageView.centerYAnchor.constraint(equalTo: selectionCheckbox.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 13),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 13),
        ])

        // Force LTR on container stacks so .leading/.trailing always map to physical left/right.
        // This keeps bubble positions, footer, header, and reply preview consistent in all languages.
        containerStackView.semanticContentAttribute = .forceLeftToRight
        messageColumnStack.semanticContentAttribute = .forceLeftToRight
        footerStackView.semanticContentAttribute = .forceLeftToRight
        reactionsStackView.semanticContentAttribute = .forceLeftToRight

        configureRTLInternal()
    }

    // MARK: - RTL

    private var isRTL: Bool { UIApplication.isRTL() }

    private func configureRTLInternal() {
        guard isRTL else { return }

        // Selection checkbox: move to right side in RTL
        selectionCheckboxLeft?.isActive = false
        selectionCheckboxRight?.isActive = true

        // Swipe reply icon: position to the right of the bubble in RTL
        swipeReplyIconLeadingRTL?.isActive = true
        swipeReplyIconTrailingLTR?.isActive = false
    }

    func overrideBubbleWidth(_ width: CGFloat) {
        bubbleWidthConstraint?.constant = min(width, maxBubbleWidth)
    }

    func setBubbleContentInsets(top: CGFloat = 6, horizontal: CGFloat = 8, bottom: CGFloat = 6) {
        csTop?.constant = top
        csLeading?.constant = horizontal
        csTrailing?.constant = -horizontal
        csBottom?.constant = -bottom
    }

    private func setupReplyPreview() {

        replyPreviewContainer.addSubview(replyAccentBar)

        // Body row: type icon (optional) + preview text (up to 3 lines)
        let replyBodyRow = UIStackView(arrangedSubviews: [replyTypeIconView, replyContentLabel])
        replyBodyRow.axis = .horizontal
        replyBodyRow.spacing = MessageCellMetrics.replyBodyRowSpacing
        replyBodyRow.alignment = .top
        replyBodyRow.translatesAutoresizingMaskIntoConstraints = false

        // Text column: sender name on top, body row below
        let replyTextStack = UIStackView(arrangedSubviews: [replySenderLabel, replyBodyRow])
        replyTextStack.axis = .vertical
        replyTextStack.spacing = MessageCellMetrics.replyRowSpacing
        replyTextStack.alignment = .leading
        replyTextStack.translatesAutoresizingMaskIntoConstraints = false

        // Outer row: text column (fills) | thumbnail (fixed, trailing)
        let replyContentRow = UIStackView(arrangedSubviews: [replyTextStack, replyThumbnailView])
        replyContentRow.axis = .horizontal
        replyContentRow.spacing = MessageCellMetrics.replyContentRowSpacing
        replyContentRow.alignment = .center
        replyContentRow.translatesAutoresizingMaskIntoConstraints = false

        replyPreviewContainer.addSubview(replyContentRow)

        // Accent bar on the left side (always LTR)
        let accentBarLeading = replyAccentBar.leftAnchor.constraint(equalTo: replyPreviewContainer.leftAnchor, constant: MessageCellMetrics.replyAccentBarLeading)
        let accentBarTop = replyAccentBar.topAnchor.constraint(equalTo: replyPreviewContainer.topAnchor, constant: MessageCellMetrics.replyAccentBarPadV)
        let accentBarBottom = replyAccentBar.bottomAnchor.constraint(equalTo: replyPreviewContainer.bottomAnchor, constant: -MessageCellMetrics.replyAccentBarPadV)
        let accentBarWidth = replyAccentBar.widthAnchor.constraint(equalToConstant: MessageCellMetrics.replyAccentBarWidth)

        // Content row sits to the right of the accent bar
        let contentRowLeading = replyContentRow.leftAnchor.constraint(equalTo: replyAccentBar.rightAnchor, constant: MessageCellMetrics.replyAccentToContentGap)
        let contentRowTrailing = replyContentRow.rightAnchor.constraint(equalTo: replyPreviewContainer.rightAnchor, constant: -MessageCellMetrics.replyContentRowTrailing)

        NSLayoutConstraint.activate([
            accentBarLeading,
            accentBarTop, accentBarBottom, accentBarWidth,

            contentRowLeading,
            contentRowTrailing,
            replyContentRow.topAnchor.constraint(equalTo: replyPreviewContainer.topAnchor, constant: MessageCellMetrics.replyContentRowPadV),
            replyContentRow.bottomAnchor.constraint(equalTo: replyPreviewContainer.bottomAnchor, constant: -MessageCellMetrics.replyContentRowPadV),

            // Type icon: small fixed square
            replyTypeIconView.widthAnchor.constraint(equalToConstant: MessageCellMetrics.replyTypeIconSize),
            replyTypeIconView.heightAnchor.constraint(equalToConstant: MessageCellMetrics.replyTypeIconSize),

            // Thumbnail: fixed 48x48 on the trailing side
            replyThumbnailView.widthAnchor.constraint(equalToConstant: MessageCellMetrics.replyThumbnailSize),
            replyThumbnailView.heightAnchor.constraint(equalToConstant: MessageCellMetrics.replyThumbnailSize),
        ])
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGestureRecognizer = pan
        pan.delegate = self
        addGestureRecognizer(pan)

        let replyTap = UITapGestureRecognizer(target: self, action: #selector(handleReplyPreviewTap))
        replyPreviewContainer.addGestureRecognizer(replyTap)
        replyPreviewContainer.isUserInteractionEnabled = true
    }

    private func setupReactionPills() {
        for _ in 0..<4 {
            let pill = ReactionPillView()
            pill.isHidden = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleReactionTap(_:)))
            pill.addGestureRecognizer(tap)
            pill.isUserInteractionEnabled = true
            reactionsStackView.addArrangedSubview(pill)
            reactionPills.append(pill)
        }
    }

    // MARK: - Configuration

    /// Single entry point called by the data source — base + content configured together.
    func configure(with model: MessageCellModel, isInSelectionMode: Bool = false) {
        self.cellModel = model
        panGestureRecognizer?.isEnabled = !model.isDeletedState

        configureLayout(model: model)
        configureSenderName(model: model)
        configureReplyPreview(model: model)
        if model.isDeletedState {
            configureDeletedContent(model: model)
        } else {
            configureContent(with: model)
        }
        configureFooter(model: model)
        configureReactions(model: model)
        configureTags(model: model)
        configureSelection(model: model, isInSelectionMode: isInSelectionMode)
        if !model.isDeletedState {
            configureBubbleAppearance(model: model)
        }
        applyDeletedStateIfNeeded(model: model)
    }

    private func configureDeletedContent(model: MessageCellModel) {
        deletedLabel.text = model.displayContent.isEmpty
            ? ChatStrings.chat_messageDeleted.localizedString()
            : model.displayContent
        deletedLabel.textColor = .secondaryLabel
    }

    private func applyDeletedStateIfNeeded(model: MessageCellModel) {
        guard model.isDeletedState else {
            csTop?.isActive = true
            csBottom?.isActive = true
            csLeading?.isActive = true
            csTrailing?.isActive = true
            overlayTopCS?.isActive = false
            overlayBottomCS?.isActive = false
            overlayLeadingCS?.isActive = false
            overlayTrailingCS?.isActive = false
            contentStackView.isHidden = false
            deletedOverlay.isHidden = true
            bubbleContainer.clipsToBounds = false
            bubbleContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
            bubbleContainer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            return
        }

        csTop?.isActive = false
        csBottom?.isActive = false
        csLeading?.isActive = false
        csTrailing?.isActive = false
        overlayTopCS?.isActive = true
        overlayBottomCS?.isActive = true
        overlayLeadingCS?.isActive = true
        overlayTrailingCS?.isActive = true

        bubbleContainer.backgroundColor = UIColor.secondarySystemBackground
        bubbleContainer.layer.cornerRadius = 16
        bubbleContainer.clipsToBounds = true
        bubbleContainer.setContentHuggingPriority(.required, for: .vertical)
        bubbleContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        replyPreviewContainer.isHidden = true
        reactionsStackView.isHidden = true
        forwardedContainer.isHidden = true
        pinnedContainer.isHidden = true
        editedLabel.isHidden = true
        statusImageView.isHidden = true
        messageColumnStack.setCustomSpacing(MessageCellMetrics.columnSpacing, after: bubbleContainer)

        contentStackView.isHidden = true
        deletedOverlay.isHidden = false

        setNeedsLayout()
        layoutIfNeeded()
    }

    private func configureLayout(model: MessageCellModel) {
        let isIncoming = model.isIncoming

        // Toggle constraint pair: incoming = left-pinned, outgoing = right-pinned
        if isIncoming {
            outgoingLeadingConstraint?.isActive = false
            outgoingTrailingConstraint?.isActive = false
            contentLeadingConstraint?.isActive = true
            contentTrailingConstraint?.isActive = true
        } else {
            contentLeadingConstraint?.isActive = false
            contentTrailingConstraint?.isActive = false
            outgoingLeadingConstraint?.isActive = true
            outgoingTrailingConstraint?.isActive = true
        }

        containerStackView.alignment = .top
        messageColumnStack.semanticContentAttribute = isIncoming ? .forceLeftToRight : .forceRightToLeft
        messageColumnStack.alignment = .leading

        // Reactions spacing: overlap 10pt into bubble so pills sit half on bubble, half below
        let reactionSpacing: CGFloat = MessageCellMetrics.reactionBubbleOverlap
        messageColumnStack.setCustomSpacing(reactionsStackView.isHidden ? MessageCellMetrics.columnSpacing : reactionSpacing, after: bubbleContainer)

        // Compute content-driven bubble width
        bubbleWidthConstraint?.constant = computeBubbleWidth(for: model)
    }

    private func computeBubbleWidth(for model: MessageCellModel) -> CGFloat {
        if model.isDeletedState {
            return MessageCellModel.deletedBubbleWidth(for: model.displayContent)
        }
        return MessageCellModel.computeBubbleWidth(
            kind: model.kind,
            displayContent: model.displayContent,
            isSingleEmoji: model.isSingleEmoji,
            hasReply: model.replyPreview != nil,
            showingTranslation: model.isShowingTranslation,
            mentionedUserNames: model.mentionedUserNames
        )
    }

//    private func configureSenderName(model: MessageCellModel) {
//        guard model.isIncoming, model.isGroupChat, let name = model.senderName else {
//            senderNameLabel.isHidden = true
//            return
//        }
//        senderNameLabel.text = name
//        senderNameLabel.isHidden = false
//    }
    
    private func configureSenderName(model: MessageCellModel) {
        let showHeader = model.isIncoming && model.isGroupChat
        guard showHeader else {
            senderHeaderStack.isHidden = true
            senderNameLabel.isHidden = true
            return
        }

        senderHeaderStack.isHidden = false

        let name = model.senderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
            senderNameLabel.text = name
            senderNameLabel.isHidden = false
        } else {
            senderNameLabel.text = nil
            senderNameLabel.isHidden = true
        }
    }

    private func configureReplyPreview(model: MessageCellModel) {
        guard let reply = model.replyPreview else {
            replyPreviewContainer.isHidden = true
            return
        }
        replyPreviewContainer.isHidden = false

        let isIncoming = model.isIncoming

        // Container background
        if model.isSingleEmoji {
            replyPreviewContainer.backgroundColor = UIColor.white.withAlphaComponent(0.92)
            replyAccentBar.backgroundColor = BaseMessageCell.replyGold
        } else {
            replyPreviewContainer.backgroundColor = isIncoming
                ? ChatTheme.primary.withAlphaComponent(0.08)
                : UIColor.white.withAlphaComponent(0.22)
            replyAccentBar.backgroundColor = isIncoming
                ? ChatTheme.primary
                : UIColor.white.withAlphaComponent(0.90)
        }

        // Accent bar + sender name
        let replySenderColor: UIColor
        if model.isSingleEmoji {
            replySenderColor = BaseMessageCell.replyGold
        } else {
            replySenderColor = isIncoming ? ChatTheme.primary : .white
        }
        let replySenderParagraphStyle = NSMutableParagraphStyle()
        replySenderParagraphStyle.minimumLineHeight = 15
        replySenderLabel.attributedText = NSAttributedString(
            string: reply.senderName,
            attributes: [
                .font: UIFont.chat(.semibold, size: 11),
                .foregroundColor: replySenderColor,
                .paragraphStyle: replySenderParagraphStyle
            ]
        )

        // Icon + preview text colours
        let iconTint: UIColor
        if model.isSingleEmoji {
            iconTint = .secondaryLabel
        } else {
            iconTint = isIncoming
                ? UIColor.secondaryLabel
                : UIColor.white.withAlphaComponent(0.65)
        }

        // Per-type icon and preview text
        let iconName: String?
        switch reply.messageType {
        case "image":             iconName = "photo"
        case "video":             iconName = "video.fill"
        case "audio", "voice":    iconName = "mic.fill"
        case "post":              iconName = "square.stack.fill"
        case "reel":              iconName = "play.rectangle.fill"
        case "story":             iconName = "circle.dashed"
        case "poll":              iconName = "chart.bar.fill"
        case "location":          iconName = "location.fill"
        case "contact":           iconName = "person.fill"
        case "document":          iconName = "doc.fill"
        case "sticker":           iconName = "sticker"
        default:                  iconName = nil
        }

        let previewText: String
        let typeName = ConversationMessage.messageTypeDisplayName(reply.messageType)
        if typeName.isEmpty || typeName == ChatStrings.chat_message.localizedString() {
            previewText = reply.content.isEmpty ? ChatStrings.chat_message.localizedString() : reply.content
        } else {
            previewText = typeName
        }

        if let iconName, let img = UIImage(systemName: iconName) {
            replyTypeIconView.image = img
            replyTypeIconView.tintColor = iconTint
            replyTypeIconView.isHidden = false
        } else {
            replyTypeIconView.isHidden = true
        }
        let replyParagraphStyle = NSMutableParagraphStyle()
        replyParagraphStyle.minimumLineHeight = 15
        let replyContentColor: UIColor
        if model.isSingleEmoji {
            replyContentColor = .secondaryLabel
        } else {
            replyContentColor = isIncoming
                ? .secondaryLabel
                : UIColor.white.withAlphaComponent(0.75)
        }
        replyContentLabel.attributedText = NSAttributedString(string: previewText.htmlToString, attributes: [
            .font: UIFont.chat(size: 11),
            .foregroundColor: replyContentColor,
            .paragraphStyle: replyParagraphStyle
        ])

        // Thumbnail — visible only for media-backed types that have a URL
        replyThumbnailView.kf.cancelDownloadTask()
        replyThumbnailView.image = nil
        let thumbnailTypes = ["image", "video", "reel", "post", "story"]
        guard thumbnailTypes.contains(reply.messageType) else {
            replyThumbnailView.isHidden = true
            return
        }
        replyThumbnailView.isHidden = false

        if !reply.messageId.isEmpty,
           let cached = InMemoryMediaCache.shared.getCachedImage(for: reply.messageId) {
            replyThumbnailView.image = cached
            return
        }

        if !reply.messageId.isEmpty {
            if reply.messageType == "image",
               let localURL = MediaStorageManager.shared.getMediaURL(messageId: reply.messageId, type: .image),
               let localImage = UIImage(contentsOfFile: localURL.path) {
                replyThumbnailView.image = localImage
                InMemoryMediaCache.shared.cacheImage(localImage, for: reply.messageId)
                return
            }
            if reply.messageType == "video",
               let diskThumb = MediaStorageManager.shared.getVideoThumbnail(messageId: reply.messageId) {
                replyThumbnailView.image = diskThumb
                InMemoryMediaCache.shared.cacheImage(diskThumb, for: reply.messageId)
                return
            }
        }

        if let thumbURL = reply.thumbnailURL, let url = URL(string: thumbURL) {
            replyThumbnailView.kf.setImage(
                with: url,
                options: [.cacheOriginalImage, .loadDiskFileSynchronously]
            )
        } else {
            replyThumbnailView.isHidden = true
        }
    }

    private func configureFooter(model: MessageCellModel) {
        timeLabel.text = model.timeText

        // Edited label: fade in when transitioning from unedited → edited
        let isNowEdited = model.isEdited
        if isNowEdited && !wasPreviouslyEdited {
            editedLabel.alpha = 0
            editedLabel.isHidden = false
            UIView.animate(withDuration: 0.25) {
                self.editedLabel.alpha = 1
            }
        } else {
            editedLabel.isHidden = !isNowEdited
            editedLabel.alpha = 1
        }
        wasPreviouslyEdited = isNowEdited

        timeLabel.textColor = model.isIncoming ? ChatTheme.timeIncoming : ChatTheme.timeOutgoing
        editedLabel.textColor = timeLabel.textColor

        if !model.isIncoming {
            statusImageView.isHidden = false
            statusImageView.image = model.deliveryStatus.icon
            statusImageView.tintColor = model.deliveryStatus.tintColor
        } else {
            statusImageView.isHidden = true
        }

        let currentSubviews = footerStackView.arrangedSubviews
        for subview in currentSubviews {
            footerStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        if model.isIncoming {
            footerStackView.addArrangedSubview(timeLabel)
            footerStackView.addArrangedSubview(editedLabel)
            footerStackView.alignment = .leading
        } else {
            footerStackView.addArrangedSubview(editedLabel)
            footerStackView.addArrangedSubview(timeLabel)
            footerStackView.addArrangedSubview(statusImageView)
            footerStackView.alignment = .trailing
        }
    }

    private func configureReactions(model: MessageCellModel) {
        let reactions = model.reactions.prefix(4)

        for (index, pill) in reactionPills.enumerated() {
            if index < reactions.count {
                let reaction = reactions[reactions.index(reactions.startIndex, offsetBy: index)]
                pill.configure(emoji: reaction.emoji, count: reaction.count, isOwnReaction: false)
                pill.isHidden = false
            } else {
                pill.isHidden = true
            }
        }
        reactionsStackView.isHidden = reactions.isEmpty

        // Spacing: reactions overlap bubble, footer sits below with breathing room
        if !reactions.isEmpty {
            messageColumnStack.setCustomSpacing(MessageCellMetrics.reactionBubbleOverlap, after: bubbleContainer)
            messageColumnStack.setCustomSpacing(MessageCellMetrics.reactionPostGap, after: reactionsStackView)
        } else {
            messageColumnStack.setCustomSpacing(MessageCellMetrics.columnSpacing, after: bubbleContainer)
        }
    }

    private func configureTags(model: MessageCellModel) {
        forwardedContainer.isHidden = !model.isForwarded
        pinnedContainer.isHidden = !model.isPinned
    }

    private func configureSelection(model: MessageCellModel, isInSelectionMode: Bool) {
        applySelectionConstraints(model: model, isInSelectionMode: isInSelectionMode)

        // Block all message interactions in selection mode (media, polls, links, maps, reply preview)
        contentArea.isUserInteractionEnabled = !isInSelectionMode
        replyPreviewContainer.isUserInteractionEnabled = !isInSelectionMode
        panGestureRecognizer?.isEnabled = !isInSelectionMode

        guard isInSelectionMode || model.isSelected else {
            selectionCheckbox.isHidden = true
            checkmarkImageView.isHidden = true
            return
        }
        selectionCheckbox.isHidden = false
        updateCheckboxAppearance(isSelected: model.isSelected)
    }

    /// Called when entering/exiting selection mode — animates cell shift + checkbox fade
    func animateSelectionTransition(isInSelectionMode: Bool, isSelected: Bool) {
        guard let model = cellModel else { return }
        applySelectionConstraints(model: model, isInSelectionMode: isInSelectionMode)

        // Block/restore message interactions
        contentArea.isUserInteractionEnabled = !isInSelectionMode
        replyPreviewContainer.isUserInteractionEnabled = !isInSelectionMode
        panGestureRecognizer?.isEnabled = !isInSelectionMode

        if isInSelectionMode {
            selectionCheckbox.alpha = 0
            selectionCheckbox.isHidden = false
            updateCheckboxAppearance(isSelected: isSelected)
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                self.selectionCheckbox.alpha = 1
                self.contentView.layoutIfNeeded()
            }
        } else {
            updateCheckboxAppearance(isSelected: false)
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: {
                self.selectionCheckbox.alpha = 0
                self.contentView.layoutIfNeeded()
            }) { _ in
                if !isInSelectionMode {
                    self.selectionCheckbox.isHidden = true
                    self.checkmarkImageView.isHidden = true
                }
            }
        }
    }

    /// Called when tapping a cell to toggle selection — only animates the checkbox
    func animateCheckboxToggle(isSelected: Bool) {
        if isSelected {
            checkmarkImageView.isHidden = false
            checkmarkImageView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            selectionCheckbox.backgroundColor = BaseMessageCell.brandOrange
            selectionCheckbox.layer.borderColor = BaseMessageCell.brandOrange.cgColor
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: .curveEaseOut) {
                self.checkmarkImageView.transform = .identity
            }
        } else {
            UIView.animate(withDuration: 0.2, animations: {
                self.checkmarkImageView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
                self.selectionCheckbox.alpha = 0.7
            }) { _ in
                self.checkmarkImageView.isHidden = true
                self.checkmarkImageView.transform = .identity
                self.selectionCheckbox.backgroundColor = .clear
                self.selectionCheckbox.layer.borderColor = UIColor.gray.withAlphaComponent(0.4).cgColor
                self.selectionCheckbox.alpha = 1
            }
        }
    }

    private func applySelectionConstraints(model: MessageCellModel, isInSelectionMode: Bool) {
        // Deactivate all selection constraints first
        selectionIncomingLeading?.isActive = false
        selectionOutgoingLeading?.isActive = false
        selectionIncomingRTL?.isActive = false
        selectionOutgoingRTL?.isActive = false

        if isInSelectionMode {
            if isRTL {
                // RTL: checkbox is on the right side
                if model.isIncoming {
                    // Incoming: keep left pin (contentLeadingConstraint), limit right edge to checkbox
                    contentTrailingConstraint?.isActive = false
                    // contentLeadingConstraint stays active — checkbox is on the right, not the left
                    selectionIncomingRTL?.isActive = true
                } else {
                    // Outgoing: pin right edge to checkbox, deactivate both normal constraints
                    outgoingLeadingConstraint?.isActive = false
                    outgoingTrailingConstraint?.isActive = false
                    selectionOutgoingRTL?.isActive = true
                }
            } else {
                // LTR: checkbox is on the left side
                contentLeadingConstraint?.isActive = false
                outgoingLeadingConstraint?.isActive = false
                if model.isIncoming {
                    selectionIncomingLeading?.isActive = true
                } else {
                    selectionOutgoingLeading?.isActive = true
                }
            }
        } else {
            // Restore normal layout constraints
            if model.isIncoming {
                contentLeadingConstraint?.isActive = true
                contentTrailingConstraint?.isActive = true
            } else {
                outgoingLeadingConstraint?.isActive = true
                outgoingTrailingConstraint?.isActive = true
            }
        }
    }

    private func updateCheckboxAppearance(isSelected: Bool) {
        if isSelected {
            checkmarkImageView.isHidden = false
            selectionCheckbox.backgroundColor = BaseMessageCell.brandOrange
            selectionCheckbox.layer.borderColor = BaseMessageCell.brandOrange.cgColor
        } else {
            checkmarkImageView.isHidden = true
            selectionCheckbox.backgroundColor = .clear
            selectionCheckbox.layer.borderColor = UIColor.gray.withAlphaComponent(0.4).cgColor
        }
    }

    func configureBubbleAppearance(model: MessageCellModel) {
        bubbleContainer.backgroundColor = model.isIncoming ? ChatTheme.incomingBubble : ChatTheme.outgoingBubble

        let isTextLike: Bool
        switch model.kind {
        case .text, .unknown:
            isTextLike = true
        default:
            isTextLike = false
        }
        bubbleContainer.layer.cornerRadius = isTextLike ? 18 : 14
    }

    func applyHighlight() {
        let cornerRadius = bubbleContainer.layer.cornerRadius > 0
            ? bubbleContainer.layer.cornerRadius
            : 12
        highlightOverlay.layer.cornerRadius = cornerRadius
        highlightOverlay.alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.highlightOverlay.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.6, delay: 0.8) {
                self.highlightOverlay.alpha = 0
            }
        }
    }
    
//    func updateReplyPreviewForOutgoingBubble() {
//        replyAccentBar.backgroundColor = UIColor.white.withAlphaComponent(0.9)
//        let ps = NSMutableParagraphStyle()
//        ps.minimumLineHeight = 15
//
//        if let senderText = replySenderLabel.attributedText?.string {
//            replySenderLabel.attributedText = NSAttributedString(
//                string: senderText.htmlToString,
//                attributes: [
//                    .font: UIFont.chat(.semibold, size: 11),
//                    .foregroundColor: UIColor.white,
//                    .paragraphStyle: ps
//                ]
//            )
//        }
//
//        if let contentText = replyContentLabel.attributedText?.string {
//            replyContentLabel.attributedText = NSAttributedString(
//                string: contentText.htmlToString,
//                attributes: [
//                    .font: UIFont.chat(size: 11),
//                    .foregroundColor: UIColor.white.withAlphaComponent(0.85),
//                    .paragraphStyle: ps
//                ]
//            )
//        }
//
//        replyTypeIconView.tintColor = UIColor.white.withAlphaComponent(0.85)
//    }

    func updateReplyPreviewForLightBubble() {
        replyPreviewContainer.backgroundColor = UIColor.black.withAlphaComponent(0.05)
        replyAccentBar.backgroundColor = BaseMessageCell.replyGold

        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight = 15

        if let senderText = replySenderLabel.attributedText?.string {
            replySenderLabel.attributedText = NSAttributedString(string: senderText.htmlToString, attributes: [
                .font: UIFont.chat(.semibold, size: 11),
                .foregroundColor: BaseMessageCell.replyGold,
                .paragraphStyle: ps
            ])
        }
        if let contentText = replyContentLabel.attributedText?.string {
            replyContentLabel.attributedText = NSAttributedString(string: contentText.htmlToString, attributes: [
                .font: UIFont.chat(size: 11),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: ps
            ])
        }
        replyTypeIconView.tintColor = .secondaryLabel
    }

    func wrapInReplyBubble(model: MessageCellModel, innerInsets: CGFloat = MessageCellMetrics.mediaReplyBubblePadH) {
        guard model.replyPreview != nil else { return }
        bubbleContainer.backgroundColor = model.isIncoming ? ChatTheme.incomingBubble : ChatTheme.outgoingBubble
        bubbleContainer.layer.cornerRadius = 18
        bubbleContainer.clipsToBounds = true
        setBubbleContentInsets(top: innerInsets, horizontal: innerInsets, bottom: innerInsets)
    }

    // MARK: - Subclass Override Points

    func configureContent(with model: MessageCellModel) {
        // Override in subclasses
    }

    // MARK: - Layout


    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()

        // Reset transforms/animations
        layer.removeAllAnimations()
        contentView.layer.removeAllAnimations()
        bubbleContainer.layer.removeAllAnimations()
        highlightOverlay.layer.removeAllAnimations()

        transform = .identity
        contentView.transform = .identity
        bubbleContainer.transform = .identity

        alpha = 1
        contentView.alpha = 1
        bubbleContainer.alpha = 1
        highlightOverlay.alpha = 0

        // Reset bubble
        bubbleContainer.backgroundColor = .clear
        bubbleContainer.layer.cornerRadius = 16
        bubbleContainer.layer.mask = nil
        bubbleContainer.clipsToBounds = false

        // Reset stack states
        reactionsStackView.isHidden = true
        replyPreviewContainer.isHidden = true
        senderHeaderStack.isHidden = true
        senderNameLabel.isHidden = true
        deletedOverlay.isHidden = true
        deletedLabel.text = nil

        // Reset deleted-state constraints
        csTop?.constant = MessageCellMetrics.textProfilePadTop
        csBottom?.constant = -MessageCellMetrics.textProfilePadBottom
        csLeading?.constant = MessageCellMetrics.textProfilePadH
        csTrailing?.constant = -MessageCellMetrics.textProfilePadH
        csTop?.isActive = true
        csBottom?.isActive = true
        csLeading?.isActive = true
        csTrailing?.isActive = true
        overlayTopCS?.isActive = false
        overlayBottomCS?.isActive = false
        overlayLeadingCS?.isActive = false
        overlayTrailingCS?.isActive = false
        contentStackView.isHidden = false

        // Reset swipe state
        containerStackView.transform = .identity

        // VERY IMPORTANT
        layoutIfNeeded()
    }

    /// Snapshot of the bubble content for media viewer transition
    func snapshotThumbnail() -> UIImage? {
        let renderer = UIGraphicsImageRenderer(bounds: bubbleContainer.bounds)
        return renderer.image { _ in
            bubbleContainer.drawHierarchy(in: bubbleContainer.bounds, afterScreenUpdates: false)
        }
    }

    /// The media image view for Sceyt-style viewer transition. Subclasses with images override this.
    var mediaImageView: UIImageView? { nil }

    // MARK: - Gesture Handlers

    @objc private func handleTap() {
        guard let model = cellModel, !model.isDeletedState else { return }
        if model.isSelected || selectionCheckbox.isHidden == false {
            actionsDelegate?.cellDidToggleSelection(self, messageId: model.stableId)
            return
        }
        actionsDelegate?.cellDidTapMessage(self, model: model)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let model = cellModel, !model.isDeletedState else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        actionsDelegate?.cellDidLongPress(self, model: model)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let model = cellModel, !model.isDeletedState else { return }

        // Block swipe-to-reply for pending/failed outgoing messages
        if !model.isIncoming && (model.deliveryStatus == .sending || model.deliveryStatus == .failed) {
            gesture.isEnabled = false
            gesture.isEnabled = true
            return
        }

        let translation = gesture.translation(in: contentView)
        let velocity = gesture.velocity(in: contentView)

        switch gesture.state {
        case .began:
            isSwipeActive = false
            hasPassedThreshold = false

        case .changed:
            var newX = translation.x
            // RTL: swipe LEFT to reply; LTR: swipe RIGHT to reply
            let swipePositive = isRTL ? (newX < 0) : (newX > 0)
            guard swipePositive else {
                if isSwipeActive { cancelSwipe() }
                return
            }
            newX = abs(newX) // Work with positive magnitude

            isSwipeActive = true

            let threshold: CGFloat = 50
            let maxOffset: CGFloat = 80

            if newX <= threshold {
                // Linear tracking up to threshold
            } else {
                // Elastic resistance beyond threshold
                let excess = newX - threshold
                newX = threshold + excess * 0.3
                if !hasPassedThreshold {
                    hasPassedThreshold = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            newX = min(newX, maxOffset)

            let direction: CGFloat = isRTL ? -1 : 1
            containerStackView.transform = CGAffineTransform(translationX: newX * direction, y: 0)

        case .ended, .cancelled:
            let signedTranslation = isRTL ? -translation.x : translation.x
            let signedVelocity = isRTL ? -velocity.x : velocity.x
            let shouldTrigger = hasPassedThreshold
                || signedTranslation > swipeThreshold
                || (signedVelocity > 300 && signedTranslation > 20)

            let horizontalDistance = abs(translation.x)
            let verticalDistance = abs(translation.y)
            let isHorizontalSwipe = horizontalDistance > verticalDistance * 1.5

            if shouldTrigger && isHorizontalSwipe {
                actionsDelegate?.cellDidSwipeToReply(self, model: model)
            }

            resetSwipeTransforms()

        default:
            resetSwipeTransforms()
        }
    }

    private func resetSwipeTransforms() {
        isSwipeActive = false
        hasPassedThreshold = false
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5, options: .curveEaseOut) {
            self.containerStackView.transform = .identity
        }
    }

    private func cancelSwipe() {
        isSwipeActive = false
        hasPassedThreshold = false
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3, options: .curveEaseOut) {
            self.containerStackView.transform = .identity
        }
    }

    @objc private func handleReplyPreviewTap() {
        guard let model = cellModel, let reply = model.replyPreview else { return }
        actionsDelegate?.cellDidTapReplyPreview(self, messageId: reply.messageId)
    }

    @objc private func handleReactionTap(_ gesture: UITapGestureRecognizer) {
        guard let model = cellModel, !model.isDeletedState else { return }
        guard let tappedPill = gesture.view as? ReactionPillView,
              let index = reactionPills.firstIndex(of: tappedPill),
              index < model.reactions.count else { return }
        actionsDelegate?.cellDidTapReaction(self, model: model, reaction: model.reactions[index])
    }
}

// MARK: - Gesture Recognizer Delegate

extension BaseMessageCell: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: contentView)
        // LTR: right swipe; RTL: left swipe (WhatsApp-style swipe-to-reply)
        let signedVelocity = isRTL ? -velocity.x : velocity.x
        return signedVelocity > abs(velocity.y) * 1.5 && signedVelocity > 50
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Do NOT allow simultaneous with scroll view pan — prevents the flash
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't let the cell-level tap gesture absorb taps on reaction pills
        if gestureRecognizer is UITapGestureRecognizer && !(gestureRecognizer.view is ReactionPillView) {
            if touch.view is ReactionPillView { return false }
        }
        return true
    }
}


final class ReactionPillView: UIView {

    private let emojiLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.chat(size: 16)
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    private let countLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.chat(.medium, size: 10)
        l.textColor = .secondaryLabel
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true

        let hStack = UIStackView(arrangedSubviews: [emojiLabel, countLabel])
        hStack.axis = .horizontal
        hStack.spacing = 2
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hStack)

        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            hStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ReactionPillView else { return false }
        return self === other
    }

    func configure(emoji: String, count: Int, isOwnReaction: Bool) {
        emojiLabel.text = emoji
        countLabel.text = count > 1 ? "\(count)" : nil
        countLabel.isHidden = count <= 1
    }
}
