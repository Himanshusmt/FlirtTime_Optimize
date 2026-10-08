import UIKit
import CoreData
import Combine

final class ChatMessageFRC: NSObject, NSFetchedResultsControllerDelegate {

    // MARK: - Callbacks

    /// Fires on every FRC content change with the full grouped message list.
    var onMessagesChanged: (([MessageGroup]) -> Void)?

    // MARK: - Properties

    private let conversationId: String
    private let context: NSManagedObjectContext
    private var frc: NSFetchedResultsController<CDMessage>?
    private let messageRepo = MessageRepository()

    /// Cached conversion of all fetched CDMessage → ConversationMessage.
    private(set) var messages: [ConversationMessage] = []

    // MARK: - Init

    init(conversationId: String, context: NSManagedObjectContext) {
        self.conversationId = conversationId
        self.context = context
        super.init()
    }

    // MARK: - Fetch

    func fetch() {
        let request = CDMessage.fetchRequest() as NSFetchRequest<CDMessage>
        request.predicate = NSPredicate(format: "conversationId == %@", conversationId)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        request.fetchBatchSize = 50
        request.returnsObjectsAsFaults = false

        frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        frc?.delegate = self

        do {
            try frc?.performFetch()
            rebuildMessages()
        } catch {
            AppLogger.debug("[ChatMessageFRC] fetch error: \(error)")
        }
    }

    // MARK: - FRC Delegate

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        rebuildMessages()
    }

    // MARK: - Conversion

    private func rebuildMessages() {
        guard let objects = frc?.fetchedObjects else { return }

        messages = objects.compactMap { messageRepo.convertToConversationMessage($0) }
            .filter { msg in
                guard msg.isDeleted == true else { return true }
                let isEveryone = msg.metadata?["isDeletedEveryone"]?.value as? Bool ?? false
                return isEveryone
            }

        let groups = Self.groupMessagesByDate(messages)
        onMessagesChanged?(groups)
    }

    // MARK: - Grouping (mirrors ChatStateManager.groupMessagesByDate)

    static func groupMessagesByDate(_ messages: [ConversationMessage]) -> [MessageGroup] {
        var groups: [String: [ConversationMessage]] = [:]

        for message in messages {
            let dateString = message.createdAt
            let dateKey = dateString.isEmpty ? "unknown" : String(dateString.prefix(10))
            groups[dateKey, default: []].append(message)
        }

        return groups.map { date, msgs in
            MessageGroup(
                date: date,
                messages: msgs.sorted {
                    let lhs = $0.createdAt
                    let rhs = $1.createdAt
                    if lhs.isEmpty { return false }
                    if rhs.isEmpty { return true }
                    return lhs < rhs
                }
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Query Helpers

    var lastMessage: ConversationMessage? { messages.last }
    var firstMessage: ConversationMessage? { messages.first }
    var count: Int { messages.count }

    func message(withId id: String) -> ConversationMessage? {
        messages.first { $0.id == id }
    }

    func containsMessage(withId id: String) -> Bool {
        messages.contains { $0.id == id }
    }

    var activeMessages: [ConversationMessage] {
        messages.filter { $0.isDeleted != true }
    }

    var newestCreatedAt: String? {
        messages.last?.createdAt
    }

    var oldestCreatedAt: String? {
        messages.first?.createdAt
    }

    // MARK: - Teardown

    func invalidate() {
        frc?.delegate = nil
        frc = nil
        messages = []
    }

    deinit {
        invalidate()
    }
}
