//
//  S3MediaUploader.swift
//  FlirttimeNew
//

import Foundation
import RxSwift

/// The `data` of POST `media/presigned-url`.
struct PresignedUpload: Codable {
    /// Presigned S3 PUT URL.
    let uploadUrl: String?
    /// Full-size image URL, saved in the backend and used for full screen / zoom.
    let publicUrl: String?
    /// 400x400 Lambda thumbnail for grids and avatars.
    let thumbnailUrl: String?
    /// S3 object key; Create Moment saves this, never the presigned URL.
    let imageKey: String?
    let key: String?
    let expiresIn: Int?

    var resolvedKey: String? {
        [imageKey, key].compactMap { $0 }.first { !$0.isEmpty }
    }
}

/// PUTs raw bytes to a presigned S3 URL.
///
/// Uses a plain `URLSession`: the app's Alamofire session adds `Authorization`, which S3 must not receive.
enum S3MediaUploader {

    private static let maxAttempts = 3

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    static func put(data: Data, to urlString: String, contentType: String) -> Single<Void> {
        guard let url = URL(string: urlString) else {
            return .error(APIError.apiError("Invalid upload URL"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return attempt(request: request, data: data, attempt: 1)
    }

    private static func attempt(request: URLRequest, data: Data, attempt: Int) -> Single<Void> {
        upload(request: request, data: data)
            .catch { error in
                guard isTransient(error), attempt < maxAttempts else { return .error(error) }
                let delay = Int(pow(2.0, Double(attempt - 1)))
                return Single<Void>.just(())
                    .delay(.seconds(delay), scheduler: ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                    .flatMap { Self.attempt(request: request, data: data, attempt: attempt + 1) }
            }
    }

    private static func upload(request: URLRequest, data: Data) -> Single<Void> {
        Single.create { single in
            #if DEBUG
            print("===== S3 UPLOAD ===== PUT \(request.url?.host ?? "") \(data.count) bytes")
            #endif
            let task = session.uploadTask(with: request, from: data) { _, response, error in
                if let error {
                    single(.failure(error))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                #if DEBUG
                print("===== S3 UPLOAD ===== status \(status)")
                #endif
                if (200...299).contains(status) {
                    single(.success(()))
                } else {
                    single(.failure(APIError.apiError("Photo upload failed (\(status))")))
                }
            }
            task.resume()
            return Disposables.create { task.cancel() }
        }
    }

    /// TLS failures, timeouts and dropped connections are retried.
    private static func isTransient(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
                NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(nsError.code)
    }
}
