import UIKit

final class ChatBlockOverlayView: UIView {

    var onUnblock: (() -> Void)?
    var onDeleteChat: (() -> Void)?

    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.medium, size: 18)
        lbl.textColor = .black
        lbl.text = ChatStrings.chat_userBlocked.localizedString()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let messageLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(size: 14)
        lbl.textColor = .gray
        lbl.numberOfLines = 0
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let unblockButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(ChatStrings.chat_unblock.localizedString(), for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = UIFont.chat(.semibold, size: 15)
        btn.backgroundColor = ChatTheme.primaryLight
        btn.layer.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let deleteButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(ChatStrings.chat_deleteChat.localizedString(), for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = UIFont.chat(.semibold, size: 15)
        btn.backgroundColor = .systemRed
        btn.layer.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var buttonStack: UIStackView = {
        let sv = UIStackView(arrangedSubviews: [unblockButton, deleteButton])
        sv.axis = .horizontal
        sv.spacing = 12
        sv.distribution = .fillEqually
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
        backgroundColor = .white

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: -1)

        addSubview(titleLabel)
        addSubview(messageLabel)
        addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            buttonStack.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 16),
            buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            buttonStack.heightAnchor.constraint(equalToConstant: 44),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])

        unblockButton.addTarget(self, action: #selector(unblockTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        enforceRTLIfNeeded()
    }

    func configure(userName: String?) {
        let name = userName ?? "user"
        messageLabel.text = String(format: ChatStrings.chat_unblockToSend.localizedString(), name)
    }

    @objc private func unblockTapped() { onUnblock?() }
    @objc private func deleteTapped() { onDeleteChat?() }
}
