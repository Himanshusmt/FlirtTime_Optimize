//
//  QuickMomentsListViewController.swift
//  FlirttimeNew
//
//  Grid of everyone's Quick Moments, pushed from Discover's "Quick Moments" pill.
//

import UIKit

final class QuickMomentsListViewController: BaseViewController {

    var onOpenMoment: ((MomentsProfile, Int) -> Void)?

    private struct Item {
        let profile: MomentsProfile
        let index: Int
        var moment: MomentsStory { profile.moments[index] }
    }

    private var items: [Item] = []
    private let emptyLabel = UILabel.vibeLabel(.regular, 15, color: AppColor.DoveGray, lines: 0)

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

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 4, left: 16, bottom: 24, right: 16)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsVerticalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        view.register(QuickMomentCell.self, forCellWithReuseIdentifier: QuickMomentCell.reuseID)
        return view
    }()

    init(profiles: [MomentsProfile]) {
        super.init(nibName: nil, bundle: nil)
        setItems(from: profiles)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        setUI()
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
    }

    func configure(with profiles: [MomentsProfile]) {
        setItems(from: profiles)
        if isViewLoaded { reload() }
    }

    private func setItems(from profiles: [MomentsProfile]) {
        items = profiles.flatMap { profile in profile.moments.indices.map { Item(profile: profile, index: $0) } }
            .sorted { ($0.moment.postedAt ?? .distantPast) > ($1.moment.postedAt ?? .distantPast) }
    }

    private func reload() {
        emptyLabel.isHidden = !items.isEmpty
        collectionView.reloadData()
    }

    private func setUI() {
        emptyLabel.text = "No Moments to show right now."
        emptyLabel.textAlignment = .center
        [backButton, titleLabel, collectionView, emptyLabel].forEach {
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

            collectionView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 8),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }
}

extension QuickMomentsListViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: QuickMomentCell.reuseID, for: indexPath) as! QuickMomentCell
        let item = items[indexPath.item]
        cell.configure(profile: item.profile, moment: item.moment)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = floor((collectionView.bounds.width - 16 * 2 - 12) / 2)
        return CGSize(width: width, height: width * 1.4)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = items[indexPath.item]
        onOpenMoment?(item.profile, item.index)
    }
}

private final class QuickMomentCell: UICollectionViewCell {

    static let reuseID = "QuickMomentCell"

    private let imageView = UIImageView()
    private let avatar = UIImageView()
    private let nameLabel = UILabel.vibeLabel(.bold, 14, style: .subheadline, color: .white)
    private let timeLabel = UILabel.vibeLabel(.regular, 11, style: .caption2, color: UIColor.white.withAlphaComponent(0.85))

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 20
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.backgroundColor = AppColor.AthensGray
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        imageView.pinEdges(to: contentView)
        let shade = MomentsGradientView(colors: [.clear, UIColor.black.withAlphaComponent(0.7)],
                                        start: CGPoint(x: 0.5, y: 0.55), end: CGPoint(x: 0.5, y: 1))
        contentView.addSubview(shade)
        shade.pinEdges(to: contentView)

        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 14
        avatar.layer.borderWidth = 2
        avatar.layer.borderColor = AppColor.Punch.cgColor
        let texts = UIStackView(arrangedSubviews: [nameLabel, timeLabel])
        texts.axis = .vertical
        let row = UIStackView(arrangedSubviews: [avatar, texts])
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 28),
            avatar.heightAnchor.constraint(equalToConstant: 28),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -10),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(profile: MomentsProfile, moment: MomentsStory) {
        imageView.loadImage(path: moment.imagePath, placeholder: UIImage(named: "ProfileBlur"))
        avatar.loadImage(path: profile.photos.first, placeholder: UIImage(named: "ProfileBlur"))
        nameLabel.text = profile.displayName
        timeLabel.text = moment.postedAgoText
        accessibilityLabel = "\(profile.displayName)'s moment" + (moment.postedAgoText.map { ", \($0)" } ?? "")
    }

    override var isHighlighted: Bool {
        didSet { UIView.animate(withDuration: 0.15) { self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity } }
    }
}
