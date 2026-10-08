//
//  VibeGiftViewController.swift
//  FlirttimeNew
//
//  Gift picker for someone else's vibe: multi-select gifts, check balance, send.
//

import UIKit

final class VibeGiftViewController: BaseViewController {

    static let preferredSheetHeight: CGFloat = 480

    /// Called with the number of gifts sent.
    var onGiftsSent: ((Int) -> Void)?

    private let viewModel: VibeGiftViewModel
    private let receiverName: String

    private let itemsPerRow: CGFloat = 4
    private let itemSpacing: CGFloat = 10
    private let sectionInset: CGFloat = 16

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.bold, size: 18)
        label.textColor = AppColor.MineShaft
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()

    private let balanceLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.medium, size: 14)
        label.textColor = AppColor.DoveGray
        return label
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = itemSpacing
        layout.minimumInteritemSpacing = itemSpacing
        layout.sectionInset = UIEdgeInsets(top: 8, left: sectionInset, bottom: 8, right: sectionInset)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(VibeGiftCollectionViewCell.self, forCellWithReuseIdentifier: VibeGiftCollectionViewCell.identifier)
        return collectionView
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = AppColor.Punch
        spinner.hidesWhenStopped = true
        return spinner
    }()

    private let warningLabel: UILabel = {
        let label = UILabel()
        label.text = "You don't have enough coins for these gifts"
        label.font = UIFont.fredoka(.regular, size: 13)
        label.textColor = AppColor.Punch
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private lazy var sendButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = AppColor.Punch
        configuration.baseForegroundColor = AppColor.AppWhite
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        return button
    }()

    init(vibe: Vibe) {
        viewModel = VibeGiftViewModel(vibeId: vibe.id)
        receiverName = vibe.author?.displayName ?? ""
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        titleLabel.text = receiverName.isEmpty ? "Send a gift" : "Send a gift to \(receiverName)"
        setUI()
        refreshState()
        loadCatalog()
    }

    private func setUI() {
        let coinImageView = UIImageView(image: UIImage(named: "singleCoin"))
        coinImageView.contentMode = .scaleAspectFit

        let balanceStack = UIStackView(arrangedSubviews: [coinImageView, balanceLabel])
        balanceStack.axis = .horizontal
        balanceStack.spacing = 6
        balanceStack.alignment = .center

        [titleLabel, balanceStack, collectionView, loadingIndicator, warningLabel, sendButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            balanceStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            balanceStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            coinImageView.widthAnchor.constraint(equalToConstant: 18),
            coinImageView.heightAnchor.constraint(equalToConstant: 18),

            collectionView.topAnchor.constraint(equalTo: balanceStack.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: warningLabel.topAnchor, constant: -8),

            loadingIndicator.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),

            warningLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            warningLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            warningLabel.bottomAnchor.constraint(equalTo: sendButton.topAnchor, constant: -8),

            sendButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            sendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            sendButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            sendButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func refreshState() {
        balanceLabel.text = "Balance: \(viewModel.coinBalance) coins"

        let count = viewModel.selectedGiftIds.count
        let title: String
        if count == 0 {
            title = "Select a gift"
        } else {
            title = "Send \(count) \(count == 1 ? "gift" : "gifts") · \(viewModel.selectedAmount) coins"
        }
        var attributedTitle = AttributedString(title)
        attributedTitle.font = UIFont.fredoka(.medium, size: 16)
        sendButton.configuration?.attributedTitle = attributedTitle
        sendButton.configuration?.showsActivityIndicator = viewModel.isSending

        warningLabel.isHidden = viewModel.canAffordSelection
        sendButton.isEnabled = count > 0 && viewModel.canAffordSelection && !viewModel.isSending
        sendButton.alpha = sendButton.isEnabled || viewModel.isSending ? 1 : 0.5
        isModalInPresentation = viewModel.isSending
    }

    private func loadCatalog() {
        loadingIndicator.startAnimating()
        viewModel.loadCatalog { [weak self] result in
            guard let self else { return }
            self.loadingIndicator.stopAnimating()
            if case .failure(let error) = result {
                self.aCustomToastView.show(message: error.message)
            }
            self.collectionView.reloadData()
            self.refreshState()
        }
    }

    @objc private func sendTapped() {
        viewModel.sendSelectedGifts { [weak self] result in
            guard let self else { return }
            self.refreshState()
            switch result {
            case .success(let sentCount):
                let onGiftsSent = self.onGiftsSent
                self.dismiss(animated: true) {
                    onGiftsSent?(sentCount)
                }
            case .failure(let error):
                self.aCustomToastView.show(message: error.message)
            }
        }
        refreshState()
    }
}

// MARK: - UICollectionView
extension VibeGiftViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.gifts.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VibeGiftCollectionViewCell.identifier, for: indexPath) as? VibeGiftCollectionViewCell else {
            return UICollectionViewCell()
        }
        let gift = viewModel.gifts[indexPath.item]
        cell.configure(with: gift, isSelected: viewModel.isSelected(gift))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        toggle(at: indexPath)
        return false
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let available = collectionView.bounds.width - sectionInset * 2 - itemSpacing * (itemsPerRow - 1)
        let width = floor(max(available, 0) / itemsPerRow)
        return CGSize(width: width, height: width + 24)
    }

    private func toggle(at indexPath: IndexPath) {
        guard !viewModel.isSending else { return }
        let gift = viewModel.gifts[indexPath.item]
        viewModel.toggleSelection(gift)
        if let cell = collectionView.cellForItem(at: indexPath) as? VibeGiftCollectionViewCell {
            cell.configure(with: gift, isSelected: viewModel.isSelected(gift))
        }
        refreshState()
    }
}
