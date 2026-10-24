import Foundation
import UIKit
import RxSwift
import Alamofire

final class SessionManager {
    let backendClient: BackendClient
    let defaults: BetterUserDefaults

    init(backendClient: BackendClient, defaults: BetterUserDefaults) {
        self.backendClient = backendClient
        self.defaults = defaults
    }

    var user: User? { ChatAuthStore.shared.currentUser }

    func isNetworkReachable() -> Bool {
        return NetworkReachabilityManager()?.isReachable ?? false
    }

    /// NEW API — GET `chat/messages/{messageId}/info`
    /// Returns delivery/read recipients (`deliveredTo`, `readBy`) for Message Info sheet.
    func messageInfo(messageId: String) -> Single<MessageInfoModel> {
        let apiRequest: ApiRequest = ApiRequest(method: .get, endPoint: .messageInfo(messageId))
        return backendClient.loadModelData(request: apiRequest)
    }

    func getReportUserReasons() -> Single<ReportReasonsData> {
        let languageCode = UIApplication.getLanguageCode()
        let apiRequest: ApiRequest = ApiRequest(method: .get, endPoint: .reportUserReason(languageCode))
        return backendClient.load(request: apiRequest)
    }

    /// FlirtTime — POST `/api/v1/users/{id}/report`
    /// Body: `{ reason, description?, conversationId? }`
    func reportuser(
        userID: String,
        reason: String,
        description: String? = nil,
        conversationId: String? = nil
    ) -> Single<DataRequest> {
        var params: [String: Any] = ["reason": reason]
        if let description, !description.isEmpty { params["description"] = description }
        if let conversationId, !conversationId.isEmpty { params["conversationId"] = conversationId }
        let apiRequest = ApiRequest(method: .post, endPoint: .reportUser(userID), parameters: params)
        AppLogger.debug("ChatAPI: POST /api/v1/users/\(userID)/report reason=\(reason)")
        return backendClient.loadDataRequest(request: apiRequest)
    }

    func checkUserBlocked(id: String, userId:String) -> Single<checkBlockedUserodel> {
        let apiRequest: ApiRequest = ApiRequest(method: .get, endPoint: .checkUserBlock(id, userId))
        return backendClient.load(request: apiRequest)
    }

    /// FlirtTime — POST `/api/v1/users/{id}/block` `{ reason }`
    func blockUser(
        id: String,
        userId: String,
        reason: String = "Inappropriate behavior"
    ) -> Single<BlockListUserDataModel> {
        let params = ["reason": reason]
        let apiRequest = ApiRequest(method: .post, endPoint: .blockUser(id), parameters: params)
        AppLogger.debug("ChatAPI: POST /api/v1/users/\(id)/block")
        return backendClient.load(request: apiRequest)
            .do(onSuccess: { _ in
                DispatchQueue.main.async {
                    BlockedUsersManager.shared.blockUser(id: id)
                }
            })
    }

    /// FlirtTime — DELETE `/api/v1/users/{id}/block`
    func unblockUser(id: String) -> Single<Bool> {
        let apiRequest = ApiRequest(method: .delete, endPoint: .unblockUser(id))
        AppLogger.debug("ChatAPI: DELETE /api/v1/users/\(id)/block")
        return backendClient.load(request: apiRequest)
            .do(onSuccess: { _ in
                DispatchQueue.main.async {
                    BlockedUsersManager.shared.unblockUser(id: id)
                }
            })
    }

    /// FlirtTime — GET `/api/v1/users/blocked?page=1&limit=20`
    func getBlockedUsers(page: Int = 1, limit: Int = 20) -> Single<BlockedUsersPage> {
        let params: [String: Any] = ["page": page, "limit": limit]
        let apiRequest = ApiRequest(
            method: .get,
            endPoint: .blockedUsers,
            parameters: params,
            encoding: URLEncoding.queryString
        )
        AppLogger.debug("ChatAPI: GET /api/v1/users/blocked?page=\(page)&limit=\(limit)")
        return backendClient.load(request: apiRequest)
            .catch { _ in
                self.backendClient.loadModelData(request: apiRequest)
            }
    }

    /// NEW API — `POST media/uploads`
    /// Body: purpose, kind, contentType, mimeType, fileName, filename, byteSize/sizeBytes
    func createMediaUpload(
        purpose: String,
        kind: String,
        contentType: String,
        fileName: String,
        byteSize: Int? = nil
    ) -> Single<MediaUploadSessionData> {
        var params = [String: Any]()
        params["purpose"] = purpose
        params["kind"] = kind
        params["contentType"] = contentType
        params["mimeType"] = contentType
        params["fileName"] = fileName
        params["filename"] = fileName
        if let byteSize, byteSize > 0 {
            params["byteSize"] = byteSize
            params["sizeBytes"] = byteSize
        }
        let apiRequest = ApiRequest(method: .post, endPoint: .mediaUploads, parameters: params)
        return backendClient.load(request: apiRequest)
    }

    /// NEW API — `POST media/uploads/{id}/complete`
    /// `thumbnail` is the uploaded thumbnail image mediaId / URL (required for video vibes).
    /// For multipart/chunk uploads pass `parts: [{ partNumber, etag }]`.
    func completeMediaUpload(
        id: String,
        sizeBytes: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        thumbnail: String? = nil,
        parts: [[String: Any]]? = nil
    ) -> Single<MediaUploadSessionData> {
        var params = [String: Any]()
        if let sizeBytes { params["sizeBytes"] = sizeBytes }
        if let width { params["width"] = width }
        if let height { params["height"] = height }
        if let thumbnail, !thumbnail.isEmpty {
            params["thumbnail"] = thumbnail
        }
        if let parts, !parts.isEmpty {
            params["parts"] = parts
        }
        let apiRequest = ApiRequest(method: .post, endPoint: .mediaUploadComplete(id), parameters: params.isEmpty ? nil : params)
        return backendClient.load(request: apiRequest)
    }

    /// NEW API — `POST media/uploads/{id}/parts`
    /// Omit `partNumbers` to receive signed URLs for all server-assigned parts.
    func requestMediaUploadParts(id: String, partNumbers: [Int]? = nil) -> Single<MediaUploadPartsData> {
        var params = [String: Any]()
        if let partNumbers, !partNumbers.isEmpty {
            params["partNumbers"] = partNumbers
        }
        // Empty body `{}` means "all parts" (per API hint).
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .mediaUploadParts(id),
            parameters: params
        )
        return backendClient.load(request: apiRequest)
    }

    /// NEW API — `POST media/uploads/{id}/abort`
    func abortMediaUpload(id: String) -> Single<DataRequest> {
        let apiRequest = ApiRequest(method: .post, endPoint: .mediaUploadAbort(id), parameters: nil)
        return backendClient.loadDataRequest(request: apiRequest)
    }

    /// NEW API — preferred photo path: `POST media/images` (multipart `file`)
    func uploadPostImageDirect(imageData: Data, purpose: String = "post") -> Single<MediaUploadSessionData> {
        let apiRequest = ApiRequest(method: .post, endPoint: .mediaImages, parameters: ["purpose": purpose])
        return backendClient.uploadImage(request: apiRequest, imageData: imageData)
    }

    /// NEW API video upload via chunked multipart (same pattern as post/reel video):
    /// `media/uploads` → `media/uploads/{id}/parts` → PUT chunks → `complete` with etags (+ optional thumbnail).
    /// Part count/size MUST come from the create response (server chooses, e.g. 16MB × N).
    func uploadVideoFileViaChunkedUploads(
        fileURL: URL,
        purpose: String = "post",
        contentType: String,
        fileName: String,
        thumbnail: String? = nil,
        chunkSize: Int = 5 * 1024 * 1024
    ) -> Single<String> {
        guard
            let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            fileSize > 0
        else {
            return .error(APIError.apiError("Video file is unreadable"))
        }

        return createMediaUpload(
            purpose: purpose,
            kind: "video",
            contentType: contentType,
            fileName: fileName,
            byteSize: fileSize
        )
        .flatMap { [weak self] session -> Single<String> in
            guard let self else { return .error(APIError.apiError("Session unavailable")) }
            guard let mediaId = session.resolvedMediaId, !mediaId.isEmpty else {
                return .error(APIError.apiError("mediaId missing from media/uploads"))
            }

            let strategy = (session.strategy ?? session.media?.strategy ?? "").lowercased()
            let hasSinglePutURL = !(session.resolvedUploadUrl ?? "").isEmpty

            // Server dictates multipart sizing (e.g. partCount=2, partSize=16MB).
            let serverPartCount = session.resolvedPartCount ?? 0
            let serverPartSize = session.resolvedPartSize ?? 0
            let effectivePartSize = serverPartSize > 0 ? serverPartSize : chunkSize
            let effectivePartCount: Int = {
                if serverPartCount > 0 { return serverPartCount }
                return max(1, Int((fileSize + effectivePartSize - 1) / effectivePartSize))
            }()

            let putFallback: () -> Single<String> = {
                guard hasSinglePutURL || strategy == "put",
                      let putURL = session.resolvedUploadUrl,
                      let data = try? Data(contentsOf: fileURL),
                      !data.isEmpty else {
                    return .error(APIError.apiError("Could not prepare video upload chunks"))
                }
                return self.putBytesToPresignedURL(
                    urlString: putURL,
                    method: (session.upload?.method ?? "PUT").uppercased(),
                    contentType: session.resolvedContentType ?? contentType,
                    body: data
                )
                .flatMap { _ in
                    self.finishVideoUpload(
                        mediaId: mediaId,
                        sizeBytes: fileSize,
                        thumbnail: thumbnail,
                        parts: nil
                    )
                }
            }

            // Hint from API: omit partNumbers to get all parts for this upload.
            return self.requestMediaUploadParts(id: mediaId, partNumbers: nil)
                .flatMap { partsData -> Single<String> in
                    var partInfos = (partsData.parts ?? []).compactMap { info -> (Int, URL)? in
                        guard let number = info.partNumber,
                              let urlString = info.resolvedUrl,
                              let url = URL(string: urlString) else {
                            return nil
                        }
                        return (number, url)
                    }
                    .sorted { $0.0 < $1.0 }

                    // If partNumber missing, assign sequential numbers from returned order.
                    if partInfos.isEmpty, let rawParts = partsData.parts, !rawParts.isEmpty {
                        partInfos = rawParts.enumerated().compactMap { index, info in
                            guard let urlString = info.resolvedUrl,
                                  let url = URL(string: urlString) else {
                                return nil
                            }
                            return (info.partNumber ?? (index + 1), url)
                        }
                        .sorted { $0.0 < $1.0 }
                    }

                    // Prefer server partCount when present; otherwise accept whatever parts were returned.
                    let partsMatchServer = serverPartCount == 0 || partInfos.count == effectivePartCount
                    guard !partInfos.isEmpty, partsMatchServer else {
                        // Retry once with explicit 1...N if omit failed / mismatched.
                        let numbers = Array(1...effectivePartCount)
                        return self.requestMediaUploadParts(id: mediaId, partNumbers: numbers)
                            .flatMap { retryData -> Single<String> in
                                let retryParts = (retryData.parts ?? []).compactMap { info -> (Int, URL)? in
                                    guard let number = info.partNumber,
                                          let urlString = info.resolvedUrl,
                                          let url = URL(string: urlString) else {
                                        return nil
                                    }
                                    return (number, url)
                                }
                                .sorted { $0.0 < $1.0 }

                                guard retryParts.count == effectivePartCount else {
                                    return putFallback()
                                }
                                return self.uploadAndCompleteVideoChunks(
                                    fileURL: fileURL,
                                    fileSize: fileSize,
                                    chunkSize: effectivePartSize,
                                    mediaId: mediaId,
                                    thumbnail: thumbnail,
                                    partInfos: retryParts
                                )
                            }
                    }

                    return self.uploadAndCompleteVideoChunks(
                        fileURL: fileURL,
                        fileSize: fileSize,
                        chunkSize: effectivePartSize,
                        mediaId: mediaId,
                        thumbnail: thumbnail,
                        partInfos: partInfos
                    )
                }
                .catch { _ in putFallback() }
        }
    }

    private func uploadAndCompleteVideoChunks(
        fileURL: URL,
        fileSize: Int,
        chunkSize: Int,
        mediaId: String,
        thumbnail: String?,
        partInfos: [(Int, URL)]
    ) -> Single<String> {
        uploadFileChunks(
            fileURL: fileURL,
            chunkSize: chunkSize,
            parts: partInfos
        )
        .flatMap { eTags in
            let completedParts: [[String: Any]] = partInfos.compactMap { number, _ in
                guard let eTag = eTags[number], !eTag.isEmpty else { return nil }
                return [
                    "partNumber": number,
                    "etag": eTag
                ]
            }
            guard completedParts.count == partInfos.count else {
                return .error(APIError.apiError("Video chunk upload incomplete"))
            }
            return self.finishVideoUpload(
                mediaId: mediaId,
                sizeBytes: fileSize,
                thumbnail: thumbnail,
                parts: completedParts
            )
        }
    }

    private func finishVideoUpload(
        mediaId: String,
        sizeBytes: Int,
        thumbnail: String?,
        parts: [[String: Any]]?,
        width: Int? = nil,
        height: Int? = nil
    ) -> Single<String> {
        let completeWithThumbnail = completeMediaUpload(
            id: mediaId,
            sizeBytes: sizeBytes,
            width: width,
            height: height,
            thumbnail: thumbnail,
            parts: parts
        )

        let complete: Single<MediaUploadSessionData>
        if let thumbnail, !thumbnail.isEmpty {
            complete = completeWithThumbnail.catch { _ in
                self.completeMediaUpload(
                    id: mediaId,
                    sizeBytes: sizeBytes,
                    width: width,
                    height: height,
                    thumbnail: nil,
                    parts: parts
                )
            }
        } else {
            complete = completeWithThumbnail
        }

        return complete
            .map { $0.resolvedMediaId ?? mediaId }
            .catch { _ in .just(mediaId) }
    }

    /// Uploads file chunks in parallel and returns map of partNumber → ETag.
    private func uploadFileChunks(
        fileURL: URL,
        chunkSize: Int,
        parts: [(Int, URL)]
    ) -> Single<[Int: String]> {
        Single.create { single in
            let queue = OperationQueue()
            queue.name = "ai.onevibe.media-uploads.video-chunks"
            queue.qualityOfService = .userInitiated
            queue.maxConcurrentOperationCount = 4

            let lock = NSLock()
            var eTags: [Int: String] = [:]
            var firstError: Error?

            let operations: [BlockOperation] = parts.map { partNumber, signedURL in
                BlockOperation {
                    lock.lock()
                    let shouldContinue = firstError == nil
                    lock.unlock()
                    guard shouldContinue else { return }

                    var uploadedETag: String?
                    for _ in 0..<3 {
                        if let eTag = Self.putFileChunk(
                            fileURL: fileURL,
                            chunkSize: chunkSize,
                            partNumber: partNumber,
                            signedURL: signedURL
                        ) {
                            uploadedETag = eTag
                            break
                        }
                    }

                    lock.lock()
                    defer { lock.unlock() }
                    if let uploadedETag {
                        eTags[partNumber] = uploadedETag
                    } else if firstError == nil {
                        firstError = APIError.apiError("Video chunk \(partNumber) failed to upload")
                    }
                }
            }

            let finish = BlockOperation {
                if let firstError {
                    single(.failure(firstError))
                } else {
                    single(.success(eTags))
                }
            }
            operations.forEach { finish.addDependency($0) }
            queue.addOperations(operations + [finish], waitUntilFinished: false)

            return Disposables.create {
                queue.cancelAllOperations()
            }
        }
    }

    private static func putFileChunk(
        fileURL: URL,
        chunkSize: Int,
        partNumber: Int,
        signedURL: URL
    ) -> String? {
        guard partNumber > 0,
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        let offset = UInt64(partNumber - 1) * UInt64(chunkSize)
        let data: Data?
        do {
            try handle.seek(toOffset: offset)
            data = try handle.read(upToCount: chunkSize)
        } catch {
            return nil
        }
        guard let data, !data.isEmpty else { return nil }

        let semaphore = DispatchSemaphore(value: 0)
        var uploadedETag: String?

        var request = URLRequest(url: signedURL)
        request.httpMethod = "PUT"

        let task = URLSession.shared.uploadTask(with: request, from: data) { _, response, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                return
            }
            uploadedETag = response.allHeaderFields.first { entry in
                String(describing: entry.key).caseInsensitiveCompare("etag") == .orderedSame
            }.map { String(describing: $0.value) }
        }
        task.resume()
        semaphore.wait()
        return uploadedETag
    }

    /// FlirtTime chat media: `POST /api/v1/media/uploads` → PUT file to `uploadUrl` → key + thumbnail.
    func uploadChatAttachment(
        data: Data,
        kind: String,
        contentType: String,
        fileName: String
    ) -> Single<ChatPresignedUploadResult> {
        createMediaUpload(
            purpose: "chat",
            kind: kind,
            contentType: contentType,
            fileName: fileName,
            byteSize: data.count
        )
        .flatMap { [weak self] session -> Single<ChatPresignedUploadResult> in
            guard let self else { return .error(APIError.apiError("Session unavailable")) }
            guard let uploadUrl = session.resolvedUploadUrl, !uploadUrl.isEmpty else {
                return .error(APIError.apiError("uploadUrl missing from media/uploads"))
            }
            guard let key = session.resolvedStorageKey, !key.isEmpty else {
                return .error(APIError.apiError("key missing from media/uploads"))
            }
            let method = (session.upload?.method ?? "PUT").uppercased()
            let headerContentType = session.resolvedContentType ?? contentType
            AppLogger.debug("ChatAPI: PUT presigned upload \(key) bytes=\(data.count) contentType=\(headerContentType)")
            return self.putBytesToPresignedURL(
                urlString: uploadUrl,
                method: method,
                contentType: headerContentType,
                body: data
            )
            .map { _ in
                ChatPresignedUploadResult(
                    key: key,
                    publicUrl: session.resolvedPublicUrl,
                    thumbnailUrl: session.resolvedThumbnailUrl,
                    contentType: headerContentType
                )
            }
        }
    }

    /// NEW API video/large file path via media/uploads session
    /// For videos, pass `thumbnail` (uploaded image mediaId or public URL) so feed/vibe media gets a poster.
    func uploadViaMediaUploadsSession(
        data: Data,
        purpose: String,
        kind: String,
        contentType: String,
        fileName: String,
        width: Int? = nil,
        height: Int? = nil,
        thumbnail: String? = nil
    ) -> Single<String> {
        if purpose == "chat" {
            return uploadChatAttachment(
                data: data,
                kind: kind,
                contentType: contentType,
                fileName: fileName
            )
            .map { $0.key }
        }

        return createMediaUpload(
            purpose: purpose,
            kind: kind,
            contentType: contentType,
            fileName: fileName,
            byteSize: data.count
        )
        .flatMap { [weak self] session -> Single<String> in
            guard let self else { return .error(APIError.apiError("Session unavailable")) }
            if let uploadUrl = session.resolvedUploadUrl, !uploadUrl.isEmpty,
               session.resolvedMediaId == nil || session.resolvedMediaId?.isEmpty == true {
                let headerContentType = session.resolvedContentType ?? contentType
                return self.putBytesToPresignedURL(
                    urlString: uploadUrl,
                    method: (session.upload?.method ?? "PUT").uppercased(),
                    contentType: headerContentType,
                    body: data
                )
                .map { session.resolvedStorageKey ?? session.resolvedPublicUrl ?? "" }
            }
            guard let mediaId = session.resolvedMediaId, !mediaId.isEmpty else {
                return .error(APIError.apiError("mediaId missing from media/uploads"))
            }
            guard let uploadUrl = session.resolvedUploadUrl, !uploadUrl.isEmpty else {
                // Some responses may already be complete/ready
                return .just(mediaId)
            }
            let method = (session.upload?.method ?? "PUT").uppercased()
            let headerContentType = session.resolvedContentType ?? contentType
            return self.putBytesToPresignedURL(
                urlString: uploadUrl,
                method: method,
                contentType: headerContentType,
                body: data
            )
            .flatMap { _ in
                self.finishVideoUpload(
                    mediaId: mediaId,
                    sizeBytes: data.count,
                    thumbnail: thumbnail,
                    parts: nil,
                    width: width,
                    height: height
                )
            }
        }
    }

    /// Same as `uploadViaMediaUploadsSession`, but returns `publicUrl` (for channel `avatarPath`).
    func uploadViaMediaUploadsSessionPublicUrl(
        data: Data,
        purpose: String,
        kind: String,
        contentType: String,
        fileName: String,
        width: Int? = nil,
        height: Int? = nil,
        thumbnail: String? = nil
    ) -> Single<String> {
        createMediaUpload(
            purpose: purpose,
            kind: kind,
            contentType: contentType,
            fileName: fileName,
            byteSize: data.count
        )
        .flatMap { [weak self] session -> Single<String> in
            guard let self else { return .error(APIError.apiError("Session unavailable")) }
            guard let mediaId = session.resolvedMediaId, !mediaId.isEmpty else {
                return .error(APIError.apiError("mediaId missing from media/uploads"))
            }
            let publicUrlFromCreate = session.resolvedPublicUrl
            guard let uploadUrl = session.resolvedUploadUrl, !uploadUrl.isEmpty else {
                guard let url = publicUrlFromCreate, !url.isEmpty else {
                    return .error(APIError.apiError("publicUrl missing from media/uploads"))
                }
                return .just(url)
            }
            let method = (session.upload?.method ?? "PUT").uppercased()
            let headerContentType = session.resolvedContentType ?? contentType
            return self.putBytesToPresignedURL(
                urlString: uploadUrl,
                method: method,
                contentType: headerContentType,
                body: data
            )
            .flatMap { _ in
                self.completeMediaUpload(
                    id: mediaId,
                    sizeBytes: data.count,
                    width: width,
                    height: height,
                    thumbnail: thumbnail,
                    parts: nil
                )
                .map { completed in
                    completed.resolvedPublicUrl ?? publicUrlFromCreate ?? ""
                }
                .catch { _ in
                    if let url = publicUrlFromCreate, !url.isEmpty {
                        return .just(url)
                    }
                    return .error(APIError.apiError("publicUrl missing from media/uploads"))
                }
            }
            .flatMap { url -> Single<String> in
                guard !url.isEmpty else {
                    return .error(APIError.apiError("publicUrl missing from media/uploads"))
                }
                return .just(url)
            }
        }
    }

    private func putBytesToPresignedURL(
        urlString: String,
        method: String,
        contentType: String,
        body: Data
    ) -> Single<Void> {
        Single.create { single in
            guard let url = URL(string: urlString) else {
                single(.failure(APIError.apiError("Invalid upload URL")))
                return Disposables.create()
            }
            var request = URLRequest(url: url)
            request.httpMethod = method.isEmpty ? "PUT" : method
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            let task = URLSession.shared.dataTask(with: request) { _, response, error in
                if let error {
                    single(.failure(error))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if (200...299).contains(status) {
                    single(.success(()))
                } else {
                    single(.failure(APIError.apiError("Presigned upload failed (\(status))")))
                }
            }
            task.resume()
            return Disposables.create { task.cancel() }
        }
    }

    /// NEW API — GET users/group-candidates?page=&limit=&q=
    /// Paginated candidates for create-group / add-members pickers.
    /// OLD: GET chat/advance-message/chat-eligible-followers (via users/)
    func getChatEligibleFollowers(search: String = "", page: Int = 1, limit: Int = 30) -> Single<PaginatedUsersResponse> {
        getGroupCandidates(search: search, page: page, limit: limit)
    }

    /// NEW API — GET users/group-candidates?page=&limit=&q=
    func getGroupCandidates(search: String = "", page: Int = 1, limit: Int = 30) -> Single<PaginatedUsersResponse> {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var params: [String: Any] = [
            "page": page,
            "limit": limit
        ]
        if !trimmed.isEmpty {
            params["q"] = trimmed
        }
        let apiRequest = ApiRequest(
            method: .get,
            endPoint: .groupCandidates,
            parameters: params,
            encoding: URLEncoding.queryString
        )
        return backendClient.load(request: apiRequest)
            .map { (list: UserListResponse) in
                let users = list.rows ?? []
                return PaginatedUsersResponse(
                    totalResults: list.count ?? users.count,
                    page: page,
                    limit: limit,
                    users: users
                )
            }
    }

    /// NEW API — GET users/{id}
    func getUserById(_ userId: String) -> Single<OtherUserResponse> {
        let apiRequest: ApiRequest = ApiRequest(method: .get, endPoint: .getUserById(userId))
        return backendClient.load(request: apiRequest)
    }

    private static func looksLikeUUID(_ value: String) -> Bool {
        let pattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    func getUsers(searchText: String, page: Int) -> Single<UserListResponse> {
        var params = [String: Any]()
        if !searchText.isEmpty {
            params["q"] = searchText
        }
        params["page"] = page
        params["limit"] = 20
        let apiRequest = ApiRequest(method: .get, endPoint: .searchUser, parameters: params, encoding: URLEncoding.queryString)
        return backendClient.load(request: apiRequest)
    }

    func getProfile(userName: String) -> Single<OtherUserResponse> {
        // NEW API — prefer users/{id}; username resolves via users/?q= then by id.
        // OLD: auth/profile?username=
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.looksLikeUUID(trimmed) {
            return getUserById(trimmed)
        }
        guard !trimmed.isEmpty else {
            return Single.error(APIError.apiError("User not found"))
        }
        return getUsers(searchText: trimmed, page: 1)
            .flatMap { list -> Single<OtherUserResponse> in
                let match = list.rows?.first(where: {
                    ($0.userName ?? "").caseInsensitiveCompare(trimmed) == .orderedSame
                }) ?? list.rows?.first
                guard let id = match?.userId ?? match?.id, !id.isEmpty else {
                    return Single.error(APIError.apiError("User not found"))
                }
                return self.getUserById(id)
            }
    }

    func getConversations(page: Int = 1,
                          limit: Int = 20,
                          search: String = "",
                          showArchived: Bool = false,
                          showPinned: Bool = false,
                          lastSync: String? = nil,
                          before: String? = nil) -> Single<ChatMessageUserData> {
        // FlirtTime — GET /api/v1/chats?page=1&limit=20
        var params = [String: Any]()
        params["page"] = "\(max(page, 1))"
        params["limit"] = "\(limit)"
        if !search.isEmpty { params["search"] = search }
        if showArchived { params["archived"] = "true" }
        if showPinned { params["showPinned"] = "true" }
        if let lastSync = lastSync, !lastSync.isEmpty {
            params["lastSync"] = lastSync
        }
        if let before = before, !before.isEmpty {
            params["cursor"] = before
            params["before"] = before
        }

        let apiRequest = ApiRequest(method: .get, endPoint: .getConversations, parameters: params, encoding: URLEncoding.queryString)
        AppLogger.debug("ChatAPI: GET /api/v1/chats?page=\(page)&limit=\(limit)")
        return backendClient.loadModelData(request: apiRequest)
            .map { (response: ChatListAPIResponse) in response.resolved }
            .catch { _ in
                self.backendClient.loadChatData(request: apiRequest)
            }
    }

    func getConversationMessages(conversationId: String, page: Int = 1, limit: Int = 30) -> Single<ConversationMessagesResponse> {
        // FlirtTime — GET /api/v1/chats/{id}/messages?page=1&limit=30
        var params = [String: Any]()
        params["page"] = page
        params["limit"] = limit
        let apiRequest = ApiRequest(method: .get, endPoint: .getConversationMessages(conversationId), parameters: params, encoding: URLEncoding.queryString)
        AppLogger.debug("ChatAPI: GET /api/v1/chats/\(conversationId)/messages?page=\(page)&limit=\(limit)")
        return backendClient.loadModelData(request: apiRequest)
    }

    func getConversationMessagesAfter(conversationId: String, afterDate: Date, limit: Int = 100) -> Single<ConversationMessagesResponse> {
        var params = [String: Any]()
        params["limit"] = limit
        
        // Format date as ISO8601 with fractional seconds
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let afterString = formatter.string(from: afterDate)
        params["after"] = afterString
        
        let apiRequest = ApiRequest(method: .get, endPoint: .getConversationMessages(conversationId), parameters: params, encoding: URLEncoding.queryString)
        return backendClient.loadModelData(request: apiRequest)
    }

    func getConversationMessagesBefore(conversationId: String, beforeDate: Date, page: Int = 1, limit: Int = 30) -> Single<ConversationMessagesResponse> {
        // FlirtTime — GET /api/v1/chats/{id}/messages?limit=30&before=ISO8601
        var params = [String: Any]()
        params["limit"] = limit
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let beforeString = formatter.string(from: beforeDate)
        params["before"] = beforeString
        if page > 1 { params["page"] = page }

        let apiRequest = ApiRequest(method: .get, endPoint: .getConversationMessages(conversationId), parameters: params, encoding: URLEncoding.queryString)
        AppLogger.debug("ChatAPI: GET /api/v1/chats/\(conversationId)/messages?limit=\(limit)&before=\(beforeString)")
        return backendClient.loadModelData(request: apiRequest)
    }

    /// DELETE `/api/v1/chats/{conversationId}/messages/{messageId}`
    /// Body: `{ "deleteType": "me" | "everyone" }`
    func deleteMessage(
        conversationId: String,
        messageId: String,
        scope: String = "me"
    ) -> Single<DataRequest> {
        let deleteType = (scope == "everyone") ? "everyone" : "me"
        let apiRequest = ApiRequest(
            method: .delete,
            endPoint: .deleteMessage(conversationId: conversationId, messageId: messageId),
            parameters: ["deleteType": deleteType],
            encoding: JSONEncoding.default
        )
        AppLogger.debug(
            "ChatAPI: DELETE /api/v1/chats/\(conversationId)/messages/\(messageId) deleteType=\(deleteType)"
        )
        return backendClient.loadDataRequest(request: apiRequest)
    }

    /// DELETE each message via `/api/v1/chats/{conversationId}/messages/{messageId}`.
    /// Body: `{ "deleteType": "me" | "everyone" }`
    func deleteChatMessages(
        conversationId: String,
        messageIds: [String],
        scope: String = "me"
    ) -> Single<Void> {
        let uniqueIds = Array(Set(
            messageIds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ))
        guard !uniqueIds.isEmpty else { return .just(()) }
        guard !conversationId.isEmpty else {
            return .error(APIError.apiError("Missing conversation id"))
        }

        return uniqueIds.reduce(Single.just(())) { [weak self] partial, messageId in
            partial.flatMap { _ -> Single<Void> in
                guard let self else { return .error(APIError.apiError("Session unavailable")) }
                return self.deleteMessage(
                    conversationId: conversationId,
                    messageId: messageId,
                    scope: scope
                ).map { _ in () }
            }
        }
    }

    /// PATCH `/api/v1/chats/{conversationId}/messages/{messageId}`
    /// Body: `{ "content": "Edited message text here" }`
    func editChatMessage(
        conversationId: String,
        messageId: String,
        content: String
    ) -> Single<ConversationMessage> {
        let apiRequest = ApiRequest(
            method: .patch,
            endPoint: .editChatMessage(conversationId: conversationId, messageId: messageId),
            parameters: ["content": content],
            encoding: JSONEncoding.default
        )
        AppLogger.debug(
            "ChatAPI: PATCH /api/v1/chats/\(conversationId)/messages/\(messageId) content=\(content.prefix(40))"
        )
        return backendClient.loadChatData(request: apiRequest)
            .map { (data: SendChatMessageAPIData) -> ConversationMessage in
                guard let message = data.message else {
                    throw APIError.apiError("editChatMessage: missing message in response")
                }
                return message
            }
            .catch { _ in
                self.decodeSentMessage(request: apiRequest)
            }
    }

    /// POST `/api/v1/chats/{conversationId}/messages/{messageId}/reply`
    /// Body: `{ "content": "...", "messageType": "text" }`
    func replyChatMessage(
        conversationId: String,
        messageId: String,
        content: String,
        messageType: String = "text",
        clientMessageId: String? = nil
    ) -> Single<ConversationMessage> {
        var params: [String: Any] = [
            "content": content,
            "messageType": messageType
        ]
        if let clientMessageId, !clientMessageId.isEmpty {
            params["clientMessageId"] = clientMessageId
        }
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .replyChatMessage(conversationId: conversationId, messageId: messageId),
            parameters: params,
            encoding: JSONEncoding.default
        )
        AppLogger.debug(
            "ChatAPI: POST /api/v1/chats/\(conversationId)/messages/\(messageId)/reply type=\(messageType)"
        )
        return backendClient.loadChatData(request: apiRequest)
            .map { (data: SendChatMessageAPIData) -> ConversationMessage in
                guard let message = data.message else {
                    throw APIError.apiError("replyChatMessage: missing message in response")
                }
                return message
            }
            .catch { _ in
                self.decodeSentMessage(request: apiRequest)
            }
    }

    /// POST `/api/v1/chats/messages/forward`
    /// Body: `{ messageIds, recipientIds, clientMessageId }`
    func forwardChatMessages(
        messageIds: [String],
        recipientIds: [String],
        clientMessageId: String
    ) -> Single<[ConversationMessage]> {
        let ids = Array(Set(messageIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        let peers = Array(Set(recipientIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        guard !ids.isEmpty else {
            return .error(APIError.apiError("Missing message ids"))
        }
        guard !peers.isEmpty else {
            return .error(APIError.apiError("Missing recipient ids"))
        }

        var params: [String: Any] = [
            "messageIds": ids,
            "recipientIds": peers
        ]
        let requestId = clientMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requestId.isEmpty {
            params["clientMessageId"] = requestId
        }

        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .forwardChatMessages,
            parameters: params,
            encoding: JSONEncoding.default
        )
        AppLogger.debug(
            "ChatAPI: POST /api/v1/chats/messages/forward messages=\(ids.count) recipients=\(peers.count)"
        )
        return backendClient.loadDataRequest(request: apiRequest)
            .map { response -> [ConversationMessage] in
                let statusCode = response.response?.statusCode ?? 0
                guard let data = response.data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw APIError.apiError("forwardChatMessages: empty response")
                }
                let explicitFailure = (json["success"] != nil || json["status"] != nil)
                    && SocketAckParser.isSuccess(json) == false
                if explicitFailure || (statusCode != 0 && !(200..<300).contains(statusCode)) {
                    let message = (json["message"] as? String)
                        ?? ((json["error"] as? [String: Any])?["message"] as? String)
                        ?? "Failed to forward message"
                    throw APIError.apiError(message)
                }
                return ForwardChatMessagesAPIData.messages(from: json)
            }
    }

    /// GET `/api/v1/chats/forward/recipients?page=1&limit=20&search=`
    func getForwardRecipients(
        search: String = "",
        page: Int = 1,
        limit: Int = ChatConstants.Pagination.forwardConversationsPageSize
    ) -> Single<ForwardRecipientsAPIData> {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var params: [String: Any] = [
            "page": max(page, 1),
            "limit": limit
        ]
        if !trimmed.isEmpty {
            params["search"] = trimmed
        }
        let apiRequest = ApiRequest(
            method: .get,
            endPoint: .getForwardRecipients,
            parameters: params,
            encoding: URLEncoding.queryString
        )
        AppLogger.debug(
            "ChatAPI: GET /api/v1/chats/forward/recipients page=\(page) limit=\(limit) search=\(trimmed)"
        )
        return backendClient.loadModelData(request: apiRequest)
            .map { (response: ForwardRecipientsAPIResponse) in response.resolved }
            .catch { _ in
                self.backendClient.load(request: apiRequest)
            }
    }

    /// NEW API — POST chat/messages/{id}/translate
    /// Body: `{ targetLanguage: String }`
    func translateChatMessage(
        messageId: String,
        targetLanguage: String
    ) -> Single<TranslateChatMessageAPIData> {
        let params: [String: Any] = ["targetLanguage": targetLanguage]
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .translateChatMessage(messageId),
            parameters: params,
            encoding: JSONEncoding.default
        )
        return backendClient.loadChatData(request: apiRequest)
    }

    /// POST `/api/v1/chats/{conversationId}/messages/{messageId}/reactions`
    /// Body: `{ emoji: String }` (add / change / toggle — same emoji again removes)
    func reactChatMessage(
        conversationId: String,
        messageId: String,
        emoji: String
    ) -> Single<ConversationMessage> {
        let params: [String: Any] = ["emoji": emoji]
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .reactChatMessage(conversationId: conversationId, messageId: messageId),
            parameters: params,
            encoding: JSONEncoding.default
        )
        return backendClient.loadDataRequest(request: apiRequest)
            .map { response -> ConversationMessage in
                guard let data = response.data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw APIError.apiError("reactChatMessage: empty response")
                }
                let payload = (json["data"] as? [String: Any]) ?? json
                var messageDict = (payload["message"] as? [String: Any]) ?? payload
                if ((messageDict["id"] as? String) ?? "").isEmpty {
                    messageDict["id"] = messageId
                }
                if messageDict["reactions"] == nil, let reactions = payload["reactions"] {
                    messageDict["reactions"] = reactions
                }

                // Sparse reaction payloads → reaction-only update (stable id, no empty cell)
                let content = (messageDict["content"] as? String) ?? (messageDict["body"] as? String) ?? ""
                let hasBody = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasMedia = (messageDict["media"] as? [Any])?.isEmpty == false
                    || (messageDict["medias"] as? [Any])?.isEmpty == false
                let hasPoll = messageDict["poll"] != nil
                if !hasBody && !hasMedia && !hasPoll {
                    if let reactionOnly = ConversationMessage.reactionUpdate(from: json, fallbackMessageId: messageId)
                        ?? ConversationMessage.reactionUpdate(from: messageDict, fallbackMessageId: messageId) {
                        return reactionOnly
                    }
                }

                guard let message = ConversationMessage.fromDictionary(messageDict) else {
                    throw APIError.apiError("reactChatMessage: failed to decode message")
                }
                return message
            }
    }

    /// FlirtTime — POST /api/v1/chats/{id}/messages
    /// Body: `{ content, messageType, metadata? }`
    ///   text     → `{ "content": "Hello", "messageType": "text" }`
    ///   image    → `{ "messageType": "image", "content": "<url>", "metadata": { "source": "photo" } }`
    ///   audio    → `{ "messageType": "audio", "content": "<url>" }`
    ///   location → `{ "messageType": "location", "metadata": { latitude, longitude, name } }`
    func sendChatMessage(
        conversationId: String,
        body: String? = nil,
        type: String? = nil,
        mediaIds: [String]? = nil,
        location: [String: Any]? = nil,
        poll: [String: Any]? = nil,
        postId: String? = nil,
        clientMessageId: String? = nil,
        replyToId: String? = nil,
        contentURL: String? = nil,
        metadata: [String: Any]? = nil
    ) -> Single<ConversationMessage> {
        let messageType = (type?.isEmpty == false ? type : "text") ?? "text"
        var params: [String: Any] = [
            "type": messageType,
            "messageType": messageType
        ]
        var meta = metadata ?? [:]

        // OneVibe: image messages are created with `mediaIds`, not a re-uploaded file.
        if let mediaIds, !mediaIds.isEmpty { params["mediaIds"] = mediaIds }

        let resolvedContent = [contentURL, body]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        switch messageType.lowercased() {
        case "image":
            if let resolvedContent,
               resolvedContent.lowercased().hasPrefix("http://")
                || resolvedContent.lowercased().hasPrefix("https://") {
                params["content"] = resolvedContent
            }
            if meta["source"] == nil { meta["source"] = "photo" }
            if !meta.isEmpty { params["metadata"] = meta }
        case "audio", "voice":
            if let resolvedContent { params["content"] = resolvedContent }
            if !meta.isEmpty { params["metadata"] = meta }
        case "location":
            if let location {
                if let lat = location["latitude"] ?? location["lat"] { meta["latitude"] = lat }
                if let lng = location["longitude"] ?? location["lng"] { meta["longitude"] = lng }
                if let name = location["name"] { meta["name"] = name }
                if let address = location["address"] { meta["address"] = address }
                if meta["name"] == nil, let address = location["address"] { meta["name"] = address }
            }
            params["metadata"] = meta
        case "contact":
            if let resolvedContent { params["content"] = resolvedContent }
            params["metadata"] = meta
        default:
            if let resolvedContent { params["content"] = resolvedContent }
            if !meta.isEmpty { params["metadata"] = meta }
        }

        if let clientMessageId, !clientMessageId.isEmpty { params["clientMessageId"] = clientMessageId }
        if let replyToId, !replyToId.isEmpty { params["replyToId"] = replyToId }
        if let poll { params["poll"] = poll }
        if let postId, !postId.isEmpty { params["postId"] = postId }

        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .sendChatMessage(conversationId),
            parameters: params,
            encoding: JSONEncoding.default
        )
        return backendClient.loadChatData(request: apiRequest)
            .map { (data: SendChatMessageAPIData) -> ConversationMessage in
                guard let message = data.message else {
                    throw APIError.apiError("sendChatMessage: missing message in response")
                }
                return message
            }
            .catch { _ in
                self.decodeSentMessage(request: apiRequest)
            }
    }

    /// FlirtTime — POST `/api/v1/chats/{id}/messages` as `multipart/form-data`
    /// with `file` / `image`, `messageType`, optional `caption`, and S3 `key`.
    func sendChatMessageMultipart(
        conversationId: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        messageType: String,
        caption: String? = nil,
        clientMessageId: String? = nil,
        recipientIds: [String]? = nil,
        extraFields: [String: Any] = [:]
    ) -> Single<ConversationMessage> {
        var params: [String: Any] = [
            "type": messageType,
            "messageType": messageType
        ]
        if let caption, !caption.isEmpty { params["caption"] = caption }
        if let clientMessageId, !clientMessageId.isEmpty { params["clientMessageId"] = clientMessageId }
        if let recipientIds {
            let peers = recipientIds.filter { !$0.isEmpty }
            if peers.count == 1 { params["recipientId"] = peers[0] }
            if !peers.isEmpty { params["recipientIds"] = peers.joined(separator: ",") }
        }
        for (key, value) in extraFields {
            params[key] = value
        }
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .sendChatMessage(conversationId),
            parameters: params
        )
        AppLogger.debug("ChatAPI: POST /api/v1/chats/\(conversationId)/messages multipart type=\(messageType) file=\(fileName)")
        return backendClient.uploadMultipart(
            request: apiRequest,
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            fileField: "file"
        )
        .map { data -> ConversationMessage in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = Self.conversationMessage(fromSendJSON: json) else {
                throw APIError.apiError("sendChatMessage multipart: missing message in response")
            }
            return message
        }
    }

    /// FlirtTime — POST `/api/v1/chat/messages` for a new 1:1 or broadcast.
    func sendDirectChatMessage(
        recipientIds: [String],
        type: String = "text",
        content: String? = nil,
        location: [String: Any]? = nil,
        metadata: [String: Any]? = nil,
        clientMessageId: String? = nil
    ) -> Single<ConversationMessage> {
        let peers = recipientIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var params: [String: Any] = ["type": type, "messageType": type]
        if peers.count == 1 {
            params["recipientId"] = peers[0]
        }
        if !peers.isEmpty {
            params["recipientIds"] = peers
        }
        if let content, !content.isEmpty { params["content"] = content }
        var meta = metadata ?? [:]
        if type.lowercased() == "location", let location {
            if let lat = location["latitude"] ?? location["lat"] { meta["latitude"] = lat }
            if let lng = location["longitude"] ?? location["lng"] { meta["longitude"] = lng }
            if let name = location["name"] { meta["name"] = name }
            if let address = location["address"] { meta["address"] = address }
            if meta["name"] == nil, let address = location["address"] { meta["name"] = address }
        }
        if !meta.isEmpty { params["metadata"] = meta }
        if let clientMessageId, !clientMessageId.isEmpty { params["clientMessageId"] = clientMessageId }

        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .sendDirectChatMessage,
            parameters: params,
            encoding: JSONEncoding.default
        )
        AppLogger.debug("ChatAPI: POST /api/v1/chat/messages type=\(type) recipients=\(peers.count)")
        return decodeSentMessage(request: apiRequest)
    }

    private func decodeSentMessage(request: ApiRequest) -> Single<ConversationMessage> {
        backendClient.loadDataRequest(request: request)
            .map { response -> ConversationMessage in
                guard let data = response.data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw APIError.apiError("sendChatMessage: empty response")
                }
                guard let message = Self.conversationMessage(fromSendJSON: json) else {
                    throw APIError.apiError("sendChatMessage: missing message in response")
                }
                return message
            }
    }

    private static func conversationMessage(fromSendJSON json: [String: Any]) -> ConversationMessage? {
        let payload = (json["data"] as? [String: Any]) ?? json
        if let messageDict = payload["message"] as? [String: Any] {
            return ConversationMessage.fromDictionary(messageDict)
        }
        if let results = payload["results"] as? [[String: Any]] {
            for row in results {
                if let status = row["status"] as? String, status.lowercased() != "success" { continue }
                if var messageDict = row["message"] as? [String: Any] {
                    if (messageDict["conversationId"] as? String)?.isEmpty != false,
                       let cid = row["conversationId"] as? String {
                        messageDict["conversationId"] = cid
                    }
                    if let message = ConversationMessage.fromDictionary(messageDict) {
                        return message
                    }
                }
            }
        }
        return ConversationMessage.fromDictionary(payload)
    }

    /// FlirtTime — POST `/api/v1/chats/{id}/messages/{messageId}/pin` `{ isPinned, scope? }`
    func pinChatMessage(
        conversationId: String,
        messageId: String,
        pinned: Bool,
        pinDuration: String? = nil,
        scope: String? = nil
    ) -> Single<ConversationMessage> {
        var params: [String: Any] = [
            "isPinned": pinned,
            "pinned": pinned
        ]
        if pinned {
            params["scope"] = (scope?.isEmpty == false ? scope : "me") ?? "me"
            if let pinDuration, !pinDuration.isEmpty {
                params["pinDuration"] = pinDuration
            }
        }
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .pinConversationMessage(conversationId, messageId),
            parameters: params,
            encoding: JSONEncoding.default
        )
        AppLogger.debug("ChatAPI: POST /api/v1/chats/\(conversationId)/messages/\(messageId)/pin isPinned=\(pinned)")
        return backendClient.loadChatData(request: apiRequest)
            .map { (data: SendChatMessageAPIData) -> ConversationMessage in
                guard let message = data.message else {
                    throw APIError.apiError("pinChatMessage: missing message in response")
                }
                return message
            }
            .catch { _ -> Single<ConversationMessage> in
                self.decodeSentMessage(request: apiRequest)
                    .catch { _ -> Single<ConversationMessage> in
                        if let stub = ConversationMessage.fromDictionary([
                            "id": messageId,
                            "conversationId": conversationId,
                            "isPinned": pinned,
                            "messageType": "text",
                            "content": ""
                        ]) {
                            return .just(stub)
                        }
                        return .error(APIError.apiError("pinChatMessage: empty response"))
                    }
            }
    }

    /// FlirtTime — GET `/api/v1/chats/{id}/messages/pinned?limit=30`
    func fetchPinnedMessages(conversationId: String, limit: Int = 30) -> Single<[ConversationMessage]> {
        let params: [String: Any] = ["limit": limit]
        let apiRequest = ApiRequest(
            method: .get,
            endPoint: .getPinnedMessages(conversationId),
            parameters: params,
            encoding: URLEncoding.queryString
        )
        AppLogger.debug("ChatAPI: GET /api/v1/chats/\(conversationId)/messages/pinned?limit=\(limit)")
        return backendClient.loadChatData(request: apiRequest)
            .map { (data: PinnedMessagesAPIData) in data.messages }
            .catch { _ in
                self.backendClient.loadModelData(request: apiRequest)
                    .map { (response: ConversationMessagesResponse) in
                        let page = response.data.data
                        if !page.messages.isEmpty { return page.messages }
                        return page.pinnedMessages ?? []
                    }
            }
    }

    /// Convenience — first pinned message from GET `/messages/pinned`.
    func fetchPinnedMessage(conversationId: String) -> Single<ConversationMessage?> {
        fetchPinnedMessages(conversationId: conversationId, limit: 30)
            .map { $0.first }
    }

    /// FlirtTime — POST /api/v1/chats/{id}/read
    func markConversationReadREST(conversationId: String, messageId: String? = nil) -> Single<ChatConversationReadAPIData> {
        var params: [String: Any] = [:]
        if let messageId, !messageId.isEmpty { params["messageId"] = messageId }
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .markConversationRead(conversationId),
            parameters: params.isEmpty ? nil : params,
            encoding: JSONEncoding.default
        )
        return backendClient.loadChatData(request: apiRequest)
            .catch { _ in
                Single.just(ChatConversationReadAPIData(conversationId: conversationId, unreadCount: 0))
            }
    }

    /// PATCH `/api/v1/chats/{id}/pin` `{ isPinned: true|false }`
    func pinConversation(conversationId: String, isPinned: Bool) -> Single<UpdateConversationSettingsAPIData> {
        let params: [String: Any] = ["isPinned": isPinned]
        let apiRequest = ApiRequest(
            method: .patch,
            endPoint: .pinConversation(conversationId),
            parameters: params,
            encoding: JSONEncoding.default
        )
        AppLogger.debug("ChatAPI: PATCH /api/v1/chats/\(conversationId)/pin isPinned=\(isPinned)")
        return backendClient.loadChatData(request: apiRequest)
    }

    /// PATCH `{ isArchived: true|false }` — documented path first, then `/api/v1/chats/{id}/archive`.
    func archiveConversation(conversationId: String, isArchived: Bool) -> Single<UpdateConversationSettingsAPIData> {
        archiveConversationRequest(
            conversationId: conversationId,
            isArchived: isArchived,
            endPoint: .archiveConversationAlt(conversationId)
        )
        .catch { error in
            AppLogger.debug("ChatAPI: archive /chats path failed (\(error.localizedDescription)) — retry documented conversations path")
            return self.archiveConversationRequest(
                conversationId: conversationId,
                isArchived: isArchived,
                endPoint: .archiveConversation(conversationId)
            )
        }
    }

    private func archiveConversationRequest(
        conversationId: String,
        isArchived: Bool,
        endPoint: EndPoint
    ) -> Single<UpdateConversationSettingsAPIData> {
        let params: [String: Any] = ["isArchived": isArchived]
        let apiRequest = ApiRequest(
            method: .patch,
            endPoint: endPoint,
            parameters: params,
            encoding: JSONEncoding.default
        )
        AppLogger.debug("ChatAPI: PATCH \(endPoint.description) isArchived=\(isArchived)")
        return backendClient.loadChatData(request: apiRequest)
    }

    /// NEW API — POST chat/conversations/{id}/unread
    func markConversationUnreadREST(conversationId: String) -> Single<ChatConversationReadAPIData> {
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .markConversationUnread(conversationId),
            parameters: [:],
            encoding: JSONEncoding.default
        )
        return backendClient.loadChatData(request: apiRequest)
    }

    /// FlirtTime — POST /api/v1/chats/{id}/delivery
    func markConversationDelivered(conversationId: String, messageId: String? = nil) -> Single<DataRequest> {
        var params: [String: Any] = [:]
        if let messageId, !messageId.isEmpty { params["messageId"] = messageId }
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .markConversationDelivered(conversationId),
            parameters: params,
            encoding: JSONEncoding.default
        )
        return backendClient.loadDataRequest(request: apiRequest)
    }

    /// NEW API — PATCH chat/conversations/{id}/settings
    /// Body (FE): `{ isMuted?, isPinned?, isArchived?, labelText?, labelColor? }`
    func updateConversationSettings(
        conversationId: String,
        settings: [String: Any]
    ) -> Single<UpdateConversationSettingsAPIData> {
        let apiRequest = ApiRequest(
            method: .patch,
            endPoint: .updateConversationSettings(conversationId),
            parameters: settings,
            encoding: JSONEncoding.default
        )
        return backendClient.loadDataRequest(request: apiRequest)
            .map { response -> UpdateConversationSettingsAPIData in
                guard let data = response.data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return UpdateConversationSettingsAPIData(settings: nil)
                }
                let payload = (json["data"] as? [String: Any]) ?? json
                guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                      let decoded = try? JSONDecoder().decode(UpdateConversationSettingsAPIData.self, from: payloadData) else {
                    return UpdateConversationSettingsAPIData(settings: nil)
                }
                return decoded
            }
    }

    /// NEW API — POST chat/delivered/sync (FE syncInboxDelivered)
    func syncInboxDelivered() -> Single<ChatDeliveredSyncAPIData> {
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .syncInboxDelivered,
            parameters: [:],
            encoding: JSONEncoding.default
        )
        return backendClient.loadChatData(request: apiRequest)
    }

    /// DELETE `/api/v1/chats/{id}` with `{ "deleteType": "me" }`.
    func deleteChat(id: String) -> Single<DataRequest> {
        let apiRequest = ApiRequest(
            method: .delete,
            endPoint: .deleteChatConversation(id),
            parameters: ["deleteType": "me"],
            encoding: JSONEncoding.default
        )
        return backendClient.loadDataRequest(request: apiRequest)
    }

    /// DELETE `/api/v1/chats/{id}`
    /// Body: `{ "deleteType": "me" | "everyone" }`
    func deleteChatConversation(id: String, scope: String = "me") -> Single<Void> {
        let deleteType = (scope == "everyone") ? "everyone" : "me"
        let apiRequest = ApiRequest(
            method: .delete,
            endPoint: .deleteChatConversation(id),
            parameters: ["deleteType": deleteType],
            encoding: JSONEncoding.default
        )
        AppLogger.debug("ChatAPI: DELETE /api/v1/chats/\(id) deleteType=\(deleteType)")
        return backendClient.loadDataRequest(request: apiRequest).map { _ in () }
    }

    /// DELETE each conversation via `/api/v1/chats/{id}` with `{ "deleteType": ... }`.
    func deleteChatConversations(ids: [String], scope: String = "me") -> Single<Void> {
        let uniqueIds = Array(Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        guard !uniqueIds.isEmpty else { return .just(()) }

        return uniqueIds.reduce(Single.just(())) { [weak self] partial, conversationId in
            partial.flatMap { _ -> Single<Void> in
                guard let self else { return .error(APIError.apiError("Session unavailable")) }
                return self.deleteChatConversation(id: conversationId, scope: scope)
            }
        }
    }

    /// FlirtTime — POST /api/v1/chats `{ recipientId }`
    func createChat(participants: [String], isGroup: Bool, title: String, groupAvatar: String) -> Single<[String: Any]> {
        return createChatConversation(
            participantIds: participants,
            type: isGroup ? "group" : "direct",
            title: title.isEmpty ? nil : title,
            avatarPath: groupAvatar.isEmpty ? nil : groupAvatar
        )
    }

    /// GET `/api/v1/calls?page=1&limit=20`
    func getCallHistory(page: Int = 1, limit: Int = 20) -> Single<CallHistoryPage> {
        let safePage = max(page, 1)
        let safeLimit = max(limit, 1)
        let params: [String: Any] = [
            "page": "\(safePage)",
            "limit": "\(safeLimit)"
        ]
        let apiRequest = ApiRequest(
            method: .get,
            endPoint: .getCallHistory,
            parameters: params,
            encoding: URLEncoding.queryString
        )
        AppLogger.debug("ChatAPI: GET /api/v1/calls?page=\(safePage)&limit=\(safeLimit)")
        return backendClient.loadDataRequest(request: apiRequest).map { response in
            Self.parseCallHistory(data: response.data, page: safePage, limit: safeLimit)
        }
    }

    /// DELETE `/api/v1/calls/{id}`
    func deleteCallHistoryItem(id: String) -> Single<Void> {
        let apiRequest = ApiRequest(method: .delete, endPoint: .deleteCallHistoryItem(id))
        AppLogger.debug("ChatAPI: DELETE /api/v1/calls/\(id)")
        return backendClient.loadDataRequest(request: apiRequest).map { _ in () }
    }

    /// DELETE `/api/v1/calls`
    func deleteAllCallHistory() -> Single<Void> {
        let apiRequest = ApiRequest(method: .delete, endPoint: .deleteAllCallHistory)
        AppLogger.debug("ChatAPI: DELETE /api/v1/calls")
        return backendClient.loadDataRequest(request: apiRequest).map { _ in () }
    }

    private static func parseCallHistory(data: Data?, page: Int, limit: Int) -> CallHistoryPage {
        guard let data, !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return CallHistoryPage(calls: [], page: page, hasMore: false)
        }

        let root = json as? [String: Any]
        let payload: Any
        if let dataObject = root?["data"] {
            payload = dataObject
        } else {
            payload = json
        }

        var rawItems: [[String: Any]] = []
        var pagination: [String: Any] = [:]
        if let array = payload as? [[String: Any]] {
            rawItems = array
        } else if let dict = payload as? [String: Any] {
            pagination = dict
            let candidates = [dict["calls"], dict["items"], dict["history"], dict["results"], dict["rows"]]
            for candidate in candidates {
                if let array = candidate as? [[String: Any]] {
                    rawItems = array
                    break
                }
            }
            if let nested = dict["pagination"] as? [String: Any] {
                pagination.merge(nested) { current, _ in current }
            }
        }

        let decoder = JSONDecoder()
        let calls: [AgoraCallDto] = rawItems.compactMap { item in
            guard let itemData = try? JSONSerialization.data(withJSONObject: item) else { return nil }
            return try? decoder.decode(AgoraCallDto.self, from: itemData)
        }.filter { !$0.id.isEmpty }

        let currentPage = intValue(pagination["page"]) ?? page
        let pageSize = intValue(pagination["limit"]) ?? intValue(pagination["pageSize"]) ?? limit
        let total = intValue(pagination["total"])
        let totalPages = intValue(pagination["totalPages"])
        let hasMore: Bool
        if let flag = pagination["hasMore"] as? Bool {
            hasMore = flag
        } else if let totalPages {
            hasMore = currentPage < totalPages
        } else if let total, pageSize > 0 {
            hasMore = currentPage * pageSize < total
        } else {
            hasMore = rawItems.count >= pageSize
        }

        return CallHistoryPage(calls: calls, page: currentPage, hasMore: hasMore)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    /// Routes by media type: audio → `POST /api/v1/calls`, video → `POST /api/v1/calls/video/initiate`.
    func startAgoraCall(conversationId: String, type: String, calleeId: String? = nil) -> Single<[String: Any]> {
        let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        AppLogger.debug("startAgoraCall type=\(normalized) conversationId=\(conversationId)")
        if normalized == "audio" || normalized == "voice" {
            return startUnifiedCall(conversationId: conversationId, type: "audio", calleeId: calleeId)
        }
        return initiateVideoCall(calleeId: calleeId ?? "", conversationId: conversationId)
    }

    /// GET `/api/v1/calls/{id}` with video-active fallback.
    func fetchAgoraCall(callId: String) -> Single<[String: Any]> {
        getUnifiedCall(callId: callId)
            .catch { error in
                AppLogger.debug("ChatAPI: GET /api/v1/calls/\(callId) failed (\(error.localizedDescription)) — fallback video/active")
                return self.getActiveVideoCall().map { dict in
                    let id = (dict["id"] as? String) ?? (dict["callId"] as? String) ?? ""
                    if id.isEmpty || id == callId { return dict }
                    if let call = dict["call"] as? [String: Any] {
                        let nestedId = (call["id"] as? String) ?? (call["callId"] as? String) ?? ""
                        if nestedId == callId { return dict }
                    }
                    return dict
                }
            }
    }

    /// POST `/api/v1/calls` `{ conversationId, type }` — voice uses `type=audio`.
    func startUnifiedCall(conversationId: String, type: String, calleeId: String? = nil) -> Single<[String: Any]> {
        var params: [String: Any] = [
            "conversationId": conversationId,
            "type": type
        ]
        if let calleeId {
            let trimmed = calleeId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                params["calleeId"] = trimmed
            }
        }
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .startUnifiedCall,
            parameters: params,
            encoding: JSONEncoding.default
        )
        AppLogger.debug("ChatAPI: POST /api/v1/calls conversationId=\(conversationId) type=\(type)")
        return unwrapJSON(apiRequest)
    }

    func acceptUnifiedCall(callId: String) -> Single<[String: Any]> {
        let apiRequest = ApiRequest(method: .post, endPoint: .acceptUnifiedCall(callId))
        AppLogger.debug("ChatAPI: POST /api/v1/calls/\(callId)/accept")
        return unwrapJSON(apiRequest)
    }

    func declineUnifiedCall(callId: String) -> Single<[String: Any]> {
        let apiRequest = ApiRequest(method: .post, endPoint: .declineUnifiedCall(callId))
        AppLogger.debug("ChatAPI: POST /api/v1/calls/\(callId)/decline")
        return unwrapJSON(apiRequest)
    }

    func endUnifiedCall(callId: String) -> Single<[String: Any]> {
        let apiRequest = ApiRequest(method: .post, endPoint: .endUnifiedCall(callId))
        AppLogger.debug("ChatAPI: POST /api/v1/calls/\(callId)/end")
        return unwrapJSON(apiRequest)
    }

    func leaveUnifiedCall(callId: String) -> Single<[String: Any]> {
        let apiRequest = ApiRequest(method: .post, endPoint: .leaveUnifiedCall(callId))
        AppLogger.debug("ChatAPI: POST /api/v1/calls/\(callId)/leave")
        return unwrapJSON(apiRequest)
    }

    func getUnifiedCall(callId: String) -> Single<[String: Any]> {
        let apiRequest = ApiRequest(method: .get, endPoint: .getUnifiedCall(callId))
        AppLogger.debug("ChatAPI: GET /api/v1/calls/\(callId)")
        return unwrapJSON(apiRequest)
    }

    func initiateVideoCall(calleeId: String, conversationId: String) -> Single<[String: Any]> {
        let params: [String: Any] = [
            "calleeId": calleeId,
            "conversationId": conversationId
        ]
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .initiateVideoCall,
            parameters: params,
            encoding: JSONEncoding.default
        )
        AppLogger.debug("ChatAPI: POST /api/v1/calls/video/initiate calleeId=\(calleeId) conversationId=\(conversationId)")
        return unwrapJSON(apiRequest)
    }

    func acceptVideoCall(callId: String) -> Single<[String: Any]> {
        let apiRequest = ApiRequest(method: .post, endPoint: .acceptVideoCall(callId))
        AppLogger.debug("ChatAPI: POST /api/v1/calls/video/\(callId)/accept")
        return unwrapJSON(apiRequest)
    }

    func rejectVideoCall(callId: String) -> Single<[String: Any]> {
        let apiRequest = ApiRequest(method: .post, endPoint: .rejectVideoCall(callId))
        AppLogger.debug("ChatAPI: POST /api/v1/calls/video/\(callId)/reject")
        return unwrapJSON(apiRequest)
    }

    func endVideoCall(callId: String) -> Single<[String: Any]> {
        let apiRequest = ApiRequest(method: .post, endPoint: .endVideoCall(callId))
        AppLogger.debug("ChatAPI: POST /api/v1/calls/video/\(callId)/end")
        return unwrapJSON(apiRequest)
    }

    func getActiveVideoCall() -> Single<[String: Any]> {
        let apiRequest = ApiRequest(method: .get, endPoint: .getActiveVideoCall)
        AppLogger.debug("ChatAPI: GET /api/v1/calls/video/active")
        return unwrapJSON(apiRequest)
    }

    private func unwrapJSON(_ apiRequest: ApiRequest) -> Single<[String: Any]> {
        backendClient.loadDataRequest(request: apiRequest).map { response -> [String: Any] in
            guard let data = response.data else { return [:] }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            if let dataObj = json["data"] as? [String: Any] {
                if let session = dataObj["session"] as? [String: Any] {
                    return session
                }
                return dataObj
            }
            if let session = json["session"] as? [String: Any] {
                return session
            }
            return json
        }
    }

    /// FlirtTime — POST /api/v1/chats `{ recipientId }`
    func createChatConversation(
        participantIds: [String],
        type: String = "direct",
        title: String? = nil,
        avatarPath: String? = nil
    ) -> Single<[String: Any]> {
        let recipientId = participantIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        return createChat(recipientId: recipientId)
    }

    /// FlirtTime — POST /api/v1/chats `{ "recipientId": "<userId>" }`
    func createChat(recipientId: String) -> Single<[String: Any]> {
        let params: [String: Any] = ["recipientId": recipientId]
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .createChatConversation,
            parameters: params,
            encoding: JSONEncoding.default
        )
        AppLogger.debug("ChatAPI: POST /api/v1/chats recipientId=\(recipientId)")
        return backendClient.loadDataRequest(request: apiRequest).map { response -> [String: Any] in
            guard let data = response.data else { return [:] }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let dataObj = json["data"] as? [String: Any] {
                        if let conversation = dataObj["conversation"] as? [String: Any] {
                            return conversation
                        }
                        if let chat = dataObj["chat"] as? [String: Any] {
                            return chat
                        }
                        return dataObj
                    }

                    if let dataArray = json["data"] as? [[String: Any]],
                       let firstObj = dataArray.first {
                        return firstObj
                    }
                    if json["id"] != nil || json["conversationId"] != nil {
                        return json
                    }
                }
            } catch {
                AppLogger.debug("Error parsing POST /api/v1/chats response: \(error)")
            }
            return [:]
        }
    }

    /// FlirtTime — GET /api/v1/chats/{id} (header, peer, shared interests)
    func getConversationDetail(conversationId: String) -> Single<ChatMessageRow> {
        let apiRequest = ApiRequest(method: .get, endPoint: .getGroupDetails(conversationId))
        // Prefer full-body decode (handles success/data/conversation nesting)
        return backendClient.loadModelData(request: apiRequest)
            .map { (response: ConversationDetailAPIResponse) -> ChatMessageRow in
                guard let row = response.resolvedConversation else {
                    throw APIError.apiError("getConversationDetail: missing conversation")
                }
                return row
            }
            .catch { _ in
                // FE path: unwrap `{ success, data }` then `{ conversation }` or bare conversation
                self.backendClient.loadChatData(request: apiRequest)
                    .map { (payload: ConversationDetailPayload) in payload.conversation }
            }
    }

    /// NEW API — GET chat/conversations/{id}/members (FE fetchConversationMembers)
    func getConversationMembers(conversationId: String) -> Single<[Participant]> {
        let apiRequest = ApiRequest(method: .get, endPoint: .getGroupMembers(conversationId))
        return backendClient.loadChatData(request: apiRequest)
            .map { (payload: ConversationMembersPayload) in payload.members ?? [] }
            .catch { _ in
                self.backendClient.loadModelData(request: apiRequest)
                    .map { (envelope: ConversationMembersEnvelope) in envelope.resolvedMembers }
                    .catchAndReturn([])
            }
    }

    /// OLD — POST chat/media/generate-presigned-url; NEW Media docs use media/uploads / media/upload-url
    func generateChatPresignedURL(mimeType: String,
                                  fileName: String,
                                  folderType: String,
                                  completion: @escaping (Result<PresignedData, Error>) -> Void) {
        
        guard let currentBaseURL = ChatConfig.baseURL,
              let apiURL = URL(string: EndPoint.chatPresignedURL.description, relativeTo: currentBaseURL) else {
            let err = NSError(domain: "", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Chat base URL not configured"
            ])
            completion(.failure(err))
            return
        }

        let token = ChatAuthStore.shared.accessToken
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(token)",
            "Accept-Language": UIApplication.getLanguageCode()
        ]
        let parameters: [String: Any] = [
            "mimeType": mimeType,
            "fileName": fileName,
            "folderType": folderType
        ]
        
        print("Requesting chat presigned URL → mimeType:", mimeType, "fileName:", fileName, "folderType:", folderType)
        
        APILogger.session.request(apiURL,
                   method: .post,
                   parameters: parameters,
                   encoding: JSONEncoding.default,
                   headers: headers)
        .responseData { response in
            if let httpStatus = response.response?.statusCode {
                print("Chat presigned URL HTTP status: \(httpStatus)")
            }
            switch response.result {
            case .success(let rawData):
                if let jsonString = String(data: rawData, encoding: .utf8) {
                    print("Chat presigned URL raw response:", jsonString)
                }
                guard let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
                      let dataDict = json["data"] as? [String: Any] else {
                    let err = NSError(domain: "", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Chat presigned URL: unexpected response structure"
                    ])
                    print("Chat presigned URL: could not parse response data dict")
                    completion(.failure(err))
                    return
                }
                
                let uploadUrl = dataDict["url"] as? String
                let key = dataDict["key"] as? String
                let uploadId = dataDict["uploadId"] as? String
                let presignedData = PresignedData(key: key, uploadUrl: uploadUrl, uploadId: uploadId, message: nil)
                completion(.success(presignedData))
            case .failure(let error):
                print("Chat presigned URL request failed:", error.localizedDescription)
                completion(.failure(error))
            }
        }
    }
}
