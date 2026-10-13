//
//  ExploreTabPageView.swift
//  FlirttimeNew
//

import UIKit

final class ExploreTabPageView: UIView {

    let tab: ExploreTab
    let collectionView: UICollectionView
    var onRefresh: (() -> Void)?
    var onUpsellTap: (() -> Void)?

    private let contentStack = UIStackView()
    private let upsellView = UIControl()
    private let upsellLabel = UILabel()
    private let emptyStateView = UIStackView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let refreshControl = UIRefreshControl()

    init(tab: ExploreTab) {
        self.tab = tab
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 120, right: 16)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        backgroundColor = .clear

        contentStack.axis = .vertical
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        setUpUpsell()
        contentStack.addArrangedSubview(upsellView)

        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceVertical = true
        collectionView.tag = tab.rawValue
        collectionView.register(UserInteractionCVC.self, forCellWithReuseIdentifier: UserInteractionCVC.identifier)
        refreshControl.tintColor = AppColor.Punch
        refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        collectionView.refreshControl = refreshControl
        contentStack.addArrangedSubview(collectionView)

        setUpEmptyState()

        loadingIndicator.color = AppColor.Punch
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyStateView.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor, constant: -40),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),

            loadingIndicator.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor, constant: -40)
        ])
    }

    private func setUpUpsell() {
        let card = UIView()
        card.backgroundColor = AppColor.Punch.withAlphaComponent(0.08)
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColor.Punch.withAlphaComponent(0.25).cgColor
        card.isUserInteractionEnabled = false
        card.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)))
        icon.tintColor = AppColor.Punch
        icon.setContentHuggingPriority(.required, for: .horizontal)

        upsellLabel.font = .fredoka(.medium, size: 13)
        upsellLabel.textColor = AppColor.MineShaft
        upsellLabel.numberOfLines = 2

        let cta = UILabel()
        cta.text = "Unlock"
        cta.font = .fredoka(.bold, size: 13)
        cta.textColor = .white
        cta.textAlignment = .center
        cta.backgroundColor = AppColor.Punch
        cta.layer.cornerRadius = 14
        cta.clipsToBounds = true
        cta.setContentHuggingPriority(.required, for: .horizontal)
        cta.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [icon, upsellLabel, cta])
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        upsellView.addSubview(card)
        upsellView.addTarget(self, action: #selector(upsellTapped), for: .touchUpInside)
        upsellView.isHidden = true

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: upsellView.topAnchor, constant: 12),
            card.leadingAnchor.constraint(equalTo: upsellView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: upsellView.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: upsellView.bottomAnchor),

            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),

            cta.heightAnchor.constraint(equalToConstant: 28),
            cta.widthAnchor.constraint(equalToConstant: 72)
        ])
    }

    private func setUpEmptyState() {
        let circle = UIView()
        circle.backgroundColor = AppColor.Punch.withAlphaComponent(0.1)
        circle.layer.cornerRadius = 44
        circle.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: tab.iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold)))
        icon.tintColor = AppColor.Punch
        icon.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.text = tab.emptyTitle
        titleLabel.font = .fredoka(.bold, size: 19)
        titleLabel.textColor = AppColor.MineShaft
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let messageLabel = UILabel()
        messageLabel.text = tab.emptyMessage
        messageLabel.font = .fredoka(.regular, size: 14)
        messageLabel.textColor = AppColor.LabelTextColor
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        emptyStateView.axis = .vertical
        emptyStateView.alignment = .center
        emptyStateView.spacing = 8
        emptyStateView.isHidden = true
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addArrangedSubview(circle)
        emptyStateView.setCustomSpacing(18, after: circle)
        emptyStateView.addArrangedSubview(titleLabel)
        emptyStateView.addArrangedSubview(messageLabel)
        addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: 88),
            circle.heightAnchor.constraint(equalToConstant: 88),
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor)
        ])
    }

    @objc private func refreshPulled() {
        onRefresh?()
    }

    @objc private func upsellTapped() {
        onUpsellTap?()
    }

    func setLoading(_ loading: Bool) {
        if loading {
            emptyStateView.isHidden = true
            if !refreshControl.isRefreshing {
                loadingIndicator.startAnimating()
            }
        } else {
            loadingIndicator.stopAnimating()
            refreshControl.endRefreshing()
        }
    }

    func reload(itemCount: Int) {
        setLoading(false)
        collectionView.reloadData()
        emptyStateView.isHidden = itemCount > 0
    }

    func setUpsell(text: String?) {
        upsellLabel.text = text
        upsellView.isHidden = text == nil
    }
}
