import UIKit
import Combine
import Kingfisher

final class ChatDetailNavBar: UIView {

    let contentLayoutGuide = UILayoutGuide()
    private var contentTopConstraint: NSLayoutConstraint?

    // MARK: - Callbacks

    var onBack: (() -> Void)?
    var onProfileTap: (() -> Void)?
    var onVoiceCall: (() -> Void)?
    var onVideoCall: (() -> Void)?
    var onShareChannel: (() -> Void)?
    var onUnfollowChannel: (() -> Void)?
    var onFollowChannel: (() -> Void)?
    var onDeleteChannel: (() -> Void)?
    var onGroupLinkTap: (() -> Void)?
    var onMore: (() -> Void)?

    var sharePopoverAnchorView: UIView { channelMenuButton }

    // MARK: - Config

    private let isGroupChat: Bool
    private let isChannel: Bool
    private let isChannelAdmin: Bool
    private var isChannelFollowed: Bool
    private let hasResolvedChannelRole: Bool
    private let isGroupParticipant: Bool
    private let showCallButtons: Bool
    private let otherUserId: String?

    // MARK: - Subviews

    private let backButton: UIButton = {
        let btn = UIButton(type: .system)

        let image = UIImage(named: ChatAssets.back)?
            .imageFlippedForRightToLeftLayoutDirection()
        btn.setImage(image?.withRenderingMode(.alwaysOriginal), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false

        return btn
    }()

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let onlineDot: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.systemGreen
        v.layer.cornerRadius = 5
        v.layer.borderWidth = 2
        v.layer.borderColor = UIColor.white.cgColor
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(.medium, size: 16)
        lbl.textColor = ChatTheme.textPrimary
        lbl.lineBreakMode = .byTruncatingTail
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let verifiedBadge: UIImageView = {
        let iv = UIImageView(image: UIImage(named: ChatAssets.verified))
        iv.isHidden = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let subtitleLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(size: 12)
        lbl.textColor = ChatTheme.textSecondary
        lbl.lineBreakMode = .byTruncatingTail
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let statusDot: UIView = {
        let v = UIView()
        v.backgroundColor = ChatTheme.success
        v.layer.cornerRadius = 4
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let moreButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: ChatAssets.menu), for: .normal)
        btn.tintColor = ChatTheme.primary
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let voiceCallButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: ChatAssets.voiceCall)?.withRenderingMode(.alwaysOriginal), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let videoCallButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: ChatAssets.videoCall)?.withRenderingMode(.alwaysOriginal), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let channelMenuButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(named: ChatAssets.menu), for: .normal)
        btn.tintColor = ChatTheme.primary
        btn.titleLabel?.font = UIFont.chat(.semibold, size: 18)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let bottomDivider: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.gray.withAlphaComponent(0.2)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()
    private let chatListSocket = ChatListSocketService.shared

    // MARK: - Data

    private let groupTitle: String
    private var groupParticipants: [GroupParticipant]
    private let user: UserRes?
    private let headerUserData: UserRes?
    private let activeStatus: String
    private var userStatus: String
    private let channelFollowersCount: Int?
    private var participantsCount: Int?
    private var hasReceivedStatus = false
    private var placeholderTimer: Timer?
    private var currentAvatarURLString: String?

    // MARK: - Init

    init(isGroupChat: Bool, groupTitle: String, groupParticipants: [GroupParticipant],
         user: UserRes?, headerUserData: UserRes?, activeStatus: String, userStatus: String,
         isGroupParticipant: Bool, showCallButtons: Bool, isChannel: Bool = false,
         isChannelAdmin: Bool = false, isChannelFollowed: Bool = false,
         hasResolvedChannelRole: Bool = false, channelFollowersCount: Int? = nil,
         otherUserId: String? = nil, channelShareURL: URL? = nil,
         groupAvatarUrl: String? = nil, conversationId: String? = nil,
         participantsCount: Int? = nil) {

        self.isGroupChat = isGroupChat
        self.groupTitle = groupTitle
        self.groupParticipants = groupParticipants
        self.user = user
        self.headerUserData = headerUserData
        self.activeStatus = activeStatus
        self.userStatus = userStatus
        self.isGroupParticipant = isGroupParticipant
        self.showCallButtons = showCallButtons
        self.isChannel = isChannel
        self.isChannelAdmin = isChannelAdmin
        self.isChannelFollowed = isChannelFollowed
        self.hasResolvedChannelRole = hasResolvedChannelRole
        self.channelFollowersCount = channelFollowersCount
        self.participantsCount = participantsCount
        self.otherUserId = otherUserId

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white
        // Must be opaque so the shadow renders correctly and the chat background doesn't bleed through.
        isOpaque = true
        clipsToBounds = false

        setupViews(groupAvatarUrl: groupAvatarUrl, conversationId: conversationId)
        configureTitle()
        setupActions()
        bindOnlineStatus()
        updateSubtitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        placeholderTimer?.invalidate()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        contentTopConstraint?.constant = safeAreaInsets.top
    }

    // MARK: - Setup

    private func setupViews(groupAvatarUrl: String?, conversationId: String?) {
        // Content layout guide — pinned to safe-area top (skips status bar)
        addLayoutGuide(contentLayoutGuide)
        contentTopConstraint = contentLayoutGuide.topAnchor.constraint(equalTo: topAnchor, constant: safeAreaInsets.top)
        contentTopConstraint?.isActive = true
        NSLayoutConstraint.activate([
            contentLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowRadius = 1
        layer.shadowOffset = CGSize(width: 0, height: 1)

        // Back button
        addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            backButton.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        // Avatar
        addSubview(avatarImageView)
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 16),
            avatarImageView.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 50),
            avatarImageView.heightAnchor.constraint(equalToConstant: 50),
        ])
        avatarImageView.layer.cornerRadius = 25

        // Online dot
        addSubview(onlineDot)
        NSLayoutConstraint.activate([
            onlineDot.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 2),
            onlineDot.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 2),
            onlineDot.widthAnchor.constraint(equalToConstant: 10),
            onlineDot.heightAnchor.constraint(equalToConstant: 10),
        ])

        // Verified badge
        addSubview(verifiedBadge)
        NSLayoutConstraint.activate([
            verifiedBadge.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 2),
            verifiedBadge.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 4),
            verifiedBadge.widthAnchor.constraint(equalToConstant: 18),
            verifiedBadge.heightAnchor.constraint(equalToConstant: 18),
        ])

        loadAvatarImage(groupAvatarUrl: groupAvatarUrl, conversationId: conversationId)

        // Title + subtitle stack
        let titleRow = UIStackView(arrangedSubviews: [titleLabel])
        titleRow.axis = .horizontal
        titleRow.spacing = 4
        titleRow.alignment = .center

        configureTitle()
        
        let subtitleRow = UIStackView(arrangedSubviews: [statusDot, subtitleLabel])
        subtitleRow.axis = .horizontal
        subtitleRow.spacing = 4
        subtitleRow.alignment = .center
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
        ])

        let infoStack = UIStackView(arrangedSubviews: [titleRow, subtitleRow])
        infoStack.axis = .vertical
        infoStack.spacing = 2
        infoStack.alignment = .leading
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(infoStack)
        NSLayoutConstraint.activate([
            infoStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            infoStack.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor),
            infoStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -150),
        ])

        // Tap on name/status area to open profile or group detail
        infoStack.isUserInteractionEnabled = true
        infoStack.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(profileTapped)))

        // Right-side buttons
        if isChannel {
            setupChannelMenuButton()
        } else if isGroupChat {
            // Group: voice/video call + keep profile tap for group detail.
            if showCallButtons && isGroupParticipant {
                setupCallButtons()
            }
        } else if showCallButtons {
            setupCallButtons()
        }

        // Bottom divider
        addSubview(bottomDivider)
        NSLayoutConstraint.activate([
            bottomDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomDivider.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        // Title
        

        enforceRTLIfNeeded()
    }

    private func loadAvatarImage(groupAvatarUrl: String?, conversationId: String?) {
        if isGroupChat {
            if let conversationId,
               let url = groupAvatarUrl, !url.isEmpty,
               let cached = ProfilePictureCache.shared.getCachedImageSync(userId: "group_\(conversationId)", urlString: url) {
                avatarImageView.image = cached
                currentAvatarURLString = url
                return
            }
            if let url = groupAvatarUrl, !url.isEmpty {
                currentAvatarURLString = url
                let placeholder = ConversationIconCache.shared.image(forId: conversationId ?? "") ?? makeInitialAvatar(text: groupTitle)
                avatarImageView.kf.setImage(with: URL(string: url), placeholder: placeholder)
            } else if let conversationId, let cached = ConversationIconCache.shared.image(forId: conversationId) {
                avatarImageView.image = cached
            } else {
                avatarImageView.image = makeInitialAvatar(text: groupTitle)
            }
        } else {
            let displayUser = headerUserData ?? user
            let urlString = displayUser?.profilePictureDetails?.filePath?.isEmpty == false
                ? displayUser?.profilePictureDetails?.filePath
                : displayUser?.profilePicture
            if let otherUserId, !otherUserId.isEmpty,
               let urlString,
               let cached = ProfilePictureCache.shared.getCachedImageSync(userId: otherUserId, urlString: urlString) {
                avatarImageView.image = cached
                currentAvatarURLString = urlString
                return
            }
            if let urlString, let url = URL(string: urlString) {
                currentAvatarURLString = urlString
                avatarImageView.kf.setImage(with: url, placeholder: makeInitialAvatar(text: displayUser?.fullName ?? displayUser?.userName ?? ""))
            } else {
                avatarImageView.image = makeInitialAvatar(text: displayUser?.fullName ?? displayUser?.userName ?? "")
            }
        }
    }

    private func makeInitialAvatar(text: String) -> UIImage? {
        let initial = text.first.map(String.init) ?? "?"
        let size = CGSize(width: 50, height: 50)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            ChatTheme.primary.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.chat(.semibold, size: 20),
                .foregroundColor: UIColor.white
            ]
            let textSize = initial.size(withAttributes: attrs)
            initial.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attrs)
        }
    }

    private func configureTitle() {
        if isChannel {
            titleLabel.text = groupTitle.isEmpty ? ChatStrings.chat_channelLabel.localizedString() : groupTitle
        } else if isGroupChat {
            titleLabel.text = groupTitle.isEmpty ? ChatStrings.chat_groupChat.localizedString() : groupTitle
        } else {
            titleLabel.text = resolvedDisplayName
            let isVerified = (headerUserData?.verified == true) || (user?.verified == true)
            verifiedBadge.isHidden = !isVerified
        }
    }

    private var resolvedDisplayName: String {
        let candidates: [String?] = [
            headerUserData?.fullName, headerUserData?.userName,
            user?.fullName, user?.userName
        ]
        for c in candidates {
            if let s = c?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s != "--" { return s }
        }
        return ChatStrings.chat_userFallback.localizedString()
    }

    // MARK: - Subtitle

    private func updateSubtitle() {
        if isChannel {
            applySubtitleText(channelFollowerCountText())
        } else if isGroupChat {
            applySubtitleText(memberCountText())
        } else {
            applySubtitleText(resolvedStatusText)
        }
    }

    /// Shows last-seen / online under the name, or hides the line so the name stays vertically centered.
    private func applySubtitleText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        statusDot.isHidden = trimmed != ChatStrings.chat_online.localizedString()
        if trimmed.isEmpty {
            hideSubtitleAndCenterTitle()
        } else {
            let wasHidden = subtitleLabel.isHidden
            subtitleLabel.isHidden = false
            transitionToStatus(trimmed)
            if wasHidden {
                animateInfoStackLayout()
            }
        }
    }

    private func hideSubtitleAndCenterTitle() {
        placeholderTimer?.invalidate()
        placeholderTimer = nil
        let alreadyHidden = subtitleLabel.isHidden && subtitleLabel.alpha == 0
        subtitleLabel.text = nil
        subtitleLabel.isHidden = true
        subtitleLabel.alpha = 0
        guard !alreadyHidden else { return }
        animateInfoStackLayout()
    }

    private func animateInfoStackLayout() {
        guard window != nil else { return }
        UIView.animate(withDuration: 0.2) {
            self.layoutIfNeeded()
        }
    }

    private func showPlaceholder() {
        guard subtitleLabel.text != ChatStrings.chat_tapForContactInfo.localizedString() else { return }
        subtitleLabel.text = ChatStrings.chat_tapForContactInfo.localizedString()
        subtitleLabel.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.subtitleLabel.alpha = 1
        }
        schedulePlaceholderExpiry()
    }

    private func transitionToStatus(_ text: String) {
        hasReceivedStatus = true
        // Cancel placeholder so real Online / last seen shows immediately
        placeholderTimer?.invalidate()
        placeholderTimer = nil

        let currentText = subtitleLabel.text ?? ""
        if currentText != text {
            UIView.transition(with: subtitleLabel, duration: 0.25, options: .transitionCrossDissolve) {
                self.subtitleLabel.text = text
                self.subtitleLabel.alpha = 1
            }
        } else {
            subtitleLabel.alpha = 1
        }
    }

    private func schedulePlaceholderExpiry() {
        placeholderTimer?.invalidate()
        placeholderTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.placeholderTimer = nil
            let text = self.resolvedStatusText
            if !text.isEmpty {
                self.crossDissolveToText(text)
            } else {
                UIView.animate(withDuration: 0.3) {
                    self.subtitleLabel.alpha = 0
                }
            }
        }
    }

    private func crossDissolveToText(_ text: String) {
        UIView.transition(with: subtitleLabel, duration: 0.25, options: .transitionCrossDissolve) {
            self.subtitleLabel.text = text
            self.subtitleLabel.alpha = 1
        }
    }

    private var resolvedStatusText: String {
        // Only show online / last seen. Empty (nobody) keeps the name vertically centered.
        userStatus.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func memberCountText() -> String {
        // FE: `${conv.participantsCount} members`
        let count = max(participantsCount ?? 0, groupParticipants.count)
        switch count {
        case 0: return ""
        case 1: return ChatStrings.chat_1member.localizedString()
        default: return "\(count) " + ChatStrings.chat_members.localizedString()
        }
    }

    private func channelFollowerCountText() -> String {
        guard let count = channelFollowersCount else { return "" }
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
        return count == 1 ? "\(formatted) \(ChatStrings.chat_follower.localizedString())" : "\(formatted) \(ChatStrings.chat_followers.localizedString())"
    }

    // MARK: - Online Status Binding

    private func bindOnlineStatus() {
        // Keep the avatar online indicator permanently hidden on the chat header.
        onlineDot.isHidden = true
        guard !isGroupChat, !isChannel, otherUserId != nil else { return }
        chatListSocket.$onlineUserIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.onlineDot.isHidden = true
                self.updateSubtitle()
            }
            .store(in: &cancellables)
    }

    // MARK: - Call Buttons

    private func setupCallButtons() {
        voiceCallButton.isHidden = false
        videoCallButton.isHidden = false
        addSubview(voiceCallButton)
        addSubview(videoCallButton)
        addSubview(moreButton)
        NSLayoutConstraint.activate([
            moreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            moreButton.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 32),
            moreButton.heightAnchor.constraint(equalToConstant: 40),

            videoCallButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -4),
            videoCallButton.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor),
            videoCallButton.widthAnchor.constraint(equalToConstant: 40),
            videoCallButton.heightAnchor.constraint(equalToConstant: 40),

            voiceCallButton.trailingAnchor.constraint(equalTo: videoCallButton.leadingAnchor, constant: -8),
            voiceCallButton.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor),
            voiceCallButton.widthAnchor.constraint(equalToConstant: 40),
            voiceCallButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func setupChannelMenuButton() {
        addSubview(channelMenuButton)
        NSLayoutConstraint.activate([
            channelMenuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            channelMenuButton.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor),
            channelMenuButton.widthAnchor.constraint(equalToConstant: 40),
            channelMenuButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    // MARK: - Actions

    private func setupActions() {
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        avatarImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(profileTapped)))
        avatarImageView.isUserInteractionEnabled = true
        voiceCallButton.addTarget(self, action: #selector(voiceCallTapped), for: .touchUpInside)
        videoCallButton.addTarget(self, action: #selector(videoCallTapped), for: .touchUpInside)
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        moreButton.isHidden = isChannel || isGroupChat
        channelMenuButton.addTarget(self, action: #selector(channelMenuTapped), for: .touchUpInside)
        channelMenuButton.isHidden = !isChannel
        // Channels never show call buttons; groups use them when participant.
        if isChannel {
            voiceCallButton.isHidden = true
            videoCallButton.isHidden = true
        } else if isGroupChat, !(showCallButtons && isGroupParticipant) {
            voiceCallButton.isHidden = true
            videoCallButton.isHidden = true
        }
    }

    @objc private func backTapped() { onBack?() }

    @objc private func profileTapped() {
        if !isGroupChat || isGroupParticipant { onProfileTap?() }
    }

    @objc private func voiceCallTapped() { onVoiceCall?() }
    @objc private func videoCallTapped() { onVideoCall?() }
    @objc private func moreTapped() { onMore?() }

    @objc private func channelMenuTapped() {
        guard isChannel else { return }
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: ChatStrings.chat_shareChannel.localizedString(), style: .default) { [weak self] _ in
            self?.onShareChannel?()
        })

        if isChannelAdmin {
            alert.addAction(UIAlertAction(title: ChatStrings.chat_deleteChannel.localizedString(), style: .destructive) { [weak self] _ in
                self?.onDeleteChannel?()
            })
        } else if isChannelFollowed {
            alert.addAction(UIAlertAction(title: ChatStrings.chat_unfollowChannel.localizedString(), style: .destructive) { [weak self] _ in
                self?.onUnfollowChannel?()
            })
        } else {
            alert.addAction(UIAlertAction(title: ChatStrings.chat_followChannel.localizedString(), style: .default) { [weak self] _ in
                self?.onFollowChannel?()
            })
        }

        alert.addAction(UIAlertAction(title: ChatStrings.chat_cancel.localizedString(), style: .cancel))
        if let vc = findViewController() {
            if let popover = alert.popoverPresentationController {
                popover.sourceView = channelMenuButton
                popover.sourceRect = channelMenuButton.bounds
            }
            vc.present(alert, animated: true)
        }
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }

    // MARK: - Dynamic Updates (called from VC via Combine bindings)

    // AFTER — dispatch only if needed
    func updateHeader(userData: UserRes?) {
        guard let userData else { return }

        let update = {
            let name = userData.fullName ?? userData.userName ?? "User"
            if self.titleLabel.text != name {
                self.titleLabel.text = name
            }
            let shouldShowVerified = (userData.verified == true)
            if self.verifiedBadge.isHidden == shouldShowVerified {
                self.verifiedBadge.isHidden = !shouldShowVerified
            }

            let urlString = userData.profilePictureDetails?.filePath?.isEmpty == false
                ? userData.profilePictureDetails?.filePath
                : userData.profilePicture

            guard let urlString, let url = URL(string: urlString) else { return }
            guard self.currentAvatarURLString != urlString else { return }
            self.currentAvatarURLString = urlString
            self.avatarImageView.kf.setImage(
                with: url,
                placeholder: self.makeInitialAvatar(text: name)
            )
        }

        if Thread.isMainThread {
            update()          // instant — no extra run-loop hop
        } else {
            DispatchQueue.main.async { update() }
        }
    }

    func updateTitle(_ title: String) {
        guard isGroupChat || isChannel else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, titleLabel.text != trimmed else { return }
        titleLabel.text = trimmed
    }

    func updateAvatar(urlString: String) {
        guard currentAvatarURLString != urlString, let url = URL(string: urlString) else { return }
        currentAvatarURLString = urlString
        avatarImageView.kf.setImage(with: url)
    }

    func updateMemberCount(_ participants: [GroupParticipant], participantsCount: Int? = nil) {
        groupParticipants = participants
        if let participantsCount { self.participantsCount = participantsCount }
        updateSubtitle()
    }

    func updateChannelFollowState(isFollowed: Bool) {
        isChannelFollowed = isFollowed
    }

    func updateStatus(_ statusText: String) {
        guard !isGroupChat && !isChannel else { return }
        userStatus = statusText
        updateSubtitle()
    }
}
