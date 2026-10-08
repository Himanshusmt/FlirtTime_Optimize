import UIKit

/// Bottom sheet to pick a target language for chat message translation (with search).
final class TranslateLanguagePickerSheet: UIView {

    var onLanguageSelected: ((LiveTranslationLanguages.Entry) -> Void)?
    var onDismiss: (() -> Void)?

    private var filteredLanguages: [LiveTranslationLanguages.Entry] = LiveTranslationLanguages.all
    private var selectedCode: String = ""
    private var sheetTopConstraint: NSLayoutConstraint?
    private var containerBottomConstraint: NSLayoutConstraint?
    private var panGesture: UIPanGestureRecognizer?
    private var panStartY: CGFloat = 0
    private var isDraggingSheet = false

    private let dimmingView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.alpha = 0
        return v
    }()

    private let containerView: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius = 24
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.1
        v.layer.shadowRadius = 10
        v.layer.shadowOffset = CGSize(width: 0, height: -5)
        v.clipsToBounds = true
        return v
    }()

    private let handleView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.gray.withAlphaComponent(0.4)
        v.layer.cornerRadius = 3
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = ChatStrings.chat_translate.localizedString()
        l.font = UIFont.chat(.semibold, size: 17)
        l.textColor = .label
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let searchBarContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.systemGray6
        v.layer.cornerRadius = 10
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let searchIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        iv.tintColor = UIColor.secondaryLabel
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private lazy var searchBar: UITextField = {
        let f = UITextField()
        f.placeholder = ChatStrings.chat_search.localizedString()
        f.font = UIFont.chat(size: 15)
        f.clearButtonMode = .whileEditing
        f.returnKeyType = .search
        f.autocorrectionType = .no
        f.autocapitalizationType = .none
        f.spellCheckingType = .no
        f.translatesAutoresizingMaskIntoConstraints = false
        f.delegate = self
        f.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        return f
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.backgroundColor = .white
        tv.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tv.rowHeight = 52
        tv.keyboardDismissMode = .onDrag
        tv.contentInsetAdjustmentBehavior = .never
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(LanguageRowCell.self, forCellReuseIdentifier: LanguageRowCell.reuseId)
        tv.dataSource = self
        tv.delegate = self
        return tv
    }()

    private let emptyLabel: UILabel = {
        let l = UILabel()
        l.text = ChatStrings.chat_noResultsFound.localizedString()
        l.font = UIFont.chat(.medium, size: 15)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupViews() {
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        addSubview(dimmingView)
        addSubview(containerView)
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        containerView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: bottomAnchor),

            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        containerBottomConstraint = containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        containerBottomConstraint?.isActive = true

        sheetTopConstraint = containerView.topAnchor.constraint(equalTo: topAnchor)
        sheetTopConstraint?.isActive = true

        containerView.addSubview(handleView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(searchBarContainer)
        searchBarContainer.addSubview(searchIcon)
        searchBarContainer.addSubview(searchBar)
        containerView.addSubview(tableView)
        containerView.addSubview(emptyLabel)

        // Opaque header strip so list content cannot draw under title/search.
        let headerBackground = UIView()
        headerBackground.backgroundColor = .white
        headerBackground.translatesAutoresizingMaskIntoConstraints = false
        containerView.insertSubview(headerBackground, belowSubview: handleView)

        NSLayoutConstraint.activate([
            handleView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            handleView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            handleView.widthAnchor.constraint(equalToConstant: 40),
            handleView.heightAnchor.constraint(equalToConstant: 5),

            titleLabel.topAnchor.constraint(equalTo: handleView.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            searchBarContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            searchBarContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            searchBarContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            searchBarContainer.heightAnchor.constraint(equalToConstant: 40),

            searchIcon.leadingAnchor.constraint(equalTo: searchBarContainer.leadingAnchor, constant: 10),
            searchIcon.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 16),
            searchIcon.heightAnchor.constraint(equalToConstant: 16),

            searchBar.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: searchBarContainer.trailingAnchor, constant: -10),
            searchBar.topAnchor.constraint(equalTo: searchBarContainer.topAnchor),
            searchBar.bottomAnchor.constraint(equalTo: searchBarContainer.bottomAnchor),

            headerBackground.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerBackground.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerBackground.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerBackground.bottomAnchor.constraint(equalTo: searchBarContainer.bottomAnchor, constant: 12),

            tableView.topAnchor.constraint(equalTo: headerBackground.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])

        containerView.bringSubviewToFront(headerBackground)
        containerView.bringSubviewToFront(handleView)
        containerView.bringSubviewToFront(titleLabel)
        containerView.bringSubviewToFront(searchBarContainer)

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapDimming))
        dimmingView.addGestureRecognizer(tap)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    func present(in parent: UIView, selectedCode: String? = nil) {
        self.selectedCode = (selectedCode ?? getSelectedLanguage())
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        filteredLanguages = LiveTranslationLanguages.all

        parent.addSubview(self)
        frame = parent.bounds

        let screenHeight = parent.bounds.height
        sheetTopConstraint?.constant = screenHeight
        layoutIfNeeded()
        tableView.reloadData()
        tableView.setContentOffset(.zero, animated: false)

        UIView.animate(withDuration: 0.2) {
            self.dimmingView.alpha = 0.4
        }
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: .curveEaseOut
        ) {
            self.sheetTopConstraint?.constant = self.restingTopConstant()
            parent.layoutIfNeeded()
        } completion: { _ in
            self.tableView.setContentOffset(.zero, animated: false)
        }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        containerView.addGestureRecognizer(pan)
        panGesture = pan
    }

    func dismiss(completion: (() -> Void)? = nil) {
        isDraggingSheet = true
        searchBar.resignFirstResponder()
        let screenHeight = bounds.height
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: .curveEaseOut,
            animations: {
                self.dimmingView.alpha = 0
                self.sheetTopConstraint?.constant = screenHeight
                self.containerBottomConstraint?.constant = 0
                self.superview?.layoutIfNeeded()
            }
        ) { _ in
            self.isDraggingSheet = false
            self.removeFromSuperview()
            self.onDismiss?()
            completion?()
        }
    }

    private func restingTopConstant() -> CGFloat {
        max(120, bounds.height * 0.35)
    }

    @objc private func didTapDimming() {
        dismiss()
    }

    @objc private func searchTextChanged() {
        filteredLanguages = LiveTranslationLanguages.filtered(query: searchBar.text ?? "")
        emptyLabel.isHidden = !filteredLanguages.isEmpty
        tableView.reloadData()
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }

        let keyboardInView = convert(frame, from: nil)
        let overlap = max(0, bounds.height - keyboardInView.origin.y)
        containerBottomConstraint?.constant = -overlap

        UIView.animate(withDuration: duration) {
            self.superview?.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        containerBottomConstraint?.constant = 0
        UIView.animate(withDuration: duration) {
            self.superview?.layoutIfNeeded()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)

        switch gesture.state {
        case .began:
            panStartY = sheetTopConstraint?.constant ?? restingTopConstant()
            searchBar.resignFirstResponder()
        case .changed:
            let next = max(restingTopConstant(), panStartY + translation.y)
            sheetTopConstraint?.constant = next
        case .ended, .cancelled:
            let current = sheetTopConstraint?.constant ?? restingTopConstant()
            if velocity.y > 900 || current > restingTopConstant() + 120 {
                dismiss()
            } else {
                UIView.animate(withDuration: 0.25) {
                    self.sheetTopConstraint?.constant = self.restingTopConstant()
                    self.layoutIfNeeded()
                }
            }
        default:
            break
        }
    }
}

// MARK: - UITableView

extension TranslateLanguagePickerSheet: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredLanguages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LanguageRowCell.reuseId, for: indexPath) as! LanguageRowCell
        let entry = filteredLanguages[indexPath.row]
        cell.configure(title: entry.label, subtitle: entry.id)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = filteredLanguages[indexPath.row]
        selectedCode = entry.code.lowercased()
        dismiss { [weak self] in
            self?.onLanguageSelected?(entry)
        }
    }
}

extension TranslateLanguagePickerSheet: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - Row cell

private final class LanguageRowCell: UITableViewCell {
    static let reuseId = "LanguageRowCell"

    private let titleLbl: UILabel = {
        let l = UILabel()
        l.font = UIFont.chat(.medium, size: 16)
        l.textColor = .label
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let subtitleLbl: UILabel = {
        let l = UILabel()
        l.font = UIFont.chat(.regular, size: 13)
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        contentView.addSubview(titleLbl)
        contentView.addSubview(subtitleLbl)

        NSLayoutConstraint.activate([
            titleLbl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLbl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLbl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            subtitleLbl.leadingAnchor.constraint(equalTo: titleLbl.leadingAnchor),
            subtitleLbl.topAnchor.constraint(equalTo: titleLbl.bottomAnchor, constant: 2),
            subtitleLbl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            subtitleLbl.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, subtitle: String) {
        titleLbl.text = title
        subtitleLbl.text = subtitle
        accessoryType = .none
    }
}
