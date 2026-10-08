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

    func reportuser(userID : String, reason : String) -> Single<DataRequest>{
        var params = [String:Any]()
        params["user_id"] = userID
        params["reason"] = reason
        let apiRequest: ApiRequest = ApiRequest(method: .post, endPoint: .reportUser, parameters: params)
        return backendClient.loadDataRequest(request: apiRequest)
    }

    func checkUserBlocked(id: String, userId:String) -> Single<checkBlockedUserodel> {
        let apiRequest: ApiRequest = ApiRequest(method: .get, endPoint: .checkUserBlock(id, userId))
        return backendClient.load(request: apiRequest)
    }

    func blockUser(id: String,userId:String) -> Single<BlockListUserDataModel> {
        // NEW API — POST users/{id}/block (no body required)
        let apiRequest: ApiRequest = ApiRequest(method: .post, endPoint: .blockUser(id), parameters: nil)
        return backendClient.load(request: apiRequest)
            .do(onSuccess: { _ in
                // Notify all screens (home feed etc.) so the blocked user's content is removed,
                // no matter which tab/screen the block was triggered from.
                DispatchQueue.main.async {
                    BlockedUsersManager.shared.blockUser(id: id)
                }
            })
    }

    func unblockUser(id: String) -> Single<Bool> {
        let apiRequest: ApiRequest = ApiRequest(method: .delete, endPoint: .unblockUser(id))
        return backendClient.load(request: apiRequest)
            .do(onSuccess: { _ in
                DispatchQueue.main.async {
                    BlockedUsersManager.shared.unblockUser(id: id)
                }
            })
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
        // NEW API — GET chat/conversations?limit=30&archived=true|false (FE fetchConversations)
        // Use String values so URLEncoding emits `archived=false` (not `0`/`1`).
        var params = [String: Any]()
        params["limit"] = "\(limit)"
        params["archived"] = showArchived ? "true" : "false"
        // Keep page for older backends; FE primarily uses limit + cursor.
        params["page"] = "\(page)"
        // Legacy filters kept for compatibility if backend still accepts them
        if !search.isEmpty { params["search"] = search }
        if showPinned { params["showPinned"] = "true" }
        if let lastSync = lastSync, !lastSync.isEmpty {
            params["lastSync"] = lastSync
        }
        if let before = before, !before.isEmpty {
            params["cursor"] = before
            params["before"] = before
        }
        
        let apiRequest = ApiRequest(method: .get, endPoint: .getConversations, parameters: params, encoding: URLEncoding.queryString)
        print("ChatAPI: getConversations → chat/conversations?limit=\(limit)&archived=\(showArchived ? "true" : "false")")
        return backendClient.loadChatData(request: apiRequest)
            .do(onError: { _ in })
                }

    func getConversationMessages(conversationId: String, page: Int = 1, limit: Int = 40) -> Single<ConversationMessagesResponse> {
        // NEW API — GET chat/conversations/{id}/messages?limit=40 (+ page / cursor / before)
        var params = [String: Any]()
        params["page"] = page
        params["limit"] = limit
        let apiRequest = ApiRequest(method: .get, endPoint: .getConversationMessages(conversationId), parameters: params, encoding: URLEncoding.queryString)
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

    func getConversationMessagesBefore(conversationId: String, beforeDate: Date, page: Int = 1, limit: Int = 20) -> Single<ConversationMessagesResponse> {
        var params = [String: Any]()
        params["page"] = page
        params["limit"] = limit
        
        // Format date as ISO8601 with fractional seconds
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let beforeString = formatter.string(from: beforeDate)
        params["before"] = beforeString
        
        let apiRequest = ApiRequest(method: .get, endPoint: .getConversationMessages(conversationId), parameters: params, encoding: URLEncoding.queryString)
        return backendClient.loadModelData(request: apiRequest)
    }

    /// Legacy — DELETE chat/messages/{id}?scope=me|everyone
    func deleteMessage(id: String, scope: String = "me") -> Single<DataRequest> {
        let normalizedScope = (scope == "everyone") ? "everyone" : "me"
        let apiRequest = ApiRequest(
            method: .delete,
            endPoint: .deleteMessage(id, normalizedScope)
        )
        return backendClient.loadDataRequest(request: apiRequest)
    }

    /// NEW API — POST chat/messages/delete (FE / web parity)
    /// Body: `{ messageIds: string[], scope: "me" | "everyone" }`
    func deleteChatMessages(
        messageIds: [String],
        scope: String = "me"
    ) -> Single<Void> {
        let uniqueIds = Array(Set(
            messageIds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ))
        guard !uniqueIds.isEmpty else { return .just(()) }

        let normalizedScope = (scope == "everyone") ? "everyone" : "me"
        let params: [String: Any] = [
            "messageIds": uniqueIds,
            "scope": normalizedScope
        ]
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .deleteChatMessages,
            parameters: params,
            encoding: JSONEncoding.default
        )
        return backendClient.loadDataRequest(request: apiRequest).map { _ in () }
    }

    /// NEW API — PATCH chat/messages/{id} (FE edit message)
    /// Body: `{ body: String }` (optional `type` for parity with web)
    func editChatMessage(
        messageId: String,
        body: String,
        type: String? = nil
    ) -> Single<ConversationMessage> {
        var params: [String: Any] = ["body": body]
        if let type, !type.isEmpty {
            params["type"] = type
        }
        let apiRequest = ApiRequest(
            method: .patch,
            endPoint: .editChatMessage(messageId),
            parameters: params,
            encoding: JSONEncoding.default
        )
        return backendClient.loadChatData(request: apiRequest)
            .map { (data: SendChatMessageAPIData) -> ConversationMessage in
                guard let message = data.message else {
                    throw APIError.apiError("editChatMessage: missing message in response")
                }
                return message
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

    /// NEW API — POST chat/messages/{id}/react
    /// Body: `{ emoji: String }` (toggle — same emoji again removes)
    func reactChatMessage(
        messageId: String,
        emoji: String
    ) -> Single<ConversationMessage> {
        let params: [String: Any] = ["emoji": emoji]
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .reactChatMessage(messageId),
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

    /// NEW API — POST chat/messages (FE `sendChatMessage`)
    /// Body: conversationId, body?, type?, mediaIds?, location?, poll?, postId?, clientMessageId?, replyToId?
    func sendChatMessage(
        conversationId: String,
        body: String? = nil,
        type: String? = nil,
        mediaIds: [String]? = nil,
        location: [String: Any]? = nil,
        poll: [String: Any]? = nil,
        postId: String? = nil,
        clientMessageId: String? = nil,
        replyToId: String? = nil
    ) -> Single<ConversationMessage> {
        var params: [String: Any] = ["conversationId": conversationId]
        if let body { params["body"] = body }
        if let type, !type.isEmpty { params["type"] = type }
        if let mediaIds, !mediaIds.isEmpty { params["mediaIds"] = mediaIds }
        if let location { params["location"] = location }
        if let poll { params["poll"] = poll }
        if let postId, !postId.isEmpty { params["postId"] = postId }
        if let clientMessageId, !clientMessageId.isEmpty { params["clientMessageId"] = clientMessageId }
        if let replyToId, !replyToId.isEmpty { params["replyToId"] = replyToId }

        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .sendChatMessage,
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
    }

    /// NEW API — PATCH chat/conversations/{id}/messages/{messageId}/pin (FE `pinChatMessage`)
    /// Body: `{ pinned: Bool, pinDuration?: String }`
    func pinChatMessage(
        conversationId: String,
        messageId: String,
        pinned: Bool,
        pinDuration: String? = nil
    ) -> Single<ConversationMessage> {
        var params: [String: Any] = ["pinned": pinned]
        if pinned, let pinDuration, !pinDuration.isEmpty {
            params["pinDuration"] = pinDuration
        }
        let apiRequest = ApiRequest(
            method: .patch,
            endPoint: .pinConversationMessage(conversationId, messageId),
            parameters: params,
            encoding: JSONEncoding.default
        )
        return backendClient.loadChatData(request: apiRequest)
            .map { (data: SendChatMessageAPIData) -> ConversationMessage in
                guard let message = data.message else {
                    throw APIError.apiError("pinChatMessage: missing message in response")
                }
                return message
            }
    }

    /// NEW API — GET chat/conversations/{id}/pinned-message (FE `fetchPinnedMessage`)
    func fetchPinnedMessage(conversationId: String) -> Single<ConversationMessage?> {
        let apiRequest = ApiRequest(
            method: .get,
            endPoint: .getPinnedMessage(conversationId)
        )
        return backendClient.loadChatData(request: apiRequest)
            .map { (data: PinnedMessageAPIData) -> ConversationMessage? in
                data.message
            }
    }

    /// NEW API — POST chat/conversations/{id}/read (FE markConversationRead)
    func markConversationReadREST(conversationId: String, messageId: String? = nil) -> Single<ChatConversationReadAPIData> {
        var params: [String: Any] = [:]
        if let messageId, !messageId.isEmpty { params["messageId"] = messageId }
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .markConversationRead(conversationId),
            parameters: params,
            encoding: JSONEncoding.default
        )
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

    /// NEW API — POST chat/conversations/{id}/delivered (FE markConversationDelivered)
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

    /// OLD name — now maps to NEW `DELETE chat/conversations/{id}?scope=me`
    func deleteChat(id: String) -> Single<DataRequest> {
        let apiRequest = ApiRequest(
            method: .delete,
            endPoint: .deleteChatConversation(id, "me"),
            parameters: [:],
            encoding: URLEncoding.queryString
        )
        return backendClient.loadDataRequest(request: apiRequest)
    }

    /// NEW API — DELETE `chat/conversations/{id}?scope=me|everyone`
    /// `scope=me` hides for you only; `scope=everyone` destroys for all participants.
    func deleteChatConversation(id: String, scope: String = "me") -> Single<Void> {
        let normalizedScope = (scope == "everyone") ? "everyone" : "me"
        let apiRequest = ApiRequest(
            method: .delete,
            endPoint: .deleteChatConversation(id, normalizedScope),
            parameters: [:],
            encoding: URLEncoding.queryString
        )
        return backendClient.loadDataRequest(request: apiRequest).map { _ in () }
    }

    /// NEW API — bulk delete: pass `ids` array + `scope` flag.
    /// Single id → `DELETE chat/conversations/{id}?scope=…`
    /// Multiple ids → `DELETE chat/conversations` with body `{ id: [...], scope }`
    func deleteChatConversations(ids: [String], scope: String = "me") -> Single<Void> {
        let normalizedScope = (scope == "everyone") ? "everyone" : "me"
        let uniqueIds = Array(Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        guard !uniqueIds.isEmpty else { return .just(()) }

        if uniqueIds.count == 1 {
            return deleteChatConversation(id: uniqueIds[0], scope: normalizedScope)
        }

        let params: [String: Any] = [
            "id": uniqueIds,
            "scope": normalizedScope
        ]
        let apiRequest = ApiRequest(
            method: .delete,
            endPoint: .deleteChatConversationsBulk,
            parameters: params,
            encoding: JSONEncoding.default
        )
        return backendClient.loadDataRequest(request: apiRequest)
            .map { _ in () }
            .catch { [weak self] _ -> Single<Void> in
                // Fallback: OpenAPI documents per-id delete — apply same scope flag to each
                guard let self else { return .error(APIError.apiError("Session unavailable")) }
                return uniqueIds.reduce(Single.just(())) { partial, id in
                    partial.flatMap { self.deleteChatConversation(id: id, scope: normalizedScope) }
                }
            }
    }

    /// NEW API — POST chat/conversations. Prefer `createChatConversation`. OLD body used participants/isGroup/groupAvatar.
    func createChat(participants: [String], isGroup: Bool, title: String, groupAvatar: String) -> Single<[String: Any]> {
        return createChatConversation(
            participantIds: participants,
            type: isGroup ? "group" : "direct",
            title: title.isEmpty ? nil : title,
            avatarPath: groupAvatar.isEmpty ? nil : groupAvatar
        )
    }

    /// NEW API — POST calls/ (Android StartCallRequest)
    /// Body: `{ conversationId, type: "audio"|"video" }`
    /// Response: `{ success, data: { call, token, uid, appId } }` (CallSession)
    func startAgoraCall(conversationId: String, type: String) -> Single<[String: Any]> {
        let params: [String: Any] = [
            "conversationId": conversationId,
            "type": type
        ]
        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .startAgoraCall,
            parameters: params,
            encoding: JSONEncoding.default
        )
        return backendClient.loadDataRequest(request: apiRequest).map { response -> [String: Any] in
            guard let data = response.data else { return [:] }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            if let dataObj = json["data"] as? [String: Any] {
                return dataObj
            }
            return json
        }
    }

    /// NEW API — GET calls/{callId}
    /// Used to hide the Join banner when the group call has already ended.
    func fetchAgoraCall(callId: String) -> Single<[String: Any]> {
        let apiRequest = ApiRequest(
            method: .get,
            endPoint: .getAgoraCall(callId),
            parameters: nil,
            encoding: URLEncoding.default
        )
        return backendClient.loadDataRequest(request: apiRequest).map { response -> [String: Any] in
            guard let data = response.data else { return [:] }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            if let dataObj = json["data"] as? [String: Any] {
                return dataObj
            }
            return json
        }
    }

    /// NEW API — POST chat/conversations
    /// Body: `{ participantIds, type: "direct"|"group", title?, avatarPath? }`
    /// Response: `{ success, data: { conversation: { id, ... } }, message }`
    func createChatConversation(
        participantIds: [String],
        type: String = "direct",
        title: String? = nil,
        avatarPath: String? = nil
    ) -> Single<[String: Any]> {
        var params: [String: Any] = [
            "participantIds": participantIds,
            "type": type
        ]
        if let title, !title.isEmpty {
            params["title"] = title
        }
        if let avatarPath, !avatarPath.isEmpty {
            params["avatarPath"] = avatarPath
        }

        let apiRequest = ApiRequest(
            method: .post,
            endPoint: .createChatConversation,
            parameters: params,
            encoding: JSONEncoding.default
        )
        return backendClient.loadDataRequest(request: apiRequest).map { response -> [String: Any] in
            guard let data = response.data else { return [:] }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // NEW: data.conversation { id, peer, members, ... }
                    if let dataObj = json["data"] as? [String: Any] {
                        if let conversation = dataObj["conversation"] as? [String: Any] {
                            return conversation
                        }
                        return dataObj
                    }

                    if let dataArray = json["data"] as? [[String: Any]],
                       let firstObj = dataArray.first {
                        return firstObj
                    }
                    if let dataAnyArray = json["data"] as? [Any],
                       let firstDict = dataAnyArray.first as? [String: Any] {
                        return firstDict
                    }
                    // Some responses return the conversation at the root
                    if json["id"] != nil || json["conversationId"] != nil {
                        return json
                    }
                }
            } catch {
                print("Error parsing NEW chat/conversations response: \(error)")
            }
            return [:]
        }
    }

    /// NEW API — GET chat/conversations/{id}
    /// FE: `fetchConversation` → `{ conversation }` with `members` + `participantsCount`.
    /// https://onevibe.walit.in/api/v1/chat/conversations/{id}
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
        
        AF.request(apiURL,
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
