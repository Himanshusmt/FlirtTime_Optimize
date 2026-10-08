//
//  NotificationViewController.swift
//  FlirtTime
//
//  Created by SMT Sourabh on 23/05/24.
//

import UIKit
import Combine

final class NotificationViewController: BaseViewController, Instantiable {

    private struct Section {
        let title: String
        var items: [NotificationData]
    }

    var aNotificationViewModel = NotificationViewModel()
    private var sections: [Section] = []
    private var desposeBag: Set<AnyCancellable> = []
    private var hasLoadedOnce = false

    static var storyboardName: StringConvertible {
        return StoryboardName.dashboard
    }

    private let topBarView = UIView()

    private lazy var backButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "BackIcon"), for: .normal)
        button.accessibilityLabel = "Back"
        button.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        return button
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Notifications"
        label.font = UIFont.fredoka(.medium, size: 20)
        label.textColor = AppColor.MineShaft
        return label
    }()

    private lazy var markAllReadButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Mark all read", for: .normal)
        button.titleLabel?.font = UIFont.fredoka(.medium, size: 14)
        button.setTitleColor(AppColor.Punch, for: .normal)
        button.isHidden = true
        button.addTarget(self, action: #selector(markAllReadTapped), for: .touchUpInside)
        return button
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.separatorStyle = .none
        tableView.backgroundColor = AppColor.AppWhite
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 84
        tableView.sectionHeaderTopPadding = 0
        tableView.contentInset.bottom = 16
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(NotificationTableViewCell.self, forCellReuseIdentifier: NotificationTableViewCell.identifier)
        return tableView
    }()

    private let refreshControl = UIRefreshControl()

    private let loader: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = AppColor.Punch
        spinner.hidesWhenStopped = true
        return spinner
    }()

    private let emptyStateView = UIView()

    private let emptyTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "No notifications yet"
        label.font = UIFont.fredoka(.medium, size: 18)
        label.textColor = AppColor.MineShaft
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        setUI()
        setBinding()
        loader.startAnimating()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkHideCustomButton(hide: true)
        aNotificationViewModel.getNotificationListAPI()
    }

    // MARK: - UI

    private func setUI() {
        [backButton, titleLabel, markAllReadButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            topBarView.addSubview($0)
        }
        [topBarView, tableView, emptyStateView, loader].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        setEmptyStateUI()

        let separator = UIView()
        separator.backgroundColor = AppColor.Iron
        separator.translatesAutoresizingMaskIntoConstraints = false
        topBarView.addSubview(separator)

        NSLayoutConstraint.activate([
            topBarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBarView.heightAnchor.constraint(equalToConstant: 56),

            backButton.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: markAllReadButton.leadingAnchor, constant: -8),

            markAllReadButton.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor, constant: -16),
            markAllReadButton.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: topBarView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            tableView.topAnchor.constraint(equalTo: topBarView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor, constant: -30),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),

            loader.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loader.centerYAnchor.constraint(equalTo: tableView.centerYAnchor)
        ])

        refreshControl.tintColor = AppColor.Punch
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    private func setEmptyStateUI() {
        let imageView = UIImageView(image: UIImage(named: "notificationNotFound"))
        imageView.contentMode = .scaleAspectFit

        let subtitleLabel = UILabel()
        subtitleLabel.text = "but someone's probably thinking about you"
        subtitleLabel.font = UIFont.fredoka(.regular, size: 15)
        subtitleLabel.textColor = AppColor.Bombay
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [imageView, emptyTitleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(16, after: imageView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(stack)
        emptyStateView.isHidden = true

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 180),
            imageView.heightAnchor.constraint(equalToConstant: 180),
            stack.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor)
        ])
    }

    // MARK: - Binding

    private func setBinding() {
        aNotificationViewModel.$arrNotification.receive(on: DispatchQueue.main).sink { [weak self] model in
            guard let self, let model else { return }
            self.hasLoadedOnce = true
            self.sections = Self.groupByDay(model)
            self.reloadContent()
        }.store(in: &desposeBag)

        aNotificationViewModel.$errorMessage.receive(on: DispatchQueue.main).sink { [weak self] errorMessage in
            guard let self, let errorMessage else { return }
            self.hasLoadedOnce = true
            if self.sections.isEmpty {
                self.emptyTitleLabel.text = errorMessage
            }
            self.reloadContent()
        }.store(in: &desposeBag)

        aNotificationViewModel.$dictNotification.receive(on: DispatchQueue.main).sink { [weak self] model in
            guard let self, let id = model?.id else { return }
            self.markReadLocally(id: id)
        }.store(in: &desposeBag)
    }

    private func reloadContent() {
        loader.stopAnimating()
        refreshControl.endRefreshing()
        tableView.reloadData()
        emptyStateView.isHidden = !(hasLoadedOnce && sections.isEmpty)
        updateMarkAllReadButton()
    }

    private func updateMarkAllReadButton() {
        markAllReadButton.isHidden = !sections.contains { $0.items.contains { $0.isRead != true } }
    }

    private func markReadLocally(id: Int) {
        for (sectionIndex, section) in sections.enumerated() {
            if let row = section.items.firstIndex(where: { $0.id == id }) {
                sections[sectionIndex].items[row].isRead = true
                tableView.reloadRows(at: [IndexPath(row: row, section: sectionIndex)], with: .none)
                updateMarkAllReadButton()
                return
            }
        }
    }

    private static func groupByDay(_ notifications: [NotificationData]) -> [Section] {
        let calendar = Calendar.current
        let sorted = notifications.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        var today: [NotificationData] = []
        var yesterday: [NotificationData] = []
        var earlier: [NotificationData] = []
        for notification in sorted {
            guard let date = notification.createdDate else {
                earlier.append(notification)
                continue
            }
            if calendar.isDateInToday(date) {
                today.append(notification)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(notification)
            } else {
                earlier.append(notification)
            }
        }
        return [Section(title: "Today", items: today),
                Section(title: "Yesterday", items: yesterday),
                Section(title: "Earlier", items: earlier)]
            .filter { !$0.items.isEmpty }
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        aNotificationViewModel.getNotificationListAPI()
    }

    @objc private func markAllReadTapped() {
        markAllReadButton.isHidden = true
        aNotificationViewModel.readAllNotificationsAPI()
    }

    @objc private func backButtonTapped() {
        navigationController?.popViewController(animated: true)
    }
}

extension NotificationViewController: UITableViewDelegate, UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: NotificationTableViewCell.identifier, for: indexPath) as? NotificationTableViewCell else {
            return UITableViewCell()
        }
        cell.setUI(data: sections[indexPath.section].items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UIView()
        header.backgroundColor = AppColor.AppWhite
        let label = UILabel()
        label.text = sections[section].title
        label.font = UIFont.fredoka(.medium, size: 15)
        label.textColor = AppColor.MineShaft
        label.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            label.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -6)
        ])
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 40
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let notification = sections[indexPath.section].items[indexPath.row]
        guard let id = notification.id else { return }
        if notification.isRead != true {
            aNotificationViewModel.readNotificationAPI(id: id)
        }
        if let dataDict = notification.data?.toDictionary() {
            NotificationManager.shared.handleNotification(dataDict, from: self)
        }
    }
}
