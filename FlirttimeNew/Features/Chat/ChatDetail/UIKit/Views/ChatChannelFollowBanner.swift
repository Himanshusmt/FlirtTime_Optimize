import UIKit

final class ChatChannelFollowBanner: UIView {

    var onFollow: (() -> Void)?
    var onUnfollow: (() -> Void)?

    private let bellIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "bell.badge"))
        iv.tintColor = .purple
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let infoLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = ChatStrings.chat_followChannelHint.localizedString()
        lbl.font = UIFont.chat(size: 14)
        lbl.textColor = .gray
        lbl.lineBreakMode = .byTruncatingTail
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let followButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(ChatStrings.chat_followChannel.localizedString(), for: .normal)
        btn.titleLabel?.font = UIFont.chat(.semibold, size: 14)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = .purple
        btn.layer.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let iv = UIActivityIndicatorView(style: .medium)
        iv.hidesWhenStopped = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let divider: UIView = {
        let v = UIView()
        v.backgroundColor = .systemGray5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var isFollowing = false
    private var isLoading = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        backgroundColor = .white
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(divider)
        addSubview(bellIcon)
        addSubview(infoLabel)
        addSubview(followButton)
        addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            bellIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bellIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            bellIcon.widthAnchor.constraint(equalToConstant: 22),
            bellIcon.heightAnchor.constraint(equalToConstant: 22),

            infoLabel.leadingAnchor.constraint(equalTo: bellIcon.trailingAnchor, constant: 12),
            infoLabel.trailingAnchor.constraint(lessThanOrEqualTo: followButton.leadingAnchor, constant: -12),
            infoLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            followButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            followButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            followButton.widthAnchor.constraint(equalToConstant: 120),
            followButton.heightAnchor.constraint(equalToConstant: 34),

            activityIndicator.centerXAnchor.constraint(equalTo: followButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: followButton.centerYAnchor),

            heightAnchor.constraint(equalToConstant: 54)
        ])

        followButton.addTarget(self, action: #selector(handleFollowTap), for: .touchUpInside)
        enforceRTLIfNeeded()
    }

    @objc private func handleFollowTap() {
        guard !isLoading else { return }
        if isFollowing {
            onUnfollow?()
        } else {
            onFollow?()
        }
    }

    func configure(isFollowing: Bool) {
        self.isFollowing = isFollowing
        if isFollowing {
            followButton.setTitle(ChatStrings.chat_followingStatus.localizedString(), for: .normal)
            followButton.backgroundColor = .systemGray4
            followButton.setTitleColor(.darkGray, for: .normal)
        } else {
            followButton.setTitle(ChatStrings.chat_followChannel.localizedString(), for: .normal)
            followButton.backgroundColor = .purple
            followButton.setTitleColor(.white, for: .normal)
        }
    }

    func setLoading(_ loading: Bool) {
        isLoading = loading
        followButton.isHidden = loading
        if loading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }
}
