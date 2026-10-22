//
//  OtherUserProfileViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh  on 16/05/24.
//
//  Another user's profile. The whole layout (colors, fonts, spacing, sections) lives in
//  OtherUserProfile.storyboard; this class only fills it with data and handles taps.
//

import UIKit
import Combine

final class OtherUserProfileViewController: BaseViewController, Instantiable {

    static var storyboardName: StringConvertible {
        return StoryboardName.otherUserProfile
    }

    private static let aboutCollapsedLines = 3
    private static let headerToNameSpacing: CGFloat = 10
    private static let momentsPerRow: CGFloat = 3
    /// Photo cards fully visible at once in the horizontal Photos carousel.
    private static let photosPerRow: CGFloat = 2
    /// Width of the next photo card left visible at the trailing edge, hinting the carousel scrolls.
    private static let photoPeekWidth: CGFloat = 36
    /// Height / width of a photo card (165 × 230).
    private static let photoAspectRatio: CGFloat = 230 / 165
    /// Resting height of the cover photo; it grows past this while the profile is pulled down.
    private static let coverHeight: CGFloat = 270
    /// Moment tiles shown before the "See all" tile takes the next slot.
    static let momentsGridLimit = 8

    // MARK: - Set by the presenting screen

    var isMyProfile = false
    var fromExploreScreen: Bool? = false
    var fromExploreMatches: Bool? = false
    var fromExploreYouLike: Bool? = false
    var fromChatScreen: Bool? = false
    var isShowSuperLikeView = false
    var userDetails: UserDetailsData?
    var userMatchesData: MatchedUser?
    var userDetailInfo: UserDetailInfo?
    /// Backend UUID; when set, the profile is loaded from `users/:userId/profile`.
    var remoteUserID: String?
    /// Photo already on the tapping cell, shown on cover/avatar before the network image lands.
    var previewImage: UIImage?
    /// `"like"` | `"super_like"` from You Liked until profile GET confirms `myAction`.
    var seededMyAction: String?

    // MARK: - Header

    @IBOutlet private weak var profileScrollView: UIScrollView!
    @IBOutlet private weak var contentStackView: UIStackView!
    @IBOutlet private weak var headerView: UIView!
    @IBOutlet private weak var coverImageView: UIImageView!
    @IBOutlet private weak var coverTopConstraint: NSLayoutConstraint!
    @IBOutlet private weak var coverHeightConstraint: NSLayoutConstraint!
    @IBOutlet private weak var coverTopShadeView: UIView!
    @IBOutlet private weak var avatarImageView: UIImageView!
    @IBOutlet private weak var onlineDotView: UIView!
    @IBOutlet private weak var backButton: UIButton!
    @IBOutlet private weak var moreButton: UIButton!

    // MARK: - Name, location, about

    @IBOutlet private weak var nameLabel: UILabel!
    @IBOutlet private weak var verifiedImageView: UIImageView!
    @IBOutlet private weak var locationLabel: UILabel!
    @IBOutlet private weak var onlineStatusLabel: UILabel!
    @IBOutlet private weak var aboutLabel: UILabel!

    // MARK: - Voice intro & Quick Moments

    @IBOutlet private weak var voiceIntroSectionView: UIView!
    @IBOutlet private weak var voicePlayButton: UIButton!
    @IBOutlet private weak var voiceWaveformHolder: UIView!
    @IBOutlet private weak var voiceDurationLabel: UILabel!
    @IBOutlet private weak var quickMomentsSectionView: UIView!
    @IBOutlet private weak var quickMomentsView: ProfileQuickMomentsView!

    // MARK: - Sections

    @IBOutlet private weak var photosSectionView: UIView!
    @IBOutlet private weak var photosCountLabel: UILabel!
    @IBOutlet private weak var photosCollectionView: UICollectionView!
    @IBOutlet private weak var interestsSectionView: UIView!
    @IBOutlet private weak var interestsTitleLabel: UILabel!
    @IBOutlet private weak var interestsChipsView: MomentsChipsView!
    @IBOutlet private weak var aboutMeSectionView: UIView!
    @IBOutlet private weak var basicInfoTableView: UITableView!
    @IBOutlet private weak var momentsCollectionView: UICollectionView!
    @IBOutlet private weak var seeAllMomentsButton: UIButton!
    @IBOutlet private weak var momentsCountLabel: UILabel!
    @IBOutlet private weak var noMomentsLabel: UILabel!

    // MARK: - Bottom action bar

    @IBOutlet private weak var actionBarFadeView: UIView!
    @IBOutlet private weak var actionBarStackView: UIStackView!
    @IBOutlet private weak var dislikeButton: UIButton!
    @IBOutlet private weak var superLikeButton: UIButton!
    @IBOutlet private weak var likeButton: UIButton!
    @IBOutlet private weak var chatButton: UIButton!

    private let viewModel = OtherUserProfileViewModel()
    private var cancellables: Set<AnyCancellable> = []
    private var details: OtherUserProfileDetails?
    private var basicInfo: [OtherUserBasicInfo] = []
    private var moments: [MomentsPost] = []
    private var voiceWaveform: VoiceWaveformView?
    private var gridLayoutWidth: CGFloat = 0
    private let refreshIndicator = ProfileRefreshIndicator()
    private var displayedCoverPath: String?
    private var displayedAvatarPath: String?
    private var displayedPhotoPaths: [String] = []
    /// Cover stretch is only for a user pull; attaching the refresh control would otherwise stretch it on first open.
    private var canStretchCover = false

    /// "💞 3 in common" on the trailing side of the Interests title row, styled like a shared-interest chip.
    private lazy var commonInterestsBadge: UIButton = {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColor.Lavenderblush
        config.baseForegroundColor = AppColor.Punch
        config.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10)
        let badge = UIButton(configuration: config)
        badge.isUserInteractionEnabled = false
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        interestsSectionView.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.trailingAnchor.constraint(equalTo: interestsSectionView.trailingAnchor, constant: -20),
            badge.centerYAnchor.constraint(equalTo: interestsTitleLabel.centerYAnchor),
            badge.leadingAnchor.constraint(greaterThanOrEqualTo: interestsTitleLabel.trailingAnchor, constant: 8)
        ])
        return badge
    }()

    private var momentsTotal: Int { max(viewModel.momentsTotal, moments.count) }
    private var showsSeeAllMomentsTile: Bool { momentsTotal > Self.momentsGridLimit }
    private var visibleMomentsCount: Int { min(moments.count, Self.momentsGridLimit) }

    private var isOwnProfile: Bool {
        if isMyProfile { return true }
        if let remoteID = details?.remoteUserID ?? remoteUserID, let myID = UserDataManager.shared.appUser?.id {
            return remoteID == myID
        }
        return details != nil && details?.userID == UserDataManager.shared.userID
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        hidesBottomBarWhenPushed = true
        contentStackView.setCustomSpacing(Self.headerToNameSpacing, after: headerView)
        momentsCollectionView.register(OtherUserSeeAllMomentsCell.self,
                                       forCellWithReuseIdentifier: OtherUserSeeAllMomentsCell.identifier)
        details = makeDetails()
        lockHeaderImageSizes()
        disableCollectionSelfSizing()
        applyPreviewImages()
        configurePullToRefresh()
        setBinding()
        hideLoadingSections()
        showProfile()
        configureActionBar()
        viewModel.loadJSON()
        loadData()
        quickMomentsView.onSelect = { [weak self] index in self?.openQuickMoment(at: index) }
        NotificationCenter.default.addObserver(self, selector: #selector(voicePlayerChanged),
                                               name: VoiceIntroPlayer.stateDidChange, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let userID = details?.userID, VoiceIntroPlayer.shared.playingProfileID == userID {
            VoiceIntroPlayer.shared.stop()
        }
        if isMovingFromParent {
            tabBarController?.tabBar.isHidden = false
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hidesBottomBarWhenPushed = true
        tabBarController?.tabBar.isHidden = true
        checkHideCustomButton(hide: true)
        backButton.isUserInteractionEnabled = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canStretchCover = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = momentsCollectionView.bounds.width
        guard width > 1, width != gridLayoutWidth else { return }
        gridLayoutWidth = width
        UIView.performWithoutAnimation {
            momentsCollectionView.collectionViewLayout.invalidateLayout()
            photosCollectionView.collectionViewLayout.invalidateLayout()
        }
    }

    /// Stops a large photo from expanding the cover/avatar to its pixel size before Auto Layout finishes.
    private func lockHeaderImageSizes() {
        [coverImageView, avatarImageView].forEach { imageView in
            imageView.setContentHuggingPriority(.required, for: .vertical)
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }

    /// iOS self-sizes flow-layout cells from the image, which looks stretched until the next layout pass.
    private func disableCollectionSelfSizing() {
        [photosCollectionView, momentsCollectionView].forEach { collectionView in
            (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.estimatedItemSize = .zero
        }
        photosCollectionView.clipsToBounds = false
    }

    // MARK: - Data

    private func loadData() {
        viewModel.getCheckUserSubscribedAPI()
        if isMyProfile {
            viewModel.loadOwnProfile()
        } else {
            viewModel.getMyInterests()
            if let remoteUserID, !remoteUserID.isEmpty {
                viewModel.loadProfile(userID: remoteUserID)
            } else if let userID = details?.userID {
                viewModel.getMoments(userID: userID)
                viewModel.getQuickMoments(userID: String(userID))
                viewModel.getVoiceIntro(userID: userID)
            }
        }
    }

    /// The profile only bounces at the top, where pulling down reloads it.
    private func configurePullToRefresh() {
        let refreshControl = UIRefreshControl()
        // Only drives the pull gesture; the stretched cover hides its spinner, so `refreshIndicator` shows progress.
        refreshControl.tintColor = .clear
        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        profileScrollView.refreshControl = refreshControl
        profileScrollView.alwaysBounceVertical = true
        profileScrollView.alwaysBounceHorizontal = false
        profileScrollView.delegate = self
        refreshIndicator.install(in: view)
    }

    @objc private func pullToRefresh() {
        refreshIndicator.beginRefreshing()
        if !viewModel.isFetching {
            loadData()
        }
        if !viewModel.isFetching {
            endRefreshing()
        }
    }

    private func endRefreshing() {
        profileScrollView.refreshControl?.endRefreshing()
        refreshIndicator.endRefreshing()
    }

    private func makeDetails() -> OtherUserProfileDetails? {
        var details: OtherUserProfileDetails?
        if isMyProfile, let info = userDetails?.userInfo {
            details = OtherUserProfileDetails(info: info)
        } else if fromExploreMatches == true, let match = userMatchesData {
            details = OtherUserProfileDetails(match: match)
        } else {
            details = userDetailInfo.map(OtherUserProfileDetails.init(info:))
        }
        if details?.myAction == nil {
            details?.myAction = seededMyAction
        }
        return details
    }

    private func refreshBasicInfo() {
        guard let details else { return }
        let next = details.basicInfo(from: viewModel.aAttributesModel?.data ?? [])
        let wasHidden = aboutMeSectionView.isHidden
        let unchanged = next.count == basicInfo.count
            && zip(next, basicInfo).allSatisfy { $0.title == $1.title && $0.value == $1.value }
        if unchanged, wasHidden == next.isEmpty { return }
        basicInfo = next
        aboutMeSectionView.isHidden = next.isEmpty
        basicInfoTableView.reloadData()
    }

    private func setBinding() {
        viewModel.$aAttributesModel.receive(on: DispatchQueue.main).sink { [weak self] model in
            guard model != nil else { return }
            self?.refreshBasicInfo()
        }.store(in: &cancellables)

        viewModel.$profile.receive(on: DispatchQueue.main).sink { [weak self] profile in
            guard let self, let profile, let remoteUserID = self.remoteUserID else { return }
            self.details = OtherUserProfileDetails(profile: profile, remoteUserID: remoteUserID, fallback: self.details)
            self.applyProfile(reloadPhotos: false)
            self.refreshBasicInfo()
            self.configureActionBar()
            self.quickMomentsView.configure(
                moments: self.viewModel.quickMomentFrames,
                avatarPath: self.details?.avatar,
                showsViewedStatus: !self.isOwnProfile
            )
        }.store(in: &cancellables)

        viewModel.$isLoadingProfile.receive(on: DispatchQueue.main).sink { [weak self] isLoading in
            guard let self else { return }
            // Seeded profiles are already readable, so only block the screen when there's nothing to show yet.
            let hasSeed = !(self.details?.name.isEmpty ?? true)
            self.setLoading(isLoading && !hasSeed)
        }.store(in: &cancellables)

        viewModel.$isFetching.receive(on: DispatchQueue.main).sink { [weak self] isFetching in
            guard let self, !isFetching, self.refreshIndicator.isRefreshing else { return }
            self.endRefreshing()
        }.store(in: &cancellables)

        viewModel.$profileError.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self, let error, self.details?.name.isEmpty != false else { return }
            self.aCustomToastView.show(message: error)
        }.store(in: &cancellables)

        viewModel.$moments.receive(on: DispatchQueue.main).sink { [weak self] vibes in
            guard let self, let vibes else { return }
            self.moments = vibes
            self.noMomentsLabel.isHidden = !vibes.isEmpty
            // The grid's own "See all" tile replaces the header button once there are more than 8 moments.
            self.seeAllMomentsButton.isHidden = vibes.isEmpty || self.showsSeeAllMomentsTile
            let total = self.momentsTotal
            self.momentsCountLabel.text = "\(total)"
            self.momentsCountLabel.isHidden = vibes.isEmpty
            self.momentsCountLabel.accessibilityLabel = "\(total) moments"
            self.momentsCollectionView.reloadData()
        }.store(in: &cancellables)

        viewModel.$quickMoments.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            let frames = self.viewModel.quickMomentFrames
            self.quickMomentsView.configure(
                moments: frames,
                avatarPath: self.details?.avatar,
                showsViewedStatus: !self.isOwnProfile
            )
            self.quickMomentsSectionView.isHidden = frames.isEmpty
        }.store(in: &cancellables)

        viewModel.$myInterests.receive(on: DispatchQueue.main).sink { [weak self] interests in
            guard interests != nil else { return }
            self?.showInterests()
        }.store(in: &cancellables)

        viewModel.$voiceIntro.receive(on: DispatchQueue.main).sink { [weak self] intro in
            self?.showVoiceIntro(intro)
        }.store(in: &cancellables)

        viewModel.$aUserActionModel.receive(on: DispatchQueue.main).sink { [weak self] model in
            guard let self, let model else { return }
            if model.status == true {
                self.aCustomToastView.show(message: model.message ?? "")
                let action = self.viewModel.completedDiscoveryAction
                if action == "nope" {
                    self.navigationController?.popViewController(animated: true)
                } else if let action {
                    self.details?.myAction = action
                    self.seededMyAction = action
                    if model.data?.is_match == true {
                        self.details?.isMatched = true
                    }
                    self.configureActionBar()
                }
            } else if UserDataManager.shared.isUserSubscriptionDone == true {
                self.aDeleteCustomPopUp.show(message: model.message ?? "", button1Text: Constants.AlertButtons.ok, button2Text: "", hideButton2: true)
            } else {
                self.showSubscriptionPopUp(subscriptionPopUpType: .superLike)
            }
        }.store(in: &cancellables)

        viewModel.$quotaBlocked.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self, let error else { return }
            self.showQuotaPopup(error)
        }.store(in: &cancellables)

        viewModel.$errorAction.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self, let error else { return }
            self.showNewAlertPopUp(Title: "Error", Msg: error, isSuccess: false) { _ in }
        }.store(in: &cancellables)

    }

    private func applyPreviewImages() {
        if coverImageView.image == nil {
            coverImageView.image = UIImage(named: "addCoverPhoto")
        }
        guard let previewImage else { return }
        if avatarImageView.image == nil { avatarImageView.image = previewImage }
    }

    private func showProfile() {
        applyProfile(reloadPhotos: true)
    }

    /// Updates header text and sections. Images and the photos grid are left alone when they have not changed.
    private func applyProfile(reloadPhotos: Bool) {
        guard let details else { return }
        applyHeaderImages()
        applyHeaderText()
        applyPhotos(forceReload: reloadPhotos)
        showInterests()
    }

    private func applyHeaderImages() {
        guard let details else { return }
        applyCover(path: details.banner)
        if displayedAvatarPath != details.avatar || avatarImageView.image == nil {
            avatarImageView.loadImage(path: details.avatar, placeholder: avatarImageView.image ?? previewImage ?? UIImage(named: "ProfileBlur"))
            displayedAvatarPath = details.avatar
        }
        avatarImageView.accessibilityLabel = "\(details.name)'s profile photo"
    }

    /// Cover waits for a real `coverPhoto`. Never use the profile face as a stand-in — that flashes for ~1s.
    private func applyCover(path: String?) {
        let banner = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let banner, !banner.isEmpty else {
            displayedCoverPath = nil
            if coverImageView.image == nil {
                coverImageView.image = UIImage(named: "addCoverPhoto")
            }
            return
        }
        guard displayedCoverPath != banner else { return }
        displayedCoverPath = banner
        let placeholder = coverImageView.image ?? UIImage(named: "addCoverPhoto")
        coverImageView.loadImage(path: banner, placeholder: placeholder) { [weak self] loaded in
            guard let self, let loaded, self.displayedCoverPath == banner else { return }
            UIView.transition(with: self.coverImageView, duration: 0.28, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.coverImageView.image = loaded
            }
        }
    }

    private func applyHeaderText() {
        guard let details else { return }
        onlineDotView.isHidden = !details.isOnline
        onlineStatusLabel.isHidden = !details.isOnline

        if nameLabel.text != details.nameAndAge {
            nameLabel.text = details.nameAndAge
        }
        verifiedImageView.isHidden = !details.isVerified

        let location = details.location?.trimmingCharacters(in: .whitespaces) ?? ""
        let locationText = location.isEmpty ? nil : "📍 \(location)"
        if locationLabel.text != locationText {
            locationLabel.text = locationText
        }
        locationLabel.isHidden = location.isEmpty

        let about = details.about?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let aboutText = about.isEmpty ? nil : "“\(about)”"
        if aboutLabel.text != aboutText {
            aboutLabel.text = aboutText
        }
        aboutLabel.isHidden = about.isEmpty
    }

    private func applyPhotos(forceReload: Bool) {
        guard let details else { return }
        let paths = details.photos.map { $0.image ?? "" }
        photosCountLabel.text = "\(details.photos.count)"
        photosCountLabel.accessibilityLabel = "\(details.photos.count) photos"

        let shouldShow = !details.photos.isEmpty
        let wasHidden = photosSectionView.isHidden
        guard forceReload || paths != displayedPhotoPaths || wasHidden != !shouldShow else { return }
        displayedPhotoPaths = paths

        if wasHidden, shouldShow {
            photosSectionView.alpha = 0
            photosSectionView.isHidden = false
            photosCollectionView.reloadData()
            UIView.animate(withDuration: 0.2) { self.photosSectionView.alpha = 1 }
        } else {
            photosSectionView.isHidden = !shouldShow
            if shouldShow { photosCollectionView.reloadData() }
        }
    }

    /// Interests shared with the signed-in user come first, in red, with their count beside the title.
    private func showInterests() {
        guard let details else { return }
        let interests: [MomentsInterest]
        if !details.interests.isEmpty {
            interests = details.interests
        } else if isMyProfile {
            interests = EditProfileAPIMapper.momentsInterests(for: details.interestIDs)
        } else {
            interests = MomentsInterestCatalog.interests(for: details.interestIDs)
        }

        let sharedIDs: Set<Int>
        if isOwnProfile {
            sharedIDs = []
        } else {
            let candidates = details.sharedInterests ?? viewModel.myInterests ?? []
            sharedIDs = Set(candidates.map(\.id)).intersection(interests.map(\.id))
        }
        let ordered = interests.filter { sharedIDs.contains($0.id) } + interests.filter { !sharedIDs.contains($0.id) }
        interestsChipsView.configure(ordered, highlighted: sharedIDs)
        interestsSectionView.isHidden = interests.isEmpty

        commonInterestsBadge.isHidden = sharedIDs.isEmpty
        commonInterestsBadge.configuration?.attributedTitle = AttributedString("💞 \(sharedIDs.count) in common", attributes: AttributeContainer([
            .font: MomentsFont.scaled(.medium, 13, style: .footnote)
        ]))
        commonInterestsBadge.accessibilityLabel = sharedIDs.count == 1
            ? "1 interest in common"
            : "\(sharedIDs.count) interests in common"
    }

    /// Sections filled by separate requests stay hidden until their data arrives.
    private func hideLoadingSections() {
        aboutMeSectionView.isHidden = true
        noMomentsLabel.isHidden = true
        seeAllMomentsButton.isHidden = true
        momentsCountLabel.isHidden = true
        voiceIntroSectionView.isHidden = true
        quickMomentsSectionView.isHidden = true
    }

    private func showVoiceIntro(_ intro: MomentsVoiceIntro?) {
        voiceIntroSectionView.isHidden = intro == nil
        guard intro != nil, let details else { return }
        if voiceWaveform == nil {
            let wave = VoiceWaveformView(seed: details.userID, barCount: 26)
            wave.activeColor = AppColor.Punch
            wave.inactiveColor = AppColor.Punch.withAlphaComponent(0.3)
            voiceWaveformHolder.addSubview(wave)
            wave.pinEdges(to: voiceWaveformHolder)
            voiceWaveform = wave
        }
        voicePlayerChanged()
    }

    @objc private func voicePlayerChanged() {
        guard let intro = viewModel.voiceIntro, let details else { return }
        let player = VoiceIntroPlayer.shared
        let isPlaying = player.playingProfileID == details.userID
        let symbol = UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
        voicePlayButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill", withConfiguration: symbol), for: .normal)
        voicePlayButton.accessibilityLabel = isPlaying
            ? "Pause \(details.name)'s voice intro"
            : "Play \(details.name)'s voice intro, \(Int(intro.duration.rounded())) seconds"
        voiceWaveform?.setProgress(isPlaying ? player.progress : 0)
        let remaining = isPlaying ? intro.duration * (1 - player.progress) : intro.duration
        voiceDurationLabel.text = VoiceIntroRecorderViewController.format(remaining.rounded(.up))
    }

    /// Same flag for showing chat and skipping the Premium gate.
    private var isMatchedWithUser: Bool {
        fromExploreMatches == true
            || userMatchesData != nil
            || details?.isMatched == true
    }

    /// Which buttons show depends on where the profile was opened from.
    private func configureActionBar() {
        moreButton.isHidden = isOwnProfile
        actionBarStackView.isHidden = isOwnProfile
        actionBarFadeView.isHidden = isOwnProfile
        guard !isOwnProfile else { return }

        let isMatched = isMatchedWithUser
        let action = details?.myAction?.lowercased()
        let hasSuperLiked = action == "super_like"
        let hasLiked = action == "like" || hasSuperLiked
        dislikeButton.isHidden = false
        likeButton.isHidden = isMatched || hasLiked
        superLikeButton.isHidden = isMatched || !hasLiked || hasSuperLiked
        chatButton.isHidden = !isMatched
    }

    // MARK: - Actions

    @IBAction private func backTapped(_ sender: UIButton) {
        sender.isUserInteractionEnabled = false
        navigationController?.popViewController(animated: true)
    }

    @IBAction private func moreTapped(_ sender: UIButton) {
        showSafetyOptions(from: sender)
    }

    @IBAction private func avatarTapped(_ sender: UITapGestureRecognizer) {
        guard let details, details.avatar?.isEmpty == false else { return }
        let preview: ProfilePhotoPreviewViewController = ProfilePhotoPreviewViewController.instantiateFromStoryboard()
        preview.photoPath = details.avatar
        preview.previewImage = avatarImageView.image
        preview.userName = details.name
        present(preview, animated: true)
    }

    @IBAction private func aboutTapped(_ sender: UITapGestureRecognizer) {
        let isCollapsed = aboutLabel.numberOfLines != 0
        aboutLabel.numberOfLines = isCollapsed ? 0 : Self.aboutCollapsedLines
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    @IBAction private func dislikeTapped(_ sender: UIButton) {
        sendInteraction(Constants.ActionType.dislike)
    }

    @IBAction private func likeTapped(_ sender: UIButton) {
        guard sendInteraction(Constants.ActionType.like) else { return }
        MomentsHaptics.threshold()
        HeartBurst.show(in: view, at: sender.convert(CGPoint(x: sender.bounds.midX, y: sender.bounds.midY), to: view))
    }

    @IBAction private func superLikeTapped(_ sender: UIButton) {
        guard sendInteraction(Constants.ActionType.favorite) else { return }
        MomentsHaptics.superVibe()
    }

    @IBAction private func voicePlayTapped(_ sender: UIButton) {
        guard let intro = viewModel.voiceIntro, let details else { return }
        VoiceIntroPlayer.shared.toggle(intro, profileID: details.userID)
    }

    @IBAction private func seeAllMomentsTapped(_ sender: UIButton) {
        openMoments()
    }

    @IBAction private func chatTapped(_ sender: UIButton) {
        if fromChatScreen == true {
            navigationController?.popViewController(animated: true)
            return
        }
        if FreeTierLimitsStore.shared.canStartChat(isMatched: isMatchedWithUser) {
            openChat()
        } else {
            showSubscriptionPopUp(subscriptionPopUpType: .chat)
        }
    }

    private func openChat() {
        guard let details else { return }
        guard let chatUserID = details.remoteUserID ?? remoteUserID, !chatUserID.isEmpty else {
            aCustomToastView.show(message: "Unable to start chat")
            return
        }
        let avatarURL = details.avatar.flatMap { path -> String? in
            guard !path.isEmpty else { return nil }
            return path.hasPrefix("http") ? path : ApiName.imgBaseURL + path
        }
        ChatProfileRouter.openChat(userID: chatUserID,
                                   name: details.name,
                                   avatarPath: avatarURL,
                                   isVerified: details.isVerified,
                                   from: self)
    }

    @discardableResult
    private func sendInteraction(_ type: String) -> Bool {
        if let blocked = quotaBlock(for: type) {
            showQuotaPopup(blocked)
            return false
        }
        guard let targetUserId = details?.remoteUserID ?? remoteUserID, !targetUserId.isEmpty else {
            aCustomToastView.show(message: "Unable to update this profile")
            return false
        }
        viewModel.clickActionAPI(interaction_type: type, targetUserId: targetUserId)
        return true
    }

    private func quotaBlock(for type: String) -> MomentsActionError? {
        switch type {
        case Constants.ActionType.like:
            return FreeTierLimitsStore.shared.blockReason(for: .interested)
        case Constants.ActionType.favorite:
            return FreeTierLimitsStore.shared.blockReason(for: .superVibe)
        default:
            return nil
        }
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

    /// Same list as Profile's "My Moments", limited to this user's moments.
    private func openMoments(focusing vibeID: String? = nil) {
        guard let details else { return }
        let scope: MomentsListViewController.Scope = isMyProfile
            ? .currentUser
            : .user(id: details.remoteUserID ?? String(details.userID), name: details.name)
        let feed = MomentsListViewController.make(scope: scope, focusVibeID: vibeID)
        navigationController?.pushViewController(feed, animated: true)
    }

    private func openQuickMoment(at index: Int) {
        // Row is newest-first; viewer plays oldest-first (same as Discover).
        let newestFirst = viewModel.quickMoments
        guard let details, newestFirst.indices.contains(index) else { return }
        let stories = Array(newestFirst.reversed())
        let playbackIndex = (newestFirst.count - 1) - index
        let userId = details.remoteUserID ?? String(details.userID)
        var profile = MomentsProfile(id: details.userID,
                                  displayName: details.name,
                                  age: details.age,
                                  isVerified: details.isVerified,
                                  gender: nil,
                                  city: details.location,
                                  distanceKm: nil,
                                  isOnline: details.isOnline,
                                  datingIntent: nil,
                                  photos: [details.avatar].compactMap { $0 },
                                  about: "",
                                  interests: [],
                                  sharedInterests: [],
                                  reasons: [],
                                  voiceIntro: nil,
                                  moments: stories.enumerated().map { $0.element.storyMoment(id: $0.offset) },
                                  vibeScore: nil)
        profile.remoteUserId = userId

        let viewer = QuickMomentViewController(profile: profile, startIndex: playbackIndex, isOwnMoments: isOwnProfile)

        if isOwnProfile {
            viewer.onShowActivity = { shownIndex, presenter in
                guard stories.indices.contains(shownIndex) else { return }
                let activity = QuickMomentActivityViewController(moment: stories[shownIndex])
                activity.modalPresentationStyle = .pageSheet
                if let sheet = activity.sheetPresentationController {
                    sheet.detents = [.medium(), .large()]
                    sheet.prefersGrabberVisible = true
                }
                presenter.present(activity, animated: true)
            }
            viewer.onDelete = { [weak self] shownIndex in
                guard let self, stories.indices.contains(shownIndex) else { return }
                self.viewModel.deleteQuickMoment(id: stories[shownIndex].id) { result in
                    switch result {
                    case .success:
                        self.aCustomToastView.show(message: "Quick moment deleted")
                    case .failure(let error):
                        self.aCustomToastView.show(message: error.message)
                    }
                }
            }
        } else {
            var seen = Set<String>()
            viewer.onMomentShown = { [weak self] shownIndex in
                guard let self, stories.indices.contains(shownIndex), !stories[shownIndex].hasViewed,
                      seen.insert(stories[shownIndex].id).inserted else { return }
                self.viewModel.markQuickMomentViewed(id: stories[shownIndex].id)
            }
            viewer.onReport = { [weak self] _, _ in
                guard let self, let details = self.details else { return }
                MockDiscover.shared.report(userID: details.userID)
                self.aCustomToastView.show(message: "Thanks for letting us know. We'll review this.")
            }
        }
        viewer.onDismiss = { [weak self] in
            guard let self, !self.isOwnProfile else { return }
            self.viewModel.getQuickMoments(userID: userId)
        }
        present(viewer, animated: true)
    }

    private func openPhoto(at index: Int) {
        guard let details, !isOwnProfile else { return }
        let viewer = ShowOtherUserImageVC(details: details, startIndex: index)
        viewer.callBack = { [weak self] _ in
            if UserDataManager.shared.isUserSubscriptionDone != true {
                self?.showSubscriptionPopUp(subscriptionPopUpType: .compliment)
            }
        }
        present(viewer, animated: true)
    }

    // MARK: - Block / Report

    private func showSafetyOptions(from sourceView: UIView) {
        guard let details else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Report \(details.name)", style: .destructive) { [weak self] _ in
            self?.showReportReasons(from: sourceView)
        })
        sheet.addAction(UIAlertAction(title: "Block \(details.name)", style: .destructive) { [weak self] _ in
            self?.confirmBlock()
        })
        sheet.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = sourceView
        present(sheet, animated: true)
    }

    // TODO: send the report to the report-user endpoint once it is integrated.
    private func showReportReasons(from sourceView: UIView) {
        guard let details else { return }
        let sheet = UIAlertController(title: "Report \(details.name)", message: "Why are you reporting this profile?", preferredStyle: .actionSheet)
        MomentsReportReason.allCases.forEach { reason in
            sheet.addAction(UIAlertAction(title: reason.title, style: .default) { [weak self] _ in
                MockDiscover.shared.report(userID: details.userID)
                self?.aCustomToastView.show(message: "Thanks for letting us know. We'll review this profile.")
            })
        }
        sheet.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = sourceView
        present(sheet, animated: true)
    }

    private func confirmBlock() {
        guard let details else { return }
        let alert = UIAlertController(title: "Block \(details.name)?",
                                      message: "They won't be able to see your profile or contact you.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: "Block", style: .destructive) { [weak self] _ in
            guard let self else { return }
            BlockedUsersManager.shared.blockUser(id: String(details.userID))
            self.aCustomToastView.show(message: "\(details.name) has been blocked")
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
}

// MARK: - Scrolling

extension OtherUserProfileViewController {

    /// Pins the bottom edge so the profile never rubber-bands past its content; pulling down at the top
    /// stretches the cover photo up to the screen edge instead of revealing the background.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === profileScrollView else { return }
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
        guard coverTopConstraint.constant != -stretch else { return }
        coverTopConstraint.constant = -stretch
        coverHeightConstraint.constant = Self.coverHeight + stretch
        coverTopShadeView.transform = CGAffineTransform(translationX: 0, y: -stretch)
    }
}

// MARK: - Photos & Moments

extension OtherUserProfileViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView === photosCollectionView { return details?.photos.count ?? 0 }
        return visibleMomentsCount + (showsSeeAllMomentsTile ? 1 : 0)
    }

    private func isSeeAllMomentsTile(_ collectionView: UICollectionView, _ indexPath: IndexPath) -> Bool {
        collectionView === momentsCollectionView && showsSeeAllMomentsTile && indexPath.item == visibleMomentsCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView === photosCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OtherUserPhotoCell.identifier, for: indexPath) as! OtherUserPhotoCell
            let photos = details?.photos ?? []
            cell.configure(photoPath: photos[indexPath.item].image, index: indexPath.item, total: photos.count, name: details?.name ?? "")
            return cell
        }
        if isSeeAllMomentsTile(collectionView, indexPath) {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OtherUserSeeAllMomentsCell.identifier, for: indexPath) as! OtherUserSeeAllMomentsCell
            let next = moments.indices.contains(visibleMomentsCount) ? moments[visibleMomentsCount] : nil
            cell.configure(remainingCount: momentsTotal - visibleMomentsCount, previewVibe: next)
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OtherUserMomentCell.identifier, for: indexPath) as! OtherUserMomentCell
        cell.configure(vibe: moments[indexPath.item], index: indexPath.item, total: momentsTotal)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let flow = collectionViewLayout as? UICollectionViewFlowLayout else { return .zero }
        if collectionView === photosCollectionView {
            return photoCellSize(in: collectionView, flow: flow)
        }
        let availableWidth = collectionView.bounds.width > 1 ? collectionView.bounds.width : view.bounds.width
        let spacing = flow.minimumInteritemSpacing * (Self.momentsPerRow - 1)
        let width = floor((availableWidth - spacing) / Self.momentsPerRow)
        return CGSize(width: width, height: width * 1.35)
    }

    private func photoCellSize(in collectionView: UICollectionView, flow: UICollectionViewFlowLayout) -> CGSize {
        let availableWidth = collectionView.bounds.width > 1 ? collectionView.bounds.width : view.bounds.width
        let availableHeight = collectionView.bounds.height > 1 ? collectionView.bounds.height : 230
        let photoCount = CGFloat(details?.photos.count ?? 0)
        if photoCount > Self.photosPerRow {
            let spacing = flow.minimumLineSpacing * Self.photosPerRow
            let width = floor((availableWidth - flow.sectionInset.left - spacing - Self.photoPeekWidth) / Self.photosPerRow)
            return CGSize(width: max(width, 1), height: availableHeight)
        }
        let insets = flow.sectionInset.left + flow.sectionInset.right
        let spacing = flow.minimumLineSpacing * (Self.photosPerRow - 1)
        let width = floor((availableWidth - insets - spacing) / Self.photosPerRow)
        return CGSize(width: max(width, 1), height: min(availableHeight, floor(max(width, 1) * Self.photoAspectRatio)))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView === photosCollectionView {
            openPhoto(at: indexPath.item)
        } else if isSeeAllMomentsTile(collectionView, indexPath) {
            openMoments()
        } else {
            openMoments(focusing: moments[indexPath.item].id)
        }
    }
}

// MARK: - More about me

extension OtherUserProfileViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        basicInfo.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: OtherUserBasicInfoCell.identifier, for: indexPath) as! OtherUserBasicInfoCell
        cell.configure(info: basicInfo[indexPath.row], isLast: indexPath.row == basicInfo.count - 1)
        return cell
    }
}
