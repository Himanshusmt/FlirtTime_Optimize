//
//  VibeMomentsViewController.swift
//  FlirttimeNew
//
//  Full-screen, story-style Moments viewer for a Discover profile.
//

import UIKit

final class VibeMomentsViewController: UIViewController {

    var onReport: ((VibeProfile) -> Void)?
    var onViewProfile: ((VibeProfile) -> Void)?

    private enum PauseReason { case holding, typing, sheet, background }

    private static let momentDuration: CFTimeInterval = 5
    private static let reactions = ["😍", "🔥", "😂", "😮", "👏", "❤️"]

    private let profile: VibeProfile
    private var index: Int

    private var elapsed: CFTimeInterval = 0
    private var lastTimestamp: CFTimeInterval?
    private var displayLink: CADisplayLink?
    private var pauseReasons = Set<PauseReason>()

    private let imageView = UIImageView()
    private let progressStack = UIStackView()
    private let timeLabel = UILabel.vibeLabel(.regular, 12, style: .caption1, color: UIColor.white.withAlphaComponent(0.8))
    private let captionLabel = UILabel.vibeLabel(.bold, 20, style: .title3, color: .white, lines: 3)
    private let locationLabel = UILabel.vibeLabel(.regular, 13, style: .footnote, color: UIColor.white.withAlphaComponent(0.85))
    private let captionStack = UIStackView()
    private let header = UIStackView()
    private let reactionsStack = UIStackView()
    private let replyField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let bottomStack = UIStackView()
    private lazy var previousButton = arrowButton("chevron.left", label: "Previous moment") { [weak self] in self?.go(by: -1) }
    private lazy var nextButton = arrowButton("chevron.right", label: "Next moment") { [weak self] in self?.go(by: 1) }

    private var progressBars: [MomentProgressBar] { progressStack.arrangedSubviews.compactMap { $0 as? MomentProgressBar } }
    private var currentBar: MomentProgressBar? { progressBars.indices.contains(index) ? progressBars[index] : nil }
    private var currentMoment: VibeMoment? { profile.moments.indices.contains(index) ? profile.moments[index] : nil }
    private var chromeViews: [UIView] { [progressStack, header, previousButton, nextButton, captionStack, bottomStack] }

    init(profile: VibeProfile, startIndex: Int) {
        self.profile = profile
        self.index = min(max(0, startIndex), max(0, profile.moments.count - 1))
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.maximumContentSizeCategory = .accessibilityMedium

        let container = UIView()
        container.layer.cornerRadius = 24
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(imageTapped(_:)))
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(imageHeld(_:)))
        hold.minimumPressDuration = 0.2
        tap.require(toFail: hold)
        imageView.addGestureRecognizer(tap)
        imageView.addGestureRecognizer(hold)
        container.addSubview(imageView)
        imageView.pinEdges(to: container)

        let topShade = VibeGradientView(colors: [UIColor.black.withAlphaComponent(0.5), .clear],
                                        start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))
        let bottomShade = VibeGradientView(colors: [.clear, UIColor.black.withAlphaComponent(0.8)],
                                           start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))
        [topShade, bottomShade].forEach {
            $0.isUserInteractionEnabled = false
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }

        progressStack.spacing = 4
        progressStack.distribution = .fillEqually
        profile.moments.forEach { _ in progressStack.addArrangedSubview(MomentProgressBar()) }
        progressStack.isAccessibilityElement = false

        buildHeader()
        captionStack.addArrangedSubview(captionLabel)
        captionStack.addArrangedSubview(locationLabel)
        captionStack.axis = .vertical
        captionStack.spacing = 6
        buildBottomBar()

        [progressStack, header, previousButton, nextButton, captionStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomStack)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            topShade.topAnchor.constraint(equalTo: container.topAnchor),
            topShade.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topShade.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topShade.heightAnchor.constraint(equalToConstant: 140),
            bottomShade.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottomShade.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomShade.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomShade.heightAnchor.constraint(equalTo: container.heightAnchor, multiplier: 0.5),

            progressStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            progressStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            progressStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            progressStack.heightAnchor.constraint(equalToConstant: 3),

            header.topAnchor.constraint(equalTo: progressStack.bottomAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

            previousButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            previousButton.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
            nextButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            nextButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),

            bottomStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            bottomStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            bottomStack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),

            captionStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            captionStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            captionStack.bottomAnchor.constraint(equalTo: bottomStack.topAnchor, constant: -16)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        update(animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentedViewController == nil else { return }
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: - UI

    private func buildHeader() {
        let avatar = UIImageView()
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 18
        avatar.layer.borderWidth = 2
        avatar.layer.borderColor = UIColor.white.cgColor
        avatar.loadImage(path: profile.photos.first, placeholder: UIImage(named: "ProfileBlur"))
        let name = UILabel.vibeLabel(.bold, 16, style: .headline, color: .white)
        name.text = profile.displayName
        let names = UIStackView(arrangedSubviews: [name, timeLabel])
        names.axis = .vertical

        let profileButton = UIButton(type: .custom)
        let identity = UIStackView(arrangedSubviews: [avatar, names])
        identity.spacing = 10
        identity.alignment = .center
        identity.isUserInteractionEnabled = false
        profileButton.addSubview(identity)
        identity.pinEdges(to: profileButton)
        profileButton.accessibilityLabel = "View \(profile.displayName)'s profile"
        profileButton.addAction(UIAction { [weak self] _ in
            guard let self, let onViewProfile = self.onViewProfile else { return }
            onViewProfile(self.profile)
        }, for: .touchUpInside)

        let more = iconButton("ellipsis", label: "More options")
        more.addAction(UIAction { [weak self, unowned more] _ in self?.showOptions(from: more) }, for: .touchUpInside)
        let close = iconButton("xmark", label: "Close")
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        [profileButton, UIView(), more, close].forEach { header.addArrangedSubview($0) }
        header.alignment = .center
        header.spacing = 6
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 36),
            avatar.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func buildBottomBar() {
        reactionsStack.distribution = .fillEqually
        reactionsStack.spacing = 6
        Self.reactions.forEach { emoji in
            let button = UIButton(type: .custom)
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 28)
            button.accessibilityLabel = "React \(emoji)"
            button.addAction(UIAction { [weak self, unowned button] _ in self?.react(emoji, from: button) }, for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            reactionsStack.addArrangedSubview(button)
        }

        let field = UIView()
        field.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        field.layer.cornerRadius = 24
        field.layer.cornerCurve = .continuous
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor

        replyField.textColor = .white
        replyField.tintColor = .white
        replyField.font = VibeFont.scaled(.regular, 16, style: .body)
        replyField.adjustsFontForContentSizeCategory = true
        replyField.attributedPlaceholder = NSAttributedString(
            string: "Reply to \(profile.displayName)…",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.75)])
        replyField.returnKeyType = .send
        replyField.enablesReturnKeyAutomatically = true
        replyField.keyboardAppearance = .dark
        replyField.delegate = self
        replyField.addAction(UIAction { [weak self] _ in self?.updateSendButton() }, for: .editingChanged)
        replyField.translatesAutoresizingMaskIntoConstraints = false
        field.addSubview(replyField)

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = VibeTheme.brandGradient[1]
        config.baseForegroundColor = .white
        config.image = UIImage(systemName: "paperplane.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold))
        sendButton.configuration = config
        sendButton.accessibilityLabel = "Send reply"
        sendButton.addAction(UIAction { [weak self] _ in self?.sendReply() }, for: .touchUpInside)

        let inputRow = UIStackView(arrangedSubviews: [field, sendButton])
        inputRow.spacing = 10
        inputRow.alignment = .center

        NSLayoutConstraint.activate([
            field.heightAnchor.constraint(equalToConstant: 48),
            replyField.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 18),
            replyField.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -14),
            replyField.topAnchor.constraint(equalTo: field.topAnchor),
            replyField.bottomAnchor.constraint(equalTo: field.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 48),
            sendButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        bottomStack.axis = .vertical
        bottomStack.spacing = 10
        bottomStack.addArrangedSubview(reactionsStack)
        bottomStack.addArrangedSubview(inputRow)
        updateSendButton()
    }

    private func updateSendButton() {
        let hasText = !(replyField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard sendButton.isHidden == hasText else { return }
        UIView.animate(withDuration: 0.2) { self.sendButton.isHidden = !hasText }
    }

    private func iconButton(_ symbol: String, label: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = label
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
        return button
    }

    private func arrowButton(_ symbol: String, label: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.35)
        config.baseForegroundColor = .white
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))
        let button = UIButton(configuration: config)
        button.accessibilityLabel = label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
        return button
    }

    // MARK: - Playback

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        if pauseReasons.contains(.sheet), presentedViewController == nil, !isBeingDismissed {
            pauseReasons.remove(.sheet)
        }
        guard let last = lastTimestamp, pauseReasons.isEmpty, !UIAccessibility.isVoiceOverRunning else { return }
        elapsed += link.timestamp - last
        if elapsed >= Self.momentDuration {
            go(by: 1)
        } else {
            currentBar?.progress = CGFloat(elapsed / Self.momentDuration)
        }
    }

    private func pause(_ reason: PauseReason) { pauseReasons.insert(reason) }
    private func resume(_ reason: PauseReason) { pauseReasons.remove(reason) }

    @objc private func appWillResignActive() { pause(.background) }
    @objc private func appDidBecomeActive() { resume(.background) }

    // MARK: - Navigation

    @objc private func imageTapped(_ tap: UITapGestureRecognizer) {
        if replyField.isFirstResponder {
            view.endEditing(true)
            return
        }
        go(by: tap.location(in: imageView).x < imageView.bounds.width * 0.35 ? -1 : 1)
    }

    @objc private func imageHeld(_ hold: UILongPressGestureRecognizer) {
        switch hold.state {
        case .began:
            pause(.holding)
            setChromeHidden(true)
        case .ended, .cancelled, .failed:
            resume(.holding)
            setChromeHidden(false)
        default:
            break
        }
    }

    private func setChromeHidden(_ hidden: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.chromeViews.forEach { $0.alpha = hidden ? 0 : 1 }
        }
    }

    private func go(by delta: Int) {
        let target = index + delta
        guard profile.moments.indices.contains(target) else {
            if target >= profile.moments.count {
                pause(.sheet)
                dismiss(animated: true)
            } else {
                elapsed = 0
                currentBar?.progress = 0
            }
            return
        }
        index = target
        update(animated: true)
    }

    private func update(animated: Bool) {
        guard profile.moments.indices.contains(index) else { return }
        elapsed = 0
        let moment = profile.moments[index]
        let apply = { self.imageView.loadImage(path: moment.imagePath, placeholder: UIImage(named: "ProfileBlur")) }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: imageView, duration: 0.25, options: .transitionCrossDissolve, animations: apply)
        } else {
            apply()
        }
        for (i, bar) in progressBars.enumerated() {
            bar.progress = i < index ? 1 : 0
        }
        timeLabel.text = moment.postedAgoText
        captionLabel.text = moment.caption
        captionLabel.isHidden = moment.caption == nil
        locationLabel.text = profile.city.map { "📍 \($0)" }
        locationLabel.isHidden = profile.city == nil
        previousButton.isHidden = index == 0
        nextButton.isHidden = index >= profile.moments.count - 1
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "\(profile.displayName)'s moment \(index + 1) of \(profile.moments.count). " + (moment.caption ?? "")
    }

    // MARK: - Reactions & replies

    private func react(_ emoji: String, from button: UIView) {
        guard let moment = currentMoment else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        VibeAnalytics.track(.vibeMomentReacted, profileID: profile.id,
                            properties: ["moment_id": moment.id, "reaction": emoji])
        floatEmoji(emoji, from: button)
        showConfirmation("\(emoji) Sent to \(profile.displayName)")
        // Give the reaction a moment to land before the Moment moves on.
        elapsed = min(elapsed, Self.momentDuration - 1.5)
    }

    private func sendReply() {
        let text = (replyField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let moment = currentMoment else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        VibeAnalytics.track(.vibeMomentReplied, profileID: profile.id,
                            properties: ["moment_id": moment.id, "length": text.count])
        replyField.text = nil
        updateSendButton()
        view.endEditing(true)
        showConfirmation("Reply sent to \(profile.displayName)")
    }

    private func floatEmoji(_ emoji: String, from source: UIView) {
        let origin = source.convert(CGPoint(x: source.bounds.midX, y: source.bounds.midY), to: view)
        let count = UIAccessibility.isReduceMotionEnabled ? 1 : 7
        for i in 0..<count {
            let label = UILabel()
            label.text = emoji
            label.font = .systemFont(ofSize: i == 0 ? 56 : CGFloat.random(in: 26...40))
            label.sizeToFit()
            label.center = origin
            label.isAccessibilityElement = false
            view.addSubview(label)

            if UIAccessibility.isReduceMotionEnabled {
                label.alpha = 0
                UIView.animate(withDuration: 0.2, animations: { label.alpha = 1 }) { _ in
                    UIView.animate(withDuration: 0.4, delay: 0.5, animations: { label.alpha = 0 }) { _ in label.removeFromSuperview() }
                }
                continue
            }

            let rise = CGFloat.random(in: 220...360)
            let drift = i == 0 ? 0 : CGFloat.random(in: -90...90)
            label.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            UIView.animate(withDuration: 1.3, delay: Double(i) * 0.06, options: .curveEaseOut, animations: {
                label.center = CGPoint(x: origin.x + drift, y: origin.y - rise)
                label.transform = CGAffineTransform(rotationAngle: CGFloat.random(in: -0.4...0.4)).scaledBy(x: 1.15, y: 1.15)
            })
            UIView.animate(withDuration: 0.5, delay: 0.85 + Double(i) * 0.06, options: [], animations: {
                label.alpha = 0
            }) { _ in label.removeFromSuperview() }
        }
    }

    private func showConfirmation(_ text: String) {
        view.subviews.filter { $0.accessibilityIdentifier == "momentConfirmation" }.forEach { $0.removeFromSuperview() }
        let pill = PaddedPillLabel(dark: true)
        pill.text = text
        pill.accessibilityIdentifier = "momentConfirmation"
        pill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14)
        ])
        UIAccessibility.post(notification: .announcement, argument: text)
        pill.alpha = 0
        pill.transform = CGAffineTransform(translationX: 0, y: 8)
        UIView.animate(withDuration: 0.25, animations: {
            pill.alpha = 1
            pill.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 1.6, animations: { pill.alpha = 0 }) { _ in pill.removeFromSuperview() }
        }
    }

    private func showOptions(from sourceView: UIView) {
        pause(.sheet)
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if onViewProfile != nil {
            sheet.addAction(UIAlertAction(title: "View \(profile.displayName)'s profile", style: .default) { [weak self] _ in
                guard let self else { return }
                self.onViewProfile?(self.profile)
            })
        }
        sheet.addAction(UIAlertAction(title: "Report Moment", style: .destructive) { [weak self] _ in
            guard let self else { return }
            VibeSafety.presentReportReasons(for: self.profile, from: self, sourceView: sourceView) { [weak self] in
                guard let self else { return }
                self.dismiss(animated: true) { self.onReport?(self.profile) }
            }
        })
        sheet.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = sourceView
        present(sheet, animated: true)
    }
}

extension VibeMomentsViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        pause(.typing)
        UIView.animate(withDuration: 0.2) { self.captionStack.alpha = 0 }
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        resume(.typing)
        UIView.animate(withDuration: 0.2) { self.captionStack.alpha = 1 }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendReply()
        return false
    }
}

/// A single story segment: a translucent track with a white fill.
private final class MomentProgressBar: UIView {
    private let fill = UIView()

    var progress: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.white.withAlphaComponent(0.35)
        layer.cornerRadius = 1.5
        clipsToBounds = true
        fill.backgroundColor = .white
        addSubview(fill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * min(max(progress, 0), 1), height: bounds.height)
    }
}
