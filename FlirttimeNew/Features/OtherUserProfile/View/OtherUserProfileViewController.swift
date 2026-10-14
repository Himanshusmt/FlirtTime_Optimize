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

    // MARK: - Header

    @IBOutlet private weak var contentStackView: UIStackView!
    @IBOutlet private weak var headerView: UIView!
    @IBOutlet private weak var coverImageView: UIImageView!
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
    private var momentsLayoutWidth: CGFloat = 0

    private var isOwnProfile: Bool {
        isMyProfile || (details != nil && details?.userID == UserDataManager.shared.userID)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStackView.setCustomSpacing(Self.headerToNameSpacing, after: headerView)
        details = makeDetails()
        setBinding()
        showProfile()
        configureActionBar()
        viewModel.loadJSON()
        viewModel.getCheckUserSubscribedAPI()
        if isMyProfile {
            viewModel.loadOwnProfile()
        } else if let userID = details?.userID {
            viewModel.getMoments(userID: userID)
            viewModel.getQuickMoments(userID: userID)
            viewModel.getVoiceIntro(userID: userID)
        }
        quickMomentsView.onSelect = { [weak self] index in self?.openQuickMoment(at: index) }
        NotificationCenter.default.addObserver(self, selector: #selector(voicePlayerChanged),
                                               name: VoiceIntroPlayer.stateDidChange, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let userID = details?.userID, VoiceIntroPlayer.shared.playingProfileID == userID {
            VoiceIntroPlayer.shared.stop()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
        backButton.isUserInteractionEnabled = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if momentsCollectionView.bounds.width != momentsLayoutWidth {
            momentsLayoutWidth = momentsCollectionView.bounds.width
            momentsCollectionView.collectionViewLayout.invalidateLayout()
        }
    }

    // MARK: - Data

    private func makeDetails() -> OtherUserProfileDetails? {
        if isMyProfile, let info = userDetails?.userInfo {
            return OtherUserProfileDetails(info: info)
        }
        if fromExploreMatches == true, let match = userMatchesData {
            return OtherUserProfileDetails(match: match)
        }
        return userDetailInfo.map(OtherUserProfileDetails.init(info:))
    }

    private func setBinding() {
        viewModel.$aAttributesModel.receive(on: DispatchQueue.main).sink { [weak self] model in
            guard let self, let model, let details = self.details else { return }
            self.basicInfo = details.basicInfo(from: model.data ?? [])
            self.aboutMeSectionView.isHidden = self.basicInfo.isEmpty
            self.basicInfoTableView.reloadData()
        }.store(in: &cancellables)

        viewModel.$moments.receive(on: DispatchQueue.main).sink { [weak self] vibes in
            guard let self, let vibes else { return }
            self.moments = vibes
            self.noMomentsLabel.isHidden = !vibes.isEmpty
            self.seeAllMomentsButton.isHidden = vibes.isEmpty
            let total = max(self.viewModel.momentsTotal, vibes.count)
            self.momentsCountLabel.text = "\(total)"
            self.momentsCountLabel.isHidden = vibes.isEmpty
            self.momentsCountLabel.accessibilityLabel = "\(total) moments"
            self.momentsCollectionView.reloadData()
        }.store(in: &cancellables)

        viewModel.$quickMoments.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            let frames = self.viewModel.quickMomentFrames
            self.quickMomentsView.configure(moments: frames, avatarPath: self.details?.avatar)
            self.quickMomentsSectionView.isHidden = frames.isEmpty
        }.store(in: &cancellables)

        viewModel.$voiceIntro.receive(on: DispatchQueue.main).sink { [weak self] intro in
            self?.showVoiceIntro(intro)
        }.store(in: &cancellables)

        viewModel.$aUserActionModel.receive(on: DispatchQueue.main).sink { [weak self] model in
            guard let self, let model else { return }
            if model.status == true {
                self.aCustomToastView.show(message: model.message ?? "")
                self.navigationController?.popViewController(animated: true)
            } else if UserDataManager.shared.isUserSubscriptionDone == true {
                self.aDeleteCustomPopUp.show(message: model.message ?? "", button1Text: Constants.AlertButtons.ok, button2Text: "", hideButton2: true)
            } else {
                self.showSubscriptionPopUp(subscriptionPopUpType: .superLike)
            }
        }.store(in: &cancellables)

        viewModel.$errorAction.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self, let error else { return }
            self.showNewAlertPopUp(Title: "Error", Msg: error, isSuccess: false) { _ in }
        }.store(in: &cancellables)

        viewModel.$aCheckUserSubscribe.receive(on: DispatchQueue.main).sink { model in
            guard let model else { return }
            UserDataManager.shared.isUserSubscriptionDone = model.data?.isActive != false
        }.store(in: &cancellables)
    }

    private func showProfile() {
        guard let details else { return }

        let banner = details.banner?.isEmpty == false ? details.banner : details.avatar
        coverImageView.loadImage(path: banner, placeholder: UIImage(named: "addCoverPhoto"))
        avatarImageView.loadImage(path: details.avatar, placeholder: UIImage(named: "ProfileBlur"))
        avatarImageView.accessibilityLabel = "\(details.name)'s profile photo"
        onlineDotView.isHidden = !details.isOnline
        onlineStatusLabel.isHidden = !details.isOnline

        nameLabel.text = details.nameAndAge
        verifiedImageView.isHidden = !details.isVerified

        let location = details.location?.trimmingCharacters(in: .whitespaces) ?? ""
        locationLabel.text = "📍 \(location)"
        locationLabel.isHidden = location.isEmpty

        let about = details.about?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        aboutLabel.text = "“\(about)”"
        aboutLabel.isHidden = about.isEmpty

        photosCountLabel.text = "\(details.photos.count)"
        photosSectionView.isHidden = details.photos.isEmpty
        photosCollectionView.reloadData()

        let interests = isMyProfile
            ? EditProfileAPIMapper.momentsInterests(for: details.interestIDs)
            : MomentsInterestCatalog.interests(for: details.interestIDs)
        interestsChipsView.configure(interests, highlighted: [])
        interestsSectionView.isHidden = interests.isEmpty

        aboutMeSectionView.isHidden = true
        noMomentsLabel.isHidden = true
        seeAllMomentsButton.isHidden = true
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

    /// Which buttons show depends on where the profile was opened from.
    private func configureActionBar() {
        moreButton.isHidden = isOwnProfile
        actionBarStackView.isHidden = isOwnProfile
        actionBarFadeView.isHidden = isOwnProfile
        guard !isOwnProfile else { return }

        let isMatched = fromExploreMatches == true
        let onlySuperLike = fromExploreScreen == true && !isMatched && isShowSuperLikeView
        let onlyChat = isMatched || (fromExploreScreen == true && !isShowSuperLikeView)
        dislikeButton.isHidden = onlyChat || onlySuperLike
        likeButton.isHidden = onlyChat || onlySuperLike
        superLikeButton.isHidden = !onlySuperLike
        chatButton.isHidden = onlySuperLike
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
        MomentsHaptics.threshold()
        HeartBurst.show(in: view, at: sender.convert(CGPoint(x: sender.bounds.midX, y: sender.bounds.midY), to: view))
        sendInteraction(Constants.ActionType.like)
    }

    @IBAction private func superLikeTapped(_ sender: UIButton) {
        MomentsHaptics.superVibe()
        sendInteraction(Constants.ActionType.favorite)
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
        let isMatched = userMatchesData?.matchedUserID != nil
        if UserDataManager.shared.isUserSubscriptionDone == true || isMatched {
            openChat()
        } else {
            showSubscriptionPopUp(subscriptionPopUpType: .chat)
        }
    }

    private func openChat() {
        guard let details else { return }
        let avatarURL = details.avatar.flatMap { path -> String? in
            guard !path.isEmpty else { return nil }
            return path.hasPrefix("http") ? path : ApiName.imgBaseURL + path
        }
        ChatProfileRouter.openChat(userID: details.userID,
                                   name: details.name,
                                   avatarPath: avatarURL,
                                   isVerified: details.isVerified,
                                   from: self)
    }

    private func sendInteraction(_ type: String) {
        guard let userID = details?.userID else { return }
        viewModel.clickActionAPI(interaction_type: type, user_ID: userID)
    }

    /// Same list as Profile's "My Moments", limited to this user's moments.
    private func openMoments(focusing vibeID: String? = nil) {
        guard let details else { return }
        let scope: MomentsListViewController.Scope = isMyProfile
            ? .currentUser
            : .user(id: String(details.userID), name: details.name)
        let feed = MomentsListViewController.make(scope: scope, focusVibeID: vibeID)
        navigationController?.pushViewController(feed, animated: true)
    }

    private func openQuickMoment(at index: Int) {
        let frames = viewModel.quickMomentFrames
        guard let details, frames.indices.contains(index) else { return }
        let profile = MomentsProfile(id: details.userID,
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
                                  moments: frames,
                                  vibeScore: nil)
        present(QuickMomentViewController(profile: profile, startIndex: index, isOwnMoments: isMyProfile), animated: true)
    }

    private func openPhoto(at index: Int) {
        guard let details, !isOwnProfile else { return }
        let viewer: ShowOtherUserImageVC = ShowOtherUserImageVC.instantiateFromStoryboard()
        viewer.isMyProfile = false
        viewer.userID = details.userID
        viewer.imgUsers = details.photos
        viewer.itemIndex = index
        viewer.userName = details.name
        viewer.callBack = { [weak self] _ in
            if UserDataManager.shared.isUserSubscriptionDone != true {
                self?.showSubscriptionPopUp(subscriptionPopUpType: .compliment)
            }
        }
        viewer.modalPresentationStyle = .overCurrentContext
        viewer.modalTransitionStyle = .crossDissolve
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

// MARK: - Photos & Moments

extension OtherUserProfileViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        collectionView === photosCollectionView ? (details?.photos.count ?? 0) : moments.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView === photosCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OtherUserPhotoCell.identifier, for: indexPath) as! OtherUserPhotoCell
            let photos = details?.photos ?? []
            cell.configure(photoPath: photos[indexPath.item].image, index: indexPath.item, total: photos.count, name: details?.name ?? "")
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OtherUserMomentCell.identifier, for: indexPath) as! OtherUserMomentCell
        cell.configure(vibe: moments[indexPath.item], index: indexPath.item, total: moments.count)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let flow = collectionViewLayout as? UICollectionViewFlowLayout else { return .zero }
        guard collectionView === momentsCollectionView else { return flow.itemSize }
        let spacing = flow.minimumInteritemSpacing * (Self.momentsPerRow - 1)
        let width = floor((collectionView.bounds.width - spacing) / Self.momentsPerRow)
        return CGSize(width: width, height: width * 1.35)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView === photosCollectionView {
            openPhoto(at: indexPath.item)
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
