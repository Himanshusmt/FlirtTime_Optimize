//
//  ProfileViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 18/05/24.
//

import UIKit
import Photos
import Combine
import StoreKit

class ProfileViewController: BaseViewController {

    private static let coverHeight: CGFloat = 240
    private static let ringSize: CGFloat = 136
    private static let avatarSize: CGFloat = 118
    private static let aboutCollapsedLines = 3

    private let aProfileViewModel = ProfileViewModel()
    private let aBannerModel = SetBannerModel()
    private var desposeBag: Set<AnyCancellable> = []
    private var userProfileData: UserDetailsData?
    private var coverImageUrl: String?
    private var selectedImage: UIImage?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let refreshIndicator = ProfileRefreshIndicator()

    // Header
    private let coverImageView = UIImageView()
    private var coverTopConstraint: NSLayoutConstraint?
    private var coverHeightConstraint: NSLayoutConstraint?
    private var coverTopShade: UIView?
    private let topButtonsTopConstraintOffset: CGFloat = 6
    private var topButtonsTopConstraint: NSLayoutConstraint?
    private let progressRing = CircularProgressView(frame: CGRect(x: 0, y: 0, width: ProfileViewController.ringSize, height: ProfileViewController.ringSize))
    private let avatarImageView = UIImageView()
    private let completionButton = UIButton(type: .custom)

    // Identity
    private let nameLabel = UILabel.vibeLabel(.bold, 26, style: .title1, color: AppColor.AppBlack)
    private let verifiedImageView = UIImageView(image: UIImage(named: "verifyIcon"))
    private let locationLabel = UILabel.vibeLabel(.regular, 14, style: .subheadline, color: AppColor.DoveGray)
    private let aboutLabel = UILabel.vibeLabel(.regular, 15, style: .body, color: AppColor.MineShaft, lines: ProfileViewController.aboutCollapsedLines)

    // Sections
    private let voiceIntroView = ProfileVoiceIntroView(style: .profile)
    private let quickMomentsView = ProfileQuickMomentsView()
    private let quickMomentsHint = UILabel.vibeLabel(.regular, 13, style: .footnote, color: AppColor.DoveGray, lines: 0)
    private lazy var quickMomentsHintContainer = padded(quickMomentsHint, top: 0)
    private let interestsChips = MomentsChipsView()
    private lazy var interestsContainer = padded(section("My Interests", content: interestsChips, actionTitle: "Edit") { [weak self] in
        self?.openEditProfile()
    }, top: 28)
    private let momentsGrid = ProfileMomentsGridView()
    private let momentsSeeAllButton = UIButton(type: .system)
    private let uploadViewModel = MomentsUploadViewModel.shared
    private let photosRow = UIStackView()
    private lazy var photosContainer = padded(section("My Photos", content: horizontalScroller(for: photosRow, height: 150), actionTitle: "Edit") { [weak self] in
        self?.openEditProfile()
    }, top: 28, horizontal: 0)
    private lazy var premiumCardContainer = padded(makePremiumCard(), top: 24)
    private lazy var membershipCard: SubscriptionMembershipCard = {
        let card = SubscriptionMembershipCard()
        card.onManage = { [weak self] in self?.manageSubscription() }
        return card
    }()
    private lazy var membershipCardContainer = padded(membershipCard, top: 24)

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        setUI()
        setBinding()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: false)
        loadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        AppTabBarController.buttonD.isHidden = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        voiceIntroView.stopIfPlaying()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        AppTabBarController.buttonD.isHidden = true
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        topButtonsTopConstraint?.constant = view.safeAreaInsets.top + topButtonsTopConstraintOffset
    }

    private func loadData() {
        aProfileViewModel.getProfileDataAPI()
        aProfileViewModel.getMyProfile()
        aProfileViewModel.getQuickMoments()
        aProfileViewModel.getMyMoments()
        SubscriptionMembershipStore.shared.refresh()
    }

    @objc private func pullToRefresh() {
        refreshIndicator.beginRefreshing()
        if !aProfileViewModel.isFetching {
            loadData()
        }
        if !aProfileViewModel.isFetching {
            endRefreshing()
        }
    }

    private func endRefreshing() {
        scrollView.refreshControl?.endRefreshing()
        refreshIndicator.endRefreshing()
    }

    // MARK: - Binding

    private func setBinding() {
        aProfileViewModel.$aUserProfileModel.receive(on: DispatchQueue.main).sink { [weak self] model in
            guard let self, let model else { return }
            self.userProfileData = model
        }.store(in: &desposeBag)

        aProfileViewModel.$myProfile.receive(on: DispatchQueue.main).sink { [weak self] data in
            guard let self, let data else { return }
            self.setMyProfile(data)
        }.store(in: &desposeBag)

        aProfileViewModel.$quickMoments.receive(on: DispatchQueue.main).sink { [weak self] moments in
            guard let self else { return }
            let frames = moments.enumerated().map { $1.storyMoment(id: $0) }
            self.quickMomentsView.configure(moments: frames, avatarPath: self.avatarPath)
            self.quickMomentsHintContainer.isHidden = !moments.isEmpty
        }.store(in: &desposeBag)

        aProfileViewModel.$myMoments.receive(on: DispatchQueue.main).sink { [weak self] vibes in
            guard let self, let vibes else { return }
            self.momentsGrid.configure(vibes: vibes)
            let total = self.aProfileViewModel.myMomentsTotal
            self.momentsSeeAllButton.isHidden = vibes.isEmpty
            self.momentsSeeAllButton.configuration?.attributedTitle = AttributedString(
                total > vibes.count ? "See all (\(total))" : "See all",
                attributes: AttributeContainer([.font: MomentsFont.scaled(.medium, 14, style: .subheadline)]))
        }.store(in: &desposeBag)

        uploadViewModel.$uploadProgress.receive(on: DispatchQueue.main).sink { [weak self] progress in
            self?.momentsGrid.setUploadProgress(progress)
        }.store(in: &desposeBag)

        uploadViewModel.uploadFinished.receive(on: DispatchQueue.main).sink { [weak self] result in
            guard case .success = result else { return }
            self?.aProfileViewModel.getMyMoments()
        }.store(in: &desposeBag)

        aProfileViewModel.$isFetching.receive(on: DispatchQueue.main).sink { [weak self] isFetching in
            guard let self, !isFetching, self.refreshIndicator.isRefreshing else { return }
            self.endRefreshing()
        }.store(in: &desposeBag)

        aProfileViewModel.$errorMessage.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self, let error else { return }
            self.showNewAlertPopUp(Title: "Error", Msg: error, isSuccess: false) { _ in }
        }.store(in: &desposeBag)

        aBannerModel.$aUploadBannerModel.receive(on: DispatchQueue.main).sink { [weak self] model in
            guard let self, let model else { return }
            self.aActivityIndicator.hide()
            self.coverImageView.loadImage(path: model.data?.image_url, placeholder: UIImage(named: "addCoverPhoto"))
            self.aProfileViewModel.getMyProfile()
        }.store(in: &desposeBag)

        aBannerModel.$errorBannerMessage.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self, let error else { return }
            self.aActivityIndicator.hide()
            self.showImageAlertPopUp(TitleMsg: error, TitleBtn: "Discard")
        }.store(in: &desposeBag)

        NotificationCenter.default.publisher(for: .userSubscriptionStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateSubscriptionCards() }
            .store(in: &desposeBag)

        SubscriptionMembershipStore.shared.$membership
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateSubscriptionCards() }
            .store(in: &desposeBag)
    }

    private var avatarPath: String? {
        aProfileViewModel.myProfile?.profile?.avatarURL
    }

    /// The username from `auth/me`; `users/profile` only sends the nickname as `displayName`.
    private var headerName: String {
        let username = UserDataManager.shared.appUser?.username?.trimmingCharacters(in: .whitespaces) ?? ""
        if !username.isEmpty { return username }
        return (aProfileViewModel.myProfile?.profile?.displayName ?? "").firstLetterCapitalized
    }

    private func setMyProfile(_ data: MyProfileData) {
        let info = data.profile

        if let cover = info?.coverPhoto?.bestURL {
            coverImageUrl = cover.hasPrefix("http") ? cover : ApiName.imgBaseURL + cover
            coverImageView.loadImage(path: cover, placeholder: UIImage(named: "addCoverPhoto"))
        } else {
            coverImageUrl = nil
            coverImageView.image = UIImage(named: "addCoverPhoto")
        }
        avatarImageView.loadImage(path: avatarPath, placeholder: UIImage(named: "ProfileBlur"))
        voiceIntroView.configure(intro: data.voiceIntro?.userVoiceIntro)
        quickMomentsView.configure(moments: aProfileViewModel.quickMomentFrames, avatarPath: avatarPath)

        let completion = min(max(info?.completionPercentage ?? 0, 0), 100)
        progressRing.setProgressWithAnimation(duration: 1.2, value: Float(completion) / 100)
        completionButton.configuration?.attributedTitle = AttributedString("\(completion)% complete", attributes: AttributeContainer([
            .font: MomentsFont.scaled(.medium, 13, style: .footnote)
        ]))
        completionButton.accessibilityLabel = "Profile \(completion) percent complete. Edit profile"

        let name = headerName
        nameLabel.text = info?.age.map { "\(name), \($0)" } ?? name
        verifiedImageView.isHidden = info?.isVerified != true

        let location = info?.locationText ?? ""
        locationLabel.text = location.isEmpty ? nil : "📍 \(location)"
        locationLabel.isHidden = location.isEmpty

        let about = info?.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        aboutLabel.text = about.isEmpty ? nil : "“\(about)”"
        aboutLabel.isHidden = about.isEmpty

        let interests = data.vibeInterests
        interestsChips.configure(interests, highlighted: [])
        interestsContainer.isHidden = interests.isEmpty

        setPhotos(info?.photoURLs ?? [])
        updateSubscriptionCards()
    }

    private func updateSubscriptionCards() {
        let membership = SubscriptionMembershipStore.shared.membership
        let hasActiveMembership = membership?.isCurrentlyActive == true
        let subscribed = hasActiveMembership
            || aProfileViewModel.myProfile?.isSubscribed == true
            || UserDataManager.shared.isUserSubscriptionDone == true
        premiumCardContainer.isHidden = subscribed
        membershipCardContainer.isHidden = !hasActiveMembership
        if let membership, hasActiveMembership {
            membershipCard.configure(membership)
        }
    }

    private func manageSubscription() {
        if let scene = view.window?.windowScene {
            Task { @MainActor in
                try? await AppStore.showManageSubscriptions(in: scene)
            }
        } else {
            openPremium()
        }
    }

    // MARK: - UI

    private func setUI() {
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = self
        scrollView.contentInset.bottom = 120
        view.addSubview(scrollView)
        scrollView.pinEdges(to: view)

        let refreshControl = UIRefreshControl()
        // Only drives the pull gesture; the stretched cover hides its spinner, so `refreshIndicator` shows progress.
        refreshControl.tintColor = .clear
        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        scrollView.refreshControl = refreshControl
        refreshIndicator.install(in: view)

        contentStack.axis = .vertical
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        contentStack.addArrangedSubview(makeHeader())
        contentStack.addArrangedSubview(padded(makeIdentity(), top: 12))
        contentStack.addArrangedSubview(padded(makeActionButtons(), top: 20))
        contentStack.addArrangedSubview(padded(makeVoiceSection(), top: 28))
        contentStack.addArrangedSubview(makeQuickMomentsSection())
        contentStack.addArrangedSubview(premiumCardContainer)
        contentStack.addArrangedSubview(membershipCardContainer)
        updateSubscriptionCards()
        contentStack.addArrangedSubview(interestsContainer)
        contentStack.addArrangedSubview(padded(makeMomentsSection(), top: 28))
        contentStack.addArrangedSubview(photosContainer)
    }

    private func padded(_ content: UIView, top: CGFloat, horizontal: CGFloat = 20) -> UIView {
        let wrapper = UIView()
        wrapper.addSubview(content)
        content.pinEdges(to: wrapper, insets: UIEdgeInsets(top: top, left: horizontal, bottom: 0, right: horizontal))
        return wrapper
    }

    // MARK: Header

    private func makeHeader() -> UIView {
        let header = UIView()

        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.backgroundColor = AppColor.Lavenderblush
        coverImageView.image = UIImage(named: "addCoverPhoto")
        coverImageView.isAccessibilityElement = true
        coverImageView.accessibilityLabel = "Cover photo"

        let topShade = MomentsGradientView(colors: [UIColor.black.withAlphaComponent(0.35), .clear],
                                        start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))
        let bottomFade = MomentsGradientView(colors: [AppColor.AppWhite.withAlphaComponent(0), AppColor.AppWhite],
                                          start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))

        let settings = circleButton(symbol: "gearshape.fill", label: "Settings")
        settings.addAction(UIAction { [weak self] _ in self?.settingsTapped() }, for: .touchUpInside)
        let camera = circleButton(symbol: "camera.fill", label: "Change cover photo")
        camera.addAction(UIAction { [weak self] _ in self?.openImageSelectionMethodPopUp() }, for: .touchUpInside)
        let topButtons = UIStackView(arrangedSubviews: [UIView(), camera, settings])
        topButtons.spacing = 10

        progressRing.startAngle = CGFloat(-0.5 * Double.pi)
        progressRing.endAngle = CGFloat(1.5 * Double.pi)
        progressRing.setTrackColor = AppColor.Lavenderblush
        progressRing.setProgressColor = AppColor.Punch
        progressRing.setTrackLineWidth = 5
        progressRing.setProgressLineWidth = 6
        progressRing.setProgressWithAnimation(duration: 0, value: 0)
        progressRing.backgroundColor = AppColor.AppWhite
        progressRing.layer.cornerRadius = Self.ringSize / 2
        progressRing.isAccessibilityElement = false

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = Self.avatarSize / 2
        avatarImageView.backgroundColor = AppColor.AthensGray
        avatarImageView.isAccessibilityElement = true
        avatarImageView.accessibilityLabel = "Profile photo"

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColor.Punch
        config.baseForegroundColor = .white
        config.image = UIImage(systemName: "pencil", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        config.imagePlacement = .trailing
        config.imagePadding = 5
        config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12)
        completionButton.configuration = config
        completionButton.layer.shadowColor = AppColor.Punch.cgColor
        completionButton.layer.shadowOpacity = 0.3
        completionButton.layer.shadowRadius = 6
        completionButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        completionButton.addAction(UIAction { [weak self] _ in self?.openEditProfile() }, for: .touchUpInside)

        [coverImageView, topShade, bottomFade, topButtons, progressRing, avatarImageView, completionButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview($0)
        }

        let topConstraint = topButtons.topAnchor.constraint(equalTo: header.topAnchor, constant: 50)
        topButtonsTopConstraint = topConstraint
        let coverTop = coverImageView.topAnchor.constraint(equalTo: header.topAnchor)
        let coverHeight = coverImageView.heightAnchor.constraint(equalToConstant: Self.coverHeight)
        coverTopConstraint = coverTop
        coverHeightConstraint = coverHeight
        coverTopShade = topShade

        NSLayoutConstraint.activate([
            coverTop,
            coverImageView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            coverHeight,

            topShade.topAnchor.constraint(equalTo: header.topAnchor),
            topShade.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            topShade.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            topShade.heightAnchor.constraint(equalToConstant: 110),

            bottomFade.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            bottomFade.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            bottomFade.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor),
            bottomFade.heightAnchor.constraint(equalToConstant: 90),

            topConstraint,
            topButtons.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            topButtons.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),

            progressRing.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            progressRing.centerYAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: -16),
            progressRing.widthAnchor.constraint(equalToConstant: Self.ringSize),
            progressRing.heightAnchor.constraint(equalToConstant: Self.ringSize),

            avatarImageView.centerXAnchor.constraint(equalTo: progressRing.centerXAnchor),
            avatarImageView.centerYAnchor.constraint(equalTo: progressRing.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: Self.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Self.avatarSize),

            completionButton.centerXAnchor.constraint(equalTo: progressRing.centerXAnchor),
            completionButton.centerYAnchor.constraint(equalTo: progressRing.bottomAnchor),
            completionButton.bottomAnchor.constraint(equalTo: header.bottomAnchor)
        ])
        return header
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

    // MARK: Identity

    private func makeIdentity() -> UIView {
        nameLabel.textAlignment = .center
        nameLabel.accessibilityTraits = .header
        verifiedImageView.contentMode = .scaleAspectFit
        verifiedImageView.isHidden = true
        verifiedImageView.isAccessibilityElement = true
        verifiedImageView.accessibilityLabel = "Verified"
        NSLayoutConstraint.activate([
            verifiedImageView.widthAnchor.constraint(equalToConstant: 20),
            verifiedImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
        let nameRow = UIStackView(arrangedSubviews: [nameLabel, verifiedImageView])
        nameRow.spacing = 6
        nameRow.alignment = .center

        locationLabel.textAlignment = .center
        aboutLabel.textAlignment = .center
        aboutLabel.isUserInteractionEnabled = true
        aboutLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleAbout)))
        aboutLabel.accessibilityHint = "Double tap to show more or less"

        let stack = UIStackView(arrangedSubviews: [nameRow, locationLabel, aboutLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.setCustomSpacing(12, after: locationLabel)
        return stack
    }

    @objc private func toggleAbout() {
        let collapsed = aboutLabel.numberOfLines != 0
        aboutLabel.numberOfLines = collapsed ? 0 : Self.aboutCollapsedLines
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    // MARK: Actions row

    private func makeActionButtons() -> UIView {
        var edit = UIButton.Configuration.filled()
        edit.cornerStyle = .capsule
        edit.baseBackgroundColor = AppColor.Lavenderblush
        edit.baseForegroundColor = AppColor.Punch
        edit.image = UIImage(systemName: "pencil", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        edit.imagePadding = 8
        edit.attributedTitle = AttributedString("Edit Profile", attributes: AttributeContainer([.font: MomentsFont.scaled(.medium, 16)]))
        let editButton = UIButton(configuration: edit)
        editButton.addAction(UIAction { [weak self] _ in self?.openEditProfile() }, for: .touchUpInside)

        var add = UIButton.Configuration.filled()
        add.cornerStyle = .capsule
        add.baseBackgroundColor = AppColor.Punch
        add.baseForegroundColor = .white
        add.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        add.imagePadding = 8
        add.attributedTitle = AttributedString("Add Moment", attributes: AttributeContainer([.font: MomentsFont.scaled(.medium, 16)]))
        let addButton = UIButton(configuration: add)
        addButton.layer.shadowColor = AppColor.Punch.cgColor
        addButton.layer.shadowOpacity = 0.35
        addButton.layer.shadowRadius = 10
        addButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        addButton.addAction(UIAction { [weak self] _ in self?.openAddMoment() }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [editButton, addButton])
        row.spacing = 12
        row.distribution = .fillEqually
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        return row
    }

    // MARK: Voice intro

    private func makeVoiceSection() -> UIView {
        voiceIntroView.onRecord = { [weak self] in self?.recordVoiceIntro() }
        return section("My Voice", content: voiceIntroView, actionTitle: nil, action: nil)
    }

    private func recordVoiceIntro() {
        voiceIntroView.stopIfPlaying()
        VoiceIntroRecorderViewController.present(from: self) { [weak self] intro in
            guard let self else { return }
            self.voiceIntroView.configure(intro: intro)
            self.aProfileViewModel.getMyProfile()
            self.aCustomToastView.show(message: "Voice intro saved")
        }
    }

    // MARK: Quick Moments

    private func makeQuickMomentsSection() -> UIView {
        let header = sectionHeader("Quick Moments", actionTitle: "+ Add") { [weak self] in self?.openAddQuickMoment() }
        quickMomentsHint.text = "Share a quick photo or thought. People can react and reply to it."
        quickMomentsView.onAdd = { [weak self] in self?.openAddQuickMoment() }
        quickMomentsView.onSelect = { [weak self] index in self?.openQuickMoment(at: index) }
        quickMomentsView.heightAnchor.constraint(equalToConstant: ProfileQuickMomentsView.preferredHeight).isActive = true

        quickMomentsHintContainer.isHidden = true
        let stack = UIStackView(arrangedSubviews: [padded(header, top: 0), quickMomentsView, quickMomentsHintContainer])
        stack.axis = .vertical
        stack.spacing = 12
        let wrapper = UIView()
        wrapper.addSubview(stack)
        stack.pinEdges(to: wrapper, insets: UIEdgeInsets(top: 28, left: 0, bottom: 0, right: 0))
        return wrapper
    }

    // MARK: My Moments

    private func makeMomentsSection() -> UIView {
        let title = UILabel.vibeLabel(.bold, 18, style: .headline, color: AppColor.AppBlack)
        title.text = "My Moments"
        title.accessibilityTraits = .header

        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = AppColor.Punch
        config.contentInsets = .zero
        config.attributedTitle = AttributedString("See all", attributes: AttributeContainer([.font: MomentsFont.scaled(.medium, 14, style: .subheadline)]))
        momentsSeeAllButton.configuration = config
        momentsSeeAllButton.setContentHuggingPriority(.required, for: .horizontal)
        momentsSeeAllButton.accessibilityLabel = "See all, My Moments"
        momentsSeeAllButton.isHidden = true
        momentsSeeAllButton.addAction(UIAction { [weak self] _ in self?.openMyMoments() }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [title, UIView(), momentsSeeAllButton])
        header.alignment = .center

        momentsGrid.onSelect = { [weak self] vibe in self?.openMyMoments(focusing: vibe.id) }
        momentsGrid.onAdd = { [weak self] in self?.openAddMoment() }

        let stack = UIStackView(arrangedSubviews: [header, momentsGrid])
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }

    // MARK: Premium

    private func makePremiumCard() -> UIView {
        let card = MomentsGradientView(colors: MomentsTheme.brandGradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 1))
        card.isUserInteractionEnabled = true
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = AppColor.Punch.cgColor
        card.layer.shadowOpacity = 0.3
        card.layer.shadowRadius = 14
        card.layer.shadowOffset = CGSize(width: 0, height: 6)

        let crown = UIImageView(image: UIImage(systemName: "crown.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)))
        crown.tintColor = MomentsTheme.gold
        crown.contentMode = .center
        crown.backgroundColor = .white
        crown.layer.cornerRadius = 28
        let badge = UIView()
        badge.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        badge.layer.cornerRadius = 36
        badge.addSubview(crown)
        crown.pinEdges(to: badge, insets: UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))

        let title = UILabel.vibeLabel(.bold, 19, style: .headline, color: .white)
        title.text = "Enjoy All Benefits"
        let subtitle = UILabel.vibeLabel(.regular, 13, style: .footnote, color: UIColor.white.withAlphaComponent(0.92), lines: 0)
        subtitle.text = "Unlimited swiping, see who likes you and match without ads."

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .white
        config.baseForegroundColor = AppColor.Punch
        config.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 18, bottom: 9, trailing: 18)
        config.attributedTitle = AttributedString("Upgrade to premium", attributes: AttributeContainer([.font: MomentsFont.scaled(.bold, 15)]))
        let upgrade = UIButton(configuration: config)
        upgrade.addAction(UIAction { [weak self] _ in self?.openPremium() }, for: .touchUpInside)

        let texts = UIStackView(arrangedSubviews: [title, subtitle, upgrade])
        texts.axis = .vertical
        texts.alignment = .leading
        texts.spacing = 4
        texts.setCustomSpacing(12, after: subtitle)

        let row = UIStackView(arrangedSubviews: [badge, texts])
        row.spacing = 14
        row.alignment = .center
        card.addSubview(row)
        row.pinEdges(to: card, insets: UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16))
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 72),
            badge.heightAnchor.constraint(equalToConstant: 72)
        ])
        return card
    }

    // MARK: Photos

    private func setPhotos(_ photos: [String]) {
        photosRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, photo) in photos.enumerated() {
            let button = UIButton(type: .custom)
            let image = UIImageView()
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.layer.cornerRadius = 18
            image.layer.cornerCurve = .continuous
            image.backgroundColor = AppColor.AthensGray
            image.isUserInteractionEnabled = false
            image.loadImage(path: photo, placeholder: UIImage(named: "ProfileBlur"))
            button.addSubview(image)
            image.pinEdges(to: button)
            button.widthAnchor.constraint(equalToConstant: 116).isActive = true
            button.accessibilityLabel = "Your photo \(index + 1) of \(photos.count)"
            button.addAction(UIAction { [weak self] _ in self?.openEditProfile() }, for: .touchUpInside)
            photosRow.addArrangedSubview(button)
        }
        photosContainer.isHidden = photos.isEmpty
    }

    private func horizontalScroller(for row: UIStackView, height: CGFloat) -> UIView {
        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = false
        scroller.alwaysBounceHorizontal = true
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            row.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor, constant: -20),
            row.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor),
            scroller.heightAnchor.constraint(equalToConstant: height)
        ])
        return scroller
    }

    // MARK: Section helpers

    private func sectionHeader(_ title: String, actionTitle: String?, action: (() -> Void)?) -> UIView {
        let label = UILabel.vibeLabel(.bold, 18, style: .headline, color: AppColor.AppBlack)
        label.text = title
        label.accessibilityTraits = .header
        let row = UIStackView(arrangedSubviews: [label, UIView()])
        row.alignment = .center
        if let actionTitle, let action {
            var config = UIButton.Configuration.plain()
            config.baseForegroundColor = AppColor.Punch
            config.contentInsets = .zero
            config.attributedTitle = AttributedString(actionTitle, attributes: AttributeContainer([.font: MomentsFont.scaled(.medium, 14, style: .subheadline)]))
            let button = UIButton(configuration: config)
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.accessibilityLabel = "\(actionTitle), \(title)"
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        return row
    }

    /// A titled section; `content` keeps its own horizontal insets when it's full-width (photos).
    private func section(_ title: String, content: UIView, actionTitle: String?, action: (() -> Void)?) -> UIView {
        let header = sectionHeader(title, actionTitle: actionTitle, action: action)
        let isFullWidth = content is UIScrollView
        let stack = UIStackView(arrangedSubviews: [isFullWidth ? padded(header, top: 0) : header, content])
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }

    // MARK: - Navigation

    private func openEditProfile() {
        let aEditProfileViewController: EditProfileViewController = EditProfileViewController.instantiateFromStoryboard()
        aEditProfileViewController.coverImageUrl = coverImageUrl
        navigationController?.pushViewController(aEditProfileViewController, animated: true)
    }

    private func openMyMoments(focusing vibeID: String? = nil) {
        navigationController?.pushViewController(MomentsListViewController.make(scope: .currentUser, focusVibeID: vibeID), animated: true)
    }

    private func openAddMoment() {
        guard !uploadViewModel.isUploading else {
            aCustomToastView.show(message: "Please wait, your last moment is still uploading")
            return
        }
        let aAddMomentViewController: AddMomentViewController = AddMomentViewController.instantiateFromStoryboard()
        aAddMomentViewController.callBackAction = { [weak self] in
            guard let self else { return }
            self.scrollToMoments()
        }
        navigationController?.pushViewController(aAddMomentViewController, animated: true)
    }

    private func scrollToMoments() {
        view.layoutIfNeeded()
        let frame = momentsGrid.convert(momentsGrid.bounds, to: scrollView)
        let maxOffset = max(scrollView.contentSize.height + scrollView.contentInset.bottom - scrollView.bounds.height, 0)
        scrollView.setContentOffset(CGPoint(x: 0, y: min(max(frame.minY - 140, 0), maxOffset)), animated: false)
    }

    private func openAddQuickMoment() {
        let composer = AddQuickMomentViewController()
        composer.onShare = { [weak self] text, background, image in
            guard let self else { return }
            self.aActivityIndicator.show()
            self.aProfileViewModel.createQuickMoment(text: text, background: background, image: image) { [weak self] result in
                guard let self else { return }
                self.aActivityIndicator.hide()
                switch result {
                case .success: self.aCustomToastView.show(message: "Quick moment shared")
                case .failure(let error): self.aCustomToastView.show(message: error.message)
                }
            }
        }
        present(composer, animated: true)
    }

    private func showQuickMomentActivity(at index: Int, from presenter: UIViewController) {
        let moments = aProfileViewModel.quickMoments
        guard moments.indices.contains(index) else { return }
        let activity = QuickMomentActivityViewController(moment: moments[index])
        activity.modalPresentationStyle = .pageSheet
        if let sheet = activity.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(activity, animated: true)
    }

    private func deleteQuickMoment(at index: Int) {
        let moments = aProfileViewModel.quickMoments
        guard moments.indices.contains(index) else { return }
        aProfileViewModel.deleteQuickMoment(id: moments[index].id) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: self.aCustomToastView.show(message: "Quick moment deleted")
            case .failure(let error): self.aCustomToastView.show(message: error.message)
            }
        }
    }

    private func openQuickMoment(at index: Int) {
        let moments = aProfileViewModel.quickMomentFrames
        guard moments.indices.contains(index) else { return }
        let info = aProfileViewModel.myProfile?.profile
        let name = headerName
        let profile = MomentsProfile(id: (info?.id ?? UserDataManager.shared.appUser?.id ?? "").stableID,
                                  displayName: name.isEmpty ? "You" : name,
                                  age: nil,
                                  isVerified: info?.isVerified == true,
                                  gender: nil,
                                  city: nil,
                                  distanceKm: nil,
                                  isOnline: nil,
                                  datingIntent: nil,
                                  photos: [avatarPath].compactMap { $0 },
                                  about: "",
                                  interests: [],
                                  sharedInterests: [],
                                  reasons: [],
                                  voiceIntro: nil,
                                  moments: moments,
                                  vibeScore: nil)
        let viewer = QuickMomentViewController(profile: profile, startIndex: index, isOwnMoments: true)
        viewer.onShowActivity = { [weak self] index, presenter in self?.showQuickMomentActivity(at: index, from: presenter) }
        viewer.onDelete = { [weak self] index in self?.deleteQuickMoment(at: index) }
        present(viewer, animated: true)
    }

    private func settingsTapped() {
        let aSettingsViewController: SettingsViewController = SettingsViewController.instantiateFromStoryboard()
        navigationController?.pushViewController(aSettingsViewController, animated: true)
    }

    private func openImageSelectionMethodPopUp() {
        let aImageSelectionMethodVC: ImageSelectionMethodVC = ImageSelectionMethodVC.instantiateFromStoryboard()
        aImageSelectionMethodVC.callBack = { [weak self] useCamera in
            if useCamera {
                self?.checkCameraAuthorization()
            } else {
                self?.requestPhotoLibraryAccess()
            }
        }
        aImageSelectionMethodVC.modalPresentationStyle = .overCurrentContext
        tabBarController?.present(aImageSelectionMethodVC, animated: true, completion: nil)
    }
}

// MARK: - UIScrollViewDelegate

extension ProfileViewController: UIScrollViewDelegate {
    /// Pins the bottom edge so the profile never rubber-bands past its content; pulling down at the top
    /// stretches the cover photo up to the screen edge instead of revealing the background.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        let translation = scrollView.panGestureRecognizer.translation(in: scrollView).y
        hideShowTabBar(isHide: translation < 0)

        let maxOffsetY = max(0, scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
        if scrollView.contentOffset.y > maxOffsetY {
            scrollView.contentOffset.y = maxOffsetY
        }
        let pull = max(0, -scrollView.contentOffset.y)
        stretchCover(by: pull)
        refreshIndicator.update(pullDistance: pull)
    }

    private func stretchCover(by stretch: CGFloat) {
        guard let coverTopConstraint, coverTopConstraint.constant != -stretch else { return }
        coverTopConstraint.constant = -stretch
        coverHeightConstraint?.constant = Self.coverHeight + stretch
        coverTopShade?.transform = CGAffineTransform(translationX: 0, y: -stretch)
    }
}

// MARK: - Cover photo

extension ProfileViewController {

    func uploadSelectedImage(_ selectedImage: UIImage?) {
        guard let image = selectedImage else { return }
        aActivityIndicator.show()
        aBannerModel.uploadCoverPhotoAPI(image: image.fixedOrientation())
    }

    func requestPhotoLibraryAccess() {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            if status == .authorized {
                self?.openPhotoLibrary()
            } else {
                DispatchQueue.main.async {
                    self?.showPhotoLibraryAccessAlert()
                }
            }
        }
    }

    func checkCameraAuthorization() {
        DispatchQueue.main.async {
            let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if cameraAuthorizationStatus == .denied || cameraAuthorizationStatus == .restricted {
                self.showCameraAccessAlert()
            } else {
                let aFaceVerificationViewController: FaceVerificationViewController = FaceVerificationViewController.instantiateFromStoryboard()
                aFaceVerificationViewController.headerText = Constants.ProfileVerification.startPosing
                aFaceVerificationViewController.isHideScanningImage = true
                aFaceVerificationViewController.callBackAction = { [weak self] image in
                    if let selectedImage = image {
                        self?.uploadSelectedImage(selectedImage)
                    }
                }
                aFaceVerificationViewController.modalPresentationStyle = .overCurrentContext
                self.tabBarController?.present(aFaceVerificationViewController, animated: true, completion: nil)
            }
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let selectedImage = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage) {
            self.selectedImage = selectedImage
        }
        picker.dismiss(animated: true) {
            self.uploadSelectedImage(self.selectedImage)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}
