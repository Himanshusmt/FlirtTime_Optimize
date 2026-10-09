//
//  VibeProfileViewController.swift
//  FlirttimeNew
//
//  Vibe Details: why you're seeing this person, their words, voice, Moments and interests.
//

import UIKit

final class VibeProfileViewController: BaseViewController {

    var onAction: ((VibeAction, [ConnectReason]?, VibeReaction?) -> Void)?
    var onInterestTapped: ((VibeInterest) -> Void)?
    /// `true` when the profile was blocked, `false` when it was reported.
    var onHide: ((VibeProfile, Bool) -> Void)?

    private let profile: VibeProfile

    private let scrollView = UIScrollView()
    private let galleryScrollView = UIScrollView()
    private let counter = PaddedPillLabel()
    private let bottomBar = UIView()
    private var waveform: VoiceWaveformView?
    private let playButton = UIButton(type: .custom)

    init(profile: VibeProfile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        setUI()
        NotificationCenter.default.addObserver(self, selector: #selector(playerChanged), name: VoiceIntroPlayer.stateDidChange, object: nil)
        playerChanged()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if VoiceIntroPlayer.shared.playingProfileID == profile.id {
            VoiceIntroPlayer.shared.stop()
        }
    }

    // MARK: - UI

    private func setUI() {
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        let content = UIView()
        let gallery = makeGallery()
        let sheet = makeSheet()
        [scrollView, bottomBar].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        [content, gallery, sheet].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        scrollView.addSubview(content)
        content.addSubview(gallery)
        content.addSubview(sheet)
        setBottomBar()
        let topButtons = makeTopButtons()

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            gallery.topAnchor.constraint(equalTo: content.topAnchor),
            gallery.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            gallery.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            gallery.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.56),

            sheet.topAnchor.constraint(equalTo: gallery.bottomAnchor, constant: -28),
            sheet.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sheet.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            sheet.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topButtons.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            topButtons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            topButtons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    private func makeTopButtons() -> UIStackView {
        let back = circleButton(symbol: "chevron.left", label: "Back")
        back.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        let more = circleButton(symbol: "ellipsis", label: "More options")
        more.addAction(UIAction { [weak self, unowned more] _ in self?.showSafetyOptions(from: more) }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [back, UIView(), more])
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        return stack
    }

    private func circleButton(symbol: String, label: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.35)
        config.baseForegroundColor = .white
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))
        let button = UIButton(configuration: config)
        button.accessibilityLabel = label
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
        return button
    }

    // MARK: Gallery

    private func makeGallery() -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        galleryScrollView.isPagingEnabled = true
        galleryScrollView.showsHorizontalScrollIndicator = false
        galleryScrollView.delegate = self
        container.addSubview(galleryScrollView)
        galleryScrollView.pinEdges(to: container)

        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        galleryScrollView.addSubview(row)
        for (index, photo) in profile.photos.enumerated() {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.backgroundColor = AppColor.AthensGray
            imageView.loadImage(path: photo, placeholder: UIImage(named: "ProfileBlur"))
            imageView.isAccessibilityElement = true
            imageView.accessibilityLabel = "\(profile.displayName)'s photo \(index + 1) of \(profile.photos.count)"
            imageView.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Like this photo") { [weak self] _ in
                self?.react(VibeReaction(target: .photo(index)))
                return true
            }]
            row.addArrangedSubview(imageView)
            imageView.widthAnchor.constraint(equalTo: galleryScrollView.frameLayoutGuide.widthAnchor).isActive = true
            imageView.heightAnchor.constraint(equalTo: galleryScrollView.frameLayoutGuide.heightAnchor).isActive = true
        }
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(galleryDoubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        galleryScrollView.addGestureRecognizer(doubleTap)

        let topShade = VibeGradientView(colors: [UIColor.black.withAlphaComponent(0.4), .clear],
                                        start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))
        let shade = VibeGradientView(colors: [.clear, UIColor.black.withAlphaComponent(0.7)],
                                     start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 1))
        [topShade, shade].forEach {
            $0.isUserInteractionEnabled = false
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }

        var badges: [UIView] = []
        if profile.isOnline == true {
            let online = PaddedPillLabel()
            online.setDot(AppColor.OceanGreen)
            online.text = "Online now"
            badges.append(online)
        }
        badges.append(UIView())
        counter.text = "1/\(profile.photos.count)"
        counter.isHidden = profile.photos.count < 2
        badges.append(counter)
        let badgeRow = UIStackView(arrangedSubviews: badges)
        badgeRow.alignment = .center

        let name = UILabel.vibeLabel(.bold, 30, style: .largeTitle, color: .white)
        name.text = profile.nameAndAge
        name.accessibilityTraits = .header
        let nameRow = UIStackView(arrangedSubviews: [name])
        nameRow.spacing = 6
        nameRow.alignment = .center
        if profile.isVerified {
            let verified = UIButton(type: .system)
            verified.setImage(UIImage(systemName: "checkmark.seal.fill",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)), for: .normal)
            verified.tintColor = UIColor(red: 0.36, green: 0.67, blue: 1, alpha: 1)
            verified.accessibilityLabel = "Verified profile"
            verified.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                VibeVerificationInfo.present(for: self.profile, from: self)
            }, for: .touchUpInside)
            nameRow.addArrangedSubview(verified)
        }
        nameRow.addArrangedSubview(UIView())
        let info = UIStackView(arrangedSubviews: [nameRow])
        info.axis = .vertical
        info.spacing = 2
        let metaParts = [profile.locationLine, profile.datingIntent.map { "Looking for \($0.lowercased())" }].compactMap { $0 }
        if !metaParts.isEmpty {
            let meta = UILabel.vibeLabel(.regular, 15, style: .subheadline, color: UIColor.white.withAlphaComponent(0.9), lines: 2)
            meta.text = metaParts.joined(separator: " · ")
            info.addArrangedSubview(meta)
        }

        [badgeRow, info].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        NSLayoutConstraint.activate([
            topShade.topAnchor.constraint(equalTo: container.topAnchor),
            topShade.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topShade.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topShade.heightAnchor.constraint(equalToConstant: 130),
            shade.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            shade.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            shade.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            shade.heightAnchor.constraint(equalTo: container.heightAnchor, multiplier: 0.5),

            badgeRow.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 56),
            badgeRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            badgeRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            info.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            info.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            info.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -44),

            row.topAnchor.constraint(equalTo: galleryScrollView.contentLayoutGuide.topAnchor),
            row.leadingAnchor.constraint(equalTo: galleryScrollView.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: galleryScrollView.contentLayoutGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: galleryScrollView.contentLayoutGuide.bottomAnchor)
        ])
        return container
    }

    // MARK: Details sheet

    private func makeSheet() -> UIView {
        let sheet = UIView()
        sheet.backgroundColor = AppColor.AppWhite
        sheet.layer.cornerRadius = 28
        sheet.layer.cornerCurve = .continuous
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 22
        sheet.addSubview(stack)
        stack.pinEdges(to: sheet, insets: UIEdgeInsets(top: 24, left: 20, bottom: 28, right: 20))

        stack.addArrangedSubview(makeWhySection())
        if !profile.about.isEmpty || profile.voiceIntro != nil {
            stack.addArrangedSubview(makeVibeSection())
        }
        if !profile.moments.isEmpty {
            let moments = MomentsPreviewView(tileSize: 68)
            moments.configure(with: profile.moments, name: profile.displayName, visibleCount: 4)
            moments.onTap = { [weak self] index in self?.openMoments(at: index) }
            stack.addArrangedSubview(section("Moments", content: moments))
        }
        if !profile.interests.isEmpty {
            let chips = VibeChipsView()
            chips.configure(profile.interests, highlighted: Set(profile.sharedInterests.map(\.id)))
            chips.onTap = { [weak self] interest in self?.onInterestTapped?(interest) }
            stack.addArrangedSubview(section("Interests", content: chips))
        }
        return sheet
    }

    private func makeWhySection() -> UIView {
        let title = sectionTitle("Why This Vibe?")
        let header = UIStackView(arrangedSubviews: [title, UIView()])
        header.alignment = .center
        if let score = profile.vibeScore {
            let badge = UILabel.vibeLabel(.bold, 13, style: .footnote, color: AppColor.Punch)
            badge.text = "\(score)% Vibe"
            badge.accessibilityLabel = "\(score) percent vibe, based on shared interests"
            let pill = UIView()
            pill.backgroundColor = AppColor.Lavenderblush
            pill.layer.cornerRadius = 13
            pill.addSubview(badge)
            badge.pinEdges(to: pill, insets: UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10))
            header.addArrangedSubview(pill)
        }

        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 10
        for reason in profile.reasons {
            let icon = UILabel()
            icon.text = profile.emoji(forReason: reason)
            icon.font = .systemFont(ofSize: 17)
            icon.textAlignment = .center
            icon.backgroundColor = AppColor.Lavenderblush
            icon.layer.cornerRadius = 10
            icon.clipsToBounds = true
            icon.isAccessibilityElement = false
            let text = UILabel.vibeLabel(.regular, 15, style: .subheadline, color: AppColor.MineShaft, lines: 0)
            text.text = reason
            let row = UIStackView(arrangedSubviews: [icon, text])
            row.spacing = 12
            row.alignment = .center
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 34),
                icon.heightAnchor.constraint(equalToConstant: 34)
            ])
            rows.addArrangedSubview(row)
        }
        let stack = UIStackView(arrangedSubviews: [header, rows])
        stack.axis = .vertical
        stack.spacing = 14
        return stack
    }

    private func makeVibeSection() -> UIView {
        var views: [UIView] = []
        if !profile.about.isEmpty {
            let quote = UILabel.vibeLabel(.medium, 17, style: .body, color: AppColor.MineShaft, lines: 0)
            quote.text = "“\(profile.about)”"
            views.append(quote)
        }
        if let intro = profile.voiceIntro {
            views.append(makeVoicePlayer(intro))
        }
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 12
        return section("\(profile.displayName)'s Vibe", content: stack)
    }

    private func makeVoicePlayer(_ intro: VibeVoiceIntro) -> UIView {
        let container = UIView()
        container.backgroundColor = AppColor.Lavenderblush.withAlphaComponent(0.7)
        container.layer.cornerRadius = 28

        playButton.backgroundColor = AppColor.Punch
        playButton.tintColor = .white
        playButton.layer.cornerRadius = 20
        playButton.addAction(UIAction { [weak self] _ in self?.toggleVoice() }, for: .touchUpInside)
        let wave = VoiceWaveformView(seed: profile.id, barCount: 24)
        wave.activeColor = AppColor.Punch
        wave.inactiveColor = AppColor.Punch.withAlphaComponent(0.3)
        waveform = wave
        let duration = UILabel.vibeLabel(.medium, 13, style: .caption1, color: AppColor.DoveGray)
        duration.text = intro.durationText
        duration.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [playButton, wave, duration])
        row.spacing = 12
        row.alignment = .center
        container.addSubview(row)
        row.pinEdges(to: container, insets: UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 16))
        NSLayoutConstraint.activate([
            playButton.widthAnchor.constraint(equalToConstant: 40),
            playButton.heightAnchor.constraint(equalToConstant: 40),
            wave.heightAnchor.constraint(equalToConstant: 30)
        ])
        return container
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let label = UILabel.vibeLabel(.bold, 18, style: .headline, color: AppColor.AppBlack)
        label.text = text
        label.accessibilityTraits = .header
        return label
    }

    private func section(_ title: String, content: UIView) -> UIView {
        let stack = UIStackView(arrangedSubviews: [sectionTitle(title), content])
        stack.axis = .vertical
        stack.spacing = 10
        return stack
    }

    private func setBottomBar() {
        bottomBar.backgroundColor = AppColor.AppWhite
        bottomBar.layer.shadowColor = UIColor.black.cgColor
        bottomBar.layer.shadowOpacity = 0.06
        bottomBar.layer.shadowRadius = 10
        bottomBar.layer.shadowOffset = CGSize(width: 0, height: -3)

        var notMyVibe = UIButton.Configuration.filled()
        notMyVibe.cornerStyle = .capsule
        notMyVibe.baseForegroundColor = AppColor.Punch
        notMyVibe.baseBackgroundColor = AppColor.Lavenderblush
        notMyVibe.attributedTitle = AttributedString("Not my vibe", attributes: AttributeContainer([.font: VibeFont.scaled(.medium, 16)]))
        let notMyVibeButton = UIButton(configuration: notMyVibe)
        notMyVibeButton.addAction(UIAction { [weak self] _ in self?.onAction?(.notMyVibe, nil, nil) }, for: .touchUpInside)

        var connect = UIButton.Configuration.filled()
        connect.cornerStyle = .capsule
        connect.baseBackgroundColor = AppColor.Punch
        connect.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        connect.imagePlacement = .trailing
        connect.imagePadding = 8
        connect.attributedTitle = AttributedString("Connect", attributes: AttributeContainer([.font: VibeFont.scaled(.medium, 16)]))
        let connectButton = UIButton(configuration: connect)
        connectButton.layer.shadowColor = AppColor.Punch.cgColor
        connectButton.layer.shadowOpacity = 0.35
        connectButton.layer.shadowRadius = 10
        connectButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        connectButton.addAction(UIAction { [weak self] _ in self?.showConnectBecause() }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [notMyVibeButton, connectButton])
        row.spacing = 12
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            row.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])
    }

    // MARK: - Actions

    @objc private func galleryDoubleTapped(_ tap: UITapGestureRecognizer) {
        let page = galleryScrollView.bounds.width > 0 ? Int((galleryScrollView.contentOffset.x / galleryScrollView.bounds.width).rounded()) : 0
        if let container = galleryScrollView.superview {
            HeartBurst.show(in: container, at: tap.location(in: container))
        }
        react(VibeReaction(target: .photo(page)))
    }

    private func react(_ reaction: VibeReaction) {
        VibeHaptics.threshold()
        let delay = UIAccessibility.isReduceMotionEnabled ? 0.1 : 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.onAction?(.interested, nil, reaction)
        }
    }

    private func toggleVoice() {
        guard let intro = profile.voiceIntro else { return }
        if VoiceIntroPlayer.shared.playingProfileID != profile.id {
            VibeAnalytics.track(.vibeVoicePlayed, profileID: profile.id)
        }
        VoiceIntroPlayer.shared.toggle(intro, profileID: profile.id)
    }

    @objc private func playerChanged() {
        let player = VoiceIntroPlayer.shared
        let isPlaying = player.playingProfileID == profile.id
        playButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)), for: .normal)
        playButton.accessibilityLabel = isPlaying ? "Pause voice intro" : "Play voice intro"
        waveform?.setProgress(isPlaying ? player.progress : 0)
    }

    private func showConnectBecause() {
        let connectVC = ConnectBecauseViewController(profile: profile)
        connectVC.onSend = { [weak self] reasons in
            self?.dismiss(animated: true) {
                self?.onAction?(.interested, reasons, nil)
            }
        }
        connectVC.modalPresentationStyle = .pageSheet
        if let sheet = connectVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(connectVC, animated: true)
    }

    private func openMoments(at index: Int) {
        VibeAnalytics.track(.vibeMomentOpened, profileID: profile.id)
        let momentsVC = VibeMomentsViewController(profile: profile, startIndex: index)
        momentsVC.onReport = { [weak self] profile in
            self?.onHide?(profile, false)
        }
        present(momentsVC, animated: true)
    }

    private func showSafetyOptions(from sourceView: UIView) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Report \(profile.displayName)", style: .destructive) { [weak self] _ in
            self?.showReportReasons(from: sourceView)
        })
        sheet.addAction(UIAlertAction(title: "Block \(profile.displayName)", style: .destructive) { [weak self] _ in
            self?.confirmBlock()
        })
        sheet.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = sourceView
        present(sheet, animated: true)
    }

    private func showReportReasons(from sourceView: UIView) {
        VibeSafety.presentReportReasons(for: profile, from: self, sourceView: sourceView) { [weak self] in
            guard let self else { return }
            self.onHide?(self.profile, false)
        }
    }

    private func confirmBlock() {
        let alert = UIAlertController(title: "Block \(profile.displayName)?",
                                      message: "They won't be able to see your profile or contact you, and you won't see them in Discover.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: "Block", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.onHide?(self.profile, true)
        })
        present(alert, animated: true)
    }
}

extension VibeProfileViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === galleryScrollView, scrollView.bounds.width > 0 else { return }
        let page = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
        counter.text = "\(min(max(page, 0), profile.photos.count - 1) + 1)/\(profile.photos.count)"
    }
}
