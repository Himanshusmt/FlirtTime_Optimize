import UIKit
import Kingfisher

enum MessageInfoReceiptStatus {
    case sent
    case delivered
    case read

    var tickImageName: String {
        switch self {
        case .sent: return ChatAssets.tickSent
        case .delivered: return ChatAssets.tickDelivered
        case .read: return ChatAssets.tickRead
        }
    }

    var tickTint: UIColor {
        switch self {
        case .sent, .delivered: return .secondaryLabel
        case .read: return ChatTheme.readReceipt
        }
    }

    var statusTitle: String {
        switch self {
        case .sent: return "Sent"
        case .delivered: return ChatStrings.chat_deliveredTo.localizedString()
        case .read: return ChatStrings.chat_readBy.localizedString()
        }
    }
}

struct MessageInfoEntry {
    let userId: String
    let fullName: String?
    let userName: String?
    let profileImage: String?
    let isVerified: Bool
    let receiptStatus: MessageInfoReceiptStatus
    /// Primary timestamp for this receipt status
    let timestamp: String?
    let sentAt: String?
    let deliveredAt: String?
    let readAt: String?
}

final class MessageInfoSheetVC: UIViewController {

    private var readBy: [MessageInfoEntry] = []
    private var deliveredTo: [MessageInfoEntry] = []
    private var sentTo: [MessageInfoEntry] = []

    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = ChatStrings.chat_messageInfo.localizedString()
        lbl.font = UIFont.chat(.semibold, size: 17)
        lbl.textAlignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private let loadingView: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        return spinner
    }()

    private let emptyLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = ChatStrings.chat_noInfoAvailable.localizedString()
        lbl.textColor = .secondaryLabel
        lbl.font = UIFont.chat(size: 15)
        lbl.textAlignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.isHidden = true
        return lbl
    }()

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoParserFallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "yMMMdHHmm", options: 0, locale: Locale.current)
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setupLayout()
        showLoading()
    }

    private func setupLayout() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(MessageInfoCell.self, forCellReuseIdentifier: MessageInfoCell.identifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 76, bottom: 0, right: 16)
        tableView.isHidden = true

        view.addSubview(titleLabel)
        view.addSubview(tableView)
        view.addSubview(loadingView)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    func showLoading() {
        loadingView.startAnimating()
        tableView.isHidden = true
        emptyLabel.isHidden = true
    }

    func populate(
        readBy: [MessageInfoEntry],
        deliveredTo: [MessageInfoEntry],
        sentTo: [MessageInfoEntry] = []
    ) {
        self.readBy = readBy
        self.deliveredTo = deliveredTo
        self.sentTo = sentTo
        loadingView.stopAnimating()

        let isEmpty = readBy.isEmpty && deliveredTo.isEmpty && sentTo.isEmpty
        tableView.isHidden = isEmpty
        emptyLabel.isHidden = !isEmpty
        if !isEmpty { tableView.reloadData() }
    }

    static func formatTimestamp(_ isoString: String?) -> String? {
        guard let isoString, !isoString.isEmpty,
              let date = isoParser.date(from: isoString) ?? isoParserFallback.date(from: isoString) else {
            return nil
        }
        return timeFormatter.string(from: date)
    }
}

extension MessageInfoSheetVC: UITableViewDelegate, UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        activeSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries(for: activeSections[section]).count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let kind = activeSections[section]
        let count = entries(for: kind).count
        switch kind {
        case .read: return "\(ChatStrings.chat_readBy.localizedString()) · \(count)"
        case .delivered: return "\(ChatStrings.chat_deliveredTo.localizedString()) · \(count)"
        case .sent: return "Sent · \(count)"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: MessageInfoCell.identifier,
            for: indexPath
        ) as? MessageInfoCell else {
            return UITableViewCell()
        }
        let entry = entries(for: activeSections[indexPath.section])[indexPath.row]
        cell.configure(with: entry)
        return cell
    }

    private enum InfoSection { case read, delivered, sent }

    private var activeSections: [InfoSection] {
        var sections: [InfoSection] = []
        if !readBy.isEmpty { sections.append(.read) }
        if !deliveredTo.isEmpty { sections.append(.delivered) }
        if !sentTo.isEmpty { sections.append(.sent) }
        return sections
    }

    private func entries(for section: InfoSection) -> [MessageInfoEntry] {
        switch section {
        case .read: return readBy
        case .delivered: return deliveredTo
        case .sent: return sentTo
        }
    }
}

// MARK: - Cell

final class MessageInfoCell: UITableViewCell {

    static let identifier = "MessageInfoCell"

    private let profileImageView = UIImageView()
    private let nameLabel = UILabel()
    private let verifiedBadge = UIImageView()
    private let userNameLabel = UILabel()
    private let nameRow = UIStackView()
    private let textColumn = UIStackView()
    private let statusStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground

        profileImageView.layer.cornerRadius = 24
        profileImageView.clipsToBounds = true
        profileImageView.contentMode = .scaleAspectFill
        profileImageView.translatesAutoresizingMaskIntoConstraints = false
        profileImageView.image = UIImage(systemName: "person.circle.fill")
        profileImageView.tintColor = .tertiaryLabel
        profileImageView.backgroundColor = .tertiarySystemFill

        nameLabel.font = UIFont.chat(.semibold, size: 16)
        nameLabel.textColor = .label
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Same placement as chat header avatar badge
        verifiedBadge.image = UIImage(named: ChatAssets.verified)
        verifiedBadge.contentMode = .scaleAspectFit
        verifiedBadge.translatesAutoresizingMaskIntoConstraints = false
        verifiedBadge.isHidden = true

        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 4
        nameRow.addArrangedSubview(nameLabel)

        userNameLabel.font = UIFont.chat(.regular, size: 13)
        userNameLabel.textColor = .secondaryLabel
        userNameLabel.lineBreakMode = .byTruncatingTail
        userNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusStack.axis = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 4

        textColumn.axis = .vertical
        textColumn.alignment = .fill
        textColumn.spacing = 2
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        textColumn.addArrangedSubview(nameRow)
        textColumn.addArrangedSubview(userNameLabel)
        textColumn.addArrangedSubview(statusStack)

        contentView.addSubview(profileImageView)
        contentView.addSubview(verifiedBadge)
        contentView.addSubview(textColumn)

        NSLayoutConstraint.activate([
            profileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            profileImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            profileImageView.widthAnchor.constraint(equalToConstant: 48),
            profileImageView.heightAnchor.constraint(equalToConstant: 48),
            profileImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -14),

            verifiedBadge.trailingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 2),
            verifiedBadge.bottomAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: 4),
            verifiedBadge.widthAnchor.constraint(equalToConstant: 18),
            verifiedBadge.heightAnchor.constraint(equalToConstant: 18),

            textColumn.leadingAnchor.constraint(equalTo: profileImageView.trailingAnchor, constant: 12),
            textColumn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textColumn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            textColumn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    func configure(with entry: MessageInfoEntry) {
        nameLabel.text = displayName(entry.fullName, entry.userName)
        if let userName = entry.userName?.trimmingCharacters(in: .whitespacesAndNewlines), !userName.isEmpty {
            userNameLabel.text = "@\(userName)"
            userNameLabel.isHidden = false
        } else {
            userNameLabel.text = nil
            userNameLabel.isHidden = true
        }

        verifiedBadge.isHidden = !entry.isVerified

        if let image = entry.profileImage, let url = URL(string: image) {
            profileImageView.kf.setImage(with: url, placeholder: UIImage(systemName: "person.circle.fill"))
        } else {
            profileImageView.image = UIImage(systemName: "person.circle.fill")
        }

        rebuildStatusRows(for: entry)
    }

    private func rebuildStatusRows(for entry: MessageInfoEntry) {
        statusStack.arrangedSubviews.forEach {
            statusStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        // Read — blue double tick
        if entry.receiptStatus == .read || entry.readAt != nil {
            statusStack.addArrangedSubview(
                makeStatusRow(
                    imageName: MessageInfoReceiptStatus.read.tickImageName,
                    tint: MessageInfoReceiptStatus.read.tickTint,
                    title: "Read",
                    time: MessageInfoSheetVC.formatTimestamp(entry.readAt ?? entry.timestamp)
                )
            )
        }

        // Delivered — gray double tick (only when we have deliver evidence)
        if entry.receiptStatus == .delivered || entry.deliveredAt != nil {
            statusStack.addArrangedSubview(
                makeStatusRow(
                    imageName: MessageInfoReceiptStatus.delivered.tickImageName,
                    tint: MessageInfoReceiptStatus.delivered.tickTint,
                    title: "Delivered",
                    time: MessageInfoSheetVC.formatTimestamp(
                        entry.deliveredAt ?? (entry.receiptStatus == .delivered ? entry.timestamp : nil)
                    )
                )
            )
        }

        // Sent — gray single tick
        if entry.receiptStatus == .sent {
            statusStack.addArrangedSubview(
                makeStatusRow(
                    imageName: MessageInfoReceiptStatus.sent.tickImageName,
                    tint: MessageInfoReceiptStatus.sent.tickTint,
                    title: "Sent",
                    time: MessageInfoSheetVC.formatTimestamp(entry.sentAt ?? entry.timestamp)
                )
            )
        }

        if statusStack.arrangedSubviews.isEmpty {
            statusStack.addArrangedSubview(
                makeStatusRow(
                    imageName: entry.receiptStatus.tickImageName,
                    tint: entry.receiptStatus.tickTint,
                    title: entry.receiptStatus == .read ? "Read"
                        : (entry.receiptStatus == .delivered ? "Delivered" : "Sent"),
                    time: MessageInfoSheetVC.formatTimestamp(entry.timestamp)
                )
            )
        }
    }

    private func makeStatusRow(imageName: String, tint: UIColor, title: String, time: String?) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6

        let tick = UIImageView(image: UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate))
        tick.tintColor = tint
        tick.contentMode = .scaleAspectFit
        tick.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tick.widthAnchor.constraint(equalToConstant: 16),
            tick.heightAnchor.constraint(equalToConstant: 12)
        ])

        let label = UILabel()
        label.font = UIFont.chat(.medium, size: 12)
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        if let time, !time.isEmpty {
            label.text = "\(title)  ·  \(time)"
        } else {
            label.text = title
        }

        row.addArrangedSubview(tick)
        row.addArrangedSubview(label)
        return row
    }

    private func displayName(_ name: String?, _ userName: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return userName ?? "Unknown"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        profileImageView.kf.cancelDownloadTask()
        profileImageView.image = UIImage(systemName: "person.circle.fill")
        nameLabel.text = nil
        userNameLabel.text = nil
        verifiedBadge.isHidden = true
        statusStack.arrangedSubviews.forEach {
            statusStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }
}
