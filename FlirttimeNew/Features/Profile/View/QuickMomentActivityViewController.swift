//
//  QuickMomentActivityViewController.swift
//  FlirttimeNew
//
//  Who reacted to and replied on one of the signed-in user's Quick Moments.
//

import UIKit

final class QuickMomentActivityViewController: UIViewController {

    private enum Section: Int, CaseIterable {
        case replies, reactions

        var title: String {
            switch self {
            case .replies: return "Replies"
            case .reactions: return "Reactions"
            }
        }
    }

    private struct Row {
        let author: MomentsAuthor?
        let detail: String
        let trailing: String?
        let createdAt: String?
    }

    private let moment: QuickMoment
    private var rows: [Section: [Row]] = [:]
    private var sections: [Section] { Section.allCases.filter { !(rows[$0] ?? []).isEmpty } }

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = AppColor.AppWhite
        tableView.dataSource = self
        tableView.allowsSelection = false
        tableView.register(ActivityCell.self, forCellReuseIdentifier: ActivityCell.reuseID)
        return tableView
    }()

    init(moment: QuickMoment) {
        self.moment = moment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite

        rows[.replies] = (moment.replies ?? [])
            .sorted { (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast) }
            .map { Row(author: $0.author, detail: $0.body, trailing: nil, createdAt: $0.createdAt) }
        rows[.reactions] = (moment.reactions ?? [])
            .sorted { (MomentsDate.date(from: $0.createdAt) ?? .distantPast) > (MomentsDate.date(from: $1.createdAt) ?? .distantPast) }
            .map { Row(author: $0.author, detail: "Reacted to your quick moment", trailing: $0.emoji, createdAt: $0.createdAt) }

        let title = UILabel.vibeLabel(.bold, 20, style: .headline, color: AppColor.AppBlack)
        title.text = "Activity"
        title.accessibilityTraits = .header
        let summary = UILabel.vibeLabel(.regular, 14, style: .subheadline, color: AppColor.DoveGray)
        let reactions = moment.reactions?.count ?? 0
        let replies = moment.replies?.count ?? 0
        summary.text = "\(reactions) \(reactions == 1 ? "reaction" : "reactions") · \(replies) \(replies == 1 ? "reply" : "replies")"
        let header = UIStackView(arrangedSubviews: [title, summary])
        header.axis = .vertical
        header.spacing = 2

        let emptyLabel = UILabel.vibeLabel(.regular, 15, color: AppColor.DoveGray, lines: 0)
        emptyLabel.text = "No reactions or replies yet.\nWhen someone reacts or replies, you'll see it here."
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = !sections.isEmpty

        [header, tableView, emptyLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 48),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }
}

extension QuickMomentActivityViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows[sections[section]]?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ActivityCell.reuseID, for: indexPath) as! ActivityCell
        if let row = rows[sections[indexPath.section]]?[indexPath.row] {
            cell.configure(author: row.author, detail: row.detail, trailing: row.trailing, createdAt: row.createdAt)
        }
        return cell
    }
}

private final class ActivityCell: UITableViewCell {

    static let reuseID = "QuickMomentActivityCell"

    private let avatar = UIImageView()
    private let nameLabel = UILabel.vibeLabel(.medium, 15, style: .subheadline, color: AppColor.AppBlack)
    private let timeLabel = UILabel.vibeLabel(.regular, 12, style: .caption1, color: AppColor.SilverChalice)
    private let detailLabel = UILabel.vibeLabel(.regular, 14, style: .subheadline, color: AppColor.MineShaft, lines: 0)
    private let trailingLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
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
        let texts = UIStackView(arrangedSubviews: [nameRow, detailLabel])
        texts.axis = .vertical
        texts.spacing = 2
        let row = UIStackView(arrangedSubviews: [avatar, texts, trailingLabel])
        row.spacing = 12
        row.alignment = .center
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14))
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(author: MomentsAuthor?, detail: String, trailing: String?, createdAt: String?) {
        avatar.loadImage(path: author?.profilePicture, placeholder: UIImage(named: "ProfileBlur"))
        let name = author?.displayName ?? "Someone"
        nameLabel.text = name
        timeLabel.text = MomentsDate.timeAgo(from: createdAt)
        detailLabel.text = detail
        trailingLabel.text = trailing
        trailingLabel.isHidden = trailing == nil
        accessibilityLabel = [name, trailing, detail, timeLabel.text].compactMap { $0 }.joined(separator: ", ")
    }
}
