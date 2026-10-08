import UIKit

/// Banner shown in a group chat when a call is still live (left, missed, or after app kill).
final class ChatGroupCallRejoinBanner: UIView {

    var onRejoin: (() -> Void)?

    private let iconView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "phone.fill"))
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.semibold, size: 13)
        lbl.textColor = .white
        lbl.text = "Group call ongoing"
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let subtitleLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.regular, size: 11)
        lbl.textColor = UIColor.white.withAlphaComponent(0.85)
        lbl.text = "Tap to join"
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let rejoinButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Join", for: .normal)
        btn.setTitleColor(.systemGreen, for: .normal)
        btn.titleLabel?.font = UIFont.chat(.bold, size: 13)
        btn.backgroundColor = .white
        btn.layer.cornerRadius = 14
        btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = UIColor(red: 0.13, green: 0.55, blue: 0.30, alpha: 1)
        translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(textStack)
        addSubview(rejoinButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: rejoinButton.leadingAnchor, constant: -10),

            rejoinButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rejoinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            rejoinButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        rejoinButton.addTarget(self, action: #selector(rejoinTapped), for: .touchUpInside)
        let tap = UITapGestureRecognizer(target: self, action: #selector(rejoinTapped))
        addGestureRecognizer(tap)
    }

    func configure(isVideo: Bool) {
        iconView.image = UIImage(systemName: isVideo ? "video.fill" : "phone.fill")
        titleLabel.text = isVideo ? "Group video call ongoing" : "Group call ongoing"
    }

    @objc private func rejoinTapped() {
        onRejoin?()
    }
}
