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

/// Attaches the FlirtTime Bearer token used by the rest of the app.
/// A 401 on an authenticated chat call ends the session (no refresh endpoint yet).
final class ChatRequestInterceptor: RequestInterceptor {

    private static let authPaths = ["/auth/email/", "/auth/phone/", "/auth/apple"]

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var urlRequest = urlRequest
        let token = ChatAuthStore.shared.accessToken
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
        if statusCode == 401, !Self.authPaths.contains(where: { path.contains($0) }) {
            AppTokenStore.shared.clear()
            ChatAuthStore.shared.update(accessToken: "", refreshToken: "")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .chatSessionExpired, object: nil)
                NotificationCenter.default.post(name: .appSessionExpired, object: nil)
            }
        }
        completion(.doNotRetryWithError(error))
    }
}
