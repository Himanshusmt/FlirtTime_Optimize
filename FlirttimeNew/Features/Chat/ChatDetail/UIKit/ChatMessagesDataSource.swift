import UIKit
import Combine

// MARK: - Date Header View

final class DateSeparatorHeaderView: UICollectionReusableView {
    static let cellId = "DateSeparatorHeaderView"

    private let label: UILabel = {
        let label = UILabel()
        label.font = UIFont.chat(.regular, size: 12)
        label.textColor = ChatTheme.datePillText
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let capsuleView: UIView = {
        let view = UIView()
        view.backgroundColor = ChatTheme.datePill
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        addSubview(capsuleView)
        capsuleView.addSubview(label)

        NSLayoutConstraint.activate([
            capsuleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            capsuleView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            capsuleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            capsuleView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.4),

            label.topAnchor.constraint(equalTo: capsuleView.topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor, constant: -4),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        capsuleView.layer.cornerRadius = capsuleView.frame.height / 2
    }

    func configure(text: String) {
        label.text = text
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        label.text = nil
    }
}

// MARK: - Data Source

final class ChatMessagesDataSource: NSObject {

    private(set) var diffableDataSource: UICollectionViewDiffableDataSource<ChatDateSection, ChatMessageCellItem>?
    private weak var collectionView: UICollectionView?
    weak var actionsDelegate: MessageCellActionsDelegate?
    private(set) var currentModels: [MessageCellModel] = []

    var modelCache: [String: MessageCellModel] = [:]
    private var itemByStableId: [String: ChatMessageCellItem] = [:]
    private var stableIdByMessageId: [String: String] = [:]

    private var currentUserId: String?
    private var isGroupChat: Bool = false
    private var showingTranslations: Set<String> = []
    private var groupParticipants: [GroupParticipant] = []
    var isInSelectionMode: Bool = false
    var selectedMessageIds: Set<String> = []
    var expandedMessageIds: Set<String> = []

    // When true, the cell provider uses animated selection transition instead of instant configure
    var isAnimatingSelectionTransition = false
    var isAnimatingCheckboxToggle = false

    private let cellClasses: [(String, UICollectionViewCell.Type)] = [
        (TextMessageCell.cellId, TextMessageCell.self),
        (ImageMessageCell.cellId, ImageMessageCell.self),
        (VideoMessageCell.cellId, VideoMessageCell.self),
        (ChatAudioMessageCell.cellId, ChatAudioMessageCell.self),
        (SystemMessageCell.cellId, SystemMessageCell.self),
        (LocationMessageCell.cellId, LocationMessageCell.self),
        (ContactMessageCell.cellId, ContactMessageCell.self),
    ]

    init(collectionView: UICollectionView, currentUserId: String?, isGroupChat: Bool) {
        self.collectionView = collectionView
        self.currentUserId = currentUserId
        self.isGroupChat = isGroupChat
        super.init()

        // Register all cell classes with the collection view
        for (id, cellClass) in cellClasses {
            collectionView.register(cellClass, forCellWithReuseIdentifier: id)
        }

        setupDataSource(collectionView)
    }

    private func setupDataSource(_ collectionView: UICollectionView) {
        let headerRegistration = UICollectionView.SupplementaryRegistration<DateSeparatorHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let self else { return }
            let snapshot = self.diffableDataSource?.snapshot()
            let sections = snapshot?.sectionIdentifiers ?? []
            guard indexPath.section < sections.count else { return }
            header.configure(text: sections[indexPath.section].displayText)
        }

        diffableDataSource = UICollectionViewDiffableDataSource(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item -> UICollectionViewCell? in
            guard let self else { return nil }
            let model = self.modelCache[item.stableId] ?? item.model

            // Sync expanded state so TextMessageCell can pick it up
            TextMessageCell.expandedMessageIds = self.expandedMessageIds

//            if let existing = collectionView.cellForItem(at: indexPath) {
//                if let sysCell = existing as? SystemMessageCell {
//                    sysCell.configure(text: item.message.content ?? "")
//                    return sysCell
//                }
//                if let cell = existing as? BaseMessageCell {
//                    cell.actionsDelegate = self.actionsDelegate
//                    if self.isAnimatingSelectionTransition {
//                        cell.animateSelectionTransition(
//                            isInSelectionMode: self.isInSelectionMode,
//                            isSelected: model.isSelected
//                        )
//                    } else if self.isAnimatingCheckboxToggle {
//                        cell.animateCheckboxToggle(isSelected: model.isSelected)
//                    } else {
//                        cell.configure(with: model, isInSelectionMode: self.isInSelectionMode)
//                    }
//                    return cell
//                }
//            }

            let identifier = item.kind == .system ? SystemMessageCell.cellId : item.kind.cellIdentifier
            let rawCell = collectionView.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath)

            if let sysCell = rawCell as? SystemMessageCell {
                sysCell.configure(text: item.message.content ?? "")
                return sysCell
            }

            guard let cell = rawCell as? BaseMessageCell else {
                return rawCell
            }

            cell.actionsDelegate = self.actionsDelegate
            cell.configure(with: model, isInSelectionMode: self.isInSelectionMode)
            return cell
        }

        diffableDataSource?.supplementaryViewProvider = { collectionView, kind, indexPath in
            guard kind == UICollectionView.elementKindSectionHeader else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    // MARK: - Apply Snapshot

    var totalItemCount: Int { diffableDataSource?.snapshot().numberOfItems ?? 0 }

    var onSnapshotApplied: ((Int) -> Void)?

    var firstMessageId: String? { diffableDataSource?.snapshot().itemIdentifiers.first?.message.id }

    var latestMessageId: String? { diffableDataSource?.snapshot().itemIdentifiers.last?.message.id }

    var latestMessageCreatedAt: String? { diffableDataSource?.snapshot().itemIdentifiers.last?.message.createdAt }

    // In ChatMessagesDataSource, add this helper
//    func injectUnreadDivider(at messageId: String, in groups: inout [MessageGroup]) {
//        for groupIndex in groups.indices {
//            if let msgIndex = groups[groupIndex].messages.firstIndex(where: { $0.id == messageId }),
//               msgIndex > 0 {
//                // Insert a fake "divider" message before the first unread
//                var dividerMsg = groups[groupIndex].messages[msgIndex]
//                dividerMsg.id = "__unread_divider__"
//                // inject it — handled by cellIdentifier below
//                groups[groupIndex].messages.insert(dividerMsg, at: msgIndex)
//                return
//            }
//        }
//    }
    
    func applyMessages(_ groups: [MessageGroup], animated: Bool = false) {
        var snapshot = NSDiffableDataSourceSnapshot<ChatDateSection, ChatMessageCellItem>()
        var models: [MessageCellModel] = []
        var nextItemByStableId: [String: ChatMessageCellItem] = [:]
        var nextStableIdByMessageId: [String: String] = [:]
        var seenIds: Set<String> = []  // Deduplicate by both stableId and message.id

        for group in groups {
            let section = ChatDateSection(date: group.date, displayText: ChatDateSection.displayText(for: group.date))
            snapshot.appendSections([section])

            for message in group.messages {
                // Deduplicate by stableId (primary) and server id (secondary)
                let stableId = message.stableId
                let serverId = message.id
                if seenIds.contains(stableId) { continue }
                if !serverId.isEmpty && seenIds.contains(serverId) { continue }
                seenIds.insert(stableId)
                if !serverId.isEmpty { seenIds.insert(serverId) }

                let translationKey = serverId.isEmpty ? stableId : serverId
                var model = MessageCellModel.from(
                    message,
                    isGroupChat: isGroupChat,
                    currentUserId: currentUserId,
                    showingTranslation: showingTranslations.contains(translationKey),
                    groupParticipants: groupParticipants
                )
                model.isSelected = selectedMessageIds.contains(model.stableId)
                models.append(model)
                modelCache[model.stableId] = model
                let item = ChatMessageCellItem(stableId: model.stableId, kind: model.kind, message: message, model: model)
                nextItemByStableId[item.stableId] = item
                if !serverId.isEmpty {
                    nextStableIdByMessageId[serverId] = item.stableId
                }
                snapshot.appendItems([item], toSection: section)
            }
        }

        currentModels = models
        itemByStableId = nextItemByStableId
        stableIdByMessageId = nextStableIdByMessageId

        // Prune modelCache to remove entries no longer in the snapshot
        if modelCache.count > 300 {
            let activeIds = Set(snapshot.itemIdentifiers.map(\.stableId))
            modelCache = modelCache.filter { activeIds.contains($0.key) }
        }

        applySnapshotSafely(snapshot, animated: animated)
    }

    func applySnapshotSafely(_ snapshot: NSDiffableDataSourceSnapshot<ChatDateSection, ChatMessageCellItem>, animated: Bool) {
        guard let collectionView else { return }
        onSnapshotApplied?(snapshot.numberOfItems)

        if animated { guard collectionView.window != nil else { return } }

        let ids = snapshot.itemIdentifiers
        let uniqueIds = Set(ids)
        if ids.count != uniqueIds.count {
            // O(n) duplicate detection for logging
            var countById: [String: Int] = [:]
            for id in ids { countById[id.stableId, default: 0] += 1 }
            let dupeIds = Set(countById.filter { $0.value > 1 }.keys)
            AppLogger.debug("[DataSource] Dropping \(dupeIds.count) duplicate item(s): \(dupeIds)")

            // Rebuild snapshot without duplicates, skipping sections that become empty
            var clean = NSDiffableDataSourceSnapshot<ChatDateSection, ChatMessageCellItem>()
            var seen: Set<String> = []
            for section in snapshot.sectionIdentifiers {
                let deduped = snapshot.itemIdentifiers(inSection: section).filter { item in
                    guard !seen.contains(item.stableId) else { return false }
                    seen.insert(item.stableId)
                    return true
                }
                guard !deduped.isEmpty else { continue }
                clean.appendSections([section])
                clean.appendItems(deduped, toSection: section)
            }
            diffableDataSource?.apply(clean, animatingDifferences: false)
            return
        }
        diffableDataSource?.apply(snapshot, animatingDifferences: animated)
    }

    func updateMessage(_ message: ConversationMessage) {
        batchReconfigure([message])
    }

    func batchReconfigure(_ messages: [ConversationMessage], animated: Bool = false) {
        let snapshot = diffableDataSource?.snapshot()
        let liveItems = snapshot?.itemIdentifiers ?? []
        let liveByStableId = Dictionary(uniqueKeysWithValues: liveItems.map { ($0.stableId, $0) })
        var itemsToReconfigure: [ChatMessageCellItem] = []
        var seen: Set<String> = []

        for message in messages {
            let stableId = message.stableId
            if MessageCellModel.isMessageDeleted(message) {
                MessageCellModel.invalidateHeightCache(forStableId: stableId)
            }
            let translationKey = message.id.isEmpty ? message.stableId : message.id
            let freshModel = MessageCellModel.from(
                message,
                isGroupChat: isGroupChat,
                currentUserId: currentUserId,
                showingTranslation: showingTranslations.contains(translationKey),
                groupParticipants: groupParticipants
            )
            var mutableModel = freshModel
            mutableModel.isSelected = selectedMessageIds.contains(stableId)

            modelCache[stableId] = mutableModel

            if let idx = currentModels.firstIndex(where: { $0.stableId == stableId }) {
                currentModels[idx] = mutableModel
            }

            guard seen.insert(stableId).inserted,
                  let liveItem = liveByStableId[stableId] else { continue }
            itemsToReconfigure.append(liveItem)
        }

        guard !itemsToReconfigure.isEmpty else { return }

        let indexPaths = itemsToReconfigure.compactMap { diffableDataSource?.indexPath(for: $0) }

        let configureCells = {
            for item in itemsToReconfigure {
                guard let indexPath = self.diffableDataSource?.indexPath(for: item) else { continue }
                if let cell = self.collectionView?.cellForItem(at: indexPath) as? BaseMessageCell {
                    let model = self.modelCache[item.stableId] ?? item.model
                    cell.configure(with: model, isInSelectionMode: self.isInSelectionMode)
                }
            }
        }

        let invalidateItemLayout = {
            guard let collectionView = self.collectionView,
                  let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout,
                  !indexPaths.isEmpty else { return }
            let context = UICollectionViewFlowLayoutInvalidationContext()
            context.invalidateItems(at: indexPaths)
            layout.invalidateLayout(with: context)
            collectionView.layoutIfNeeded()
        }

        let applyReconfigureSnapshot = {
            guard var snapshot = self.diffableDataSource?.snapshot() else { return }
            snapshot.reconfigureItems(itemsToReconfigure)
            self.diffableDataSource?.apply(snapshot, animatingDifferences: false)
        }

        configureCells()
        applyReconfigureSnapshot()

        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
                invalidateItemLayout()
            }
        } else {
            invalidateItemLayout()
        }
    }

    func model(at indexPath: IndexPath) -> MessageCellModel? {
        guard let item = diffableDataSource?.itemIdentifier(for: indexPath) else { return nil }
        return modelCache[item.stableId] ?? item.model
    }

    func updateConfig(currentUserId: String?, isGroupChat: Bool, showingTranslations: Set<String>, groupParticipants: [GroupParticipant] = []) {
        self.currentUserId = currentUserId
        self.isGroupChat = isGroupChat
        self.showingTranslations = showingTranslations
        self.groupParticipants = groupParticipants
    }

    func reconfigureAllForSelection(isInSelectionMode: Bool, selectedMessageIds: Set<String>) {
        self.isInSelectionMode = isInSelectionMode
        self.selectedMessageIds = selectedMessageIds
        self.isAnimatingSelectionTransition = true

        let snapshot = diffableDataSource?.snapshot()
        let allItems = snapshot?.itemIdentifiers ?? []

        for item in allItems {
            if var model = modelCache[item.stableId] {
                model.isSelected = selectedMessageIds.contains(model.stableId)
                    || selectedMessageIds.contains(model.message.id)
                modelCache[item.stableId] = model
            }
        }

        for item in allItems {
            guard let indexPath = diffableDataSource?.indexPath(for: item) else { continue }
            if let cell = self.collectionView?.cellForItem(at: indexPath) as? BaseMessageCell {
                let model = modelCache[item.stableId] ?? item.model
                if isAnimatingSelectionTransition {
                    cell.animateSelectionTransition(isInSelectionMode: isInSelectionMode, isSelected: model.isSelected)
                } else {
                    cell.configure(with: model, isInSelectionMode: isInSelectionMode)
                }
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.isAnimatingSelectionTransition = false
        }
    }

    func reconfigureForSelectionToggle(changedIds: Set<String>, selectedMessageIds: Set<String>) {
        self.selectedMessageIds = selectedMessageIds
        self.isAnimatingCheckboxToggle = true

        let snapshot = diffableDataSource?.snapshot()
        var itemsToReconfigure: [ChatMessageCellItem] = []

        for item in snapshot?.itemIdentifiers ?? [] {
            if changedIds.contains(item.stableId) {
                if var model = modelCache[item.stableId] {
                    model.isSelected = selectedMessageIds.contains(model.stableId)
                    modelCache[item.stableId] = model
                    itemsToReconfigure.append(item)
                }
            }
        }

        guard !itemsToReconfigure.isEmpty else {
            self.isAnimatingCheckboxToggle = false
            return
        }

        for item in itemsToReconfigure {
            guard let indexPath = diffableDataSource?.indexPath(for: item) else { continue }
            if let cell = self.collectionView?.cellForItem(at: indexPath) as? BaseMessageCell {
                let model = modelCache[item.stableId] ?? item.model
                if isAnimatingCheckboxToggle {
                    cell.animateCheckboxToggle(isSelected: model.isSelected)
                } else {
                    cell.configure(with: model, isInSelectionMode: isInSelectionMode)
                }
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.isAnimatingCheckboxToggle = false
        }
    }

    func findItem(withId id: String) -> ChatMessageCellItem? {
        if let item = itemByStableId[id] {
            return item
        }
        if let stableId = stableIdByMessageId[id] {
            return itemByStableId[stableId]
        }
        return itemByStableId.values.first(where: { $0.message.id == id })
    }

    func indexPath(forItemId id: String) -> IndexPath? {
        guard let item = findItem(withId: id) else { return nil }
        return diffableDataSource?.indexPath(for: item)
    }
}

// MARK: - Message Cell Item

struct ChatMessageCellItem: Hashable {
    let stableId: String
    let kind: MessageKind
    let message: ConversationMessage
    let model: MessageCellModel

    func hash(into hasher: inout Hasher) {
        hasher.combine(stableId)
    }

    static func == (lhs: ChatMessageCellItem, rhs: ChatMessageCellItem) -> Bool {
        lhs.stableId == rhs.stableId
    }
}
