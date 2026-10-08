import UIKit
import Kingfisher

// MARK: - Reply Banner

final class ChatReplyBanner: UIView {

    var onCancel: (() -> Void)?

    override var intrinsicContentSize: CGSize {
        isHidden ? .zero : super.intrinsicContentSize
    }

    private let accentBar: UIView = {
        let v = UIView()
        v.backgroundColor = ChatTheme.primary
        v.layer.cornerRadius = 1.5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let senderLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.semibold, size: 12)
        lbl.textColor = ChatTheme.primary
        lbl.lineBreakMode = .byTruncatingTail
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let previewLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(size: 12)
        lbl.textColor = .gray
        lbl.lineBreakMode = .byTruncatingTail
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let thumbnailImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 4
        iv.isHidden = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let playIconOverlay: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "play.fill"))
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.isHidden = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: ChatAssets.close)?.withRenderingMode(.alwaysTemplate), for: .normal)
        btn.tintColor = ChatTheme.textSecondary
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = UIColor.gray.withAlphaComponent(0.08)
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(accentBar)
        addSubview(senderLabel)
        addSubview(previewLabel)
        addSubview(thumbnailImageView)
        addSubview(playIconOverlay)
        addSubview(cancelButton)

        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            accentBar.centerYAnchor.constraint(equalTo: centerYAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 3),
            accentBar.heightAnchor.constraint(equalToConstant: 24),

            senderLabel.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 8),
            senderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            senderLabel.trailingAnchor.constraint(lessThanOrEqualTo: thumbnailImageView.leadingAnchor, constant: -8),

            previewLabel.leadingAnchor.constraint(equalTo: senderLabel.leadingAnchor),
            previewLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 0),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: thumbnailImageView.leadingAnchor, constant: -8),
            previewLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            thumbnailImageView.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
            thumbnailImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailImageView.widthAnchor.constraint(equalToConstant: 36),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 36),

            playIconOverlay.centerXAnchor.constraint(equalTo: thumbnailImageView.centerXAnchor),
            playIconOverlay.centerYAnchor.constraint(equalTo: thumbnailImageView.centerYAnchor),
            playIconOverlay.widthAnchor.constraint(equalToConstant: 14),
            playIconOverlay.heightAnchor.constraint(equalToConstant: 14),

            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 24),
            cancelButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        enforceRTLIfNeeded()
    }

    func configure(senderName: String, previewText: String, thumbnail: UIImage? = nil, isVideo: Bool = false) {
        senderLabel.text = senderName
        previewLabel.text = String(previewText.prefix(80)).htmlToString
        if let thumbnail {
            thumbnailImageView.isHidden = false
            thumbnailImageView.image = thumbnail
            playIconOverlay.isHidden = !isVideo
        } else {
            thumbnailImageView.isHidden = true
            thumbnailImageView.image = nil
            playIconOverlay.isHidden = true
        }
    }

    @objc private func cancelTapped() { onCancel?() }
}

// MARK: - Edit Banner

final class ChatEditBanner: UIView {

    var onCancel: (() -> Void)?

    override var intrinsicContentSize: CGSize {
        isHidden ? .zero : super.intrinsicContentSize
    }

    private let accentBar: UIView = {
        let v = UIView()
        v.backgroundColor = ChatTheme.link
        v.layer.cornerRadius = 1.5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.semibold, size: 12)
        lbl.textColor = ChatTheme.link
        lbl.text = ChatStrings.chat_editingMessage.localizedString()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let previewLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(size: 12)
        lbl.textColor = .gray
        lbl.lineBreakMode = .byTruncatingTail
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: ChatAssets.close)?.withRenderingMode(.alwaysTemplate), for: .normal)
        btn.tintColor = ChatTheme.textSecondary
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = UIColor.blue.withAlphaComponent(0.08)
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(accentBar)
        addSubview(titleLabel)
        addSubview(previewLabel)
        addSubview(cancelButton)

        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            accentBar.centerYAnchor.constraint(equalTo: centerYAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 3),
            accentBar.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -8),

            previewLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            previewLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 0),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -8),
            previewLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 24),
            cancelButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        enforceRTLIfNeeded()
    }

    func configure(previewText: String) {
        previewLabel.text = String(previewText.prefix(80)).htmlToString
    }

    @objc private func cancelTapped() { onCancel?() }
}
