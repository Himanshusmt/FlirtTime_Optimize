//
//  CoreDataManager.swift
//  FlirttimeNew
//
//  Created by Awais on 23/01/26.
//

import CoreData
import Foundation

enum CoreDataError: LocalizedError {
    case storeLoadingFailed(underlying: NSError)
    case migrationFailed(underlying: NSError)
    case contextNotAvailable
    case saveFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .storeLoadingFailed(let error):
            return "Failed to load Core Data store: \(error.localizedDescription)"
        case .migrationFailed(let error):
            return "Core Data migration failed: \(error.localizedDescription)"
        case .contextNotAvailable:
            return "Core Data context is not available"
        case .saveFailed(let error):
            return "Failed to save Core Data changes: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .storeLoadingFailed, .migrationFailed:
            return "Please restart the app. If the issue persists, try reinstalling the app."
        case .saveFailed:
            return "Try again later. If the issue persists, contact support."
        case .contextNotAvailable:
            return "Restart the app to restore functionality."
        }
    }
}

class CoreDataManager {
    static let shared = CoreDataManager()

    static let CoreDataStoreErrorNotification = Notification.Name("CoreDataStoreErrorNotification")
    static let CoreDataMigrationRequiredNotification = Notification.Name("CoreDataMigrationRequiredNotification")

    private var isStoreLoaded = false
    private var recoveryAttempted = false

    private struct RecoveryMarker: Codable {
        let timestamp: Date
        let reason: String
        let errorDomain: String?
        let errorCode: Int?
    }

    private init() {}

    private var shouldAllowInMemoryFallback: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "ChatDataModel")

        let storeURL = applicationSupportDirectoryURL().appendingPathComponent("ChatDataModel.sqlite")
        migrateLegacyStoreIfNeeded(to: storeURL)
        AppLogger.debug("[CoreData] store at: \(storeURL.path)")

        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldInferMappingModelAutomatically = true
        description.shouldMigrateStoreAutomatically = true
        container.persistentStoreDescriptions = [description]

        loadStores(for: container)

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        container.viewContext.undoManager = nil

        return container
    }()

    private func loadStores(for container: NSPersistentContainer) {
        container.loadPersistentStores { [weak self] storeDescription, error in
            guard let self = self else { return }

            if let error = error as NSError? {
                AppLogger.debug("[CoreData] store load failed: code=\(error.code) domain=\(error.domain) \(error.localizedDescription)")

                let isMigrationError = error.code == 134110 || error.domain == "Cocoa"
                if isMigrationError {
                    self.writeRecoveryMarker(reason: "migration-error", error: error)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: CoreDataManager.CoreDataMigrationRequiredNotification,
                            object: nil,
                            userInfo: ["error": error]
                        )
                    }

                    if !self.recoveryAttempted {
                        self.recoveryAttempted = true
                        AppLogger.debug("[CoreData] attempting store recovery")
                        DispatchQueue.main.async {
                            self.attemptStoreRecovery(container: container, storeURL: storeDescription.url)
                        }
                        return
                    }
                }

                self.isStoreLoaded = false
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: CoreDataManager.CoreDataStoreErrorNotification,
                        object: nil,
                        userInfo: ["error": error, "recoveryAttempted": self.recoveryAttempted]
                    )
                }
                self.handleFinalStoreLoadFailure(container: container, error: error)
            } else {
                self.isStoreLoaded = true
                self.clearRecoveryMarker()
                AppLogger.debug("[CoreData] store loaded at: \(storeDescription.url?.path ?? "in-memory")")
            }
        }
    }

    private func attemptStoreRecovery(container: NSPersistentContainer, storeURL: URL?) {
        guard let storeURL = storeURL else {
            AppLogger.debug("[CoreData] cannot recover: no store URL")
            handleFinalStoreLoadFailure(container: container, error: nil)
            return
        }

        AppLogger.debug("[CoreData] recreating store at: \(storeURL.path)")

        backupSQLiteStoreFiles(at: storeURL, reason: "attempt-store-recovery")
        try? container.persistentStoreCoordinator.destroyPersistentStore(at: storeURL, ofType: NSSQLiteStoreType)
        removeSQLiteStoreFiles(at: storeURL)
        loadStores(for: container)
    }

    private func handleFinalStoreLoadFailure(container: NSPersistentContainer, error: NSError?) {
        isStoreLoaded = false
        writeRecoveryMarker(reason: "store-load-failed", error: error)

        if shouldAllowInMemoryFallback {
            AppLogger.debug("[CoreData] falling back to in-memory store (debug only)")
            setupInMemoryStore(container: container)
            return
        }

        AppLogger.debug("[CoreData] Release: in-memory fallback disabled, store unavailable")
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: CoreDataManager.CoreDataStoreErrorNotification,
                object: nil,
                userInfo: [
                    "error": error as Any,
                    "recoveryAttempted": self.recoveryAttempted,
                    "isFatal": true,
                    "inMemoryFallbackAllowed": false
                ]
            )
        }
    }

    private func setupInMemoryStore(container: NSPersistentContainer) {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { [weak self] _, error in
            if let error = error {
                AppLogger.debug("[CoreData] in-memory store failed: \(error)")
            } else {
                AppLogger.debug("[CoreData] in-memory store loaded")
                self?.isStoreLoaded = true
            }
        }
    }

    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }

    lazy var writeContext: NSManagedObjectContext = {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        context.name = "CoreDataManager.writeContext"
        return context
    }()

    lazy var readContext: NSManagedObjectContext = {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        context.name = "CoreDataManager.readContext"
        context.stalenessInterval = 0
        return context
    }()

    var backgroundContext: NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    var isStoreAvailable: Bool {
        return isStoreLoaded
    }

    // MARK: - Transactional Operations

    func performTransaction<T>(in context: NSManagedObjectContext, block: () throws -> T) -> Result<T, Error> {
        guard isStoreAvailable else {
            return .failure(CoreDataError.contextNotAvailable)
        }

        return Result {
            let result = try block()
            try context.save()
            return result
        }
    }

    func performAsyncTransaction<T>(
        in context: NSManagedObjectContext,
        block: @escaping () throws -> T,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        guard isStoreAvailable else {
            completion(.failure(CoreDataError.contextNotAvailable))
            return
        }

        context.perform { [weak self] in
            guard self != nil else {
                completion(.failure(CoreDataError.contextNotAvailable))
                return
            }

            do {
                let result = try block()
                try context.save()
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch {
                AppLogger.debug("[CoreData] async transaction failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func performBatchOperation<T>(
        items: [T],
        batchSize: Int = 100,
        in context: NSManagedObjectContext,
        operation: @escaping (T, NSManagedObjectContext) throws -> Void,
        completion: @escaping (Bool, Int) -> Void
    ) {
        guard isStoreAvailable else {
            completion(false, 0)
            return
        }

        context.perform { [weak self] in
            guard let self = self else {
                completion(false, 0)
                return
            }

            var processedCount = 0
            var shouldContinue = true

            while processedCount < items.count && shouldContinue {
                let endIndex = min(processedCount + batchSize, items.count)
                let batch = Array(items[processedCount..<endIndex])

                do {
                    for item in batch {
                        try operation(item, context)
                    }
                    try context.save()
                    processedCount = endIndex

                    DispatchQueue.main.async {
                        completion(true, processedCount)
                    }
                } catch {
                    AppLogger.debug("[CoreData] batch failed at \(processedCount): \(error.localizedDescription)")
                    shouldContinue = false

                    DispatchQueue.main.async {
                        completion(false, processedCount)
                    }
                }
            }

            if processedCount == items.count {
                AppLogger.debug("[CoreData] batch completed: \(processedCount) items")
            }
        }
    }

    func saveContext() {
        guard isStoreAvailable else { return }

        let context = persistentContainer.viewContext
        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            AppLogger.debug("[CoreData] save failed (main): \(error.localizedDescription)")
        }
    }

    func saveContext(_ context: NSManagedObjectContext, completion: ((Bool) -> Void)? = nil) {
        guard isStoreAvailable else {
            completion?(false)
            return
        }

        context.perform { [weak self] in
            guard self != nil else {
                completion?(false)
                return
            }

            guard context.hasChanges else {
                completion?(true)
                return
            }

            do {
                try context.save()
                completion?(true)
            } catch {
                AppLogger.debug("[CoreData] save failed (background): \(error.localizedDescription)")
                completion?(false)
            }
        }
    }

    func saveContextWithRetry(_ context: NSManagedObjectContext, maxRetries: Int = 2, completion: ((Bool) -> Void)? = nil) {
        var attempts = 0

        func attemptSave() {
            context.perform { [weak self] in
                guard self != nil else {
                    completion?(false)
                    return
                }

                guard context.hasChanges else {
                    completion?(true)
                    return
                }

                do {
                    try context.save()
                    completion?(true)
                } catch {
                    attempts += 1
                    if attempts < maxRetries {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            attemptSave()
                        }
                    } else {
                        AppLogger.debug("[CoreData] save failed after \(maxRetries) attempts: \(error.localizedDescription)")
                        completion?(false)
                    }
                }
            }
        }

        attemptSave()
    }

    func clearAllEntities() {
        guard isStoreAvailable else { return }

        let context = self.writeContext
        let entityNames = context.persistentStoreCoordinator?.managedObjectModel.entities.compactMap { $0.name } ?? []

        context.performAndWait { [weak self] in
            guard let self = self else { return }
            var totalDeleted = 0

            for entityName in entityNames {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                deleteRequest.resultType = .resultTypeCount

                do {
                    let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                    totalDeleted += result?.result as? Int ?? 0
                } catch {
                    AppLogger.debug("[CoreData] batch delete failed for \(entityName): \(error.localizedDescription)")
                }
            }

            do {
                try context.save()
                AppLogger.debug("[CoreData] cleared \(totalDeleted) objects")
            } catch {
                AppLogger.debug("[CoreData] save after clear failed: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                self.viewContext.refreshAllObjects()
                self.viewContext.reset()
            }
        }
    }

    func resetCoreDataStore() {
        guard let storeURL = persistentContainer.persistentStoreCoordinator.persistentStores.first?.url else {
            AppLogger.debug("[CoreData] no persistent store found to reset")
            return
        }

        AppLogger.debug("[CoreData] resetting store at: \(storeURL.path)")
        backupSQLiteStoreFiles(at: storeURL, reason: "manual-reset")
        writeRecoveryMarker(reason: "manual-reset", error: nil)

        do {
            try persistentContainer.persistentStoreCoordinator.destroyPersistentStore(at: storeURL, ofType: NSSQLiteStoreType, options: nil)
        } catch {
            AppLogger.debug("[CoreData] failed to destroy store: \(error)")
        }

        removeSQLiteStoreFiles(at: storeURL)
    }

    func checkAndHandleMigration() -> Bool {
        guard let url = persistentContainer.persistentStoreDescriptions.first?.url else {
            AppLogger.debug("[CoreData] no store URL found")
            return false
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            AppLogger.debug("[CoreData] no existing store - fresh install")
            return true
        }

        let metadata: [String: Any]
        do {
            metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url)
        } catch {
            AppLogger.debug("[CoreData] could not read store metadata: \(error)")
            return false
        }

        let compatible = persistentContainer.managedObjectModel.isConfiguration(
            withName: nil,
            compatibleWithStoreMetadata: metadata
        )

        if !compatible {
            AppLogger.debug("[CoreData] schema migration needed")
        }

        return compatible
    }

    // MARK: - Private Helpers

    private func applicationSupportDirectoryURL() -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FlirtTimeChat", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func removeSQLiteStoreFiles(at storeURL: URL) {
        let fileManager = FileManager.default
        let paths = [
            storeURL.path,
            storeURL.path + "-wal",
            storeURL.path + "-shm",
            storeURL.path + "-journal"
        ]

        for path in paths where fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }
    }

    private func backupSQLiteStoreFiles(at storeURL: URL, reason: String) {
        let fileManager = FileManager.default
        let sourcePaths = [
            storeURL.path,
            storeURL.path + "-wal",
            storeURL.path + "-shm",
            storeURL.path + "-journal"
        ]

        let existingPaths = sourcePaths.filter { fileManager.fileExists(atPath: $0) }
        guard !existingPaths.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let backupDir = applicationSupportDirectoryURL()
            .appendingPathComponent("CoreDataBackup", isDirectory: true)
            .appendingPathComponent("\(reason)_\(formatter.string(from: Date()))", isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
            for sourcePath in existingPaths {
                let sourceURL = URL(fileURLWithPath: sourcePath)
                let destinationURL = backupDir.appendingPathComponent(sourceURL.lastPathComponent)
                try? fileManager.removeItem(at: destinationURL)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
            AppLogger.debug("[CoreData] backed up sqlite artifacts to \(backupDir.path)")
        } catch {
            AppLogger.debug("[CoreData] failed to backup sqlite artifacts: \(error)")
        }
    }

    private var recoveryMarkerURL: URL {
        applicationSupportDirectoryURL().appendingPathComponent("coredata_recovery_marker.json")
    }

    private func writeRecoveryMarker(reason: String, error: NSError?) {
        let marker = RecoveryMarker(
            timestamp: Date(),
            reason: reason,
            errorDomain: error?.domain,
            errorCode: error?.code
        )
        do {
            let data = try JSONEncoder().encode(marker)
            try data.write(to: recoveryMarkerURL, options: .atomic)
        } catch {
            AppLogger.debug("[CoreData] failed writing recovery marker: \(error)")
        }
    }

    private func clearRecoveryMarker() {
        let path = recoveryMarkerURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    private func migrateLegacyStoreIfNeeded(to targetStoreURL: URL) {
        let fileManager = FileManager.default
        let legacyStoreURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatDataModel.sqlite")

        guard legacyStoreURL.path != targetStoreURL.path else { return }
        guard fileManager.fileExists(atPath: legacyStoreURL.path) else { return }
        guard !fileManager.fileExists(atPath: targetStoreURL.path) else { return }

        let sourcePaths = [
            legacyStoreURL.path,
            legacyStoreURL.path + "-wal",
            legacyStoreURL.path + "-shm",
            legacyStoreURL.path + "-journal"
        ]

        for sourcePath in sourcePaths where fileManager.fileExists(atPath: sourcePath) {
            let suffix = String(sourcePath.dropFirst(legacyStoreURL.path.count))
            let destinationPath = targetStoreURL.path + suffix
            try? fileManager.moveItem(atPath: sourcePath, toPath: destinationPath)
        }
    }
}
