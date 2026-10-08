import UIKit

final class ContactMessageCell: BaseMessageCell {

    static let cellId = "ContactMessageCell"

    // MARK: - Subviews

    private let avatarView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 18
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let initialsLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.chat(.semibold, size: 15)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.chat(.semibold, size: 15)
        label.numberOfLines = 1
        label.textAlignment = .natural
        return label
    }()

    private let phoneLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.chat(size: 13)
        label.numberOfLines = 1
        label.textAlignment = .natural
        return label
    }()

    private let textStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 2
        sv.alignment = .leading
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupContentArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContentArea()
    }

    private func setupContentArea() {
        avatarView.addSubview(initialsLabel)
        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(phoneLabel)
        contentArea.addSubview(avatarView)
        contentArea.addSubview(textStack)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleContactTap))
        contentArea.addGestureRecognizer(tap)

        NSLayoutConstraint.activate([
            avatarView.leftAnchor.constraint(equalTo: contentArea.leftAnchor, constant: 4),
            avatarView.centerYAnchor.constraint(equalTo: contentArea.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),

            initialsLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            textStack.leftAnchor.constraint(equalTo: avatarView.rightAnchor, constant: 10),
            textStack.rightAnchor.constraint(equalTo: contentArea.rightAnchor, constant: -6),
            textStack.centerYAnchor.constraint(equalTo: contentArea.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: contentArea.topAnchor, constant: 6),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: contentArea.bottomAnchor, constant: -6),
        ])
    }

    // MARK: - Configure

    override func configureContent(with model: MessageCellModel) {
        let meta = model.message.metadata
        let contactName = meta?["contactName"]?.value as? String ?? ""
        let contactPhone = meta?["contactPhone"]?.value as? String ?? ""

        nameLabel.text = contactName.isEmpty ? ChatStrings.chat_contact.localizedString() : contactName
        initialsLabel.text = String((contactName.isEmpty ? "?" : contactName).prefix(1)).uppercased()
        phoneLabel.text = contactPhone.isEmpty ? nil : contactPhone
        phoneLabel.isHidden = contactPhone.isEmpty
    }

    override func configureBubbleAppearance(model: MessageCellModel) {
        bubbleContainer.backgroundColor = model.isIncoming ? ChatTheme.incomingBubble : ChatTheme.outgoingBubble
        bubbleContainer.layer.cornerRadius = 18

        if model.isIncoming {
            nameLabel.textColor = ChatTheme.incomingText
            phoneLabel.textColor = ChatTheme.primary
            avatarView.backgroundColor = ChatTheme.primary
            initialsLabel.textColor = .white
        } else {
            nameLabel.textColor = ChatTheme.outgoingText
            phoneLabel.textColor = ChatTheme.outgoingText.withAlphaComponent(0.85)
            avatarView.backgroundColor = .white
            initialsLabel.textColor = ChatTheme.primary
        }

        if model.replyPreview != nil {
            wrapInReplyBubble(model: model, innerInsets: 6)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        phoneLabel.text = nil
        initialsLabel.text = nil
        phoneLabel.isHidden = false
    }

    // MARK: - Actions

    @objc private func handleContactTap() {
        guard let model = cellModel else { return }
        guard let phone = model.message.metadata?["contactPhone"]?.value as? String, !phone.isEmpty,
              let presenter = UIApplication.shared.topViewController() else {
            actionsDelegate?.cellDidTapMessage(self, model: model)
            return
        }

        let alert = UIAlertController(title: phone, message: nil, preferredStyle: .actionSheet)
        alert.view.tintColor = ChatTheme.primary
        alert.addAction(UIAlertAction(title: ChatStrings.chat_call.localizedString(), style: .default) { _ in
            let digits = phone.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel://\(digits)"), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: ChatStrings.chat_copyPhone.localizedString(), style: .default) { _ in
            UIPasteboard.general.string = phone
        })
        alert.addAction(UIAlertAction(title: ChatStrings.chat_cancel.localizedString(), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = bubbleContainer
            popover.sourceRect = bubbleContainer.bounds
        }
        presenter.present(alert, animated: true)
    }
}
