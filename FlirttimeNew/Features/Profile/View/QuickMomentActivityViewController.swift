//
//  QuickMomentActivityViewController.swift
//  FlirttimeNew
//
//  Own Quick Moment sheet: Viewed-by header plus one row per person.
//  Reactors first, then remaining viewers. A reply sits under the name
//  (one line, tap to expand); otherwise the long time sits under the name.
//

import UIKit
import RxSwift
import Swinject

final class QuickMomentActivityViewController: UIViewController {

    var onDelete: (() -> Void)?

    private struct Row {
        let key: String
        let author: MomentsAuthor?
        var message: String?
        var trailing: String?
        var occurredAt: String?
        var fallbackTime: String?
        var sortDate: Date
    }

    private static let pageSize = 30

    private let moment: QuickMoment
    private var rows: [Row] = []
    private var expandedKeys = Set<String>()
    private var page = 0
    private var viewsCount = 0
    private var reactionsCount = 0
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
        label.accessibilityTraits = .header
        return label
    }()

    private lazy var moreButton: UIButton = {
        let button = UIButton(type: .system)
        button.accessibilityLabel = "More options"
        button.addAction(UIAction { [weak self] _ in self?.showDeleteOptions() }, for: .touchUpInside)
        let dots = UIStackView()
        dots.axis = .vertical
        dots.alignment = .center
        dots.spacing = 2.5
        dots.isUserInteractionEnabled = false
        dots.translatesAutoresizingMaskIntoConstraints = false
        for _ in 0..<3 {
            let dot = UIView()
            dot.backgroundColor = AppColor.MineShaft
            dot.layer.cornerRadius = 1.5
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 3),
                dot.heightAnchor.constraint(equalToConstant: 3)
            ])
            dots.addArrangedSubview(dot)
        }
        button.addSubview(dots)
        NSLayoutConstraint.activate([
            dots.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            dots.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        return button
    }()

    private let viewsStatLabel = UILabel.vibeLabel(.regular, 13, style: .footnote, color: AppColor.SilverChalice)
    private let reactionsStatLabel = UILabel.vibeLabel(.regular, 13, style: .footnote, color: AppColor.SilverChalice)
    private let repliesStatLabel = UILabel.vibeLabel(.regular, 13, style: .footnote, color: AppColor.SilverChalice)
    private let headerStack = UIStackView()
    private let headerDivider = UIView()
    private let headerBackground = MomentsGradientView(
        colors: [MomentsTheme.blushGradient[0], AppColor.AppWhite],
        start: CGPoint(x: 0.5, y: 0),
        end: CGPoint(x: 0.5, y: 1)
    )

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
        tableView.allowsSelection = true
        tableView.register(ActivityCell.self, forCellReuseIdentifier: ActivityCell.reuseID)
        return tableView
    }()

    init(moment: QuickMoment) {
        self.moment = moment
        viewsCount = moment.viewsCount
        reactionsCount = moment.reactionsCount
        repliesTotal = moment.repliesCount
        super.init(nibName: nil, bundle: nil)
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

        setUpHeader()
        updateHeader()

        headerDivider.backgroundColor = AppColor.Gallery

        [headerBackground, headerStack, headerDivider, tableView, emptyLabel, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        view.sendSubviewToBack(headerBackground)
        NSLayoutConstraint.activate([
            headerBackground.topAnchor.constraint(equalTo: view.topAnchor),
            headerBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBackground.bottomAnchor.constraint(equalTo: headerDivider.bottomAnchor),

            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            moreButton.widthAnchor.constraint(equalToConstant: ActivityCell.emojiColumnWidth),
            moreButton.heightAnchor.constraint(equalToConstant: 32),

            headerDivider.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            headerDivider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerDivider.heightAnchor.constraint(equalToConstant: 1),

            tableView.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 48),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 48)
        ])
        loadPage(reset: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        moreButton.isHidden = false
    }

    private func setUpHeader() {
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        moreButton.setContentHuggingPriority(.required, for: .horizontal)
        moreButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        let titleRow = UIStackView(arrangedSubviews: [titleLabel, moreButton])
        titleRow.alignment = .center
        titleRow.spacing = 8

        let statsRow = UIStackView(arrangedSubviews: [
            viewsStatLabel, reactionsStatLabel, repliesStatLabel, UIView()
        ])
        statsRow.alignment = .center
        statsRow.spacing = 14

        headerStack.axis = .vertical
        headerStack.spacing = 6
        headerStack.alignment = .fill
        headerStack.addArrangedSubview(titleRow)
        headerStack.addArrangedSubview(statsRow)
    }

    private func updateHeader() {
        titleLabel.text = "Viewed by \(viewsCount.vibeCountText)"
        viewsStatLabel.text = "👁 \(viewsCount.vibeCountText)"
        let reactionIcons = moment.topReactions.prefix(3).joined()
        reactionsStatLabel.text = "\(reactionIcons.isEmpty ? "❤️" : reactionIcons) \(reactionsCount.vibeCountText)"
        repliesStatLabel.text = "💬 \(repliesTotal.vibeCountText)"
        headerStack.accessibilityLabel = "Viewed by \(viewsCount), \(viewsCount) views, \(reactionsCount) reactions, \(repliesTotal) replies"
    }

    private func showDeleteOptions() {
        guard onDelete != nil else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Delete quick moment", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.dismiss(animated: true) { self.onDelete?() }
        })
        sheet.addAction(UIAlertAction(title: Constants.AlertButtons.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = moreButton
        present(sheet, animated: true)
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

        if page == 1 {
            rows = Self.mergedRows(from: data)
            viewsCount = max(data.viewsTotal, moment.viewsCount)
            reactionsCount = max(data.reactionsTotal, moment.reactionsCount)
            updateHeader()
        } else {
            applyLaterReplies(data.replies)
        }
        loadedReplyCount = page == 1 ? data.replies.count : loadedReplyCount + data.replies.count
        self.page = page
        repliesTotal = max(data.total, loadedReplyCount, moment.repliesCount)
        hasMoreReplies = !data.replies.isEmpty && loadedReplyCount < repliesTotal
        updateHeader()

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

    /// Reactors first, then remaining viewers. One row per person; latest reply sits on that row.
    private static func mergedRows(from data: QuickMomentRepliesPage) -> [Row] {
        var engagement: [Row] = []
        var viewers: [Row] = []
        var seen = Set<String>()

        for reaction in data.reactions.sorted(by: Self.newerFirst) {
            let key = personKey(reaction.author)
            guard seen.insert(key).inserted else { continue }
            engagement.append(
                Row(key: key,
                    author: reaction.author,
                    message: nil,
                    trailing: reaction.emoji.nilIfEmpty,
                    occurredAt: reaction.createdAt,
                    fallbackTime: reaction.timeAgo,
                    sortDate: MomentsDate.date(from: reaction.createdAt) ?? .distantPast)
            )
        }

        for viewer in data.viewers.sorted(by: Self.newerFirst) {
            let key = personKey(viewer.author)
            guard seen.insert(key).inserted else { continue }
            viewers.append(
                Row(key: key,
                    author: viewer.author,
                    message: nil,
                    trailing: nil,
                    occurredAt: viewer.viewedAt,
                    fallbackTime: viewer.timeAgo,
                    sortDate: MomentsDate.date(from: viewer.viewedAt) ?? .distantPast)
            )
        }

        for reply in data.replies.sorted(by: Self.newerFirst) {
            let key = personKey(reply.author)
            let text = reply.text.nilIfEmpty
            if let index = engagement.firstIndex(where: { $0.key == key }) {
                attach(reply: text, at: reply.createdAt, fallback: reply.timeAgo, to: &engagement[index])
            } else if let index = viewers.firstIndex(where: { $0.key == key }) {
                attach(reply: text, at: reply.createdAt, fallback: reply.timeAgo, to: &viewers[index])
            } else {
                seen.insert(key)
                engagement.append(
                    Row(key: key,
                        author: reply.author,
                        message: text,
                        trailing: nil,
                        occurredAt: reply.createdAt,
                        fallbackTime: reply.timeAgo,
                        sortDate: MomentsDate.date(from: reply.createdAt) ?? .distantPast)
                )
            }
        }

        return engagement + viewers
    }

    private static func attach(reply: String?, at createdAt: String?, fallback: String?, to row: inout Row) {
        if row.message == nil {
            row.message = reply
            row.occurredAt = createdAt
            row.fallbackTime = fallback
        }
    }

    private func applyLaterReplies(_ replies: [QuickMomentReply]) {
        for reply in replies.sorted(by: Self.newerFirst) {
            let key = Self.personKey(reply.author)
            let text = reply.text.nilIfEmpty
            if let index = rows.firstIndex(where: { $0.key == key }) {
                Self.attach(reply: text, at: reply.createdAt, fallback: reply.timeAgo, to: &rows[index])
                continue
            }
            rows.append(
                Row(key: key,
                    author: reply.author,
                    message: text,
                    trailing: nil,
                    occurredAt: reply.createdAt,
                    fallbackTime: reply.timeAgo,
                    sortDate: MomentsDate.date(from: reply.createdAt) ?? .distantPast)
            )
        }
    }

    private static func personKey(_ author: MomentsAuthor?) -> String {
        if let id = author?.userId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return "id:\(id)"
        }
        let name = (author?.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return name.isEmpty ? "unknown:\(UUID().uuidString)" : "name:\(name)"
    }

    private static func newerFirst(_ lhs: Date?, _ rhs: Date?) -> Bool {
        (lhs ?? .distantPast) > (rhs ?? .distantPast)
    }

    private static func newerFirst(_ lhs: QuickMomentReaction, _ rhs: QuickMomentReaction) -> Bool {
        newerFirst(MomentsDate.date(from: lhs.createdAt), MomentsDate.date(from: rhs.createdAt))
    }

    private static func newerFirst(_ lhs: QuickMomentReply, _ rhs: QuickMomentReply) -> Bool {
        newerFirst(MomentsDate.date(from: lhs.createdAt), MomentsDate.date(from: rhs.createdAt))
    }

    private static func newerFirst(_ lhs: QuickMomentViewer, _ rhs: QuickMomentViewer) -> Bool {
        newerFirst(MomentsDate.date(from: lhs.viewedAt), MomentsDate.date(from: rhs.viewedAt))
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
        cell.configure(
            author: row.author,
            message: row.message,
            trailing: row.trailing,
            occurredAt: row.occurredAt,
            fallbackTime: row.fallbackTime,
            expanded: expandedKeys.contains(row.key)
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard rows.indices.contains(indexPath.row) else { return }
        let row = rows[indexPath.row]
        guard row.message != nil else { return }

        if expandedKeys.contains(row.key) {
            expandedKeys.remove(row.key)
        } else if let cell = tableView.cellForRow(at: indexPath) as? ActivityCell, cell.canExpand {
            expandedKeys.insert(row.key)
        } else {
            return
        }
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard rows.count > 0, indexPath.row >= rows.count - 3 else { return }
        loadPage(reset: false)
    }
}

private final class ActivityCell: UITableViewCell {

    static let reuseID = "QuickMomentActivityCell"
    static let emojiColumnWidth: CGFloat = 24

    private let avatar = UIImageView()
    private let nameLabel = UILabel.vibeLabel(.medium, 15, style: .subheadline, color: AppColor.AppBlack)
    private let emojiLabel = UILabel()
    private let longTimeLabel = UILabel.vibeLabel(.regular, 12, style: .caption1, color: AppColor.SilverChalice)
    private let messageLabel = UILabel.vibeLabel(.regular, 14, style: .subheadline, color: AppColor.MineShaft, lines: 1)
    private let compactTimeLabel = UILabel.vibeLabel(.regular, 11, style: .caption2, color: AppColor.SilverChalice)
    private let messageRow = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = AppColor.AppWhite
        selectionStyle = .none
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 20
        avatar.backgroundColor = AppColor.AthensGray
        emojiLabel.font = .systemFont(ofSize: 20)
        emojiLabel.textAlignment = .center
        emojiLabel.setContentHuggingPriority(.required, for: .horizontal)
        emojiLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        compactTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        compactTimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.setContentHuggingPriority(.required, for: .horizontal)
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        emojiLabel.setContentHuggingPriority(.required, for: .vertical)

        messageRow.axis = .horizontal
        messageRow.spacing = 6
        messageRow.alignment = .firstBaseline
        messageRow.addArrangedSubview(messageLabel)
        messageRow.addArrangedSubview(compactTimeLabel)

        let texts = UIStackView(arrangedSubviews: [nameLabel, longTimeLabel, messageRow])
        texts.axis = .vertical
        texts.spacing = 2
        texts.alignment = .leading
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
        messageRow.widthAnchor.constraint(lessThanOrEqualTo: texts.widthAnchor).isActive = true
        let row = UIStackView(arrangedSubviews: [avatar, texts, emojiLabel])
        row.spacing = 12
        row.alignment = .center
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16))
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),
            emojiLabel.widthAnchor.constraint(equalToConstant: Self.emojiColumnWidth)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var canExpand: Bool {
        guard !messageRow.isHidden, let text = messageLabel.text, !text.isEmpty else { return false }
        if messageLabel.numberOfLines == 0 { return true }
        layoutIfNeeded()
        return isMessageTruncated
    }

    private var isMessageTruncated: Bool {
        guard messageLabel.bounds.width > 0, let text = messageLabel.text, let font = messageLabel.font else { return false }
        let limit = CGSize(width: messageLabel.bounds.width, height: .greatestFiniteMagnitude)
        let fullHeight = (text as NSString).boundingRect(
            with: limit,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
        return ceil(fullHeight) > ceil(messageLabel.bounds.height) + 1
    }

    func configure(
        author: MomentsAuthor?,
        message: String?,
        trailing: String?,
        occurredAt: String?,
        fallbackTime: String?,
        expanded: Bool
    ) {
        avatar.loadImage(path: author?.profilePicture, placeholder: UIImage(named: "dummy_Profile"))
        let name = author?.displayName ?? "Someone"
        nameLabel.text = name
        emojiLabel.text = trailing
        emojiLabel.isHidden = trailing == nil

        let compact = MomentsDate.timeAgo(from: occurredAt).nilIfEmpty ?? fallbackTime?.nilIfEmpty
        let long = MomentsDate.timeAgoLong(from: occurredAt).nilIfEmpty ?? fallbackTime?.nilIfEmpty
        let hasReply = message != nil

        if hasReply {
            longTimeLabel.isHidden = true
            longTimeLabel.text = nil
            messageRow.isHidden = false
            messageLabel.text = message
            messageLabel.numberOfLines = expanded ? 0 : 1
            compactTimeLabel.text = compact
            compactTimeLabel.isHidden = (compact ?? "").isEmpty
        } else {
            messageRow.isHidden = true
            messageLabel.text = nil
            compactTimeLabel.text = nil
            longTimeLabel.text = long
            longTimeLabel.isHidden = (long ?? "").isEmpty
        }

        accessibilityLabel = [name, trailing, hasReply ? message : long, hasReply ? compact : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        accessibilityHint = hasReply ? "Double tap to show or hide the full reply" : nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
