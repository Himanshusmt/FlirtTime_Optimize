//
//  ExploreViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 21/05/24.
//

import UIKit
import Combine

class ExploreViewController: BaseViewController {

    @IBOutlet weak var vwTopBar: UIView!

    private let segmentHeader = ExploreSegmentHeaderView()
    private let pagerScrollView = UIScrollView()
    private var pages: [ExploreTabPageView] = []
    private var selectedTab: ExploreTab = .likes
    private var lastPagerWidth: CGFloat = 0
    private let selectionFeedback = UISelectionFeedbackGenerator()

    private var desposeBag:Set<AnyCancellable> = []
    var aUserInteraction:InteractionResponse?
    var aMyLikeResp:MyLikeInteractionResponse?
    var aMyMatches:MatchResponse?
    var aComplimentListResponse: ComplimentListResponse?
    var aReadComplimentResponse: ReadComplimentResponse?
    var strSelectedLike:String?
    var aExploreViewModel = ExploreViewModel()

    private static let dobFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private var isSubscribed: Bool {
        UserDataManager.shared.isUserSubscriptionDone == true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setUpSegmentHeader()
        self.setUpPager()
        self.setUpBinding()
        if strSelectedLike == nil {
            strSelectedLike = Constants.UserInteractionTypes.likeYou
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.checkHideCustomButton(hide: false)
        self.scrollToTab(ExploreTab(interactionType: strSelectedLike) ?? .likes, animated: false)
        self.refreshUpsell()
        self.aExploreViewModel.getStatucCountApi()
        ExploreTab.allCases.forEach(loadTab)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        AppTabBarController.buttonD.isHidden = false
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        AppTabBarController.buttonD.isHidden = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = pagerScrollView.bounds.width
        guard width > 0, width != lastPagerWidth else { return }
        lastPagerWidth = width
        pagerScrollView.contentOffset = CGPoint(x: CGFloat(selectedTab.rawValue) * width, y: 0)
        segmentHeader.setProgress(CGFloat(selectedTab.rawValue))
    }

    // MARK: - Setup

    private func setUpSegmentHeader() {
        segmentHeader.translatesAutoresizingMaskIntoConstraints = false
        segmentHeader.onSelect = { [weak self] tab in
            self?.scrollToTab(tab, animated: true)
        }
        view.addSubview(segmentHeader)

        NSLayoutConstraint.activate([
            segmentHeader.topAnchor.constraint(equalTo: vwTopBar.bottomAnchor, constant: 4),
            segmentHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            segmentHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            segmentHeader.heightAnchor.constraint(equalToConstant: 64)
        ])
    }

    private func setUpPager() {
        pagerScrollView.isPagingEnabled = true
        pagerScrollView.showsHorizontalScrollIndicator = false
        pagerScrollView.showsVerticalScrollIndicator = false
        pagerScrollView.alwaysBounceVertical = false
        pagerScrollView.bounces = false
        pagerScrollView.contentInsetAdjustmentBehavior = .never
        pagerScrollView.delegate = self
        pagerScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pagerScrollView)

        let pagesStack = UIStackView()
        pagesStack.axis = .horizontal
        pagesStack.distribution = .fillEqually
        pagesStack.translatesAutoresizingMaskIntoConstraints = false
        pagerScrollView.addSubview(pagesStack)

        NSLayoutConstraint.activate([
            pagerScrollView.topAnchor.constraint(equalTo: segmentHeader.bottomAnchor),
            pagerScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagerScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagerScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            pagesStack.topAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.topAnchor),
            pagesStack.leadingAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.leadingAnchor),
            pagesStack.trailingAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.trailingAnchor),
            pagesStack.bottomAnchor.constraint(equalTo: pagerScrollView.contentLayoutGuide.bottomAnchor),
            pagesStack.heightAnchor.constraint(equalTo: pagerScrollView.frameLayoutGuide.heightAnchor)
        ])

        for tab in ExploreTab.allCases {
            let page = ExploreTabPageView(tab: tab)
            page.collectionView.delegate = self
            page.collectionView.dataSource = self
            page.onRefresh = { [weak self] in
                self?.aExploreViewModel.getStatucCountApi()
                self?.loadTab(tab)
            }
            page.onUpsellTap = { [weak self] in
                self?.openPremium(source: tab == .compliments ? .compliment : .superLike)
            }
            pagesStack.addArrangedSubview(page)
            page.widthAnchor.constraint(equalTo: pagerScrollView.frameLayoutGuide.widthAnchor).isActive = true
            pages.append(page)
        }
    }

    func setUpBinding(){
        self.aExploreViewModel.$aUserInteraction.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] model in
            guard let self, let model else { return }
            self.aUserInteraction = model.status ? model : nil
            self.reloadPage(.likes)
        }).store(in: &desposeBag)

        self.aExploreViewModel.$errorMessage.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] error in
            guard let self, error != nil else { return }
            self.aUserInteraction = nil
            self.reloadPage(.likes)
        }).store(in: &desposeBag)

        self.aExploreViewModel.$aMyLikeResponse.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] model in
            guard let self, let model else { return }
            self.aMyLikeResp = model
            self.reloadPage(.youLiked)
        }).store(in: &desposeBag)

        self.aExploreViewModel.$errorMyLikeMessage.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] error in
            guard let self, error != nil else { return }
            self.aMyLikeResp = nil
            self.reloadPage(.youLiked)
        }).store(in: &desposeBag)

        self.aExploreViewModel.$aMyMatches.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] model in
            guard let self, let model else { return }
            self.aMyMatches = model
            self.reloadPage(.matches)
        }).store(in: &desposeBag)

        self.aExploreViewModel.$errorMyMatches.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] error in
            guard let self, error != nil else { return }
            self.aMyMatches = nil
            self.reloadPage(.matches)
        }).store(in: &desposeBag)

        self.aExploreViewModel.$aComplimentListResponse.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] model in
            guard let self, let model else { return }
            self.aComplimentListResponse = model
            self.reloadPage(.compliments)
        }).store(in: &desposeBag)

        self.aExploreViewModel.$errorCompliment.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] error in
            guard let self, error != nil else { return }
            self.aComplimentListResponse = nil
            self.reloadPage(.compliments)
        }).store(in: &desposeBag)

        self.aExploreViewModel.$getStatusCount.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] model in
            guard let self, let data = model?.data else { return }
            self.segmentHeader.setCount(data.like_count ?? 0, for: .likes)
            self.segmentHeader.setCount((data.like_you_count ?? 0) + (data.favorite_count ?? 0), for: .youLiked)
            self.segmentHeader.setCount(data.match_count ?? 0, for: .matches)
            self.segmentHeader.setCount(data.compliment_count ?? 0, for: .compliments)
        }).store(in: &desposeBag)

        self.aExploreViewModel.$aReadComplimentResponse.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] model in
            guard let self, let model else { return }
            self.aReadComplimentResponse = model
            if model.data != nil {
                self.showComingSoon("Chat")
            }
        }).store(in: &desposeBag)

        self.aExploreViewModel.$errorReadCompliment.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] error in
            guard let self, error != nil else { return }
            self.showNewAlertPopUp(Title: "Error", Msg: "Compliment data not found", isSuccess: false, CompletionHandler: {(success) -> Void in

            })
        }).store(in: &desposeBag)
    }

    // MARK: - Tabs

    private func scrollToTab(_ tab: ExploreTab, animated: Bool) {
        let width = pagerScrollView.bounds.width
        let targetOffset = CGPoint(x: CGFloat(tab.rawValue) * width, y: 0)

        if animated, width > 0, pagerScrollView.contentOffset != targetOffset {
            pagerScrollView.setContentOffset(targetOffset, animated: true)
            return
        }

        if width > 0 {
            pagerScrollView.contentOffset = targetOffset
        }
        segmentHeader.select(tab, animated: false)
        didSelectTab(tab, withFeedback: false)
    }

    private func pagerDidSettle() {
        let width = pagerScrollView.bounds.width
        guard width > 0 else { return }
        let index = Int((pagerScrollView.contentOffset.x / width).rounded())
        guard let tab = ExploreTab(rawValue: index) else { return }
        didSelectTab(tab, withFeedback: true)
    }

    private func didSelectTab(_ tab: ExploreTab, withFeedback: Bool) {
        strSelectedLike = tab.interactionType
        guard tab != selectedTab else { return }
        selectedTab = tab
        if withFeedback {
            selectionFeedback.selectionChanged()
        }
        hideShowTabBar(isHide: false)
    }

    private func loadTab(_ tab: ExploreTab) {
        pages[tab.rawValue].setLoading(itemCount(for: tab) == 0)
        switch tab {
        case .likes:
            aExploreViewModel.getUserIneractionAPI(interactioType: tab.interactionType)
        case .youLiked:
            aExploreViewModel.getUserIneractionMyLikeAPI(interactioType: tab.interactionType)
        case .matches:
            aExploreViewModel.getUserMatchesAPI()
        case .compliments:
            aExploreViewModel.getComplimentListApi()
        }
    }

    private func reloadPage(_ tab: ExploreTab) {
        let count = itemCount(for: tab)
        pages[tab.rawValue].reload(itemCount: count)
        segmentHeader.setCount(count, for: tab)
    }

    private func refreshUpsell() {
        pages[ExploreTab.likes.rawValue].setUpsell(text: isSubscribed ? nil : "See everyone who likes you and match instantly")
        pages[ExploreTab.compliments.rawValue].setUpsell(text: isSubscribed ? nil : "Read your compliments and reply right away")
    }

    private func itemCount(for tab: ExploreTab) -> Int {
        switch tab {
        case .likes: return aUserInteraction?.data?.count ?? 0
        case .youLiked: return aMyLikeResp?.data.count ?? 0
        case .matches: return aMyMatches?.data.count ?? 0
        case .compliments: return aComplimentListResponse?.data?.compliments?.count ?? 0
        }
    }

    // MARK: - Actions

    @IBAction func notificationButtonTapped(_ sender: UIButton) {
        let aNotificationViewController:NotificationViewController = NotificationViewController.instantiateFromStoryboard()
        self.navigationController?.pushViewController(aNotificationViewController, animated: true)
    }

    @IBAction func searchButtonTapped(_ sender: UIButton) {
        let searchPeopleViewController: SearchPeopleViewController = SearchPeopleViewController.instantiateFromStoryboard()
        self.navigationController?.pushViewController(searchPeopleViewController, animated: true)
    }

    @IBAction func applyFilterButtonTapped(_ sender: UIButton) {
        VibeFiltersViewController.present(from: tabBarController ?? self, filters: .saved) { filters in
            UserDataManager.shared.filterDataModel = filters
        }
    }

    func calculateAge(from dateString: String) -> Int? {
        guard let birthDate = Self.dobFormatter.date(from: dateString) else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    private func age(from dob: String?) -> Int? {
        guard let dob, !dob.isEmpty else { return nil }
        return calculateAge(from: dob)
    }
}

extension ExploreViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    private func tab(for collectionView: UICollectionView) -> ExploreTab {
        ExploreTab(rawValue: collectionView.tag) ?? .likes
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        itemCount(for: tab(for: collectionView))
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UserInteractionCVC.identifier, for: indexPath) as? UserInteractionCVC else {
            return UICollectionViewCell()
        }

        switch tab(for: collectionView) {
        case .likes:
            let interaction = aUserInteraction?.data?[indexPath.item]
            let info = interaction?.userInfo
            cell.configure(imagePath: info?.avatar, name: info?.displayName, age: age(from: info?.dob), subtitle: info?.location,
                           isVerified: info?.isActive == true, isOnline: info?.isOnline == true,
                           isSuperLike: interaction?.interactionType == 2, isLocked: !isSubscribed)
        case .youLiked:
            let interaction = aMyLikeResp?.data[indexPath.item]
            let info = interaction?.userInfo
            cell.configure(imagePath: info?.avatar, name: info?.displayName, age: age(from: info?.dob), subtitle: info?.location,
                           isVerified: info?.isActive == true, isOnline: info?.isOnline == true,
                           isSuperLike: interaction?.interactionType == 2, isLocked: false)
        case .matches:
            let match = aMyMatches?.data[indexPath.item]
            cell.configure(imagePath: match?.avatar, name: match?.displayName, age: age(from: match?.dob), subtitle: match?.location,
                           isVerified: match?.isActive == true, isOnline: match?.isOnline == true,
                           isSuperLike: false, isLocked: false)
        case .compliments:
            let compliment = aComplimentListResponse?.data?.compliments?[indexPath.item]
            let sender = compliment?.sender
            let message = compliment.map { "\u{201C}\($0.content)\u{201D}" }
            cell.configure(imagePath: sender?.avatar, name: sender?.displayName, age: age(from: sender?.dob), subtitle: message,
                           isVerified: sender?.isActive == true, isOnline: sender?.isOnline == true,
                           isSuperLike: false, isLocked: !isSubscribed)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let aOtherUserProfileViewController:OtherUserProfileViewController = OtherUserProfileViewController.instantiateFromStoryboard()
        aOtherUserProfileViewController.fromExploreScreen = true

        switch tab(for: collectionView) {
        case .likes:
            guard isSubscribed else {
                self.showSubscriptionPopUp(subscriptionPopUpType: .superLike)
                return
            }
            aOtherUserProfileViewController.userDetailInfo = self.aUserInteraction?.data?[indexPath.item].userInfo
            self.navigationController?.pushViewController(aOtherUserProfileViewController, animated: true)
        case .youLiked:
            aOtherUserProfileViewController.userDetailInfo = self.aMyLikeResp?.data[indexPath.item].userInfo
            aOtherUserProfileViewController.isShowSuperLikeView = self.aMyLikeResp?.data[indexPath.item].interactionType == 1 ? true : false
            aOtherUserProfileViewController.fromExploreYouLike = true
            self.navigationController?.pushViewController(aOtherUserProfileViewController, animated: true)
        case .matches:
            aOtherUserProfileViewController.fromExploreMatches = true
            aOtherUserProfileViewController.userMatchesData = self.aMyMatches?.data[indexPath.item]
            self.navigationController?.pushViewController(aOtherUserProfileViewController, animated: true)
        case .compliments:
            guard isSubscribed else {
                self.showSubscriptionPopUp(subscriptionPopUpType: .chat)
                return
            }
            self.aExploreViewModel.readComplimentApi(id: self.aComplimentListResponse?.data?.compliments?[indexPath.item].id ?? 0)
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else { return .zero }
        let itemsPerRow: CGFloat = 2
        let paddingSpace = flowLayout.sectionInset.left + flowLayout.sectionInset.right + flowLayout.minimumInteritemSpacing * (itemsPerRow - 1)
        let widthPerItem = floor((collectionView.bounds.width - paddingSpace) / itemsPerRow)
        return CGSize(width: widthPerItem, height: (widthPerItem * 1.38).rounded())
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === pagerScrollView {
            let width = scrollView.bounds.width
            guard width > 0 else { return }
            segmentHeader.setProgress(scrollView.contentOffset.x / width)
            return
        }

        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        guard scrollView.contentSize.height > scrollView.frame.height else {
            hideShowTabBar(isHide: false) // No scrolling possible — show tab bar
            return
        }
        let translation = scrollView.panGestureRecognizer.translation(in: scrollView).y
        hideShowTabBar(isHide: translation < 0)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView === pagerScrollView {
            pagerDidSettle()
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if scrollView === pagerScrollView {
            pagerDidSettle()
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView === pagerScrollView, !decelerate {
            pagerDidSettle()
        }
    }
}
