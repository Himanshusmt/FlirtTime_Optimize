//
//  ChatContainer.swift
//  FlirttimeNew
//

import Foundation
import Swinject

extension Container {
    static let sharedContainer: Container = {
        let container = Container()
        let defaults = BetterUserDefaults(defaults: UserDefaults.standard)
        let apiClient = ChatAPIClient.shared

        container.register(BackendClient.self) { _ in
            apiClient
        }.inObjectScope(.container)

        container.register(SessionManager.self) { _ in
            SessionManager(backendClient: apiClient, defaults: defaults)
        }.inObjectScope(.container)

        container.register(BetterUserDefaults.self) { _ in
            defaults
        }

        container.register(CoreDataManager.self) { _ in
            CoreDataManager.shared
        }.inObjectScope(.container)

        container.register(ConversationRepositoryProtocol.self) { resolver in
            ConversationRepository(coreDataManager: resolver.resolve(CoreDataManager.self)!)
        }.inObjectScope(.container)

        container.register(MessageRepositoryProtocol.self) { resolver in
            MessageRepository(coreDataManager: resolver.resolve(CoreDataManager.self)!)
        }.inObjectScope(.container)

        return container
    }()
}
