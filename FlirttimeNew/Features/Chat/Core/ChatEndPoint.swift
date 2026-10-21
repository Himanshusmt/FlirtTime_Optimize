//
//  ChatEndPoint.swift
//  FlirttimeNew
//

import Foundation
import Alamofire

struct ApiRequest {
    let method: HTTPMethod
    let endPoint: EndPoint
    var parameters: [String: Any]? = nil
    var encoding: ParameterEncoding = JSONEncoding.default
}

/// Chat REST paths, relative to `ChatConfig.baseURL` (`https://flirttimeapi.walit.in`).
/// FlirtTime chat lives under `/api/v1/chats` and `/api/v1/calls/video`.
enum EndPoint: CustomStringConvertible {
    // Users
    case getUserById(String)
    case getProfile
    case groupCandidates
    case searchUser
    case checkUserBlock(String, String)
    case blockUser(String)
    case unblockUser(String)
    case reportUser(String)
    case blockedUsers
    case reportUserReason(String)

    // Conversations — `/api/v1/chats`
    case getConversations
    case createChatConversation
    case getGroupDetails(String)
    case getGroupMembers(String)
    case deleteChatConversation(String, String)
    case deleteChatConversationsBulk
    case updateConversationSettings(String)
    case markConversationRead(String)
    case markConversationUnread(String)
    case markConversationDelivered(String)
    case syncInboxDelivered
    case getPinnedMessage(String)
    case getPinnedMessages(String)
    case pinConversation(String)
    case pinConversationMessage(String, String)

    // Messages — `/api/v1/chats/{id}/messages` and `/api/v1/chat/messages`
    case getConversationMessages(String)
    case sendChatMessage(String)
    case sendDirectChatMessage
    case editChatMessage(String)
    case deleteMessage(String, String)
    case deleteChatMessages
    case translateChatMessage(String)
    case reactChatMessage(String)
    case messageInfo(String)

    // Media
    case mediaImages
    case mediaUploads
    case mediaUploadComplete(String)
    case mediaUploadParts(String)
    case mediaUploadAbort(String)
    case chatPresignedURL

    // Video calls — `/api/v1/calls/video`
    case startAgoraCall
    case getAgoraCall(String)
    case initiateVideoCall
    case acceptVideoCall(String)
    case rejectVideoCall(String)
    case endVideoCall(String)
    case getActiveVideoCall

    var description: String {
        switch self {
        case .getUserById(let id): return "api/v1/users/\(id)"
        case .getProfile: return "api/v1/users/"
        case .groupCandidates: return "api/v1/users/group-candidates"
        case .searchUser: return "api/v1/users/"
        case .checkUserBlock(let id, let userId): return "api/v1/user/\(id)/is-blocked?userId=\(userId)"
        case .blockUser(let id): return "api/v1/users/\(id)/block"
        case .unblockUser(let id): return "api/v1/users/\(id)/block"
        case .reportUser(let id): return "api/v1/users/\(id)/report"
        case .blockedUsers: return "api/v1/users/blocked"
        case .reportUserReason(let lang): return "api/v1/auth/report/reason?version=\(lang)"

        case .getConversations: return "api/v1/chats"
        case .createChatConversation: return "api/v1/chats"
        case .getGroupDetails(let id): return "api/v1/chats/\(id)"
        case .getGroupMembers(let id): return "api/v1/chats/\(id)/members"
        case .deleteChatConversation(let id, let scope): return "api/v1/chats/\(id)?scope=\(scope)"
        case .deleteChatConversationsBulk: return "api/v1/chats"
        case .updateConversationSettings(let id): return "api/v1/chats/\(id)/settings"
        case .markConversationRead(let id): return "api/v1/chats/\(id)/read"
        case .markConversationUnread(let id): return "api/v1/chats/\(id)/unread"
        case .markConversationDelivered(let id): return "api/v1/chats/\(id)/delivered"
        case .syncInboxDelivered: return "api/v1/chats/delivered/sync"
        case .getPinnedMessage(let id): return "api/v1/chats/\(id)/messages/pinned"
        case .getPinnedMessages(let id): return "api/v1/chats/\(id)/messages/pinned"
        case .pinConversation(let id): return "api/v1/chats/\(id)/pin"
        case .pinConversationMessage(let conversationId, let messageId):
            return "api/v1/chats/\(conversationId)/messages/\(messageId)/pin"

        case .getConversationMessages(let id): return "api/v1/chats/\(id)/messages"
        case .sendChatMessage(let id): return "api/v1/chats/\(id)/messages"
        case .sendDirectChatMessage: return "api/v1/chat/messages"
        case .editChatMessage(let id): return "api/v1/chats/messages/\(id)"
        case .deleteMessage(let id, let scope): return "api/v1/chats/messages/\(id)?scope=\(scope)"
        case .deleteChatMessages: return "api/v1/chats/messages/delete"
        case .translateChatMessage(let id): return "api/v1/chats/messages/\(id)/translate"
        case .reactChatMessage(let id): return "api/v1/chats/messages/\(id)/react"
        case .messageInfo(let id): return "api/v1/chats/messages/\(id)/info"

        case .mediaImages: return "api/v1/media/images"
        case .mediaUploads: return "api/v1/media/uploads"
        case .mediaUploadComplete(let id): return "api/v1/media/uploads/\(id)/complete"
        case .mediaUploadParts(let id): return "api/v1/media/uploads/\(id)/parts"
        case .mediaUploadAbort(let id): return "api/v1/media/uploads/\(id)/abort"
        case .chatPresignedURL: return "api/v1/chats/media/generate-presigned-url"

        case .startAgoraCall, .initiateVideoCall: return "api/v1/calls/video/initiate"
        case .getAgoraCall: return "api/v1/calls/video/active"
        case .acceptVideoCall(let id): return "api/v1/calls/video/\(id)/accept"
        case .rejectVideoCall(let id): return "api/v1/calls/video/\(id)/reject"
        case .endVideoCall(let id): return "api/v1/calls/video/\(id)/end"
        case .getActiveVideoCall: return "api/v1/calls/video/active"
        }
    }
}
