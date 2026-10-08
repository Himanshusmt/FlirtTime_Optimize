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

/// Chat REST paths, relative to `ChatConfig.baseURL`.
enum EndPoint: CustomStringConvertible {
    // Users
    case getUserById(String)
    case getProfile
    case groupCandidates
    case searchUser
    case checkUserBlock(String, String)
    case blockUser(String)
    case unblockUser(String)
    case reportUser
    case reportUserReason(String)

    // Conversations
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
    case pinConversationMessage(String, String)

    // Messages
    case getConversationMessages(String)
    case sendChatMessage
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

    // Calls
    case startAgoraCall
    case getAgoraCall(String)

    var description: String {
        switch self {
        case .getUserById(let id): return "users/\(id)"
        case .getProfile: return "users/"
        case .groupCandidates: return "users/group-candidates"
        case .searchUser: return "users/"
        case .checkUserBlock(let id, let userId): return "user/\(id)/is-blocked?userId=\(userId)"
        case .blockUser(let id): return "users/\(id)/block"
        case .unblockUser(let id): return "users/\(id)/block"
        case .reportUser: return "auth/report"
        case .reportUserReason(let lang): return "auth/report/reason?version=\(lang)"

        case .getConversations: return "chat/conversations"
        case .createChatConversation: return "chat/conversations"
        case .getGroupDetails(let id): return "chat/conversations/\(id)"
        case .getGroupMembers(let id): return "chat/conversations/\(id)/members"
        case .deleteChatConversation(let id, let scope): return "chat/conversations/\(id)?scope=\(scope)"
        case .deleteChatConversationsBulk: return "chat/conversations"
        case .updateConversationSettings(let id): return "chat/conversations/\(id)/settings"
        case .markConversationRead(let id): return "chat/conversations/\(id)/read"
        case .markConversationUnread(let id): return "chat/conversations/\(id)/unread"
        case .markConversationDelivered(let id): return "chat/conversations/\(id)/delivered"
        case .syncInboxDelivered: return "chat/delivered/sync"
        case .getPinnedMessage(let id): return "chat/conversations/\(id)/pinned-message"
        case .pinConversationMessage(let conversationId, let messageId):
            return "chat/conversations/\(conversationId)/messages/\(messageId)/pin"

        case .getConversationMessages(let id): return "chat/conversations/\(id)/messages"
        case .sendChatMessage: return "chat/messages"
        case .editChatMessage(let id): return "chat/messages/\(id)"
        case .deleteMessage(let id, let scope): return "chat/messages/\(id)?scope=\(scope)"
        case .deleteChatMessages: return "chat/messages/delete"
        case .translateChatMessage(let id): return "chat/messages/\(id)/translate"
        case .reactChatMessage(let id): return "chat/messages/\(id)/react"
        case .messageInfo(let id): return "chat/messages/\(id)/info"

        case .mediaImages: return "media/images"
        case .mediaUploads: return "media/uploads"
        case .mediaUploadComplete(let id): return "media/uploads/\(id)/complete"
        case .mediaUploadParts(let id): return "media/uploads/\(id)/parts"
        case .mediaUploadAbort(let id): return "media/uploads/\(id)/abort"
        case .chatPresignedURL: return "chat/media/generate-presigned-url"

        case .startAgoraCall: return "calls/"
        case .getAgoraCall(let id): return "calls/\(id)"
        }
    }
}
