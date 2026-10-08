//
//  ChatAPIClient.swift
//  FlirttimeNew
//

import Foundation
import Alamofire
import RxSwift

typealias BackendClient = ChatAPIClient

struct BaseApiResponse<T: Codable>: Codable {
    let code: Int?
    let message: String?
    let data: T?
    let success: Bool?
}

struct BaseResponse: Codable {
    let code: Int?
    let success: Bool?
    let status: Bool?
    let message: String?
}

enum APIError: Error {
    case apiError(String)
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .apiError(let message): return message
        }
    }
}

struct APIHTTPError: Error, LocalizedError {
    let statusCode: Int
    let message: String
    var errorDescription: String? { message }
}

extension Error {
    var statusCode: Int {
        if let httpError = self as? APIHTTPError { return httpError.statusCode }
        if let afError = self as? AFError { return afError.responseCode ?? -1 }
        return (self as NSError).userInfo["statusCode"] as? Int ?? -1
    }

    func isUnauthorized() -> Bool {
        statusCode == 401
    }
}

/// Alamofire client for the chat backend. Every request is relative to `ChatConfig.baseURL`
/// and carries the chat Bearer token through `ChatRequestInterceptor`.
final class ChatAPIClient {

    static let shared = ChatAPIClient()

    private let session: Session

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        session = Session(configuration: configuration, interceptor: ChatRequestInterceptor())
    }

    /// Decodes `{ success, data }` and returns `data`.
    func load<T: Codable>(request: ApiRequest) -> Single<T> {
        perform(request) { data, statusCode in
            try Self.unwrap(data: data, statusCode: statusCode)
        }
    }

    func loadChatData<T: Codable>(request: ApiRequest) -> Single<T> {
        load(request: request)
    }

    /// Decodes the whole body as `T`.
    func loadModelData<T: Codable>(request: ApiRequest) -> Single<T> {
        perform(request) { data, _ in
            try JSONDecoder().decode(T.self, from: data)
        }
    }

    func loadDirect<T: Codable>(request: ApiRequest) -> Single<T> {
        perform(request) { data, _ in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        }
    }

    /// Returns the finished `DataRequest` so callers can inspect `.data` themselves.
    func loadDataRequest(request: ApiRequest) -> Single<DataRequest> {
        guard let url = url(for: request.endPoint) else {
            return .error(APIError.apiError("Chat base URL is not configured"))
        }
        return Single.create { [session] single in
            let dataRequest = session.request(url, method: request.method, parameters: request.parameters, encoding: request.encoding)
            dataRequest
                .validate(statusCode: Array(200..<300) + [400, 422])
                .responseData { response in
                    if let error = response.error {
                        single(.failure(error))
                    } else {
                        single(.success(dataRequest))
                    }
                }
            return Disposables.create { dataRequest.cancel() }
        }
    }

    func uploadImage<T: Codable>(request: ApiRequest, imageData: Data?) -> Single<T> {
        guard let url = url(for: request.endPoint) else {
            return .error(APIError.apiError("Chat base URL is not configured"))
        }
        return Single.create { [session] single in
            let upload = session.upload(multipartFormData: { form in
                if let imageData {
                    form.append(imageData, withName: "file", fileName: "image.jpg", mimeType: "image/jpeg")
                }
                for (key, value) in request.parameters ?? [:] {
                    if let data = "\(value)".data(using: .utf8) {
                        form.append(data, withName: key)
                    }
                }
            }, to: url, method: request.method)
            upload
                .validate(statusCode: 200..<300)
                .responseData { response in
                    switch response.result {
                    case .success(let data):
                        do {
                            single(.success(try Self.unwrap(data: data, statusCode: response.response?.statusCode ?? 200)))
                        } catch {
                            single(.failure(error))
                        }
                    case .failure(let error):
                        single(.failure(error))
                    }
                }
            return Disposables.create { upload.cancel() }
        }
    }

    func isInternetAvailable() -> Bool {
        NetworkReachabilityManager()?.isReachable ?? false
    }

    // MARK: - Private

    private func perform<T>(_ request: ApiRequest, decode: @escaping (Data, Int) throws -> T) -> Single<T> {
        guard let url = url(for: request.endPoint) else {
            return .error(APIError.apiError("Chat base URL is not configured"))
        }
        return Single.create { [session] single in
            let dataRequest = session.request(url, method: request.method, parameters: request.parameters, encoding: request.encoding)
            dataRequest
                .validate { _, response, _ in
                    response.statusCode == 401
                        ? .failure(AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 401)))
                        : .success(())
                }
                .responseData(emptyResponseCodes: [200, 204, 205]) { response in
                    switch response.result {
                    case .success(let data):
                        do {
                            single(.success(try decode(data, response.response?.statusCode ?? 200)))
                        } catch {
                            AppLogger.debug("[ChatAPI] \(url.absoluteString) decode failed: \(error)")
                            single(.failure(error))
                        }
                    case .failure(let error):
                        single(.failure(error))
                    }
                }
            return Disposables.create { dataRequest.cancel() }
        }
    }

    private func url(for endPoint: EndPoint) -> URL? {
        let path = endPoint.description
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        guard let base = ChatConfig.baseURL else { return nil }
        let root = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        return URL(string: root + path)
    }

    private static func unwrap<T: Codable>(data: Data, statusCode: Int) throws -> T {
        let base = try? JSONDecoder().decode(BaseResponse.self, from: data)
        let succeeded = base?.success ?? base?.status ?? (200..<300).contains(statusCode)
        guard succeeded else {
            let message = base?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw APIHTTPError(statusCode: statusCode, message: (message?.isEmpty == false ? message : nil) ?? "Something went wrong")
        }
        let wrapped = try JSONDecoder().decode(BaseApiResponse<T>.self, from: data)
        if let payload = wrapped.data {
            return payload
        }
        if T.self == Bool.self, let value = true as? T {
            return value
        }
        if let empty = try? JSONDecoder().decode(T.self, from: Data("{}".utf8)) {
            return empty
        }
        throw APIError.apiError(base?.message ?? "No data found")
    }
}
