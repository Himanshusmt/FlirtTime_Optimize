//
//  QuickMomentsPagerViewController.swift
//  FlirttimeNew
//
//  WhatsApp-style tray viewer: swipe (or finish a user's last story) to move
//  from user A's Quick Moments to user B's, then C, and so on.
//

import UIKit

struct QuickMomentViewerPage {
    let item: QuickMomentTrayItem
    let isMine: Bool

    /// Own active stories first (if any), then everyone else in tray order.
    static func sequence(tray: QuickMomentTray?, selected: QuickMomentTrayItem, isMine: Bool) -> (pages: [QuickMomentViewerPage], start: Int) {
        var pages: [QuickMomentViewerPage] = []
        if let me = tray?.me, me.hasActive {
            pages.append(QuickMomentViewerPage(item: me, isMine: true))
        }
        pages += (tray?.users ?? []).filter(\.hasActive).map { QuickMomentViewerPage(item: $0, isMine: false) }

        if let start = pages.firstIndex(where: { matches($0, selected: selected, isMine: isMine) }) {
            return (pages, start)
        }

        let selectedPage = QuickMomentViewerPage(item: selected, isMine: isMine)
        if pages.isEmpty {
            return ([selectedPage], 0)
        }
        if isMine {
            pages.insert(selectedPage, at: 0)
            return (pages, 0)
        }
        pages.append(selectedPage)
        return (pages, pages.count - 1)
    }

    private static func matches(_ page: QuickMomentViewerPage, selected: QuickMomentTrayItem, isMine: Bool) -> Bool {
        if isMine { return page.isMine }
        guard !page.isMine else { return false }
        guard let pageId = page.item.user?.id, let selectedId = selected.user?.id else { return false }
        return pageId == selectedId
    }
}

enum QuickMomentViewerBuilder {
    /// API lists newest first; playback is oldest first.
    static func playbackStories(_ stories: [QuickMoment]) -> [QuickMoment] {
        Array(stories.reversed())
    }

    static func startIndex(in stories: [QuickMoment], isMine: Bool, preferLast: Bool) -> Int {
        if stories.isEmpty { return 0 }
        if preferLast { return stories.count - 1 }
        if isMine { return 0 }
        return stories.firstIndex { !$0.hasViewed } ?? 0
    }

    static func profile(item: QuickMomentTrayItem, stories: [QuickMoment], isMine: Bool) -> MomentsProfile {
        let user = item.user
        let userId = user?.id ?? stories.first?.userId
        var profile = MomentsProfile(
            id: userId?.stableID ?? 0,
            displayName: isMine ? "You" : (user?.name ?? user?.fullName ?? "Someone"),
            age: nil,
            isVerified: user?.isVerified ?? false,
            gender: nil,
            city: user?.location,
            distanceKm: nil,
            isOnline: nil,
            datingIntent: nil,
            photos: [user?.photo].compactMap { $0 },
            about: "",
            interests: [],
            sharedInterests: [],
            reasons: [],
            voiceIntro: nil,
            moments: stories.enumerated().map { $0.element.storyMoment(id: $0.offset) },
            vibeScore: nil
        )
        profile.remoteUserId = userId
        return profile
    }
}

final class QuickMomentsPagerViewController: UIViewController {

    /// Newest-first stories from `quickMoments(of:)`.
    var onLoadStories: ((QuickMomentViewerPage, @escaping ([QuickMoment]) -> Void) -> Void)?
    /// `stories` are already oldest-first so viewer indexes match.
    var onBindViewer: ((QuickMomentViewController, [QuickMoment], QuickMomentViewerPage) -> Void)?
    var onDismiss: (() -> Void)?

    private let pages: [QuickMomentViewerPage]
    private var currentIndex: Int
    private let initialStories: [QuickMoment]

    private let pageController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private var hosts: [Int: PageHost] = [:]

    init(pages: [QuickMomentViewerPage], startIndex: Int, initialStories: [QuickMoment]) {
        self.pages = pages
        self.currentIndex = min(max(0, startIndex), max(0, pages.count - 1))
        self.initialStories = initialStories
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.semanticContentAttribute = .forceLeftToRight

        pageController.dataSource = pages.count > 1 ? self : nil
        pageController.delegate = self
        pageController.view.backgroundColor = .black
        pageController.view.semanticContentAttribute = .forceLeftToRight

        addChild(pageController)
        view.addSubview(pageController.view)
        pageController.view.pinEdges(to: view)
        pageController.didMove(toParent: self)

        let start = host(at: currentIndex, preferredStart: .firstUnseen)
        start.seed(newestFirst: initialStories)
        pageController.setViewControllers([start], direction: .forward, animated: false)
        pageScrollView?.bounces = pages.count > 1
        prefetchNeighbors(of: currentIndex)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed { onDismiss?() }
    }

    func advanceToNextUser() {
        let next = currentIndex + 1
        guard pages.indices.contains(next) else {
            dismiss(animated: true)
            return
        }
        guard canOpenPage(pages[next]) else {
            presentSubscriptionPopUp(.chat)
            return
        }
        showPage(at: next, direction: .forward, preferredStart: .firstUnseen)
    }

    func rewindToPreviousUser() {
        let previous = currentIndex - 1
        guard pages.indices.contains(previous) else { return }
        let host = host(at: previous, preferredStart: .last)
        host.viewer?.jumpToLastMoment()
        show(host, direction: .reverse)
    }

    // MARK: - Pages

    private func host(at index: Int, preferredStart: PageHost.StartPreference) -> PageHost {
        if let existing = hosts[index] {
            if preferredStart == .last {
                existing.preferredStart = .last
            }
            return existing
        }
        let host = PageHost(pageIndex: index, page: pages[index], preferredStart: preferredStart)
        host.onNeedStories = { [weak self] page, completion in
            self?.onLoadStories?(page, completion)
        }
        host.onBindViewer = { [weak self] viewer, stories, page in
            guard let self else { return }
            viewer.canPageToPreviousUser = index > 0
            viewer.canPageToNextUser = index < self.pages.count - 1
            viewer.onAdvanceUser = { [weak self] in self?.advanceToNextUser() }
            viewer.onRewindUser = { [weak self] in self?.rewindToPreviousUser() }
            viewer.onChromeLockChanged = { [weak self] locked in self?.setPagingLocked(locked) }
            self.onBindViewer?(viewer, stories, page)
        }
        host.onBecameEmpty = { [weak self] pageIndex in
            self?.skipEmptyPage(pageIndex)
        }
        hosts[index] = host
        return host
    }

    private func showPage(at index: Int, direction: UIPageViewController.NavigationDirection, preferredStart: PageHost.StartPreference) {
        guard pages.indices.contains(index) else { return }
        show(host(at: index, preferredStart: preferredStart), direction: direction)
    }

    private func show(_ host: PageHost, direction: UIPageViewController.NavigationDirection) {
        currentIndex = host.pageIndex
        if !host.page.isMine {
            FreeTierLimitsStore.shared.consumeQuickMomentView(userId: host.page.item.user?.id)
        }
        view.endEditing(true)
        host.viewer?.prepareForVisiblePlayback()
        pageController.setViewControllers([host], direction: direction, animated: !UIAccessibility.isReduceMotionEnabled)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        prefetchNeighbors(of: host.pageIndex)
    }

    private func canOpenPage(_ page: QuickMomentViewerPage) -> Bool {
        page.isMine || FreeTierLimitsStore.shared.canViewOthersQuickMoments(userId: page.item.user?.id)
    }

    private func prefetchNeighbors(of index: Int) {
        [index - 1, index + 1].forEach { neighbor in
            guard pages.indices.contains(neighbor) else { return }
            self.host(at: neighbor, preferredStart: .firstUnseen).prefetch()
        }
    }

    private func skipEmptyPage(_ index: Int) {
        guard index == currentIndex else { return }
        if index + 1 < pages.count {
            showPage(at: index + 1, direction: .forward, preferredStart: .firstUnseen)
        } else if index > 0 {
            showPage(at: index - 1, direction: .reverse, preferredStart: .last)
        } else {
            dismiss(animated: true)
        }
    }

    private var pageScrollView: UIScrollView? {
        pageController.view.subviews.first { $0 is UIScrollView } as? UIScrollView
    }

    private func setPagingLocked(_ locked: Bool) {
        pageScrollView?.isScrollEnabled = !locked && pages.count > 1
    }
}

extension QuickMomentsPagerViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let host = viewController as? PageHost, host.pageIndex > 0 else { return nil }
        return self.host(at: host.pageIndex - 1, preferredStart: .firstUnseen)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let host = viewController as? PageHost, host.pageIndex + 1 < pages.count else { return nil }
        let next = pages[host.pageIndex + 1]
        guard canOpenPage(next) else { return nil }
        return self.host(at: host.pageIndex + 1, preferredStart: .firstUnseen)
    }

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        (pendingViewControllers.first as? PageHost)?.viewer?.prepareForVisiblePlayback()
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let host = pageViewController.viewControllers?.first as? PageHost else { return }
        currentIndex = host.pageIndex
        host.viewer?.prepareForVisiblePlayback()
        view.endEditing(true)
        prefetchNeighbors(of: host.pageIndex)
    }
}

// MARK: - Per-user host

private final class PageHost: UIViewController {
    enum StartPreference { case firstUnseen, last }

    let pageIndex: Int
    let page: QuickMomentViewerPage
    var preferredStart: StartPreference
    private(set) var viewer: QuickMomentViewController?

    var onNeedStories: ((QuickMomentViewerPage, @escaping ([QuickMoment]) -> Void) -> Void)?
    var onBindViewer: ((QuickMomentViewController, [QuickMoment], QuickMomentViewerPage) -> Void)?
    var onBecameEmpty: ((Int) -> Void)?

    private var newestFirst: [QuickMoment]?
    private var didRequest = false
    private let spinner = UIActivityIndicatorView(style: .large)

    init(pageIndex: Int, page: QuickMomentViewerPage, preferredStart: StartPreference) {
        self.pageIndex = pageIndex
        self.page = page
        self.preferredStart = preferredStart
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        if let newestFirst {
            installViewer(newestFirst: newestFirst)
        } else {
            loadStories()
        }
    }

    func seed(newestFirst stories: [QuickMoment]) {
        newestFirst = stories
        if isViewLoaded, viewer == nil {
            installViewer(newestFirst: stories)
        }
    }

    func prefetch() {
        loadStories()
    }

    private func loadStories() {
        guard !didRequest else { return }
        didRequest = true
        if viewer == nil, isViewLoaded {
            spinner.startAnimating()
        }
        onNeedStories?(page) { [weak self] stories in
            guard let self else { return }
            self.newestFirst = stories
            if self.isViewLoaded {
                self.installViewer(newestFirst: stories)
            }
        }
    }

    private func installViewer(newestFirst: [QuickMoment]) {
        spinner.stopAnimating()
        let stories = QuickMomentViewerBuilder.playbackStories(newestFirst)
        guard !stories.isEmpty else {
            onBecameEmpty?(pageIndex)
            return
        }
        guard viewer == nil else { return }

        let start = QuickMomentViewerBuilder.startIndex(in: stories, isMine: page.isMine, preferLast: preferredStart == .last)
        let viewer = QuickMomentViewController(
            profile: QuickMomentViewerBuilder.profile(item: page.item, stories: stories, isMine: page.isMine),
            startIndex: start,
            isOwnMoments: page.isMine
        )
        onBindViewer?(viewer, stories, page)
        addChild(viewer)
        view.addSubview(viewer.view)
        viewer.view.pinEdges(to: view)
        viewer.didMove(toParent: self)
        self.viewer = viewer
    }
}
