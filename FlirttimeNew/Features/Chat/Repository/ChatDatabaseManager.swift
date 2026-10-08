//
//  ChatDatabaseManager.swift
//  FlirttimeNew
//
//  Created by Awais on 30/09/25.
//

import Foundation

class ChatDatabaseManager {

    static let shared = ChatDatabaseManager()

    private let conversationRepository: ConversationRepositoryAsync

    init(conversationRepository: ConversationRepositoryAsync = ConversationRepository()) {
        self.conversationRepository = conversationRepository
    }

    func clearAllChatData(completion: @escaping (Bool) -> Void) {
        Task { [weak self] in
            do {
                try await self?.conversationRepository.clearAllData()
                self?.clearMediaFiles()

                AppLogger.debug("ChatDatabaseManager: All chat data cleared successfully")
                DispatchQueue.main.async {
                    completion(true)
                }
            } catch {
                AppLogger.debug("ChatDatabaseManager: Failed to clear chat data: \(error)")
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }

    private func clearMediaFiles() {
        AppLogger.debug("Clearing in-memory media caches...")

        InMemoryMediaCache.shared.clearAll()
        MediaCacheManager.shared.clearCache()
        ProfilePictureCache.shared.clearAllCache()

        AppLogger.debug("ChatDatabaseManager: All media caches cleared (in-memory only)")
    }
}
