import UIKit

final class EmojiPickerSheet: UIView {

    var onEmojiSelected: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private struct Category {
        let title: String
        let icon: String
        let items: [EmojiItem]
    }

    private var sections: [Category] = []
    private var searchResults: [EmojiItem] = []
    private var lastActiveSection: Int = -1
    private var keyboardHeight: CGFloat = 0

    private var isSearching: Bool {
        guard let text = searchBar.text else { return false }
        return !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

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
        f.placeholder = "Search emoji".localizedString()
        f.font = UIFont.chat(size: 15)
        f.clearButtonMode = .whileEditing
        f.returnKeyType = .search
        f.autocorrectionType = .no
        f.autocapitalizationType = .none
        f.spellCheckingType = .no
        f.translatesAutoresizingMaskIntoConstraints = false
        f.delegate = self
        f.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        f.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 0))
        f.leftViewMode = .always
        return f
    }()

    private let bottomBarTopLine: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let noResultsLabel: UILabel = {
        let l = UILabel()
        l.text = NSLocalizedString("No emoji found", comment: "")
        l.font = UIFont.chat(.medium, size: 15)
        l.textColor = UIColor.secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        return l
    }()

    private lazy var gridCollectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: makeGridLayout())
        cv.backgroundColor = .white
        cv.showsVerticalScrollIndicator = false
        cv.alwaysBounceVertical = true
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.register(EmojiCell.self, forCellWithReuseIdentifier: "emoji")
        cv.register(EmojiHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        cv.dataSource = self
        cv.delegate = self
        cv.keyboardDismissMode = .interactive
        return cv
    }()

    private lazy var bottomBar: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 40, height: 36)
        layout.minimumLineSpacing = 0
        layout.sectionInset = .zero

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = UIColor.systemGray6
        cv.showsHorizontalScrollIndicator = false
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.register(EmojiCategoryCell.self, forCellWithReuseIdentifier: "category")
        cv.dataSource = self
        cv.delegate = self
        cv.allowsMultipleSelection = false
        return cv
    }()

    private var sheetTopConstraint: NSLayoutConstraint?
    private var panGesture: UIPanGestureRecognizer?
    private var isDraggingSheet = false
    private var panStartTopConstant: CGFloat = 0
    private var isProgrammaticScroll = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        centerBottomBarIfNeeded()
    }

    private func centerBottomBarIfNeeded() {
        guard let layout = bottomBar.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let totalWidth = CGFloat(sections.count) * layout.itemSize.width
        let available = bottomBar.bounds.width - totalWidth
        let inset = max(0, available / 2)
        let target = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        if layout.sectionInset != target {
            layout.sectionInset = target
            layout.invalidateLayout()
        }
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
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        sheetTopConstraint = containerView.topAnchor.constraint(equalTo: topAnchor)
        sheetTopConstraint?.priority = .required
        sheetTopConstraint?.isActive = true

        containerView.addSubview(handleView)
        containerView.addSubview(searchBarContainer)
        containerView.addSubview(gridCollectionView)
        containerView.addSubview(bottomBarTopLine)
        containerView.addSubview(bottomBar)
        containerView.addSubview(noResultsLabel)

        searchBarContainer.addSubview(searchIcon)
        searchBarContainer.addSubview(searchBar)

        NSLayoutConstraint.activate([
            handleView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            handleView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            handleView.widthAnchor.constraint(equalToConstant: 48),
            handleView.heightAnchor.constraint(equalToConstant: 5),

            searchBarContainer.topAnchor.constraint(equalTo: handleView.bottomAnchor, constant: 10),
            searchBarContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            searchBarContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            searchBarContainer.heightAnchor.constraint(equalToConstant: 36),

            searchIcon.leadingAnchor.constraint(equalTo: searchBarContainer.leadingAnchor, constant: 8),
            searchIcon.centerYAnchor.constraint(equalTo: searchBarContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 16),
            searchIcon.heightAnchor.constraint(equalToConstant: 16),

            searchBar.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: searchBarContainer.trailingAnchor, constant: -8),
            searchBar.topAnchor.constraint(equalTo: searchBarContainer.topAnchor),
            searchBar.bottomAnchor.constraint(equalTo: searchBarContainer.bottomAnchor),

            gridCollectionView.topAnchor.constraint(equalTo: searchBarContainer.bottomAnchor, constant: 8),
            gridCollectionView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            gridCollectionView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            gridCollectionView.bottomAnchor.constraint(equalTo: bottomBarTopLine.topAnchor),

            bottomBarTopLine.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            bottomBarTopLine.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            bottomBarTopLine.heightAnchor.constraint(equalToConstant: 0.5),

            bottomBar.topAnchor.constraint(equalTo: bottomBarTopLine.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 36),

            noResultsLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            noResultsLabel.topAnchor.constraint(equalTo: searchBarContainer.bottomAnchor, constant: 40),
        ])

        let dimmingTap = UITapGestureRecognizer(target: self, action: #selector(handleDimmingTap))
        dimmingView.addGestureRecognizer(dimmingTap)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
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

    func present(in parent: UIView) {
        parent.addSubview(self)
        frame = parent.bounds

        let screenHeight = parent.bounds.height
        sheetTopConstraint?.constant = screenHeight

        layoutIfNeeded()
        rebuildSections()

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
                self.superview?.layoutIfNeeded()
            }) { _ in
                self.isDraggingSheet = false
                self.removeFromSuperview()
                self.onDismiss?()
                completion?()
            }
    }

    private func rebuildSections() {
        var result: [Category] = []
        let recents = RecentReactionsManager.shared.reactions
        if !recents.isEmpty {
            let recentItems: [EmojiItem] = recents.compactMap { char in
                EmojiCatalog.shared.all.first { $0.char == char }
            }
            if !recentItems.isEmpty {
                result.append(Category(title: "Recent", icon: "🕐", items: recentItems))
            }
        }
        for (name, icon, items) in EmojiCatalog.shared.byCategory {
            result.append(Category(title: name, icon: icon, items: items))
        }
        sections = result
        gridCollectionView.reloadData()
        bottomBar.reloadData()
        gridCollectionView.setContentOffset(.zero, animated: false)
        lastActiveSection = 0
        if !sections.isEmpty {
            bottomBar.selectItem(at: IndexPath(item: 0, section: 0), animated: false, scrollPosition: [])
        }
    }

    @objc private func searchTextChanged() {
        let query = searchBar.text ?? ""
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            searchResults = []
            bottomBar.isHidden = false
            bottomBarTopLine.isHidden = false
            noResultsLabel.isHidden = true
        } else {
            searchResults = EmojiCatalog.shared.search(trimmed)
            bottomBar.isHidden = true
            bottomBarTopLine.isHidden = true
            noResultsLabel.isHidden = !searchResults.isEmpty
        }
        gridCollectionView.setContentOffset(.zero, animated: false)
        gridCollectionView.reloadData()
        gridCollectionView.collectionViewLayout.invalidateLayout()
    }

    private func restingTopConstant() -> CGFloat {
        let safeTop = window?.safeAreaInsets.top ?? 0
        let minimumTop = safeTop + 8
        let ideal = bounds.height - (bounds.height * 0.6) - keyboardHeight
        return max(minimumTop, ideal)
    }

    @objc private func handleDimmingTap() {
        dismiss()
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        guard let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let windowBounds = window?.bounds else { return }
        let newHeight = endFrame.intersects(windowBounds) ? endFrame.height : 0
        guard newHeight != keyboardHeight else { return }
        keyboardHeight = newHeight
        animateToRestingPosition(with: note)
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        guard keyboardHeight != 0 else { return }
        keyboardHeight = 0
        animateToRestingPosition(with: note)
    }

    private func animateToRestingPosition(with note: Notification) {
        guard !isDraggingSheet else { return }
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveValue = (note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? 7
        let options = UIView.AnimationOptions(rawValue: UInt(curveValue << 16))

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.sheetTopConstraint?.constant = self.restingTopConstant()
            self.superview?.layoutIfNeeded()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: containerView)
        let expandedTop = (window?.safeAreaInsets.top ?? 0) + 8
        let collapsedTop = restingTopConstant()
        let dismissTop = bounds.height

        switch gesture.state {
        case .began:
            isDraggingSheet = true
            searchBar.resignFirstResponder()
            panStartTopConstant = sheetTopConstraint?.constant ?? 0
        case .changed:
            let proposed = panStartTopConstant + translation.y
            sheetTopConstraint?.constant = min(dismissTop, max(expandedTop, proposed))
        case .ended, .cancelled:
            isDraggingSheet = false
            let velocity = gesture.velocity(in: containerView)
            let current = sheetTopConstraint?.constant ?? 0
            let midDetent = (expandedTop + collapsedTop) / 2
            let dismissThreshold = collapsedTop + (dismissTop - collapsedTop) * 0.4

            let target: CGFloat
            if velocity.y < -500 {
                target = expandedTop
            } else if velocity.y > 500 {
                target = current > midDetent ? dismissTop : collapsedTop
            } else if current < midDetent {
                target = expandedTop
            } else if current < dismissThreshold {
                target = collapsedTop
            } else {
                target = dismissTop
            }

            if target >= dismissTop {
                dismiss()
            } else {
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0,
                    options: .curveEaseOut
                ) {
                    self.sheetTopConstraint?.constant = target
                    self.superview?.layoutIfNeeded()
                }
            }
            gesture.setTranslation(.zero, in: containerView)
        default:
            break
        }
    }

    private func makeGridLayout() -> UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { [weak self] _, _ in
            guard let self else { return nil }
            let columns: CGFloat = 8
            let spacing: CGFloat = 2
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / columns),
                heightDimension: .fractionalHeight(1)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(
                top: spacing, leading: spacing, bottom: spacing, trailing: spacing
            )

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(44)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                subitem: item,
                count: Int(columns)
            )

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 4, leading: 8, bottom: 8, trailing: 8
            )

            if !self.isSearching {
                let headerSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .absolute(24)
                )
                let header = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: headerSize,
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )
                header.contentInsets = NSDirectionalEdgeInsets(
                    top: 0, leading: 12, bottom: 0, trailing: 12
                )
                section.boundarySupplementaryItems = [header]
            }
            return section
        }
    }
}

extension EmojiPickerSheet: UITextFieldDelegate {

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        searchTextChanged()
        return true
    }
}

extension EmojiPickerSheet: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        if collectionView === bottomBar {
            return 1
        }
        return isSearching ? 1 : sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView === bottomBar {
            return sections.count
        }
        if isSearching {
            return searchResults.count
        }
        return sections[section].items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView === bottomBar {
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "category", for: indexPath) as? EmojiCategoryCell else {
                return UICollectionViewCell()
            }
            cell.configure(icon: sections[indexPath.item].icon)
            return cell
        }
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath) as? EmojiCell else {
            return UICollectionViewCell()
        }
        let char: String
        if isSearching {
            char = searchResults[indexPath.item].char
        } else {
            char = sections[indexPath.section].items[indexPath.item].char
        }
        cell.configure(emoji: char)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: "header",
            for: indexPath
        ) as? EmojiHeader else {
            return UICollectionReusableView()
        }
        header.configure(title: sections[indexPath.section].title.localizedString())
        return header
    }
}

extension EmojiPickerSheet: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView === bottomBar {
            guard !isSearching else { return }
            lastActiveSection = indexPath.item
            bottomBar.selectItem(at: indexPath, animated: false, scrollPosition: [])
            let headerIndexPath = IndexPath(item: 0, section: indexPath.item)
            isProgrammaticScroll = true
            if let attrs = gridCollectionView.collectionViewLayout.layoutAttributesForSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader,
                at: headerIndexPath
            ) {
                gridCollectionView.setContentOffset(CGPoint(x: 0, y: attrs.frame.origin.y), animated: false)
            } else {
                gridCollectionView.scrollToItem(at: headerIndexPath, at: .top, animated: false)
            }
            isProgrammaticScroll = false
            return
        }

        let emoji: String
        if isSearching {
            emoji = searchResults[indexPath.item].char
        } else {
            emoji = sections[indexPath.section].items[indexPath.item].char
        }
        RecentReactionsManager.shared.addReaction(emoji)
        let handler = onEmojiSelected
        dismiss(completion: {
            handler?(emoji)
        })
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === gridCollectionView, !isSearching, !sections.isEmpty, !isProgrammaticScroll else { return }
        let probe = CGPoint(x: 0, y: gridCollectionView.contentOffset.y + 1)
        let topSection: Int
        if let indexPath = gridCollectionView.indexPathForItem(at: probe) {
            topSection = indexPath.section
        } else {
            guard let minSection = gridCollectionView.indexPathsForVisibleItems.map(\.section).min() else { return }
            topSection = minSection
        }
        guard topSection != lastActiveSection else { return }
        lastActiveSection = topSection
        bottomBar.selectItem(at: IndexPath(item: topSection, section: 0), animated: false, scrollPosition: [])
    }
}

private final class EmojiCell: UICollectionViewCell {

    private let label: UILabel = {
        let l = UILabel()
        l.font = UIFont.chat(size: 30)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(emoji: String) {
        label.text = emoji
    }
}

private final class EmojiHeader: UICollectionReusableView {

    private let label: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "Fredoka-SemiBold", size: 13) ?? UIFont.chat(.bold, size: 13)
        l.textColor = ChatTheme.textPrimary
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        label.text = title
    }
}

private final class EmojiCategoryCell: UICollectionViewCell {

    private let circleBackground: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.white
        v.layer.cornerRadius = 16
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.08
        v.layer.shadowRadius = 2
        v.layer.shadowOffset = CGSize(width: 0, height: 1)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    private let iconLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.chat(size: 18)
        l.textAlignment = .center
        l.alpha = 0.4
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(circleBackground)
        contentView.addSubview(iconLabel)
        NSLayoutConstraint.activate([
            circleBackground.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            circleBackground.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            circleBackground.widthAnchor.constraint(equalToConstant: 32),
            circleBackground.heightAnchor.constraint(equalToConstant: 32),

            iconLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(icon: String) {
        iconLabel.text = icon
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconLabel.alpha = isSelected ? 1.0 : 0.4
        circleBackground.isHidden = !isSelected
    }

    override var isSelected: Bool {
        didSet {
            iconLabel.alpha = isSelected ? 1.0 : 0.4
            circleBackground.isHidden = !isSelected
        }
    }
}
