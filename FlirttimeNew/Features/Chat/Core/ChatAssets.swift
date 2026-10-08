//
//  ChatAssets.swift
//  FlirttimeNew
//

import Foundation

/// Asset-catalog names used by chat and calling screens.
enum ChatAssets {
    // Navigation & header
    static let back = "BackIcon"
    static let menu = "chat_more"
    static let search = "graySearch"
    static let verified = "verified"
    static let voiceCall = "voiceCall"
    static let videoCall = "videoCall"

    // Composer
    static let plus = "chat_plus"
    static let send = "chat_send"
    static let microphone = "chat_mic"
    static let camera = "chat_camera"
    static let gallery = "chat_gallery"
    static let reply = "chat_reply"
    static let cameraClose = "whiteCross"
    static let attach = "chat_attach"
    static let location = "chat_location"
    static let contact = "chat_contact"
    static let close = "chat_close"
    static let trash = "chat_trash"
    static let play = "chat_play"
    static let pause = "chat_pause"
    static let stop = "chat_stop"
    static let profile = "chat_profile"
    static let reportFlag = "chat_report"

    // Delivery status
    static let tickSent = "chat_tick_single"
    static let tickDelivered = "chat_tick_double"
    static let tickRead = "chat_tick_double"

    // Chat list actions
    static let newChat = "chat_new"
    static let edit = "chat_edit"
    static let unread = "chat_unread"
    static let read = "chat_read"
    static let archive = "chat_archive"
    static let pin = "chat_pin"
    static let unpin = "chat_unpin"
    static let tag = "chat_tag"
    static let mute = "muteIcon"
    static let unmute = "UnmuteIcon"
    static let delete = "chatDelete"
    static let block = "blockUserIcon"
    static let report = "reportIcon"
    static let clearChat = "clearChat"
    static let leave = "logOut"
    static let selected = "redTick"

    // Backgrounds & placeholders
    static let background = "chat_bg"
    static let backgroundPattern = "chat_bg_pattern"
    static let avatarPlaceholder = "chat_avatar_placeholder"
    static let imagePlaceholder = "imagePlaceholder"
    static let emptyState = "noCallsChats"

    // Calls
    static let acceptCall = "acceptCall"
    static let declineCall = "declineCall"
    static let callMinimize = "chat_call_minimize"
    static let incomingCall = "incomingCall"
    static let outgoingCall = "outgoingCall"
    static let missedCall = "missedCall"
}
