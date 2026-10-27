//
//  CardDetailViewController.swift
//  FlirttimeNew
//
//  Card details: why you're seeing this person, their words, voice, Moments and interests.
//

import UIKit
import RxSwift
import Swinject

final class CardDetailViewController: BaseViewController {

    var onAction: ((MomentsAction, [ConnectReason]?, MomentsReaction?) -> Void)?
    var onInterestTapped: ((MomentsInterest) -> Void)?
    /// When set, the caller sends the report or block. Otherwise this screen sends it and pops.
    var onSafetyAction: ((MomentsProfile, MomentsSafetyAction) -> Void)?
    /// Called after this screen sent a report or block itself, just before it pops.
    var onSafetyCompleted: ((MomentsSafetyAction) -> Void)?

    private var profile: MomentsProfile
    /// Moments reported from the Moments list; kept out even if the profile API still returns them.
    private var hiddenMomentIDs = Set<Int>()
    private let sessionManager = Container.appContainer.resolve(AppSessionManager.self)!
    private let disposeBag = DisposeBag()

    private let scrollView = UIScrollView()
    private var contentView: UIView?
    private var galleryScrollView = UIScrollView()
    private var counter = PaddedPillLabel()
    private let bottomBar = UIView()
    private var waveform: VoiceWaveformView?
    private var playButton = UIButton(type: .custom)
    private var actionButtons: [UIButton] = []
    private var isSendingAction = false
    private let refreshIndicator = ProfileRefreshIndicator()
    private var isLoadingDetail = false
    private var galleryTopConstraint: NSLayoutConstraint?
    private var galleryHeightConstraint: NSLayoutConstraint?
    private var galleryTopShade: UIView?
    private var galleryBaseHeight: CGFloat = 0
    /// Cover stretch is only for a user pull; attaching the refresh control would otherwise stretch it on first open.
    private var canStretchCover = false

    init(profile: MomentsProfile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        view.isOpaque = true
        setUI()
        NotificationCenter.default.addObserver(self, selector: #selector(playerChanged), name: VoiceIntroPlayer.stateDidChange, object: nil)
        playerChanged()
        loadDetail()
    }

    /// The card only carries feed fields; the full profile fills in bio, voice, Moments and the rest.
    /// On failure the screen keeps showing the card data.
    private func loadDetail() {
        guard let userID = profile.remoteUserId else {
            endRefreshing()
            return
        }
        guard !isLoadingDetail else { return }
        isLoadingDetail = true
        sessionManager.otherUserProfile(userId: userID)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] detail in
                guard let self else { return }
                self.profile = DiscoverViewModel.makeProfile(from: detail, merging: self.profile)
                self.profile.moments.removeAll { self.hiddenMomentIDs.contains($0.id) }
                self.buildContent()
                self.playerChanged()
                self.isLoadingDetail = false
                self.endRefreshing()
            }, onFailure: { [weak self] _ in
                self?.isLoadingDetail = false
                self?.endRefreshing()
            })
            .disposed(by: disposeBag)
    }

    /// Matches Other User Profile and Profile: a clear `UIRefreshControl` drives the pull,
    /// and `refreshIndicator` shows progress over the cover photo.
    private func configurePullToRefresh() {
        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .clear
        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        scrollView.refreshControl = refreshControl
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.delegate = self
        refreshIndicator.install(in: view)
    }

    @objc private func pullToRefresh() {
        refreshIndicator.beginRefreshing()
        if !isLoadingDetail {
            loadDetail()
        }
        if !isLoadingDetail {
            endRefreshing()
        }
    }

    private func endRefreshing() {
        scrollView.refreshControl?.endRefreshing()
        refreshIndicator.endRefreshing()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canStretchCover = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateGalleryBaseHeight()
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
        scrollView.backgroundColor = AppColor.AppWhite
        let fade = MomentsGradientView(colors: [AppColor.AppWhite.withAlphaComponent(0), AppColor.AppWhite],
                                       start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))
        fade.isUserInteractionEnabled = false
        [scrollView, fade, bottomBar].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        setBottomBar()
        let topButtons = makeTopButtons()
        configurePullToRefresh()

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            fade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fade.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fade.heightAnchor.constraint(equalToConstant: 120),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topButtons.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            topButtons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            topButtons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
        scrollView.contentInset.bottom = 96
        scrollView.verticalScrollIndicatorInsets.bottom = 96
        buildContent()
    }

    /// Gallery and details for the current `profile`; called again when the full profile arrives.
    private func buildContent() {
        contentView?.removeFromSuperview()
        galleryScrollView = UIScrollView()
        counter = PaddedPillLabel()
        playButton = UIButton(type: .custom)
        waveform = nil
        galleryTopConstraint = nil
        galleryHeightConstraint = nil
        galleryTopShade = nil

        let content = UIView()
        content.backgroundColor = AppColor.AppWhite
        content.clipsToBounds = false
        let gallery = makeGallery()
        let sheet = makeSheet()
        [content, gallery, sheet].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        scrollView.addSubview(content)
        content.addSubview(gallery)
        content.addSubview(sheet)
        contentView = content

        let baseHeight = galleryBaseHeight > 1 ? galleryBaseHeight : view.bounds.height * 0.56
        galleryBaseHeight = baseHeight
        let galleryTop = gallery.topAnchor.constraint(equalTo: content.topAnchor)
        let galleryHeight = gallery.heightAnchor.constraint(equalToConstant: baseHeight)
        galleryTopConstraint = galleryTop
        galleryHeightConstraint = galleryHeight

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            galleryTop,
            gallery.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            gallery.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            galleryHeight,

            sheet.topAnchor.constraint(equalTo: gallery.bottomAnchor, constant: -28),
            sheet.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sheet.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            sheet.bottomAnchor.constraint(equalTo: content.bottomAnchor)
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
                self?.react(MomentsReaction(target: .photo(index)))
                return true
            }]
            row.addArrangedSubview(imageView)
            imageView.widthAnchor.constraint(equalTo: galleryScrollView.frameLayoutGuide.widthAnchor).isActive = true
            imageView.heightAnchor.constraint(equalTo: galleryScrollView.frameLayoutGuide.heightAnchor).isActive = true
        }
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(galleryDoubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        galleryScrollView.addGestureRecognizer(doubleTap)

        let topShade = MomentsGradientView(colors: [UIColor.black.withAlphaComponent(0.4), .clear],
                                        start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))
        galleryTopShade = topShade
        let shade = MomentsGradientView(colors: [.clear, UIColor.black.withAlphaComponent(0.7)],
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
            verified.setImage(UIImage(named: "verified")?.withRenderingMode(.alwaysOriginal), for: .normal)
            verified.tintColor = .clear
            verified.imageView?.contentMode = .scaleAspectFit
            verified.contentHorizontalAlignment = .fill
            verified.contentVerticalAlignment = .fill
            verified.accessibilityLabel = "Verified profile"
            verified.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                MomentsVerificationInfo.present(for: self.profile, from: self)
            }, for: .touchUpInside)
            verified.setContentHuggingPriority(.required, for: .horizontal)
            verified.widthAnchor.constraint(equalToConstant: 24).isActive = true
            verified.heightAnchor.constraint(equalToConstant: 24).isActive = true
            nameRow.addArrangedSubview(verified)
        }
        nameRow.addArrangedSubview(UIView())
        let info = UIStackView(arrangedSubviews: [nameRow])
        info.axis = .vertical
        info.spacing = 4
        if let line = profile.locationLine {
            let pin = UIImageView(image: UIImage(systemName: "location.fill",
                                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))
            pin.tintColor = UIColor.white.withAlphaComponent(0.92)
            pin.setContentHuggingPriority(.required, for: .horizontal)
            pin.setContentCompressionResistancePriority(.required, for: .horizontal)
            let location = UILabel.vibeLabel(.regular, 15, style: .subheadline, color: UIColor.white.withAlphaComponent(0.92), lines: 2)
            location.text = line
            let locationRow = UIStackView(arrangedSubviews: [pin, location])
            locationRow.spacing = 5
            locationRow.alignment = .center
            info.addArrangedSubview(locationRow)
        }
        if let intent = profile.datingIntent {
            let lookingFor = UILabel.vibeLabel(.regular, 15, style: .subheadline, color: UIColor.white.withAlphaComponent(0.9), lines: 2)
            lookingFor.text = "Looking for \(intent.lowercased())"
            info.addArrangedSubview(lookingFor)
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
            moments.onTap = { [weak self] _ in self?.openMoments() }
            stack.addArrangedSubview(section("Moments", content: moments))
        }
        if !profile.interests.isEmpty {
            let chips = MomentsChipsView()
            chips.configure(profile.interests, highlighted: Set(profile.sharedInterests.map(\.id)))
            chips.onTap = { [weak self] interest in self?.onInterestTapped?(interest) }
            stack.addArrangedSubview(section("Interests", content: chips))
        }
        if let aboutMe = makeMoreAboutMeSection() {
            stack.addArrangedSubview(aboutMe)
        }
        return sheet
    }

    private func makeMoreAboutMeSection() -> UIView? {
        let rows = OtherUserProfileDetails.moreAboutMeRows(from: profile.aboutAnswers)
        guard !rows.isEmpty else { return nil }
        let list = UIStackView()
        list.axis = .vertical
        list.spacing = 0
        for (index, info) in rows.enumerated() {
            list.addArrangedSubview(makeAboutRow(info, isLast: index == rows.count - 1))
        }
        let card = UIView()
        card.backgroundColor = AppColor.AthensGray
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.addSubview(list)
        list.pinEdges(to: card)
        return section("More about me", content: card)
    }

    private func makeAboutRow(_ info: OtherUserBasicInfo, isLast: Bool) -> UIView {
        let icon = UIImageView()
        icon.backgroundColor = AppColor.AppWhite
        icon.layer.cornerRadius = 16
        icon.clipsToBounds = true
        if let path = info.iconPath, !path.isEmpty {
            icon.contentMode = .scaleAspectFit
            icon.loadImage(path: path)
        } else {
            icon.contentMode = .center
            icon.tintColor = AppColor.Punch
            icon.image = UIImage(systemName: "sparkles",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        }

        let title = UILabel.vibeLabel(.medium, 14, style: .subheadline, color: AppColor.DoveGray)
        title.text = info.title
        let value = UILabel.vibeLabel(.medium, 14, style: .subheadline, color: AppColor.MineShaft)
        value.text = info.value
        value.textAlignment = .right
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        let text = UIStackView(arrangedSubviews: [title, value])
        text.spacing = 8

        let row = UIStackView(arrangedSubviews: [icon, text])
        row.spacing = 12
        row.alignment = .center
        let wrapper = UIView()
        wrapper.addSubview(row)
        row.pinEdges(to: wrapper, insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32)
        ])
        if !isLast {
            let line = UIView()
            line.backgroundColor = AppColor.Iron
            line.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(line)
            NSLayoutConstraint.activate([
                line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
                line.leadingAnchor.constraint(equalTo: text.leadingAnchor),
                line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
                line.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
            ])
        }
        wrapper.isAccessibilityElement = true
        wrapper.accessibilityLabel = "\(info.title): \(info.value)"
        return wrapper
    }

    private func makeWhySection() -> UIView {
        let title = sectionTitle("Why This Match?")
        let header = UIStackView(arrangedSubviews: [title, UIView()])
        header.alignment = .center
        if let score = profile.vibeScore {
            let badge = UILabel.vibeLabel(.bold, 13, style: .footnote, color: AppColor.Punch)
            badge.text = "\(score)% Match"
            badge.accessibilityLabel = "\(score) percent match, based on shared interests"
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
        return section("About \(profile.displayName)", content: stack)
    }

    private func makeVoicePlayer(_ intro: MomentsVoiceIntro) -> UIView {
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
        bottomBar.backgroundColor = .clear
        bottomBar.isOpaque = false

        let notInterested = MomentsProfileActionButton.make(kind: .notInterested) { [weak self] in
            self?.sendAction(.notMyVibe)
        }
        let superLike = MomentsProfileActionButton.make(kind: .superLike, size: 72) { [weak self] in
            self?.sendAction(.superVibe)
        }
        let like = MomentsProfileActionButton.make(kind: .like) { [weak self] in
            self?.sendAction(.interested)
        }
        actionButtons = [notInterested, superLike, like]

        let row = UIStackView(arrangedSubviews: [notInterested, superLike, like])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 18
        row.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 8),
            row.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            row.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
    }

    // MARK: - Actions

    @objc private func galleryDoubleTapped(_ tap: UITapGestureRecognizer) {
        let page = galleryScrollView.bounds.width > 0 ? Int((galleryScrollView.contentOffset.x / galleryScrollView.bounds.width).rounded()) : 0
        if let container = galleryScrollView.superview {
            HeartBurst.show(in: container, at: tap.location(in: container))
        }
        react(MomentsReaction(target: .photo(page)))
    }

    private func react(_ reaction: MomentsReaction) {
        MomentsHaptics.threshold()
        let delay = UIAccessibility.isReduceMotionEnabled ? 0.1 : 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.sendAction(.interested, reaction: reaction)
        }
    }

    private func sendAction(_ action: MomentsAction, reaction: MomentsReaction? = nil) {
        guard !isSendingAction else { return }
        if let blocked = FreeTierLimitsStore.shared.blockReason(for: action) {
            showQuotaPopup(blocked)
            return
        }
        switch action {
        case .superVibe: MomentsHaptics.superVibe()
        case .interested: MomentsHaptics.threshold()
        default: break
        }
        if let onAction {
            isSendingAction = true
            actionButtons.forEach { $0.isEnabled = false }
            onAction(action, nil, reaction)
            return
        }
        sendActionLocally(action, reaction: reaction)
    }

    /// Used when this screen is opened outside Discover (e.g. Quick Moments → profile).
    private func sendActionLocally(_ action: MomentsAction, reaction: MomentsReaction?) {
        guard let targetUserID = profile.remoteUserId, !targetUserID.isEmpty else {
            aCustomToastView.show(message: "This profile can't be updated right now")
            return
        }
        isSendingAction = true
        actionButtons.forEach { $0.isEnabled = false }
        aActivityIndicator.show()
        sessionManager.discoveryAction(targetUserId: targetUserID, action: action.apiAction)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] result in
                guard let self else { return }
                self.aActivityIndicator.hide()
                if let coins = result.remainingCoins {
                    CoinWallet.shared.update(coins)
                }
                if action == .interested || action == .superVibe {
                    FreeTierLimitsStore.shared.refresh()
                }
                if result.isMatched == true {
                    FreeTierLimitsStore.shared.markHasMatch(userId: self.profile.remoteUserId)
                    self.presentMatchScreen(reaction: reaction)
                } else {
                    self.aCustomToastView.show(message: Self.successMessage(for: action))
                    self.navigationController?.popViewController(animated: true)
                }
            }, onFailure: { [weak self] error in
                guard let self else { return }
                self.aActivityIndicator.hide()
                self.isSendingAction = false
                self.actionButtons.forEach { $0.isEnabled = true }
                let mapped = Self.actionError(for: action, error: error)
                if mapped == .likeLimitReached || mapped == .insufficientCoins || mapped == .membershipRequired {
                    self.showQuotaPopup(mapped)
                } else {
                    self.aCustomToastView.show(message: parseError(error) ?? "Something went wrong. Please try again.")
                }
            })
            .disposed(by: disposeBag)
    }

    private func presentMatchScreen(reaction: MomentsReaction?) {
        MomentsHaptics.connected()
        MomentsAnalytics.track(.connectionCreated, profileID: profile.id)
        let connectionVC = MomentsConnectionViewController(mode: .matched(profile), reaction: reaction)
        connectionVC.onStartConversation = { [weak self] matched in
            self?.openChat(with: matched)
        }
        connectionVC.onDismiss = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        present(connectionVC, animated: true)
    }

    private func openChat(with profile: MomentsProfile) {
        guard let userID = profile.remoteUserId, !userID.isEmpty else {
            aCustomToastView.show(message: "Unable to start chat")
            return
        }
        if !FreeTierLimitsStore.shared.canStartChat(isMatched: true) {
            showSubscriptionPopUp(subscriptionPopUpType: .chat)
            return
        }
        let avatarURL = profile.photos.first.flatMap { path -> String? in
            guard !path.isEmpty else { return nil }
            return path.hasPrefix("http") ? path : ApiName.imgBaseURL + path
        }
        FreeTierLimitsStore.shared.markHasMatch(userId: userID)
        ChatProfileRouter.openChat(userID: userID,
                                   name: profile.displayName,
                                   avatarPath: avatarURL,
                                   isVerified: profile.isVerified,
                                   isMatched: true,
                                   from: self)
    }

    private func showQuotaPopup(_ error: MomentsActionError) {
        switch error {
        case .likeLimitReached:
            showSubscriptionPopUp(subscriptionPopUpType: .unlimitedSwipes)
        case .insufficientCoins, .membershipRequired:
            showSubscriptionPopUp(subscriptionPopUpType: .superLike)
        default:
            break
        }
    }

    private static func successMessage(for action: MomentsAction) -> String {
        switch action {
        case .interested: return "💗 Like sent"
        case .superVibe: return "✨ Super Like sent"
        case .notMyVibe, .nope: return "Not interested"
        }
    }

    private static func actionError(for action: MomentsAction, error: Error) -> MomentsActionError {
        if FreeTierErrorCode.isDailyLikeLimit(error) { return .likeLimitReached }
        if FreeTierErrorCode.matches(error, FreeTierErrorCode.insufficientCoins) { return .insufficientCoins }
        let statusCode = (error as? APIHTTPError)?.statusCode ?? error.statusCode
        if action == .interested, statusCode == 429 { return .likeLimitReached }
        if action == .superVibe, statusCode == 402 || statusCode == 403 { return .insufficientCoins }
        if statusCode == 502 || statusCode == 503 || statusCode == 504 { return .serverBusy }
        return .network
    }

    private func toggleVoice() {
        guard let intro = profile.voiceIntro else { return }
        if VoiceIntroPlayer.shared.playingProfileID != profile.id {
            MomentsAnalytics.track(.vibeVoicePlayed, profileID: profile.id)
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

    private func openMoments() {
        MomentsAnalytics.track(.vibeMomentOpened, profileID: profile.id)
        let userID = profile.remoteUserId ?? String(profile.id)
        let momentsList = MomentsListViewController.make(scope: .user(id: userID, name: profile.displayName))
        momentsList.onVibeRemoved = { [weak self] momentID in
            guard let self else { return }
            let hiddenID = momentID.stableID
            self.hiddenMomentIDs.insert(hiddenID)
            self.profile.moments.removeAll { $0.id == hiddenID }
            self.profile.momentsCount = max(0, self.profile.momentsCount - 1)
            self.buildContent()
            self.loadDetail()
        }
        navigationController?.pushViewController(momentsList, animated: true)
    }

    private func showSafetyOptions(from sourceView: UIView) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Block \(profile.displayName)", style: .destructive) { [weak self] _ in
            self?.confirmBlock()
        })
        sheet.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = sourceView
        present(sheet, animated: true)
    }

    private func confirmBlock() {
        let alert = UIAlertController(title: "Block \(profile.displayName)?",
                                      message: "They won't be able to see your profile or contact you, and you won't see them in Discover.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: "Block", style: .destructive) { [weak self] _ in
            self?.handleSafety(.block)
        })
        present(alert, animated: true)
    }

    private func handleSafety(_ action: MomentsSafetyAction) {
        if let onSafetyAction {
            onSafetyAction(profile, action)
        } else {
            performSafety(action)
        }
    }

    private func performSafety(_ action: MomentsSafetyAction) {
        guard let userID = profile.remoteUserId else {
            aCustomToastView.show(message: "This profile can't be reported right now")
            return
        }
        let request: Single<Void>
        switch action {
        case .report(let reason):
            request = sessionManager.reportUser(userId: userID, reason: reason.rawValue, description: reason.title)
        case .block:
            request = sessionManager.blockUser(userId: userID, reason: "Blocked from profile").map { _ in () }
        }
        let name = profile.displayName
        aActivityIndicator.show()
        request
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] in
                guard let self else { return }
                self.aActivityIndicator.hide()
                if case .block = action {
                    BlockedUsersManager.shared.blockUser(id: userID)
                    self.aCustomToastView.show(message: "\(name) has been blocked")
                } else {
                    self.aCustomToastView.show(message: "Thanks for reporting. We'll review this profile.")
                }
                self.onSafetyCompleted?(action)
                self.navigationController?.popViewController(animated: true)
            }, onFailure: { [weak self] error in
                self?.aActivityIndicator.hide()
                self?.aCustomToastView.show(message: parseError(error) ?? "Something went wrong. Please try again.")
            })
            .disposed(by: disposeBag)
    }
}

extension CardDetailViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === galleryScrollView {
            guard scrollView.bounds.width > 0 else { return }
            let page = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
            counter.text = "\(min(max(page, 0), profile.photos.count - 1) + 1)/\(profile.photos.count)"
            return
        }
        guard scrollView === self.scrollView else { return }
        let maxOffsetY = max(0, scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
        if scrollView.contentOffset.y > maxOffsetY {
            scrollView.contentOffset.y = maxOffsetY
        }
        let pull = max(0, -scrollView.contentOffset.y)
        if canStretchCover || scrollView.isDragging {
            stretchCover(by: pull)
            refreshIndicator.update(pullDistance: pull)
        }
    }

    private func stretchCover(by stretch: CGFloat) {
        guard let galleryTopConstraint, galleryTopConstraint.constant != -stretch else { return }
        galleryTopConstraint.constant = -stretch
        galleryHeightConstraint?.constant = galleryBaseHeight + stretch
        galleryTopShade?.transform = CGAffineTransform(translationX: 0, y: -stretch)
    }

    private func updateGalleryBaseHeight() {
        let next = view.bounds.height * 0.56
        guard next > 1, abs(next - galleryBaseHeight) > 0.5 else { return }
        galleryBaseHeight = next
        let pull = max(0, -scrollView.contentOffset.y)
        galleryHeightConstraint?.constant = next + pull
    }
}
