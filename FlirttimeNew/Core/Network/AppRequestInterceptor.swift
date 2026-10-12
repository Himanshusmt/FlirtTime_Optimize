//
//  AppRequestInterceptor.swift
//  FlirttimeNew
//

import Alamofire
import Foundation
import UIKit

extension Notification.Name {
    static let appSessionExpired = Notification.Name("appSessionExpired")
}

/// Attaches the FlirtTime access token. The backend has no refresh endpoint yet,
/// so a 401 on an authenticated call ends the session.
final class AppRequestInterceptor: RequestInterceptor {

    private static let authPaths = ["/auth/email/", "/auth/phone/", "/auth/apple"]

    private let store = AppTokenStore.shared

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
        if statusCode == 401, !Self.authPaths.contains(where: { path.contains($0) }) {
            store.clear()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .appSessionExpired, object: nil)
            }
        }
        completion(.doNotRetryWithError(error))
    }
}
