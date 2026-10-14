//
//  MomentLikesViewController.swift
//  FlirttimeNew
//
//  People who liked a Moment, newest first, loaded page by page from `GET moments/:id/likes`.
//

import UIKit
import RxSwift
import Swinject

final class MomentLikesViewController: UIViewController {

    private static let pageSize = 30

    private let momentId: String
    private var likes: [MomentLike] = []
    private var page = 0
    private var totalPages = 1
    private var isLoading = false

    private lazy var sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!
    private let disposeBag = DisposeBag()

    private let titleLabel = UILabel.vibeLabel(.bold, 20, style: .headline, color: AppColor.AppBlack)
    private let summaryLabel = UILabel.vibeLabel(.regular, 14, style: .subheadline, color: AppColor.DoveGray)
    private let emptyLabel = UILabel.vibeLabel(.regular, 15, color: AppColor.DoveGray, lines: 0)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = AppColor.AppWhite
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(LikeCell.self, forCellReuseIdentifier: LikeCell.reuseID)
        return tableView
    }()

    init(momentId: String) {
        self.momentId = momentId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite

        titleLabel.text = "Likes"
        titleLabel.accessibilityTraits = .header
        let header = UIStackView(arrangedSubviews: [titleLabel, summaryLabel])
        header.axis = .vertical
        header.spacing = 2

        emptyLabel.text = "No likes yet."
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        spinner.hidesWhenStopped = true

        [header, tableView, emptyLabel, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 48),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 48)
        ])
        loadNextPage()
    }

    private func loadNextPage() {
        guard !isLoading, page < totalPages else { return }
        isLoading = true
        if likes.isEmpty { spinner.startAnimating() }
        sessionManager.momentLikes(momentId: momentId, page: page + 1, limit: Self.pageSize)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] data in
                guard let self else { return }
                self.isLoading = false
                self.spinner.stopAnimating()
                self.page = data.page ?? self.page + 1
                self.totalPages = data.totalPages ?? self.page
                self.likes += data.likes ?? []
                let total = max(data.totalLikes ?? 0, self.likes.count)
                self.summaryLabel.text = "\(total) \(total == 1 ? "like" : "likes")"
                self.emptyLabel.isHidden = !self.likes.isEmpty
                self.tableView.reloadData()
            }, onFailure: { [weak self] error in
                guard let self else { return }
                self.isLoading = false
                self.spinner.stopAnimating()
                if self.likes.isEmpty {
                    self.emptyLabel.text = parseError(error) ?? "Couldn't load likes. Please try again."
                    self.emptyLabel.isHidden = false
                }
            })
            .disposed(by: disposeBag)
    }
}

extension MomentLikesViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        likes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LikeCell.reuseID, for: indexPath) as! LikeCell
        let like = likes[indexPath.row]
        cell.configure(author: like.user?.author, createdAt: like.createdAt)
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= likes.count - 5 { loadNextPage() }
    }
}

private final class LikeCell: UITableViewCell {

    static let reuseID = "MomentLikeCell"

    private let avatar = UIImageView()
    private let nameLabel = UILabel.vibeLabel(.medium, 15, style: .subheadline, color: AppColor.AppBlack)
    private let verifiedImageView = UIImageView(image: UIImage(named: "verified"))
    private let detailLabel = UILabel.vibeLabel(.regular, 13, style: .caption1, color: AppColor.DoveGray)
    private let timeLabel = UILabel.vibeLabel(.regular, 12, style: .caption1, color: AppColor.SilverChalice)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = AppColor.AppWhite
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 20
        avatar.backgroundColor = AppColor.AthensGray
        verifiedImageView.contentMode = .scaleAspectFit
        verifiedImageView.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let nameRow = UIStackView(arrangedSubviews: [nameLabel, verifiedImageView, UIView()])
        nameRow.spacing = 4
        nameRow.alignment = .center
        let texts = UIStackView(arrangedSubviews: [nameRow, detailLabel])
        texts.axis = .vertical
        texts.spacing = 2
        let row = UIStackView(arrangedSubviews: [avatar, texts, timeLabel])
        row.spacing = 12
        row.alignment = .center
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20))
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),
            verifiedImageView.widthAnchor.constraint(equalToConstant: 14),
            verifiedImageView.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(author: MomentsAuthor?, createdAt: String?) {
        avatar.loadImage(path: author?.profilePicture, placeholder: UIImage(named: "ProfileBlur"))
        let name = author?.displayName.isEmpty == false ? author!.displayName : "Someone"
        nameLabel.text = name
        verifiedImageView.isHidden = author?.verified != true
        let city = author?.location ?? ""
        detailLabel.text = city
        detailLabel.isHidden = city.isEmpty
        timeLabel.text = MomentsDate.timeAgo(from: createdAt)
        accessibilityLabel = [name, author?.verified == true ? "verified" : nil, city, timeLabel.text]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
