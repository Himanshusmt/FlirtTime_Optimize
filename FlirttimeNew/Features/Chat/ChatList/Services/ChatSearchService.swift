//
//  ChatSearchService.swift
//  FlirttimeNew
//
//  Created by Awais on 29/09/2025.
//

import Foundation
import Combine

@MainActor
class ChatSearchService: ObservableObject {
    private var searchCache: [String: SearchResult] = [:]
    private var searchWorkItem: DispatchWorkItem?
    private let searchDebounceInterval: TimeInterval = 0.25
    
    struct SearchResult {
        let pinned: [ChatMessageRow]
        let unpinned: [ChatMessageRow]
        let archived: [ChatMessageRow]
        let all: [ChatMessageRow]
    }
    
    func searchChats(_ chats: [ChatMessageRow], query: String,
                    pinnedIds: Set<String>, mutedIds: Set<String>) -> SearchResult {
        let cacheKey = "\(query)-\(chats.count)-\(pinnedIds.count)"
        
        if let cached = searchCache[cacheKey] {
            return cached
        }
        
        let result = performSearch(chats, query: query, pinnedIds: pinnedIds, mutedIds: mutedIds)
        searchCache[cacheKey] = result
        return result
    }
    
    func debouncedSearch(_ chats: [ChatMessageRow], query: String,
                        pinnedIds: Set<String>, mutedIds: Set<String>,
                        completion: @escaping (SearchResult) -> Void) {
        searchWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                let result = self?.performSearch(chats, query: query, pinnedIds: pinnedIds, mutedIds: mutedIds) ?? SearchResult(pinned: [], unpinned: [], archived: [], all: [])
                completion(result)
            }
        }
        
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + searchDebounceInterval, execute: workItem)
    }
    
    func clearCache() {
        searchCache.removeAll()
    }
        
    private func performSearch(_ chats: [ChatMessageRow], query: String,
                              pinnedIds: Set<String>, mutedIds: Set<String>) -> SearchResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !trimmedQuery.isEmpty else {
            return createBaseResults(from: chats, pinnedIds: pinnedIds)
        }
        
        let filteredChats = chats.filter { chat in
            matchesQuery(chat, query: trimmedQuery)
        }
        
        return createBaseResults(from: filteredChats, pinnedIds: pinnedIds)
    }
    
    private func createBaseResults(from chats: [ChatMessageRow], pinnedIds: Set<String>) -> SearchResult {
        let pinned = chats.filter { chat in
            guard let id = chat.id else { return false }
            return pinnedIds.contains(id) && !(chat.settings?.isArchived == true)
        }
        
        let unpinned = chats.filter { chat in
            guard let id = chat.id else { return false }
            return !pinnedIds.contains(id) && !(chat.settings?.isArchived == true)
        }
        
        let archived = chats.filter { chat in
            chat.settings?.isArchived == true || chat.isArchived
        }
        
        return SearchResult(pinned: pinned, unpinned: unpinned, archived: archived, all: chats)
    }
    
    private func matchesQuery(_ chat: ChatMessageRow, query: String) -> Bool {
        guard let id = chat.id else { return false }
        
        if let title = chat.title?.lowercased(), title.contains(query) {
            return true
        }
        
        if !chat.isGroup, let userDetails = chat.getUserDetails() {
            if let fullName = userDetails.fullName?.lowercased(), fullName.contains(query) {
                return true
            }
            if let userName = userDetails.userName?.lowercased(), userName.contains(query) {
                return true
            }
        }
        
        if let lastMessage = chat.lastMessage?.contentPreview?.lowercased(),
           lastMessage.contains(query) {
            return true
        }
        
        return false
    }
}
