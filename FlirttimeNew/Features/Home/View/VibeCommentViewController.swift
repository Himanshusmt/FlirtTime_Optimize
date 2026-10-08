//
//  VibeCommentViewController.swift
//  FlirttimeNew
//
//  Comment sheet for a vibe (presented at medium / large detents).
//

import UIKit
import IQKeyboardManagerSwift

final class VibeCommentViewController: BaseViewController {

    var onCommentsCountChanged: ((Int) -> Void)?

    private let viewModel: VibeCommentViewModel
    private var wasKeyboardManagerEnabled = true
    private var wasAutoToolbarEnabled = true

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Comments"
        label.font = UIFont.fredoka(.bold, size: 18)
        label.textColor = AppColor.MineShaft
        label.textAlignment = .center
        return label
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.keyboardDismissMode = .interactive
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
        label.text = "No comments yet.\nStart the conversation."
        label.font = UIFont.fredoka(.regular, size: 15)
        label.textColor = AppColor.DoveGray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private let inputBarView: UIView = {
        let view = UIView()
        view.backgroundColor = AppColor.AppWhite
        return view
    }()

    private let inputAvatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 16
        imageView.backgroundColor = AppColor.AthensGray
        return imageView
    }()

    private lazy var commentTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Add a comment…"
        textField.font = UIFont.fredoka(.regular, size: 15)
        textField.textColor = AppColor.MineShaft
        textField.backgroundColor = AppColor.WildSand
        textField.layer.cornerRadius = 20
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 0))
        textField.leftViewMode = .always
        textField.returnKeyType = .send
        textField.isEnabled = false
        textField.delegate = self
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        return textField
    }()

    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "Btn_Send_Message"), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.accessibilityLabel = "Send comment"
        button.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        return button
    }()

    init(vibe: Vibe) {
        viewModel = VibeCommentViewModel(vibeId: vibe.id)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.AppWhite
        setUI()
        refreshSendState()
        loadComments()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The input bar follows the keyboard itself; IQKeyboardManager would shift it twice.
        wasKeyboardManagerEnabled = IQKeyboardManager.shared.isEnabled
        wasAutoToolbarEnabled = IQKeyboardManager.shared.enableAutoToolbar
        IQKeyboardManager.shared.isEnabled = false
        IQKeyboardManager.shared.enableAutoToolbar = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        IQKeyboardManager.shared.isEnabled = wasKeyboardManagerEnabled
        IQKeyboardManager.shared.enableAutoToolbar = wasAutoToolbarEnabled
    }

    // MARK: - UI

    private func setUI() {
        let headerSeparator = UIView()
        headerSeparator.backgroundColor = AppColor.Iron
        let inputSeparator = UIView()
        inputSeparator.backgroundColor = AppColor.Iron

        [inputSeparator, inputAvatarImageView, commentTextField, sendButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            inputBarView.addSubview($0)
        }
        [titleLabel, headerSeparator, tableView, loadingIndicator, emptyStateLabel, inputBarView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            headerSeparator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            headerSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            tableView.topAnchor.constraint(equalTo: headerSeparator.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBarView.topAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 40),

            emptyStateLabel.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 40),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            inputBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            inputBarView.heightAnchor.constraint(equalToConstant: 60),

            inputSeparator.topAnchor.constraint(equalTo: inputBarView.topAnchor),
            inputSeparator.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor),
            inputSeparator.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor),
            inputSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            inputAvatarImageView.leadingAnchor.constraint(equalTo: inputBarView.leadingAnchor, constant: 16),
            inputAvatarImageView.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            inputAvatarImageView.widthAnchor.constraint(equalToConstant: 32),
            inputAvatarImageView.heightAnchor.constraint(equalToConstant: 32),

            commentTextField.leadingAnchor.constraint(equalTo: inputAvatarImageView.trailingAnchor, constant: 10),
            commentTextField.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            commentTextField.heightAnchor.constraint(equalToConstant: 40),

            sendButton.leadingAnchor.constraint(equalTo: commentTextField.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: inputBarView.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputBarView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalToConstant: 40)
        ])

        inputAvatarImageView.loadImage(path: viewModel.currentUserAuthor.profilePicture,
                                       placeholder: UIImage(named: "dummy_Profile"))
    }

    private func refreshSendState() {
        let hasText = !(commentTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText && commentTextField.isEnabled && !viewModel.isSending
        sendButton.alpha = sendButton.isEnabled ? 1 : 0.5
    }

    private func updateEmptyState() {
        emptyStateLabel.isHidden = !viewModel.comments.isEmpty
    }

    // MARK: - Data

    private func loadComments() {
        loadingIndicator.startAnimating()
        viewModel.loadComments { [weak self] result in
            guard let self else { return }
            self.loadingIndicator.stopAnimating()
            switch result {
            case .success:
                self.commentTextField.isEnabled = true
                self.tableView.reloadData()
                self.updateEmptyState()
            case .failure(let error):
                self.emptyStateLabel.text = error.message
                self.emptyStateLabel.isHidden = false
            }
            self.refreshSendState()
        }
    }

    @objc private func textChanged() {
        if let text = commentTextField.text, text.count > viewModel.maxCommentLength {
            commentTextField.text = String(text.prefix(viewModel.maxCommentLength))
        }
        refreshSendState()
    }

    @objc private func sendTapped() {
        guard sendButton.isEnabled, let text = commentTextField.text else { return }
        viewModel.addComment(text) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
                self.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
                self.updateEmptyState()
                self.onCommentsCountChanged?(self.viewModel.comments.count)
            case .failure(let error):
                self.commentTextField.text = text
                self.aCustomToastView.show(message: error.message)
            }
            self.refreshSendState()
        }
        commentTextField.text = nil
        refreshSendState()
    }
}

// MARK: - UITableViewDataSource
extension VibeCommentViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.comments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: VibeCommentTableViewCell.identifier, for: indexPath) as? VibeCommentTableViewCell else {
            return UITableViewCell()
        }
        cell.configure(with: viewModel.comments[indexPath.row])
        return cell
    }
}

// MARK: - UITextFieldDelegate
extension VibeCommentViewController: UITextFieldDelegate {

    func textFieldDidBeginEditing(_ textField: UITextField) {
        guard let sheet = sheetPresentationController, sheet.selectedDetentIdentifier != .large else { return }
        sheet.animateChanges {
            sheet.selectedDetentIdentifier = .large
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return false
    }
}
