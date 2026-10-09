//
//  NotificationTableViewCell.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 23/05/24.
//

import UIKit

final class NotificationTableViewCell: UITableViewCell {

    static let identifier = "NotificationTableViewCell"

    private static let avatarSize: CGFloat = 52
    private static let typeBadgeSize: CGFloat = 22

    private let cardView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        return view
    }()

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = NotificationTableViewCell.avatarSize / 2
        imageView.backgroundColor = AppColor.AppWhite
        return imageView
    }()

    private let typeBadgeView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = NotificationTableViewCell.typeBadgeSize / 2
        view.layer.borderWidth = 2
        view.layer.borderColor = AppColor.AppWhite.cgColor
        return view
    }()

    private let typeIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = AppColor.AppWhite
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.medium, size: 15)
        label.textColor = AppColor.MineShaft
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 13)
        label.textColor = AppColor.DoveGray
        label.numberOfLines = 2
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

    private let unreadDotView: UIView = {
        let view = UIView()
        view.backgroundColor = AppColor.Punch
        view.layer.cornerRadius = 4
        return view
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUI()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.image = nil
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        UIView.animate(withDuration: animated ? 0.15 : 0) {
            self.cardView.transform = highlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            self.cardView.alpha = highlighted ? 0.85 : 1
        }
    }

    private func setUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, timeLabel, unreadDotView])
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 8

        let textStack = UIStackView(arrangedSubviews: [titleRow, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 3

        contentView.addSubview(cardView)
        [avatarImageView, typeBadgeView, textStack].forEach(cardView.addSubview)
        typeBadgeView.addSubview(typeIconImageView)

        [cardView, avatarImageView, typeBadgeView, typeIconImageView, textStack, unreadDotView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            avatarImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            avatarImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -12),
            avatarImageView.widthAnchor.constraint(equalToConstant: Self.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Self.avatarSize),

            typeBadgeView.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 3),
            typeBadgeView.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 3),
            typeBadgeView.widthAnchor.constraint(equalToConstant: Self.typeBadgeSize),
            typeBadgeView.heightAnchor.constraint(equalToConstant: Self.typeBadgeSize),

            typeIconImageView.centerXAnchor.constraint(equalTo: typeBadgeView.centerXAnchor),
            typeIconImageView.centerYAnchor.constraint(equalTo: typeBadgeView.centerYAnchor),
            typeIconImageView.widthAnchor.constraint(equalToConstant: 11),
            typeIconImageView.heightAnchor.constraint(equalToConstant: 11),

            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -14),

            unreadDotView.widthAnchor.constraint(equalToConstant: 8),
            unreadDotView.heightAnchor.constraint(equalToConstant: 8)
        ])
    }

    func setUI(data: NotificationData) {
        let isUnread = data.isRead != true
        titleLabel.text = data.title
        bodyLabel.text = data.body
        timeLabel.text = data.createdDate.map(Self.shortElapsedText) ?? ""
        unreadDotView.isHidden = !isUnread
        cardView.backgroundColor = isUnread ? AppColor.Lavenderblush : AppColor.WildSand

        if let image = data.data?.image, !image.isEmpty {
            avatarImageView.contentMode = .scaleAspectFill
            avatarImageView.loadImage(path: image, placeholder: UIImage(named: "dummy_Profile"))
        } else {
            avatarImageView.contentMode = .scaleAspectFit
            avatarImageView.image = UIImage(named: "logo")
        }

        let style = Self.typeStyle(for: data.notificationType)
        typeBadgeView.backgroundColor = style.color
        typeIconImageView.image = UIImage(systemName: style.symbol,
                                          withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        accessibilityLabel = [data.title, data.body, timeLabel.text, isUnread ? "Unread" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private static func typeStyle(for type: NotificationType) -> (symbol: String, color: UIColor) {
        switch type {
        case .like:
            return ("heart.fill", AppColor.Punch)
        case .favorite:
            return ("star.fill", UIColor(named: "#4278FC") ?? .systemBlue)
        case .match:
            return ("sparkles", UIColor(named: "#F04349") ?? AppColor.Punch)
        case .compliment:
            return ("quote.bubble.fill", .systemPink)
        case .message:
            return ("message.fill", UIColor(named: "#4278FC") ?? .systemBlue)
        case .call, .missedCall:
            return ("phone.fill", UIColor(named: "#3BA575") ?? .systemGreen)
        case .gestureVerified, .imageVerified, .profileImageVerified:
            return ("checkmark.seal.fill", UIColor(named: "#3BA575") ?? .systemGreen)
        case .gestureUnverified, .imageUnverified, .profileImageUnverified, .incomplete:
            return ("exclamationmark", .systemOrange)
        case .membershipUpgrade:
            return ("crown.fill", .systemOrange)
        default:
            return ("bell.fill", AppColor.Punch)
        }
    }

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static func shortElapsedText(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        switch seconds {
        case ..<60:
            return "now"
        case ..<3600:
            return "\(Int(seconds / 60))m"
        case ..<86400:
            return "\(Int(seconds / 3600))h"
        default:
            if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
            if seconds < 7 * 86400 { return "\(Int(seconds / 86400))d" }
            return dayMonthFormatter.string(from: date)
        }
    }
}
