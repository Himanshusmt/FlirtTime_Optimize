//
//  MomentsCommentTableViewCell.swift
//  FlirttimeNew
//

import UIKit

/// Row used by the comment sheet and the received-gifts sheet.
final class MomentsCommentTableViewCell: UITableViewCell {

    static let identifier = "MomentsCommentTableViewCell"

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 18
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
        label.font = UIFont.fredoka(.regular, size: 13)
        label.textColor = AppColor.SilverChalice
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 15)
        label.textColor = AppColor.MineShaft
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
        button.setImage(UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)), for: .normal)
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
        textStack.spacing = 4

        [avatarImageView, textStack, trailingLabel, deleteButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        let bottom = textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        bottom.priority = .defaultHigh

        let textTrailing = textStack.trailingAnchor.constraint(equalTo: trailingLabel.leadingAnchor, constant: -8)
        textTrailing.priority = .defaultHigh
        deleteSpacing = textStack.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -4)

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.widthAnchor.constraint(equalToConstant: 36),
            avatarImageView.heightAnchor.constraint(equalToConstant: 36),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            textTrailing,
            bottom,

            trailingLabel.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            trailingLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            deleteButton.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            deleteButton.widthAnchor.constraint(equalToConstant: 30),
            deleteButton.heightAnchor.constraint(equalToConstant: 30)
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
