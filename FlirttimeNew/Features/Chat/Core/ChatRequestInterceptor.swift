//
//  ChatRequestInterceptor.swift
//  FlirttimeNew
//

import Alamofire
import Foundation
import UIKit

extension Notification.Name {
    static let chatSessionExpired = Notification.Name("chatSessionExpired")
}

/// Attaches the chat access token and recovers a 401 by refreshing once.
/// Concurrent 401s share a single `auth/refresh` call.
final class ChatRequestInterceptor: RequestInterceptor {

    private let store = ChatAuthStore.shared
    private let refreshLock = NSLock()
    private var isRefreshing = false
    private var refreshWaiters: [(RetryResult) -> Void] = []

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var urlRequest = urlRequest
        let token = store.accessToken
        if !token.isEmpty {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue(UIApplication.getLanguageCode(), forHTTPHeaderField: "Accept-Language")
        urlRequest.setValue("ios", forHTTPHeaderField: "Device")
        completion(.success(urlRequest))
    }

    func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
        let statusCode = (request.task?.response as? HTTPURLResponse)?.statusCode ?? -1
        let path = request.request?.url?.path ?? ""
        guard statusCode == 401, !path.contains("/auth/refresh") else {
            completion(.doNotRetryWithError(error))
            return
        }
        guard request.retryCount < 1, store.hasRefreshToken else {
            failSession()
            completion(.doNotRetry)
            return
        }

        refreshLock.lock()
        refreshWaiters.append(completion)
        if isRefreshing {
            refreshLock.unlock()
            return
        }
        isRefreshing = true
        refreshLock.unlock()

        performRefresh { [weak self] result in
            guard let self else { return }
            self.refreshLock.lock()
            let waiters = self.refreshWaiters
            self.refreshWaiters.removeAll()
            self.isRefreshing = false
            self.refreshLock.unlock()
            waiters.forEach { $0(result) }
        }
    }

    private func performRefresh(completion: @escaping (RetryResult) -> Void) {
        guard let base = ChatConfig.baseURL,
              let url = URL(string: "auth/refresh", relativeTo: base) else {
            completion(.doNotRetry)
            return
        }

        AF.request(
            url,
            method: .post,
            parameters: ["refreshToken": store.refreshToken],
            encoding: JSONEncoding.default,
            headers: ["Device": "ios"],
            requestModifier: { $0.timeoutInterval = 15 }
        )
        .validate(statusCode: 200..<300)
        .responseData { [weak self] response in
            guard let self else { return }
            switch response.result {
            case .success(let data):
                if let tokens = Self.parseTokens(from: data) {
                    self.store.update(accessToken: tokens.access, refreshToken: tokens.refresh)
                    completion(.retry)
                } else {
                    completion(.doNotRetry)
                }
            case .failure:
                let code = response.response?.statusCode ?? -1
                if code == 401 || code == 403 {
                    self.failSession()
                }
                completion(.doNotRetry)
            }
        }
    }

    private func failSession() {
        NotificationCenter.default.post(name: .chatSessionExpired, object: nil)
    }

    private static func parseTokens(from data: Data) -> (access: String, refresh: String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let payload = json["data"] as? [String: Any] ?? json
        let tokens = payload["tokens"] as? [String: Any]
        let access = (tokens?["accessToken"] ?? payload["accessToken"] ?? payload["token"]) as? String
        let refresh = (tokens?["refreshToken"] ?? payload["refreshToken"]) as? String
        guard let access, !access.isEmpty else { return nil }
        return (access, refresh)
    }
}
