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
    var strSelectedLike:String?
    var aExploreViewModel = ExploreViewModel()

    private var isSubscribed: Bool {
        UserDataManager.shared.isUserSubscriptionDone == true
    }

    @IBOutlet private weak var notificationButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        notificationButton.bindNotificationBadge(inset: 7)
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
        self.aExploreViewModel.loadCounts()
        NotificationBadgeStore.shared.refresh()
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
                self?.aExploreViewModel.loadCounts()
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
        aExploreViewModel.tabDidUpdate.receive(on: DispatchQueue.main).sink { [weak self] tab in
            self?.reloadPage(tab)
        }.store(in: &desposeBag)

        aExploreViewModel.$counts.receive(on: DispatchQueue.main).sink { [weak self] counts in
            guard let self, let counts else { return }
            self.segmentHeader.setCount(counts.likes, for: .likes)
            self.segmentHeader.setCount(counts.youLiked, for: .youLiked)
            self.segmentHeader.setCount(counts.matches, for: .matches)
            self.segmentHeader.setCount(counts.compliments, for: .compliments)
        }.store(in: &desposeBag)

        NotificationCenter.default.publisher(for: .userSubscriptionStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshUpsell()
                ExploreTab.allCases.forEach { self?.reloadPage($0) }
            }
            .store(in: &desposeBag)
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
        aExploreViewModel.load(tab)
    }

    private func reloadPage(_ tab: ExploreTab) {
        pages[tab.rawValue].reload(itemCount: itemCount(for: tab))
    }

    private func refreshUpsell() {
        pages[ExploreTab.likes.rawValue].setUpsell(text: isSubscribed ? nil : "See everyone who likes you and match instantly")
        pages[ExploreTab.compliments.rawValue].setUpsell(text: isSubscribed ? nil : "Read your compliments and reply right away")
    }

    private func itemCount(for tab: ExploreTab) -> Int {
        aExploreViewModel.cards(for: tab).count
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
        MomentsFiltersViewController.present(from: tabBarController ?? self, filters: .saved) { filters in
            UserDataManager.shared.filterDataModel = filters
        }
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
        let tab = tab(for: collectionView)
        guard let card = aExploreViewModel.cards(for: tab).item(at: indexPath.item) else { return cell }

        let subtitle: String?
        let isLocked: Bool
        switch tab {
        case .likes:
            subtitle = card.city
            isLocked = !isSubscribed
        case .youLiked, .matches:
            subtitle = card.city
            isLocked = false
        case .compliments:
            let message = card.message.map { "\u{201C}\($0)\u{201D}" }
            subtitle = [card.category, message].compactMap { $0 }.joined(separator: " \u{00B7} ")
            isLocked = !isSubscribed
        }
        let showsHeart = tab == .youLiked ? (card.isMatched == true || card.isSuperLike == true) : card.isSuperLike == true
        cell.configure(imagePath: card.photo, name: card.name, age: card.age,
                       distanceText: card.distanceKm?.kmAwayText,
                       subtitle: subtitle,
                       isVerified: card.isVerified == true, isOnline: card.isOnline == true,
                       isSuperLike: showsHeart, isLocked: isLocked)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        let tab = tab(for: collectionView)
        if indexPath.item >= itemCount(for: tab) - 4 {
            aExploreViewModel.loadMore(tab)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let tab = tab(for: collectionView)
        guard let card = aExploreViewModel.cards(for: tab).item(at: indexPath.item) else { return }

        switch tab {
        case .likes where !isSubscribed:
            showSubscriptionPopUp(subscriptionPopUpType: .superLike)
            return
        case .compliments where !isSubscribed:
            showSubscriptionPopUp(subscriptionPopUpType: .chat)
            return
        case .compliments:
            aExploreViewModel.markRead(card, in: tab)
        default:
            break
        }
        openProfile(card)
    }

    private func openProfile(_ card: InteractionCard) {
        let seed = OtherUserProfileRouter.Seed(userID: card.userId,
                                               name: card.name,
                                               avatar: card.photo,
                                               location: card.city,
                                               age: card.age,
                                               isVerified: card.isVerified == true,
                                               isOnline: card.isOnline == true)
        OtherUserProfileRouter.open(seed, from: self)
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
