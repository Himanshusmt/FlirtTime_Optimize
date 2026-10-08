//
//  ChatListFRCManager.swift
//  FlirttimeNew
//

import CoreData
import Combine
import Foundation
import Swinject

@MainActor
final class ChatListFRCManager: NSObject, ObservableObject {

    @Published private(set) var chats: [ChatMessageRow] = []

    private let coreDataManager: CoreDataManager
    private let sessionManager: SessionManager?
    private var frc: NSFetchedResultsController<CDConversation>?

    init(coreDataManager: CoreDataManager = .shared) {
        self.coreDataManager = coreDataManager
        self.sessionManager = Container.sharedContainer.resolve(SessionManager.self)
        super.init()
    }

    func start() {
        guard frc == nil else { return }

        let context = coreDataManager.viewContext
        let request: NSFetchRequest<CDConversation> = CDConversation.fetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil")
        request.relationshipKeyPathsForPrefetching = ["participants", "settings"]

        let pinnedDescriptor = NSSortDescriptor(key: "settings.settingsIsPinned", ascending: false)
        let timestampDescriptor = NSSortDescriptor(key: "lastMessageTimestamp", ascending: false)
        let lastMessageAtDescriptor = NSSortDescriptor(key: "lastMessageAt", ascending: false)
        request.sortDescriptors = [pinnedDescriptor, timestampDescriptor, lastMessageAtDescriptor]
        request.fetchBatchSize = 50

        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        controller.delegate = self

        do {
            try controller.performFetch()
            publish(from: controller.fetchedObjects)
            self.frc = controller
        } catch {
            AppLogger.debug("[ChatListFRCManager] performFetch failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        frc?.delegate = nil
        frc = nil
    }

    private func publish(from objects: [CDConversation]?) {
        let mapped: [ChatMessageRow] = (objects ?? []).compactMap { cdConversation in
            ConversationMapper.toDomainSnapshot(cdConversation, sessionManager: sessionManager)
        }
        chats = mapped
    }
}

extension ChatListFRCManager: NSFetchedResultsControllerDelegate {

    nonisolated func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        let objects = controller.fetchedObjects as? [CDConversation]
        Task { @MainActor [weak self] in
            self?.publish(from: objects)
        }
    }
}
