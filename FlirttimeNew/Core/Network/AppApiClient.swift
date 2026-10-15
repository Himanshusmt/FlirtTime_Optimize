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
        session = Session(configuration: configuration, interceptor: AppRequestInterceptor(), eventMonitors: [APILogger.shared])
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
        perform(endPoint: request.endPoint, makeRequest: { session, url in
            session.request(url, method: request.method, parameters: request.parameters, encoding: request.encoding)
        }, decode: decode)
    }

    private func performUpload<T>(endPoint: AppEndPoint,
                                  fields: [String: String],
                                  files: [AppMultipartFile],
                                  decode: @escaping (Data, Int) throws -> T) -> Single<T> {
        perform(endPoint: endPoint, makeRequest: { session, url in
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
                            makeRequest: @escaping (Session, URL) -> DataRequest,
                            decode: @escaping (Data, Int) throws -> T) -> Single<T> {
        guard isInternetAvailable() else {
            return .error(APIError.apiError("No Internet Connection"))
        }
        guard let url = url(for: endPoint) else {
            return .error(APIError.apiError("App base URL is not configured"))
        }
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

}

// MARK: - Logging

/// Prints every request (token, URL, headers, body) and its response (status, time, body) in DEBUG builds.
/// Attached to each Alamofire `Session`, so it sees the final request after the interceptor adds the token.
final class APILogger: EventMonitor {

    static let shared = APILogger()

    /// For one-off calls that would otherwise use `AF` (which can't take an event monitor).
    static let session = Session(eventMonitors: [APILogger.shared])

    let queue = DispatchQueue(label: "com.flirttime.api-logger", qos: .utility)

    private init() {}

    func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {
        #if DEBUG
        let headers = urlRequest.allHTTPHeaderFields ?? [:]
        let authorization = headers.first { $0.key.caseInsensitiveCompare("Authorization") == .orderedSame }?.value
        let token = authorization.map { $0.replacingOccurrences(of: "Bearer ", with: "") } ?? "None"
        print("""

        ┌───── API REQUEST [\(Self.shortID(request))] ─────
        │ Method: \(urlRequest.httpMethod ?? "-")
        │ URL: \(urlRequest.url?.absoluteString ?? "-")
        │ Token: \(token.isEmpty ? "None" : token)
        │ Headers:
        \(Self.indent(Self.prettyString(from: headers)))
        │ Body:
        \(Self.indent(Self.requestBody(request, urlRequest: urlRequest)))
        └──────────────────────────────
        """)
        #endif
    }

    func request(_ request: Request, didCompleteTask task: URLSessionTask, with error: AFError?) {
        #if DEBUG
        let response = task.response as? HTTPURLResponse
        let status = response.map { "\($0.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: $0.statusCode))" } ?? "No response"
        let duration = request.metrics.map { String(format: "%.3fs", $0.taskInterval.duration) } ?? "-"
        let data = (request as? DataRequest)?.data
        let failure = (error?.underlyingError ?? error).map { "\n│ Error: \($0.localizedDescription)" } ?? ""
        print("""

        ┌───── API RESPONSE [\(Self.shortID(request))] ─────
        │ URL: \(task.originalRequest?.url?.absoluteString ?? "-")
        │ Status: \(status)
        │ Time: \(duration)\(failure)
        │ Response:
        \(Self.indent(Self.bodyString(from: data)))
        └──────────────────────────────
        """)
        #endif
    }

    // MARK: Formatting

    /// Pairs a request with its response in the console.
    private static func shortID(_ request: Request) -> String {
        String(request.id.uuidString.prefix(8))
    }

    private static func indent(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { "│   \($0)" }.joined(separator: "\n")
    }

    private static func requestBody(_ request: Request, urlRequest: URLRequest) -> String {
        if let body = urlRequest.httpBody, !body.isEmpty {
            return bodyString(from: body)
        }
        if let upload = request as? UploadRequest, case .data(let data)? = upload.uploadable {
            let contentType = urlRequest.value(forHTTPHeaderField: "Content-Type") ?? ""
            return multipartSummary(data, contentType: contentType) ?? "<\(data.count) bytes>"
        }
        if request is UploadRequest {
            return "<streamed upload>"
        }
        return "No body"
    }

    private static func bodyString(from data: Data?) -> String {
        guard let data, !data.isEmpty else { return "No body" }
        if let object = try? JSONSerialization.jsonObject(with: data) {
            return prettyString(from: object)
        }
        return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
    }

    private static func prettyString(from object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let string = String(data: data, encoding: .utf8) else {
            return "\(object)"
        }
        return string
    }

    /// Text fields as `name: value`, files as `name: <file name, size>`.
    private static func multipartSummary(_ data: Data, contentType: String) -> String? {
        guard let boundary = contentType.components(separatedBy: "boundary=").last, contentType.contains("boundary="),
              let delimiter = "--\(boundary)".data(using: .utf8),
              let headerEnd = "\r\n\r\n".data(using: .utf8) else { return nil }

        var lines: [String] = []
        var searchStart = data.startIndex
        while let start = data.range(of: delimiter, in: searchStart..<data.endIndex) {
            let partStart = start.upperBound
            let next = data.range(of: delimiter, in: partStart..<data.endIndex)
            let partEnd = next?.lowerBound ?? data.endIndex
            searchStart = partEnd
            guard let split = data.range(of: headerEnd, in: partStart..<partEnd),
                  let headers = String(data: data[partStart..<split.lowerBound], encoding: .utf8) else {
                if next == nil { break } else { continue }
            }
            let name = value(of: "name", in: headers) ?? "?"
            var body = data[split.upperBound..<partEnd]
            if body.suffix(2) == Data("\r\n".utf8) { body = body.dropLast(2) }
            if let fileName = value(of: "filename", in: headers) {
                lines.append("\(name): <file \(fileName), \(body.count) bytes>")
            } else {
                lines.append("\(name): \(String(data: body, encoding: .utf8) ?? "<\(body.count) bytes>")")
            }
            if next == nil { break }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func value(of key: String, in headers: String) -> String? {
        guard let range = headers.range(of: "\(key)=\"") else { return nil }
        let rest = headers[range.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }
}
