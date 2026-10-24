//
//  QuickMomentsListViewController.swift
//  FlirttimeNew
//
//  Grid of everyone's Quick Moments (`GET quick-moments/tray`), pushed from Discover's "Quick Moments" pill.
//

import UIKit

final class QuickMomentsListViewController: BaseViewController {

    /// Opens the composer for a new Quick Moment.
    var onAdd: (() -> Void)?
    /// Called with the tapped user's tray entry and whether it's the signed-in user's own.
    var onOpenStories: ((QuickMomentTrayItem, Bool) -> Void)?
    /// Pull-to-refresh; the host reloads the tray and calls `configure` / `endRefreshing`.
    var onRefresh: (() -> Void)?

    private var tray: QuickMomentTray?
    private let momentsView = DiscoverMomentsView()

    private lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        button.tintColor = AppColor.MineShaft
        button.accessibilityLabel = "Back"
        button.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        return button
    }()

    private let titleLabel: UILabel = {
        let label = UILabel.vibeLabel(.bold, 20, style: .headline, color: AppColor.AppBlack)
        label.text = "Quick Moments"
        label.accessibilityTraits = .header
        return label
    }()

    init(tray: QuickMomentTray?) {
        self.tray = tray
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        momentsView.onAdd = { [weak self] in self?.onAdd?() }
        momentsView.onOpenStories = { [weak self] item, isMine in self?.onOpenStories?(item, isMine) }
        momentsView.onRefresh = { [weak self] in self?.onRefresh?() }
        setUI()
        momentsView.configure(tray: tray)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
    }

    func configure(tray: QuickMomentTray?) {
        self.tray = tray
        if isViewLoaded { momentsView.configure(tray: tray) }
    }

    func endRefreshing() {
        momentsView.endRefreshing()
    }

    private func setUI() {
        [backButton, titleLabel, momentsView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),

            momentsView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 8),
            momentsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            momentsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            momentsView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
