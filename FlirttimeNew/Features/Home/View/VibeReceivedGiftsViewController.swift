//
//  VibeReceivedGiftsViewController.swift
//  FlirttimeNew
//
//  Gifts received on the signed-in user's own vibe.
//

import UIKit

final class VibeReceivedGiftsViewController: BaseViewController {

    private let viewModel: VibeGiftViewModel

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Gifts received"
        label.font = UIFont.fredoka(.bold, size: 18)
        label.textColor = AppColor.MineShaft
        label.textAlignment = .center
        return label
    }()

    private let summaryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.fredoka(.regular, size: 14)
        label.textColor = AppColor.DoveGray
        label.textAlignment = .center
        return label
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.dataSource = self
        tableView.register(VibeCommentTableViewCell.self, forCellReuseIdentifier: VibeCommentTableViewCell.identifier)
        return tableView
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = AppColor.Punch
        spinner.hidesWhenStopped = true
        return spinner
    }()

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No gifts yet.\nGifts people send on this vibe will show up here."
        label.font = UIFont.fredoka(.regular, size: 15)
        label.textColor = AppColor.DoveGray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    init(vibe: Vibe) {
        viewModel = VibeGiftViewModel(vibeId: vibe.id)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        setUI()
        loadGifts()
    }

    private func setUI() {
        let separator = UIView()
        separator.backgroundColor = AppColor.Iron

        [titleLabel, summaryLabel, separator, tableView, loadingIndicator, emptyStateLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            summaryLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            separator.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            tableView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 40),

            emptyStateLabel.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 40),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func loadGifts() {
        loadingIndicator.startAnimating()
        viewModel.loadReceivedGifts { [weak self] result in
            guard let self else { return }
            self.loadingIndicator.stopAnimating()
            switch result {
            case .success:
                let count = self.viewModel.receivedGifts.count
                self.summaryLabel.text = "\(count) \(count == 1 ? "gift" : "gifts") · \(self.viewModel.totalReceivedCoins) coins"
                self.emptyStateLabel.isHidden = count > 0
                self.tableView.reloadData()
            case .failure(let error):
                self.emptyStateLabel.text = error.message
                self.emptyStateLabel.isHidden = false
            }
        }
    }
}

extension VibeReceivedGiftsViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.receivedGifts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: VibeCommentTableViewCell.identifier, for: indexPath) as? VibeCommentTableViewCell else {
            return UITableViewCell()
        }
        cell.configure(with: viewModel.receivedGifts[indexPath.row])
        return cell
    }
}
