//
//  QuickMomentActivityViewController.swift
//  FlirttimeNew
//
//  One list of views, reactions, and replies from GET .../replies.
//

import UIKit
import RxSwift
import Swinject

final class QuickMomentActivityViewController: UIViewController {

    private struct Row {
        let author: MomentsAuthor?
        let message: String?
        let trailing: String?
        let timeText: String?
        let sortDate: Date
    }

    private static let pageSize = 30

    private let moment: QuickMoment
    private var rows: [Row] = []
    private var page = 0
    private var repliesTotal = 0
    private var loadedReplyCount = 0
    private var hasMoreReplies = true
    private var isLoading = false
    private var didLoad = false
    private var failed = false

    private lazy var sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!
    private let disposeBag = DisposeBag()

    private let titleLabel: UILabel = {
        let label = UILabel.vibeLabel(.bold, 20, style: .headline, color: AppColor.AppBlack)
        label.text = "Activity"
        label.accessibilityTraits = .header
        return label
    }()

    private let emptyLabel = UILabel.vibeLabel(.regular, 15, color: AppColor.DoveGray, lines: 0)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let footerSpinner = UIActivityIndicatorView(style: .medium)

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = AppColor.AppWhite
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 66, bottom: 0, right: 16)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsSelection = false
        tableView.register(ActivityCell.self, forCellReuseIdentifier: ActivityCell.reuseID)
        return tableView
    }()

    init(moment: QuickMoment) {
        self.moment = moment
        super.init(nibName: nil, bundle: nil)
        repliesTotal = moment.repliesCount
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        spinner.hidesWhenStopped = true
        spinner.color = AppColor.Punch
        footerSpinner.hidesWhenStopped = true
        footerSpinner.color = AppColor.Punch
        footerSpinner.frame = CGRect(x: 0, y: 0, width: 44, height: 44)

        [titleLabel, tableView, emptyLabel, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 48),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 48)
        ])
        loadPage(reset: true)
    }

    private func loadPage(reset: Bool) {
        if isLoading { return }
        if !reset, !hasMoreReplies { return }

        let nextPage = reset ? 1 : page + 1
        isLoading = true
        failed = false
        if reset {
            hasMoreReplies = true
            spinner.startAnimating()
            emptyLabel.isHidden = true
        } else {
            updateFooter()
        }

        sessionManager.quickMomentReplies(momentId: moment.id, page: nextPage, limit: Self.pageSize)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] data in
                self?.apply(page: nextPage, data: data)
            }, onFailure: { [weak self] _ in
                self?.applyFailed()
            })
            .disposed(by: disposeBag)
    }

    private func apply(page: Int, data: QuickMomentRepliesPage) {
        isLoading = false
        didLoad = true
        failed = false

        let replyRows = data.replies.map {
            Row(author: $0.author, message: $0.text.nilIfEmpty, trailing: nil,
                timeText: MomentsDate.timeAgo(from: $0.createdAt).nilIfEmpty ?? $0.timeAgo,
                sortDate: MomentsDate.date(from: $0.createdAt) ?? .distantPast)
        }
        if page == 1 {
            let viewRows = data.viewers.map {
                Row(author: $0.author, message: "Viewed your quick moment", trailing: nil,
                    timeText: MomentsDate.timeAgo(from: $0.viewedAt).nilIfEmpty ?? $0.timeAgo,
                    sortDate: MomentsDate.date(from: $0.viewedAt) ?? .distantPast)
            }
            let reactionRows = data.reactions.map {
                Row(author: $0.author, message: nil, trailing: $0.emoji.nilIfEmpty,
                    timeText: MomentsDate.timeAgo(from: $0.createdAt).nilIfEmpty ?? $0.timeAgo,
                    sortDate: MomentsDate.date(from: $0.createdAt) ?? .distantPast)
            }
            rows = viewRows + reactionRows + replyRows
        } else {
            rows += replyRows
        }
        rows.sort { $0.sortDate > $1.sortDate }
        loadedReplyCount = page == 1 ? data.replies.count : loadedReplyCount + data.replies.count
        self.page = page
        repliesTotal = max(data.total, loadedReplyCount)
        hasMoreReplies = !data.replies.isEmpty && loadedReplyCount < repliesTotal

        spinner.stopAnimating()
        tableView.reloadData()
        if rows.isEmpty {
            emptyLabel.text = "No activity yet.\nViews, reactions, and replies will show up here."
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
        updateFooter()
    }

    private func applyFailed() {
        isLoading = false
        didLoad = true
        failed = rows.isEmpty
        spinner.stopAnimating()
        if failed {
            emptyLabel.text = "Couldn't load activity. Please try again."
            emptyLabel.isHidden = false
        }
        updateFooter()
    }

    private func updateFooter() {
        if isLoading, didLoad {
            footerSpinner.startAnimating()
            tableView.tableFooterView = footerSpinner
        } else {
            footerSpinner.stopAnimating()
            tableView.tableFooterView = nil
        }
    }
}

extension QuickMomentActivityViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ActivityCell.reuseID, for: indexPath) as! ActivityCell
        let row = rows[indexPath.row]
        cell.configure(author: row.author, message: row.message, trailing: row.trailing, timeText: row.timeText)
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard rows.count > 0, indexPath.row >= rows.count - 3 else { return }
        loadPage(reset: false)
    }
}

private final class ActivityCell: UITableViewCell {

    static let reuseID = "QuickMomentActivityCell"

    private let avatar = UIImageView()
    private let nameLabel = UILabel.vibeLabel(.medium, 15, style: .subheadline, color: AppColor.AppBlack)
    private let timeLabel = UILabel.vibeLabel(.regular, 12, style: .caption1, color: AppColor.SilverChalice)
    private let messageLabel = UILabel.vibeLabel(.regular, 14, style: .subheadline, color: AppColor.MineShaft, lines: 0)
    private let trailingLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = AppColor.AppWhite
        selectionStyle = .none
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 20
        avatar.backgroundColor = AppColor.AthensGray
        trailingLabel.font = .systemFont(ofSize: 26)
        trailingLabel.setContentHuggingPriority(.required, for: .horizontal)
        trailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let nameRow = UIStackView(arrangedSubviews: [nameLabel, timeLabel])
        nameRow.spacing = 6
        nameRow.alignment = .firstBaseline
        let texts = UIStackView(arrangedSubviews: [nameRow, messageLabel])
        texts.axis = .vertical
        texts.spacing = 2
        let row = UIStackView(arrangedSubviews: [avatar, texts, trailingLabel])
        row.spacing = 12
        row.alignment = .top
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16))
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(author: MomentsAuthor?, message: String?, trailing: String?, timeText: String?) {
        avatar.loadImage(path: author?.profilePicture, placeholder: UIImage(named: "dummy_Profile"))
        let name = author?.displayName ?? "Someone"
        nameLabel.text = name
        timeLabel.text = timeText
        timeLabel.isHidden = (timeText ?? "").isEmpty
        messageLabel.text = message
        messageLabel.isHidden = (message ?? "").isEmpty
        trailingLabel.text = trailing
        trailingLabel.isHidden = trailing == nil
        accessibilityLabel = [name, trailing, message, timeText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
