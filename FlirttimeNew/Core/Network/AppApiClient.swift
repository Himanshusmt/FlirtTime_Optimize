//
//  AppApiClient.swift
//  FlirttimeNew
//

import Foundation
import Alamofire
import RxSwift

/// Alamofire client for the FlirtTime backend. Every request is relative to `AppConfig.baseURL`.
///
/// Backend envelope:
/// - success: `{ "success": true, "message": "...", "data": { ... } }`
/// - failure: `{ "success": false, "message": "...", "error": [{ "field": "...", "message": "..." }] }`
final class AppApiClient {

    static let shared = AppApiClient()

    private let session: Session

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        session = Session(configuration: configuration, interceptor: AppRequestInterceptor())
    }

    /// Returns the whole response body as a dictionary. Used until typed models exist.
    func loadJSON(request: AppApiRequest) -> Single<[String: Any]> {
        perform(request) { data, _ in
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw APIError.apiError("Unexpected response format")
            }
            return json
        }
    }

    /// Decodes `{ success, data }` and returns `data`.
    func load<T: Codable>(request: AppApiRequest) -> Single<T> {
        perform(request) { data, _ in
            let response = try JSONDecoder().decode(BaseApiResponse<T>.self, from: data)
            guard let payload = response.data else {
                throw APIError.apiError(response.message ?? "No data found")
            }
            return payload
        }
    }

    /// Decodes the whole body as `T`.
    func loadDirect<T: Codable>(request: AppApiRequest) -> Single<T> {
        perform(request) { data, _ in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        }
    }

    /// POSTs `fields` and `files` as multipart/form-data, decodes `{ success, data }` and returns `data`.
    func upload<T: Codable>(endPoint: AppEndPoint, fields: [String: String], files: [AppMultipartFile]) -> Single<T> {
        performUpload(endPoint: endPoint, fields: fields, files: files) { data, _ in
            let response = try JSONDecoder().decode(BaseApiResponse<T>.self, from: data)
            guard let payload = response.data else {
                throw APIError.apiError(response.message ?? "No data found")
            }
            return payload
        }
    }

    /// POSTs `fields` and `files` as multipart/form-data and returns the whole response body. Used until typed models exist.
    func uploadJSON(endPoint: AppEndPoint, fields: [String: String], files: [AppMultipartFile]) -> Single<[String: Any]> {
        performUpload(endPoint: endPoint, fields: fields, files: files) { data, _ in
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw APIError.apiError("Unexpected response format")
            }
            return json
        }
    }

    func isInternetAvailable() -> Bool {
        NetworkReachabilityManager()?.isReachable ?? false
    }

    // MARK: - Private

    private func perform<T>(_ request: AppApiRequest, decode: @escaping (Data, Int) throws -> T) -> Single<T> {
        perform(endPoint: request.endPoint, method: request.method, logParameters: request.parameters, makeRequest: { session, url in
            session.request(url, method: request.method, parameters: request.parameters, encoding: request.encoding)
        }, decode: decode)
    }

    private func performUpload<T>(endPoint: AppEndPoint,
                                  fields: [String: String],
                                  files: [AppMultipartFile],
                                  decode: @escaping (Data, Int) throws -> T) -> Single<T> {
        var logParameters: [String: Any] = fields
        files.forEach { logParameters[$0.name] = "<file \($0.fileName), \($0.data.count) bytes>" }

        return perform(endPoint: endPoint, method: .post, logParameters: logParameters, makeRequest: { session, url in
            session.upload(multipartFormData: { form in
                fields.forEach { key, value in
                    form.append(Data(value.utf8), withName: key)
                }
                files.forEach { file in
                    form.append(file.data, withName: file.name, fileName: file.fileName, mimeType: file.mimeType)
                }
            }, to: url, method: .post)
        }, decode: decode)
    }

    private func perform<T>(endPoint: AppEndPoint,
                            method: HTTPMethod,
                            logParameters: [String: Any]?,
                            makeRequest: @escaping (Session, URL) -> DataRequest,
                            decode: @escaping (Data, Int) throws -> T) -> Single<T> {
        guard isInternetAvailable() else {
            return .error(APIError.apiError("No Internet Connection"))
        }
        guard let url = url(for: endPoint) else {
            return .error(APIError.apiError("App base URL is not configured"))
        }
        let startTime = Self.logRequest(method: method, url: url, parameters: logParameters)

        return Single.create { [session] single in
            let dataRequest = makeRequest(session, url)
            dataRequest
                .validate { _, response, _ in
                    response.statusCode == 401 && !endPoint.isAuthEndPoint
                        ? .failure(AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 401)))
                        : .success(())
                }
                .responseData(emptyResponseCodes: [200, 204, 205]) { response in
                    let statusCode = response.response?.statusCode ?? -1
                    Self.logResponse(url: url, statusCode: statusCode, data: response.data, startTime: startTime)

                    switch response.result {
                    case .success(let data):
                        do {
                            try Self.throwIfFailed(data: data, statusCode: statusCode)
                            single(.success(try decode(data, statusCode)))
                        } catch {
                            single(.failure(error))
                        }
                    case .failure(let error):
                        if statusCode == 401 {
                            single(.failure(APIHTTPError(statusCode: 401, message: "Session expired. Please login again.")))
                        } else {
                            single(.failure(APIError.apiError(error.localizedDescription)))
                        }
                    }
                }
            return Disposables.create { dataRequest.cancel() }
        }
    }

    private func url(for endPoint: AppEndPoint) -> URL? {
        guard let base = AppConfig.baseURL else { return nil }
        let root = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        return URL(string: root + endPoint.description)
    }

    /// Throws `APIHTTPError` with the backend message when `success` is false or the status is not 2xx.
    private static func throwIfFailed(data: Data, statusCode: Int) throws {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let success = json?["success"] as? Bool ?? (200..<300).contains(statusCode)
        guard !success else { return }
        let errorResponse = try? JSONDecoder().decode(AppErrorResponse.self, from: data)
        throw APIHTTPError(statusCode: statusCode, message: errorResponse?.displayMessage ?? "Something went wrong")
    }

    // MARK: - Logging

    @discardableResult
    private static func logRequest(method: HTTPMethod, url: URL, parameters: [String: Any]?) -> Date {
        #if DEBUG
        print("""

        ===== API REQUEST =====
        Method: \(method.rawValue)
        URL: \(url.absoluteString)
        Parameters:
        \(prettyString(from: parameters ?? [:]))
        =======================
        """)
        #endif
        return Date()
    }

    private static func logResponse(url: URL, statusCode: Int, data: Data?, startTime: Date) {
        #if DEBUG
        let elapsed = Date().timeIntervalSince(startTime)
        print("""

        ===== API RESPONSE =====
        URL: \(url.absoluteString)
        Status Code: \(statusCode)
        Time: \(String(format: "%.3f", elapsed))s
        Body:
        \(responseBodyString(from: data))
        ========================
        """)
        #endif
    }

    private static func prettyString(from object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "\(object)"
        }
        return string
    }

    private static func responseBodyString(from data: Data?) -> String {
        guard let data, !data.isEmpty else { return "No response body" }
        if let object = try? JSONSerialization.jsonObject(with: data) {
            return prettyString(from: object)
        }
        return String(data: data, encoding: .utf8) ?? "Unable to read response body"
    }
}
