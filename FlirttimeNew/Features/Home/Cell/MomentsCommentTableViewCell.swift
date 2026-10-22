//
//  MomentsCommentTableViewCell.swift
//  FlirttimeNew
//

import UIKit

/// Row used by the comment sheet and the received-gifts sheet.
final class MomentsCommentTableViewCell: UITableViewCell {

    static let identifier = "MomentsCommentTableViewCell"

    private static let avatarSize: CGFloat = 40

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = AppColor.WildSand
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        return view
    }()

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = MomentsCommentTableViewCell.avatarSize / 2
        imageView.backgroundColor = AppColor.AthensGray
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.medium, size: 15)
        label.textColor = AppColor.MineShaft
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 12)
        label.textColor = AppColor.SilverChalice
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 14)
        label.textColor = AppColor.DoveGray
        label.numberOfLines = 0
        return label
    }()

    private let trailingLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 28)
        label.textAlignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    /// Shown only for comments the signed-in user can delete.
    private var onDelete: (() -> Void)?
    private var deleteSpacing: NSLayoutConstraint?

    private lazy var deleteButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)), for: .normal)
        button.tintColor = AppColor.SilverChalice
        button.accessibilityLabel = "Delete comment"
        button.isHidden = true
        button.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        setUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.image = nil
        trailingLabel.text = nil
        onDelete = nil
        deleteButton.isHidden = true
        deleteSpacing?.isActive = false
    }

    private func setUI() {
        let headerStack = UIStackView(arrangedSubviews: [nameLabel, timeLabel, UIView()])
        headerStack.axis = .horizontal
        headerStack.alignment = .firstBaseline
        headerStack.spacing = 6

        let textStack = UIStackView(arrangedSubviews: [headerStack, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)
        [avatarImageView, textStack, trailingLabel, deleteButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview($0)
        }

        let padding: CGFloat = 12
        let textTrailing = textStack.trailingAnchor.constraint(equalTo: trailingLabel.leadingAnchor, constant: -8)
        textTrailing.priority = .defaultHigh
        deleteSpacing = textStack.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -2)
        // Keeps the card as short as its tallest item (photo or text) while both stay centred.
        let compactHeight = cardView.heightAnchor.constraint(equalToConstant: 0)
        compactHeight.priority = .defaultLow

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            compactHeight,

            avatarImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: padding),
            avatarImageView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: Self.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Self.avatarSize),
            avatarImageView.topAnchor.constraint(greaterThanOrEqualTo: cardView.topAnchor, constant: padding),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -padding),

            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: cardView.topAnchor, constant: padding),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -padding),
            textTrailing,

            trailingLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            trailingLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),

            deleteButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -6),
            deleteButton.widthAnchor.constraint(equalToConstant: 36),
            deleteButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    func configure(with comment: MomentsComment, onDelete: (() -> Void)? = nil) {
        avatarImageView.loadImage(path: comment.author?.profilePicture, placeholder: UIImage(named: "dummy_Profile"))
        nameLabel.text = comment.author?.displayName
        timeLabel.text = MomentsDate.timeAgo(from: comment.createdAt)
        bodyLabel.text = comment.body
        trailingLabel.text = nil
        self.onDelete = onDelete
        deleteButton.isHidden = onDelete == nil
        deleteSpacing?.isActive = onDelete != nil
    }

    func configure(with receivedGift: MomentsReceivedGift) {
        avatarImageView.loadImage(path: receivedGift.sender?.profilePicture, placeholder: UIImage(named: "dummy_Profile"))
        nameLabel.text = receivedGift.sender?.displayName
        timeLabel.text = MomentsDate.timeAgo(from: receivedGift.createdAt)
        let coins = receivedGift.coinsUsed ?? receivedGift.gift?.amount ?? 0
        var body = "Sent you a \(receivedGift.gift?.title ?? "gift") · \(coins) coins"
        if let message = receivedGift.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            body += "\n\"\(message)\""
        }
        bodyLabel.text = body
        let icon = receivedGift.gift?.icon
        trailingLabel.text = icon?.hasPrefix("http") == true ? "🎁" : icon
    }
}

/// A comment or reply in the comment sheet: like, reply, delete and the "View replies" toggle.
final class MomentsCommentThreadCell: UITableViewCell {

    static let identifier = "MomentsCommentThreadCell"

    var onLike: (() -> Void)?
    var onReply: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleReplies: (() -> Void)?

    private static let rootAvatarSize: CGFloat = 36
    private static let replyAvatarSize: CGFloat = 28
    private static let replyIndent: CGFloat = 46

    private var avatarLeading: NSLayoutConstraint?
    private var avatarWidth: NSLayoutConstraint?
    private var avatarHeight: NSLayoutConstraint?

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = AppColor.AthensGray
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.medium, size: 14)
        label.textColor = AppColor.MineShaft
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 12)
        label.textColor = AppColor.SilverChalice
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 14)
        label.textColor = AppColor.MineShaft
        label.numberOfLines = 0
        return label
    }()

    private lazy var replyButton: UIButton = makeTextButton(title: "Reply") { [weak self] in self?.onReply?() }
    private lazy var deleteButton: UIButton = makeTextButton(title: "Delete") { [weak self] in self?.onDelete?() }

    private lazy var repliesToggleButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = UIFont.fredoka(.medium, size: 12)
        button.setTitleColor(AppColor.DoveGray, for: .normal)
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { [weak self] _ in self?.onToggleReplies?() }, for: .touchUpInside)
        return button
    }()

    private let repliesToggleLine: UIView = {
        let view = UIView()
        view.backgroundColor = AppColor.SilverChalice
        return view
    }()

    private lazy var repliesToggleRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [repliesToggleLine, repliesToggleButton, repliesSpinner, UIView()])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        return stack
    }()

    private let repliesSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = AppColor.SilverChalice
        spinner.hidesWhenStopped = true
        spinner.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        return spinner
    }()

    private lazy var likeButton: UIButton = {
        let button = UIButton(type: .custom)
        button.tintColor = AppColor.SilverChalice
        button.addAction(UIAction { [weak self] _ in self?.likeTapped() }, for: .touchUpInside)
        return button
    }()

    private let likesCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 11)
        label.textColor = AppColor.SilverChalice
        label.textAlignment = .center
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        setUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onLike = nil
        onReply = nil
        onDelete = nil
        onToggleReplies = nil
        repliesSpinner.stopAnimating()
    }

    private func makeTextButton(title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.fredoka(.medium, size: 12)
        button.setTitleColor(AppColor.DoveGray, for: .normal)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func setUI() {
        let headerStack = UIStackView(arrangedSubviews: [nameLabel, timeLabel, UIView()])
        headerStack.axis = .horizontal
        headerStack.alignment = .firstBaseline
        headerStack.spacing = 6

        let actionsStack = UIStackView(arrangedSubviews: [replyButton, deleteButton, UIView()])
        actionsStack.axis = .horizontal
        actionsStack.alignment = .center
        actionsStack.spacing = 16

        let textStack = UIStackView(arrangedSubviews: [headerStack, bodyLabel, actionsStack, repliesToggleRow])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setCustomSpacing(0, after: actionsStack)

        let likeStack = UIStackView(arrangedSubviews: [likeButton, likesCountLabel])
        likeStack.axis = .vertical
        likeStack.alignment = .center
        likeStack.spacing = 0

        [avatarImageView, textStack, likeStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        let avatarLeading = avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        let avatarWidth = avatarImageView.widthAnchor.constraint(equalToConstant: Self.rootAvatarSize)
        let avatarHeight = avatarImageView.heightAnchor.constraint(equalToConstant: Self.rootAvatarSize)
        self.avatarLeading = avatarLeading
        self.avatarWidth = avatarWidth
        self.avatarHeight = avatarHeight

        let avatarBottom = avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)

        NSLayoutConstraint.activate([
            avatarLeading, avatarWidth, avatarHeight, avatarBottom,
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: likeStack.leadingAnchor, constant: -8),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            likeStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            likeStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            likeStack.widthAnchor.constraint(equalToConstant: 36),
            likeButton.widthAnchor.constraint(equalToConstant: 32),
            likeButton.heightAnchor.constraint(equalToConstant: 28),

            replyButton.heightAnchor.constraint(equalToConstant: 28),
            repliesToggleLine.widthAnchor.constraint(equalToConstant: 24),
            repliesToggleLine.heightAnchor.constraint(equalToConstant: 1),
            repliesToggleButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    /// `thread` is set for top-level comments to show the "View replies" toggle.
    func configure(with comment: MomentsComment,
                   isReply: Bool,
                   thread: MomentsCommentThread? = nil,
                   isLoadingReplies: Bool = false,
                   canDelete: Bool) {
        let avatarSize = isReply ? Self.replyAvatarSize : Self.rootAvatarSize
        avatarLeading?.constant = isReply ? 16 + Self.replyIndent : 16
        avatarWidth?.constant = avatarSize
        avatarHeight?.constant = avatarSize
        avatarImageView.layer.cornerRadius = avatarSize / 2
        avatarImageView.loadImage(path: comment.author?.profilePicture, placeholder: UIImage(named: "dummy_Profile"))

        nameLabel.text = comment.author?.displayName
        timeLabel.text = MomentsDate.timeAgo(from: comment.createdAt)
        bodyLabel.attributedText = Self.highlightingMentions(in: comment.body ?? "")
        deleteButton.isHidden = !canDelete

        updateLike(isLiked: comment.isLiked ?? false, count: comment.likesCount ?? 0)
        updateRepliesToggle(thread: isReply ? nil : thread, isLoading: isLoadingReplies)

        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: comment.isLiked == true ? "Unlike comment" : "Like comment") { [weak self] _ in
                self?.onLike?()
                return true
            },
            UIAccessibilityCustomAction(name: "Reply") { [weak self] _ in
                self?.onReply?()
                return true
            }
        ] + (canDelete ? [UIAccessibilityCustomAction(name: "Delete comment") { [weak self] _ in
            self?.onDelete?()
            return true
        }] : [])
    }

    func updateRepliesToggle(thread: MomentsCommentThread?, isLoading: Bool) {
        let replyCount = thread?.replyCount ?? 0
        repliesToggleRow.isHidden = thread == nil || replyCount == 0
        guard let thread, replyCount > 0 else {
            repliesSpinner.stopAnimating()
            return
        }
        let title = thread.isExpanded
            ? "Hide replies"
            : "View \(replyCount) \(replyCount == 1 ? "reply" : "replies")"
        UIView.performWithoutAnimation {
            repliesToggleButton.setTitle(title, for: .normal)
            repliesToggleButton.layoutIfNeeded()
        }
        isLoading ? repliesSpinner.startAnimating() : repliesSpinner.stopAnimating()
    }

    func updateLike(isLiked: Bool, count: Int) {
        let symbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        likeButton.setImage(UIImage(systemName: isLiked ? "heart.fill" : "heart", withConfiguration: symbol), for: .normal)
        likeButton.tintColor = isLiked ? AppColor.Punch : AppColor.SilverChalice
        likeButton.accessibilityLabel = isLiked ? "Unlike comment" : "Like comment"
        likesCountLabel.text = count > 0 ? count.vibeCountText : nil
        likesCountLabel.isHidden = count == 0
    }

    private func likeTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.12, animations: {
            self.likeButton.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }, completion: { _ in
            UIView.animate(withDuration: 0.12) { self.likeButton.transform = .identity }
        })
        onLike?()
    }

    /// Colours "@username" mentions like the OneVibe comment list.
    private static func highlightingMentions(in text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.fredoka(.regular, size: 14),
            .foregroundColor: AppColor.MineShaft
        ])
        guard let regex = try? NSRegularExpression(pattern: "@\\S+") else { return attributed }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            attributed.addAttributes([
                .font: UIFont.fredoka(.medium, size: 14),
                .foregroundColor: AppColor.Punch
            ], range: match.range)
        }
        return attributed
    }
}
