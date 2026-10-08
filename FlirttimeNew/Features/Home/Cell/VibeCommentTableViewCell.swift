//
//  VibeCommentTableViewCell.swift
//  FlirttimeNew
//

import UIKit

/// Row used by the comment sheet and the received-gifts sheet.
final class VibeCommentTableViewCell: UITableViewCell {

    static let identifier = "VibeCommentTableViewCell"

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
    }

    private func setUI() {
        let headerStack = UIStackView(arrangedSubviews: [nameLabel, timeLabel, UIView()])
        headerStack.axis = .horizontal
        headerStack.alignment = .firstBaseline
        headerStack.spacing = 6

        let textStack = UIStackView(arrangedSubviews: [headerStack, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        [avatarImageView, textStack, trailingLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        let bottom = textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        bottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.widthAnchor.constraint(equalToConstant: 36),
            avatarImageView.heightAnchor.constraint(equalToConstant: 36),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: trailingLabel.leadingAnchor, constant: -8),
            bottom,

            trailingLabel.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            trailingLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }

    func configure(with comment: VibeComment) {
        avatarImageView.loadImage(path: comment.author?.profilePicture, placeholder: UIImage(named: "dummy_Profile"))
        nameLabel.text = comment.author?.displayName
        timeLabel.text = VibeDate.timeAgo(from: comment.createdAt)
        bodyLabel.text = comment.body
        trailingLabel.text = nil
    }

    func configure(with receivedGift: VibeReceivedGift) {
        avatarImageView.loadImage(path: receivedGift.sender?.profilePicture, placeholder: UIImage(named: "dummy_Profile"))
        nameLabel.text = receivedGift.sender?.displayName
        timeLabel.text = VibeDate.timeAgo(from: receivedGift.createdAt)
        let coins = receivedGift.coinsUsed ?? receivedGift.gift?.amount ?? 0
        bodyLabel.text = "Sent you a \(receivedGift.gift?.title ?? "gift") · \(coins) coins"
        trailingLabel.text = receivedGift.gift?.icon
    }
}
