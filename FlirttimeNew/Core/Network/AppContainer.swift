//
//  AppContainer.swift
//  FlirttimeNew
//

import Foundation
import Swinject

extension Container {
    /// FlirtTime app dependencies. Separate from the chat module's `sharedContainer`.
    static let appContainer: Container = {
        let container = Container()
        let backendClient = AppBackendClient(apiClient: AppApiClient.shared)

        container.register(AppBackendClient.self) { _ in
            backendClient
        }.inObjectScope(.container)

        container.register(AppSessionManager.self) { _ in
            AppSessionManager(backendClient: backendClient)
        }.inObjectScope(.container)

        return container
    }()
}
