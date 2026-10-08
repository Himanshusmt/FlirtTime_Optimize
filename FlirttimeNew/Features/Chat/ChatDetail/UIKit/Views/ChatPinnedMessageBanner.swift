import UIKit

final class ChatPinnedMessageBanner: UIView {

    var onTap: (() -> Void)?

    private let pinIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "pin.fill"))
        iv.tintColor = ChatTheme.primary
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let textLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.medium, size: 13)
        lbl.textColor = .black
        lbl.lineBreakMode = .byTruncatingTail
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let chevron: UIImageView = {
        let baseImage = UIImage(systemName: "chevron.right")
        let isRTL = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
        let iv = UIImageView(image: isRTL ? baseImage?.withHorizontallyFlippedOrientation() : baseImage)
        iv.tintColor = .black.withAlphaComponent(0.35)
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let iv = UIActivityIndicatorView(style: .medium)
        iv.hidesWhenStopped = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let separator: UIView = {
        let v = UIView()
        v.backgroundColor = .black.withAlphaComponent(0.06)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = .white
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(pinIcon)
        addSubview(textLabel)
        addSubview(activityIndicator)
        addSubview(chevron)
        addSubview(separator)

        NSLayoutConstraint.activate([
            pinIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            pinIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinIcon.widthAnchor.constraint(equalToConstant: 14),
            pinIcon.heightAnchor.constraint(equalToConstant: 14),

            textLabel.leadingAnchor.constraint(equalTo: pinIcon.trailingAnchor, constant: 10),
            textLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 14),

            activityIndicator.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -4),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            topAnchor.constraint(equalTo: topAnchor),
            bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 44)
        ])

        pinIcon.transform = CGAffineTransform(rotationAngle: .pi / 4)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        enforceRTLIfNeeded()
    }

    @objc private func handleTap() { onTap?() }

    func configure(text: String, isLoading: Bool = false) {
        textLabel.text = text.htmlToString
        chevron.isHidden = isLoading
        if isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        pinIcon.tintColor = ChatTheme.primary
        textLabel.textColor = .black
    }
}
