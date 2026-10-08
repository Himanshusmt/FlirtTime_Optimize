//
//  ServiceContainer.swift
//  FlirttimeNew
//
//  Created by Awais on 25/09/25.
//

import Foundation
import Swinject

extension Resolver {
    func require<T>(_ type: T.Type, file: StaticString = #file, line: UInt = #line) -> T {
        guard let resolved = resolve(type) else {
            fatalError("\(type) is not registered in the Swinject Container", file: file, line: line)
        }
        return resolved
    }
}

extension Container {
    static func configureChatServices() -> Container {
        let container = Container(parent: Container.sharedContainer)

        container.register(ChatUserListViewModel.self) { resolver in
            return ChatUserListViewModel()
        }.inObjectScope(.container)

        container.register(ChatMessageServiceProtocol.self) { resolver in
            let sessionManager = resolver.require(SessionManager.self)
            let userListViewModel = resolver.require(ChatUserListViewModel.self)
            return ChatMessageService(sessionManager: sessionManager, userListViewModel: userListViewModel)
        }.inObjectScope(.container)

        container.register(ChatAudioServiceProtocol.self) { _ in
            ChatAudioService()
        }.inObjectScope(.container)

        container.register(ChatSocketServiceProtocol.self) { resolver in
            let userListViewModel = resolver.require(ChatUserListViewModel.self)
            return ChatSocketService(userListViewModel: userListViewModel)
        }.inObjectScope(.container)

        container.register(ChatStateManagerProtocol.self) { _ in
            ChatStateManager()
        }.inObjectScope(.transient)

        container.register(ChatMediaServiceProtocol.self) { resolver in
            let sessionManager = resolver.require(SessionManager.self)
            return ChatMediaService(sessionManager: sessionManager)
        }.inObjectScope(.container)

        return container
    }
}
