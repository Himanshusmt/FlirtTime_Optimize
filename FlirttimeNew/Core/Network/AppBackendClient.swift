//
//  AppBackendClient.swift
//  FlirttimeNew
//

import Foundation
import RxSwift

final class AppBackendClient {

    private let apiClient: AppApiClient

    init(apiClient: AppApiClient) {
        self.apiClient = apiClient
    }

    func loadJSON(request: AppApiRequest) -> Single<[String: Any]> {
        apiClient.loadJSON(request: request)
    }

    func load<T: Codable>(request: AppApiRequest) -> Single<T> {
        apiClient.load(request: request)
    }

    func loadDirect<T: Codable>(request: AppApiRequest) -> Single<T> {
        apiClient.loadDirect(request: request)
    }
}
