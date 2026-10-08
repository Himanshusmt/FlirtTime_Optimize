//
//  BackgroundSyncManager.swift
//  FlirttimeNew
//

import Foundation
import BackgroundTasks
import Combine
import UIKit

@MainActor
final class BackgroundSyncManager: ObservableObject {

    static let shared = BackgroundSyncManager()

    // MARK: - Configuration

    static let backgroundSyncTaskId = "com.onevibe.chat.background-sync"

    private let minimumSyncInterval: TimeInterval = 15 * 60

    private var earliestNextSync: Date?

    // MARK: - Published State

    @Published private(set) var lastBackgroundSync: Date?
    @Published private(set) var isBackgroundSyncEnabled: Bool = true

    // MARK: - Private Properties

    private var sessionManager: SessionManager?
    private var conversationRepository: ConversationRepositoryAsync?
    private let lastSyncKey = "backgroundLastSyncTime"

    // MARK: - Initialization

    private init() {
        loadLastSyncTime()
    }

    /// Configure with required dependencies
    func configure(sessionManager: SessionManager, conversationRepository: ConversationRepositoryAsync) {
        self.sessionManager = sessionManager
        self.conversationRepository = conversationRepository
    }

    // MARK: - Public Methods

    /// Register background task handler - Call this in AppDelegate didFinishLaunching
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundSyncTaskId,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundSyncTask(task as? BGAppRefreshTask)
        }
        AppLogger.debug("BackgroundSyncManager: Registered background sync task")
    }

    /// Schedule next background sync - Call when app enters background
    func scheduleBackgroundSync() {
        guard isBackgroundSyncEnabled else {
            AppLogger.debug("BackgroundSyncManager: Background sync disabled, skipping schedule")
            return
        }

        // Cancel any existing requests
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundSyncTaskId)

        // Schedule new task
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundSyncTaskId)

        // Schedule for earliest next sync time
        let earliestDate = Date(timeIntervalSinceNow: minimumSyncInterval)
        request.earliestBeginDate = earliestDate

        do {
            try BGTaskScheduler.shared.submit(request)
            earliestNextSync = earliestDate
            AppLogger.debug("BackgroundSyncManager: Scheduled sync for \(earliestDate)")
        } catch {
            AppLogger.debug("BackgroundSyncManager: Failed to schedule background sync: \(error)")
        }
    }

    /// Cancel scheduled background sync - Call when user logs out
    func cancelBackgroundSync() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundSyncTaskId)
        earliestNextSync = nil
        AppLogger.debug("BackgroundSyncManager: Cancelled background sync")
    }

    /// Enable or disable background sync
    func setBackgroundSyncEnabled(_ enabled: Bool) {
        isBackgroundSyncEnabled = enabled
        ChatUserDefaultsStore.shared.backgroundSyncEnabled = enabled

        if !enabled {
            cancelBackgroundSync()
        }

        AppLogger.debug("BackgroundSyncManager: Background sync \(enabled ? "enabled" : "disabled")")
    }

    /// Handle silent push notification - Trigger immediate sync
    func handleSilentPushNotification(userInfo: [AnyHashable: Any]) {
        AppLogger.debug("BackgroundSyncManager: Received silent push notification")

        // Check if this is a chat-related notification
        if let type = userInfo["type"] as? String, type == "message" {
            // Trigger immediate background sync
            Task {
                await performBackgroundSync()
            }
        }
    }

    // MARK: - Private Methods

    private func handleBackgroundSyncTask(_ task: BGAppRefreshTask?) {
        guard let task = task else { return }

        AppLogger.debug("BackgroundSyncManager: Handling background sync task")

        // Schedule next sync before handling current
        scheduleBackgroundSync()

        // Create expiration handler
        task.expirationHandler = { [weak self] in
            AppLogger.debug("BackgroundSyncManager: Task expired before completion")
            task.setTaskCompleted(success: false)
            self?.saveLastSyncTime()
        }

        // Perform sync
        Task { [weak self] in
            await self?.performBackgroundSync()
            task.setTaskCompleted(success: true)
            self?.saveLastSyncTime()
        }
    }

    private func performBackgroundSync() async {
        guard let sessionManager = sessionManager else {
            AppLogger.debug("BackgroundSyncManager: No session manager, skipping sync")
            return
        }

        let startTime = Date()
        AppLogger.debug("BackgroundSyncManager: Starting background sync...")

        // Get last sync timestamp
        let lastSync = ChatUserDefaultsStore.shared.lastSyncTimestamp

        do {
            // Fetch conversation updates using delta sync
            let response = try await fetchConversationsDelta(
                sessionManager: sessionManager,
                lastSync: lastSync
            )

            // Process and save updates
            await processSyncResponse(response)

            let duration = Date().timeIntervalSince(startTime)
            lastBackgroundSync = Date()

            AppLogger.debug("BackgroundSyncManager: Sync completed in \(String(format: "%.2f", duration))s")

            // Post notification for any observers
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("BackgroundSyncCompleted"),
                    object: nil,
                    userInfo: ["count": response.rows?.count ?? 0]
                )
            }
        } catch {
            AppLogger.debug("BackgroundSyncManager: Sync failed: \(error)")
        }
    }

    private func fetchConversationsDelta(
        sessionManager: SessionManager,
        lastSync: String?
    ) async throws -> ChatMessageUserData {
        try await withCheckedThrowingContinuation { continuation in
            sessionManager.getConversations(
                page: 1,
                limit: 50,
                search: "",
                showArchived: false,
                showPinned: false,
                lastSync: lastSync,
                before: nil
            )
            .subscribe(onSuccess: { response in
                continuation.resume(returning: response)
            }, onFailure: { error in
                continuation.resume(throwing: error)
            })
        }
    }

    private func processSyncResponse(_ response: ChatMessageUserData) async {
        guard let repository = conversationRepository else { return }

        // Save conversations to CoreData
        if let conversations = response.rows, !conversations.isEmpty {
            do {
                try await repository.saveConversations(conversations)
                AppLogger.debug("BackgroundSyncManager: Saved \(conversations.count) conversations")
            } catch {
                AppLogger.debug("BackgroundSyncManager: Save error: \(error)")
            }
        }

        // Update last sync timestamp
        if let serverTime = response.serverTime {
            ChatUserDefaultsStore.shared.lastSyncTimestamp = serverTime
        }

        // Process delta metadata (deletions, settings changes)
        await processDeltaMetadata(response, repository: repository)
    }

    private func processDeltaMetadata(_ response: ChatMessageUserData, repository: ConversationRepositoryAsync) async {
        // Handle deleted conversations
        if let deletedIds = response.deletedConversationIds, !deletedIds.isEmpty {
            for id in deletedIds where !id.isEmpty {
                do {
                    try await repository.deleteConversation(id: id)
                    AppLogger.debug("BackgroundSyncManager: Deleted conversation \(id)")
                } catch {
                    AppLogger.debug("BackgroundSyncManager: Delete error: \(error)")
                }
            }
        }
    }

    private func saveLastSyncTime() {
        ChatUserDefaultsStore.shared.lastBackgroundSyncDate = Date()
    }

    private func loadLastSyncTime() {
        isBackgroundSyncEnabled = ChatUserDefaultsStore.shared.backgroundSyncEnabled
        if !ChatUserDefaultsStore.shared.backgroundSyncEnabledExists {
            isBackgroundSyncEnabled = true // Default to enabled
        }

        lastBackgroundSync = ChatUserDefaultsStore.shared.lastBackgroundSyncDate
    }
}

// MARK: - AppDelegate Integration

extension BackgroundSyncManager {

    /// Call this in AppDelegate.applicationDidEnterBackground
    func applicationDidEnterBackground() {
        scheduleBackgroundSync()
    }

    /// Call this in AppDelegate.applicationWillEnterForeground
    func applicationWillEnterForeground() {
        // Check if we should sync on foreground
        if let lastSync = lastBackgroundSync,
           Date().timeIntervalSince(lastSync) > minimumSyncInterval {
            // Data is stale, trigger sync
            NotificationCenter.default.post(
                name: NSNotification.Name("RefreshConversationList"),
                object: nil
            )
        }
    }

    /// Call this in AppDelegate.applicationDidReceiveRemoteNotification for silent notifications
    func didReceiveRemoteNotification(userInfo: [AnyHashable: Any], fetchCompletionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        // Check if this is a content-available (silent) notification
        let isSilent = userInfo["aps"] as? [String: Any]
        let contentAvailable = isSilent?["content-available"] as? Int == 1

        if contentAvailable {
            handleSilentPushNotification(userInfo: userInfo)

            // Perform sync and call completion handler
            Task { [weak self] in
                await self?.performBackgroundSync()
                await MainActor.run {
                    fetchCompletionHandler(.newData)
                }
            }
        } else {
            fetchCompletionHandler(.noData)
        }
    }
}
