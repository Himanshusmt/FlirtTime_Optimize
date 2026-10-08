import UIKit
import Kingfisher

protocol MentionAutocompleteDelegate: AnyObject {
    func mentionAutocomplete(_ view: MentionAutocompleteTableView, didSelect participant: GroupParticipant)
}

final class MentionAutocompleteTableView: UIView {

    weak var delegate: MentionAutocompleteDelegate?

    private var participants: [GroupParticipant] = []

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.separatorStyle = .none
        tv.backgroundColor = .white
        tv.layer.cornerRadius = 12
        tv.layer.borderWidth = 0.8
        tv.layer.borderColor = UIColor.systemGray4.cgColor
        tv.layer.shadowColor = UIColor.black.cgColor
        tv.layer.shadowOpacity = 0.1
        tv.layer.shadowRadius = 4
        tv.layer.shadowOffset = CGSize(width: 0, height: 2)
        tv.isScrollEnabled = true
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(MentionParticipantCell.self, forCellReuseIdentifier: "MentionCell")
        return tv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isHidden = true
        clipsToBounds = false

        addSubview(tableView)
        tableView.dataSource = self
        tableView.delegate = self

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        enforceRTLIfNeeded()
    }

    func updateParticipants(_ list: [GroupParticipant]) {


        participants = list.filter {
            $0.userId != BetterUserDefaults.standard.user?.userId
        }

        tableView.reloadData()
        isHidden = participants.isEmpty
    }

    private static let rowHeight: CGFloat = 52

    func heightForParticipants() -> CGFloat {
        let maxHeight = UIScreen.main.bounds.height * 0.4
        return min(maxHeight, CGFloat(participants.count) * Self.rowHeight)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension MentionAutocompleteTableView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        participants.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "MentionCell", for: indexPath) as? MentionParticipantCell else {
            return UITableViewCell()
        }
        cell.configure(with: participants[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        52
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        delegate?.mentionAutocomplete(self, didSelect: participants[indexPath.row])
    }
}

// MARK: - Mention Cell

private final class MentionParticipantCell: UITableViewCell {

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.layer.cornerRadius = 14
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let allIconView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "person.3.fill")
        iv.tintColor = ChatTheme.primary
        iv.contentMode = .scaleAspectFit
        iv.isHidden = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(size: 14)
        lbl.textColor = .label
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let usernameLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = UIFont.chat(size: 12)
        lbl.textColor = .secondaryLabel
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        contentView.addSubview(avatarImageView)
        contentView.addSubview(allIconView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(usernameLabel)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 28),
            avatarImageView.heightAnchor.constraint(equalToConstant: 28),

            allIconView.leadingAnchor.constraint(equalTo: avatarImageView.leadingAnchor),
            allIconView.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            allIconView.widthAnchor.constraint(equalToConstant: 28),
            allIconView.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

            usernameLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            usernameLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
        ])
        contentView.enforceRTLIfNeeded()
    }

    func configure(with participant: GroupParticipant) {
        let isAll = participant.userId == "all"

        if isAll {
            avatarImageView.isHidden = true
            allIconView.isHidden = false
            nameLabel.text = ChatStrings.chat_notifyEveryone.localizedString()
            nameLabel.textColor = ChatTheme.primary
            usernameLabel.text = "@all"
            usernameLabel.textColor = ChatTheme.primary.withAlphaComponent(0.6)
        } else {
            avatarImageView.isHidden = false
            allIconView.isHidden = true
            nameLabel.text = participant.fullName
            nameLabel.textColor = .label
            usernameLabel.text = "@\(participant.userName)"
            usernameLabel.textColor = .secondaryLabel

            if let url = participant.profilePicture, !url.isEmpty {
                avatarImageView.kf.setImage(with: URL(string: url), placeholder: makeInitialAvatar(text: participant.fullName))
            } else {
                avatarImageView.image = makeInitialAvatar(text: participant.fullName)
            }
        }
    }

    private func makeInitialAvatar(text: String) -> UIImage? {
        let initial = text.first.map(String.init) ?? "?"
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            ChatTheme.primary.withAlphaComponent(0.2).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.chat(.semibold, size: 12),
                .foregroundColor: ChatTheme.primary
            ]
            let textSize = initial.size(withAttributes: attrs)
            initial.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attrs)
        }
    }
}
