import Foundation

enum ChatStrings: String {
    case cameraHoldForVideoTapForPhoto = "Hold for video, tap for photo"
    case cancel = "CANCEL"
    case chat_1member = "CHAT_1_MEMBER"
    case chat_accessToPhotosDenied = "CHAT_ACCESS_TO_PHOTOS_DENIED"
    case chat_activeUsers = "CHAT_ACTIVE_USERS"
    case chat_addLabelHere = "CHAT_ADD_LABEL_HERE"
    case chat_allowContactAccessMessage = "CHAT_ALLOW_CONTACT_ACCESS_MESSAGE"
    case chat_appleMaps = "CHAT_APPLE_MAPS"
    case chat_archive = "CHAT_ARCHIVE"
    case chat_archiveDescription = "CHAT_ARCHIVE_DESCRIPTION"
    case chat_archived = "CHAT_ARCHIVED"
    case chat_audio = "CHAT_AUDIO"
    case chat_block = "CHAT_BLOCK"
    case chat_blockUserConfirmation = "CHAT_BLOCK_USER_CONFIRMATION"
    case chat_blockUserDescription = "CHAT_BLOCK_USER_DESCRIPTION"
    case chat_blockedUserHint = "CHAT_BLOCKED_USER_HINT"
    case chat_call = "CHAT_CALL"
    case chat_camera = "CHAT_CAMERA"
    case chat_cancel = "CHAT_CANCEL"
    case chat_channelLabel = "CHAT_CHANNEL_LABEL"
    case chat_channels = "CHAT_CHANNELS"
    case chat_chats = "CHAT_CHATS"
    case chat_clearChatAction = "CHAT_CLEAR_CHAT_ACTION"
    case chat_clearChatConfirmation = "CHAT_CLEAR_CHAT_CONFIRMATION"
    case chat_clearChatDescription = "CHAT_CLEAR_CHAT_DESCRIPTION"
    case chat_contact = "CHAT_CONTACT"
    case chat_copy = "CHAT_COPY"
    case chat_copyPhone = "CHAT_COPY_PHONE"
    case chat_deleteChannel = "CHAT_DELETE_CHANNEL"
    case chat_deleteChannelConfirmation = "CHAT_DELETE_CHANNEL_CONFIRMATION"
    case chat_deleteChannelDescription = "CHAT_DELETE_CHANNEL_DESCRIPTION"
    case chat_deleteChat = "CHAT_DELETE_CHAT"
    case chat_deleteChatConfirmation = "CHAT_DELETE_CHAT_CONFIRMATION"
    case chat_deleteChatDescription = "CHAT_DELETE_CHAT_DESCRIPTION"
    case chat_deleteChats = "CHAT_DELETE_CHATS"
    case chat_deleteChatsConfirmation = "CHAT_DELETE_CHATS_CONFIRMATION"
    case chat_deleteForEveryone = "CHAT_DELETE_FOR_EVERYONE"
    case chat_deleteForEveryoneConfirmation = "CHAT_DELETE_FOR_EVERYONE_CONFIRMATION"
    case chat_deleteForEveryoneDescription = "CHAT_DELETE_FOR_EVERYONE_DESCRIPTION"
    case chat_deleteForMe = "CHAT_DELETE_FOR_ME"
    case chat_deleteForMeAndUser = "CHAT_DELETE_FOR_ME_AND_USER"
    case chat_deleteGroup = "CHAT_DELETE_GROUP"
    case chat_deleteGroupConfirmation = "CHAT_DELETE_GROUP_CONFIRMATION"
    case chat_deleteGroupDescription = "CHAT_DELETE_GROUP_DESCRIPTION"
    case chat_deleteMessageConfirmation = "CHAT_DELETE_MESSAGE_CONFIRMATION"
    case chat_deleteMessageDescription = "CHAT_DELETE_MESSAGE_DESCRIPTION"
    case chat_deleteMsgConfirmAll = "CHAT_THIS_MESSAGE_WILL_BE_DELETED_FOR_EVERYONE_IN_THIS_CHAT"
    case chat_deleteMsgConfirmMe = "CHAT_THIS_MESSAGE_WILL_BE_DELETED_FOR_YOU_ONLY_OTHER_CHAT_MEMBERS_WILL_STILL_BE_ABLE_TO_SEE_IT"
    case chat_deliveredTo = "CHAT_DELIVERED_TO"
    case chat_deselectAll = "CHAT_DESELECT_ALL"
    case chat_document = "CHAT_DOCUMENT"
    case chat_draft = "CHAT_DRAFT"
    case chat_edit = "CHAT_EDIT"
    case chat_edited = "CHAT_EDITED"
    case chat_editingMessage = "CHAT_EDITING_MESSAGE"
    case chat_errorAudioCorrupt = "CHAT_ERROR_AUDIO_CORRUPT"
    case chat_errorBlockedUserSend = "CHAT_ERROR_BLOCKED_USER_SEND"
    case chat_errorConnectionLost = "CHAT_ERROR_CONNECTION_LOST"
    case chat_errorFileTooLarge = "CHAT_ERROR_FILE_TOO_LARGE"
    case chat_errorForwardFailed = "CHAT_ERROR_FORWARD_FAILED"
    case chat_errorInvalidContent = "CHAT_ERROR_INVALID_CONTENT"
    case chat_errorLoadMessages = "CHAT_ERROR_LOAD_MESSAGES"
    case chat_errorMediaUpload = "CHAT_ERROR_MEDIA_UPLOAD"
    case chat_errorNotDelivered = "CHAT_ERROR_NOT_DELIVERED"
    case chat_errorPermission = "CHAT_ERROR_PERMISSION"
    case chat_errorRealtimeLost = "CHAT_ERROR_REALTIME_LOST"
    case chat_errorRecordingFailed = "CHAT_ERROR_RECORDING_FAILED"
    case chat_errorSendFailed = "CHAT_ERROR_SEND_FAILED"
    case chat_exitAndDeleteChannel = "CHAT_EXIT_AND_DELETE_CHANNEL"
    case chat_exitAndDeleteChannelDescription = "CHAT_EXIT_AND_DELETE_CHANNEL_DESCRIPTION"
    case chat_exitAndDeleteGroup = "CHAT_EXIT_AND_DELETE_GROUP"
    case chat_exitAndDeleteGroupDescription = "CHAT_EXIT_AND_DELETE_GROUP_DESCRIPTION"
    case chat_failedToSave = "CHAT_FAILED_TO_SAVE"
    case chat_followChannel = "CHAT_FOLLOW_CHANNEL"
    case chat_followChannelHint = "CHAT_FOLLOW_CHANNEL_HINT"
    case chat_follower = "CHAT_FOLLOWER"
    case chat_followers = "CHAT_FOLLOWERS"
    case chat_followingStatus = "CHAT_FOLLOWING_STATUS"
    case chat_forwarded = "CHAT_FORWARDED"
    case chat_gettingAddress = "CHAT_GETTING_ADDRESS"
    case chat_gettingLocation = "CHAT_GETTING_LOCATION"
    case chat_giveLabelInstruction = "CHAT_GIVE_LABEL_INSTRUCTION"
    case chat_googleMaps = "CHAT_GOOGLE_MAPS"
    case chat_groupBadge = "CHAT_GROUP_BADGE"
    case chat_groupChat = "CHAT_GROUP_CHAT"
    case chat_groups = "CHAT_GROUPS"
    case chat_labelChat = "CHAT_LABEL_CHAT"
    case chat_lastSeen = "CHAT_LAST_SEEN"
    case chat_leaveGroup = "CHAT_LEAVE_GROUP"
    case chat_leaveGroupConfirmation = "CHAT_LEAVE_GROUP_CONFIRMATION"
    case chat_leaveGroupDescription = "CHAT_LEAVE_GROUP_DESCRIPTION"
    case chat_loadingContacts = "CHAT_LOADING_CONTACTS"
    case chat_loadingUsers = "CHAT_LOADING_USERS"
    case chat_location = "CHAT_LOCATION"
    case chat_locationContent = "CHAT_LOCATION_CONTENT"
    case chat_locationPermissionDenied = "CHAT_LOCATION_PERMISSION_DENIED"
    case chat_locationPermissionRequired = "CHAT_LOCATION_PERMISSION_REQUIRED"
    case chat_locationServicesDisabled = "CHAT_LOCATION_SERVICES_DISABLED"
    case chat_locationTimeout = "CHAT_LOCATION_TIMEOUT"
    case chat_locationUnavailable = "CHAT_LOCATION_UNAVAILABLE"
    case chat_lockChat = "CHAT_LOCK_CHAT"
    case chat_markAsRead = "CHAT_MARK_AS_READ"
    case chat_markAsUnread = "CHAT_MARK_AS_UNREAD"
    case chat_members = "CHAT_MEMBERS"
    case chat_message = "CHAT_MESSAGE"
    case chat_messageDeleted = "CHAT_MESSAGE_DELETED"
    case chat_messageInfo = "CHAT_MESSAGE_INFO"
    case chat_messagesDeleted = "CHAT_MESSAGES_DELETED"
    case chat_momentNotice = "CHAT_MOMENT_NOTICE"
    case chat_moreNumbers = "CHAT_MORE_NUMBERS"
    case chat_mute = "CHAT_MUTE"
    case chat_muteConfirmation = "CHAT_MUTE_CONFIRMATION"
    case chat_muteDescription = "CHAT_MUTE_DESCRIPTION"
    case chat_newChat = "CHAT_NEW_CHAT"
    case chat_newMessage = "CHAT_NEW_MESSAGE"
    case chat_noChatsYet = "CHAT_NO_CHATS_YET"
    case chat_noContactsFound = "CHAT_NO_CONTACTS_FOUND"
    case chat_noInfoAvailable = "CHAT_NO_INFO_AVAILABLE"
    case chat_noLongerMember = "CHAT_YOU_ARE_NO_LONGER_A_MEMBER_OF_THIS_GROUP"
    case chat_noReactions = "CHAT_NO_REACTIONS"
    case chat_noResultsFound = "CHAT_NO_RESULTS_FOUND"
    case chat_noVotes = "CHAT_NO_VOTES"
    case chat_notifyEveryone = "CHAT_NOTIFY_EVERYONE"
    case chat_now = "CHAT_NOW"
    case chat_offline = "CHAT_OFFLINE"
    case chat_online = "CHAT_ONLINE"
    case chat_onlyAdminsCanSend = "CHAT_ONLY_CHANNEL_ADMINS_CAN_SEND_MESSAGES"
    case chat_openSettings = "CHAT_OPEN_SETTINGS"
    case chat_photo = "CHAT_PHOTO"
    case chat_pin = "CHAT_PIN"
    case chat_pinned = "CHAT_PINNED"
    case chat_pinnedChats = "CHAT_PINNED_CHATS"
    case chat_pinnedMessage = "CHAT_PINNED_MESSAGE"
    case chat_pleaseEnableLocation = "CHAT_PLEASE_ENABLE_LOCATION_ACCESS_IN_SETTINGS_TO_SHARE_YOUR_LOCATION"
    case chat_poll = "CHAT_POLL"
    case chat_post = "CHAT_POST"
    case chat_react = "CHAT_REACT"
    case chat_readBy = "CHAT_READ_BY"
    case chat_readMore = "CHAT_READ_MORE"
    case chat_reel = "CHAT_REEL"
    case chat_reply = "CHAT_REPLY"
    case chat_report = "CHAT_REPORT_ACTION"
    case chat_reportConfirmation = "CHAT_REPORT_CONFIRMATION"
    case chat_reportDescription = "CHAT_REPORT_DESCRIPTION"
    case chat_retake = "CHAT_RETAKE"
    case chat_retry = "CHAT_RETRY"
    case chat_savedToPhotos = "CHAT_SAVED_TO_PHOTOS"
    case chat_search = "CHAT_SEARCH"
    case chat_searchContacts = "CHAT_SEARCH_CONTACTS"
    case chat_searchUsers = "CHAT_SEARCH_USERS"
    case chat_seeOriginal = "CHAT_SEE_ORIGINAL"
    case chat_select = "CHAT_SELECT"
    case chat_selectNumber = "CHAT_SELECT_NUMBER"
    case chat_selected = "CHAT_SELECTED"
    case chat_selectedCountFormat = "CHAT_SELECTED_COUNT_FORMAT"
    case chat_sendLocation = "CHAT_SEND_LOCATION"
    case chat_sendYourCurrentLocation = "CHAT_SEND_YOUR_CURRENT_LOCATION"
    case chat_shareChannel = "CHAT_SHARE_CHANNEL"
    case chat_shareChannelText = "CHAT_SHARE_CHANNEL_TEXT"
    case chat_shareContact = "CHAT_SHARE_CONTACT"
    case chat_sticker = "CHAT_STICKER"
    case chat_story = "CHAT_STORY"
    case chat_successMessageForwarded = "CHAT_SUCCESS_MESSAGE_FORWARDED"
    case chat_tapForContactInfo = "CHAT_TAP_FOR_CONTACT_INFO"
    case chat_tapToRemove = "CHAT_TAP_TO_REMOVE"
    case chat_today = "CHAT_TODAY"
    case chat_translate = "CHAT_TRANSLATE"
    case chat_translated = "CHAT_TRANSLATED"
    case chat_typing = "CHAT_TYPING"
    case chat_unableGetLocation = "CHAT_UNABLE_GET_LOCATION"
    case chat_unblock = "CHAT_UNBLOCK"
    case chat_unblockToSend = "CHAT_UNBLOCK_TO_SEND"
    case chat_unblockUserConfirmation = "CHAT_UNBLOCK_USER_CONFIRMATION"
    case chat_unblockUserDescription = "CHAT_UNBLOCK_USER_DESCRIPTION"
    case chat_unfollowChannel = "CHAT_UNFOLLOW_CHANNEL"
    case chat_unfollowChannelConfirmation = "CHAT_UNFOLLOW_CHANNEL_CONFIRMATION"
    case chat_unmute = "CHAT_UNMUTE"
    case chat_unmuteConfirmation = "CHAT_UNMUTE_CONFIRMATION"
    case chat_unmuteDescription = "CHAT_UNMUTE_DESCRIPTION"
    case chat_unpin = "CHAT_UNPIN"
    case chat_useMedia = "CHAT_USE_MEDIA"
    case chat_userBlocked = "CHAT_USER_BLOCKED"
    case chat_userFallback = "CHAT_USER_FALLBACK"
    case chat_video = "CHAT_VIDEO"
    case chat_voteDetails = "CHAT_VOTE_DETAILS"
    case chat_yesterday = "CHAT_YESTERDAY"
    case chat_you = "CHAT_YOU"
    case delete = "Delete"
    case done = "DONE"
    case online = "online"
    case remove = "remove"
    case select_all = "SELECT_ALL"
    case somethingWentWrong = "something_went_wrong"
    case viewProfile = "View_Profile"
}

extension ChatStrings {
    func localizedString() -> String {
        ChatStrings.english[rawValue] ?? rawValue
    }

    static func getLocalizeString(title: ChatStrings) -> String {
        title.localizedString()
    }

    private static let english: [String: String] = [
        "Hold for video, tap for photo": "Hold for video, tap for photo",
        "CANCEL": "Cancel",
        "CHAT_1_MEMBER": "1 member",
        "CHAT_ACCESS_TO_PHOTOS_DENIED": "Access to photos denied",
        "CHAT_ACTIVE_USERS": "Active Users",
        "CHAT_ADD_LABEL_HERE": "Add your label here",
        "CHAT_ALLOW_CONTACT_ACCESS_MESSAGE": "Please allow contact access in Settings to share contacts.",
        "CHAT_APPLE_MAPS": "Apple Maps",
        "CHAT_ARCHIVE": "Archive",
        "CHAT_ARCHIVE_DESCRIPTION": "Are you sure you want to archive chat? You can find archived chat below search bar.",
        "CHAT_ARCHIVED": "Archived",
        "CHAT_AUDIO": "Audio",
        "CHAT_BLOCK": "Block",
        "CHAT_BLOCK_USER_CONFIRMATION": "Block User?",
        "CHAT_BLOCK_USER_DESCRIPTION": "Are you sure you want to block %@?",
        "CHAT_BLOCKED_USER_HINT": "You blocked this user",
        "CHAT_CALL": "Call",
        "CHAT_CAMERA": "Camera",
        "CHAT_CANCEL": "Cancel",
        "CHAT_CHANNEL_LABEL": "Channel",
        "CHAT_CHANNELS": "Channels",
        "CHAT_CHATS": "Chats",
        "CHAT_CLEAR_CHAT_ACTION": "Clear Chat",
        "CHAT_CLEAR_CHAT_CONFIRMATION": "Clear Chat?",
        "CHAT_CLEAR_CHAT_DESCRIPTION": "Are you sure you want to clear all messages in %@? This action cannot be undone.",
        "CHAT_CONTACT": "Contact",
        "CHAT_COPY": "Copy",
        "CHAT_COPY_PHONE": "Copy Phone Number",
        "CHAT_DELETE_CHANNEL": "Delete Channel",
        "CHAT_DELETE_CHANNEL_CONFIRMATION": "Are you sure you want to delete '%@'? This action cannot be undone.",
        "CHAT_DELETE_CHANNEL_DESCRIPTION": "Are you sure you want to delete the channel \"%@\"? This action cannot be undone.",
        "CHAT_DELETE_CHAT": "Delete Chat",
        "CHAT_DELETE_CHAT_CONFIRMATION": "Delete Chat?",
        "CHAT_DELETE_CHAT_DESCRIPTION": "Are you sure you want to delete the chat with %@? This action cannot be undone.",
        "CHAT_DELETE_CHATS": "Delete %d Chat(s)",
        "CHAT_DELETE_CHATS_CONFIRMATION": "Are you sure you want to delete %d chat(s)? This action cannot be undone.",
        "CHAT_DELETE_FOR_EVERYONE": "Delete for Everyone",
        "CHAT_DELETE_FOR_EVERYONE_CONFIRMATION": "Delete for Everyone?",
        "CHAT_DELETE_FOR_EVERYONE_DESCRIPTION": "This will delete all messages in this chat for both participants.",
        "CHAT_DELETE_FOR_ME": "Delete for Me",
        "CHAT_DELETE_FOR_ME_AND_USER": "Delete for me & %@",
        "CHAT_DELETE_GROUP": "Delete Group",
        "CHAT_DELETE_GROUP_CONFIRMATION": "Delete Group?",
        "CHAT_DELETE_GROUP_DESCRIPTION": "Are you sure you want to delete the group \"%@\"? This action cannot be undone.",
        "CHAT_DELETE_MESSAGE_CONFIRMATION": "Delete Message?",
        "CHAT_DELETE_MESSAGE_DESCRIPTION": "Are you sure you want to delete this message? This action cannot be undone.",
        "CHAT_THIS_MESSAGE_WILL_BE_DELETED_FOR_EVERYONE_IN_THIS_CHAT": "This message will be deleted for everyone in this chat.",
        "CHAT_THIS_MESSAGE_WILL_BE_DELETED_FOR_YOU_ONLY_OTHER_CHAT_MEMBERS_WILL_STILL_BE_ABLE_TO_SEE_IT": "This message will be deleted for you only. Other chat members will still be able to see it.",
        "CHAT_DELIVERED_TO": "Delivered To",
        "CHAT_DESELECT_ALL": "Deselect All",
        "CHAT_DOCUMENT": "Document",
        "CHAT_DRAFT": "Draft:",
        "CHAT_EDIT": "Edit",
        "CHAT_EDITED": "edited",
        "CHAT_EDITING_MESSAGE": "Editing message",
        "CHAT_ERROR_AUDIO_CORRUPT": "Cannot play audio. File may be corrupted.",
        "CHAT_ERROR_BLOCKED_USER_SEND": "Cannot send messages to blocked users.",
        "CHAT_ERROR_CONNECTION_LOST": "Connection lost. Check your internet and try again.",
        "CHAT_ERROR_FILE_TOO_LARGE": "File too large. Please choose a smaller file.",
        "CHAT_ERROR_FORWARD_FAILED": "Failed to forward message",
        "CHAT_ERROR_INVALID_CONTENT": "Message content is invalid or too long.",
        "CHAT_ERROR_LOAD_MESSAGES": "Failed to load messages. Pull to refresh.",
        "CHAT_ERROR_MEDIA_UPLOAD": "Media upload failed. Check your connection.",
        "CHAT_ERROR_NOT_DELIVERED": "Messages not yet delivered. Please try again.",
        "CHAT_ERROR_PERMISSION": "Permission denied. Check app settings.",
        "CHAT_ERROR_REALTIME_LOST": "Real-time connection lost. Messages may be delayed.",
        "CHAT_ERROR_RECORDING_FAILED": "Recording failed. Check microphone permissions.",
        "CHAT_ERROR_SEND_FAILED": "Message failed to send. Tap to retry.",
        "CHAT_EXIT_AND_DELETE_CHANNEL": "Exit & Delete Channel",
        "CHAT_EXIT_AND_DELETE_CHANNEL_DESCRIPTION": "Are you sure you want to exit and delete the channel \"%@\"? This action cannot be undone.",
        "CHAT_EXIT_AND_DELETE_GROUP": "Exit & Delete Group",
        "CHAT_EXIT_AND_DELETE_GROUP_DESCRIPTION": "Are you sure you want to exit and delete the group \"%@\"? This action cannot be undone.",
        "CHAT_FAILED_TO_SAVE": "Failed to save",
        "CHAT_FOLLOW_CHANNEL": "Follow Channel",
        "CHAT_FOLLOW_CHANNEL_HINT": "Follow this channel to stay updated",
        "CHAT_FOLLOWER": "Follower",
        "CHAT_FOLLOWERS": "Followers",
        "CHAT_FOLLOWING_STATUS": "Following",
        "CHAT_FORWARDED": "Forwarded",
        "CHAT_GETTING_ADDRESS": "Getting address...",
        "CHAT_GETTING_LOCATION": "Getting location...",
        "CHAT_GIVE_LABEL_INSTRUCTION": "Give a label to your chat below",
        "CHAT_GOOGLE_MAPS": "Google Maps",
        "CHAT_GROUP_BADGE": "Group",
        "CHAT_GROUP_CHAT": "Group Chat",
        "CHAT_GROUPS": "Groups",
        "CHAT_LABEL_CHAT": "Label Chat",
        "CHAT_LAST_SEEN": "Last seen",
        "CHAT_LEAVE_GROUP": "Leave Group",
        "CHAT_LEAVE_GROUP_CONFIRMATION": "Are you sure you want to leave this group? You won't be able to see new messages unless you're added back.",
        "CHAT_LEAVE_GROUP_DESCRIPTION": "Are you sure you want to leave %@? You will no longer receive messages from this group.",
        "CHAT_LOADING_CONTACTS": "Loading contacts...",
        "CHAT_LOADING_USERS": "Loading users...",
        "CHAT_LOCATION": "Location",
        "CHAT_LOCATION_CONTENT": "Location",
        "CHAT_LOCATION_PERMISSION_DENIED": "Location permission denied",
        "CHAT_LOCATION_PERMISSION_REQUIRED": "Location Permission Required",
        "CHAT_LOCATION_SERVICES_DISABLED": "Location services are turned off. Please enable them in Settings.",
        "CHAT_LOCATION_TIMEOUT": "Location request timed out",
        "CHAT_LOCATION_UNAVAILABLE": "Location Unavailable",
        "CHAT_LOCK_CHAT": "Lock chat",
        "CHAT_MARK_AS_READ": "Mark as Read",
        "CHAT_MARK_AS_UNREAD": "Mark as Unread",
        "CHAT_MEMBERS": "members",
        "CHAT_MESSAGE": "Message",
        "CHAT_MESSAGE_DELETED": "You deleted this message",
        "CHAT_MESSAGE_INFO": "Message Info",
        "CHAT_MESSAGES_DELETED": "messages deleted",
        "CHAT_MOMENT_NOTICE": "This will only take a moment",
        "CHAT_MORE_NUMBERS": "%@ more numbers",
        "CHAT_MUTE": "Mute",
        "CHAT_MUTE_CONFIRMATION": "Mute Chat?",
        "CHAT_MUTE_DESCRIPTION": "Are you sure you want to mute chat? You can unmute chat by dragging left.",
        "CHAT_NEW_CHAT": "New Chat",
        "CHAT_NEW_MESSAGE": "New message",
        "CHAT_NO_CHATS_YET": "No chats yet",
        "CHAT_NO_CONTACTS_FOUND": "No Contacts Found",
        "CHAT_NO_INFO_AVAILABLE": "No info available",
        "CHAT_YOU_ARE_NO_LONGER_A_MEMBER_OF_THIS_GROUP": "You are no longer a member of this group",
        "CHAT_NO_REACTIONS": "No reactions yet",
        "CHAT_NO_RESULTS_FOUND": "No results found",
        "CHAT_NO_VOTES": "No votes",
        "CHAT_NOTIFY_EVERYONE": "Notify everyone",
        "CHAT_NOW": "now",
        "CHAT_OFFLINE": "Offline",
        "CHAT_ONLINE": "Online",
        "CHAT_ONLY_CHANNEL_ADMINS_CAN_SEND_MESSAGES": "Only channel admins can send messages",
        "CHAT_OPEN_SETTINGS": "Open Settings",
        "CHAT_PHOTO": "Photo",
        "CHAT_PIN": "Pin",
        "CHAT_PINNED": "Pinned",
        "CHAT_PINNED_CHATS": "Pinned chats",
        "CHAT_PINNED_MESSAGE": "Pinned message",
        "CHAT_PLEASE_ENABLE_LOCATION_ACCESS_IN_SETTINGS_TO_SHARE_YOUR_LOCATION": "Please enable location access in Settings to share your location.",
        "CHAT_POLL": "Poll",
        "CHAT_POST": "Post",
        "CHAT_REACT": "React",
        "CHAT_READ_BY": "Read By",
        "CHAT_READ_MORE": "Read more",
        "CHAT_REEL": "Reel",
        "CHAT_REPLY": "Reply",
        "CHAT_REPORT_ACTION": "Report",
        "CHAT_REPORT_CONFIRMATION": "Report Chat?",
        "CHAT_REPORT_DESCRIPTION": "Are you sure you want to report %@? This will be reviewed by our team.",
        "CHAT_RETAKE": "Retake",
        "CHAT_RETRY": "Retry",
        "CHAT_SAVED_TO_PHOTOS": "Saved to Photos",
        "CHAT_SEARCH": "Search",
        "CHAT_SEARCH_CONTACTS": "Search contacts",
        "CHAT_SEARCH_USERS": "Search users...",
        "CHAT_SEE_ORIGINAL": "See Original",
        "CHAT_SELECT": "Select",
        "CHAT_SELECT_NUMBER": "Select number",
        "CHAT_SELECTED": "selected",
        "CHAT_SELECTED_COUNT_FORMAT": "%d selected",
        "CHAT_SEND_LOCATION": "Send Location",
        "CHAT_SEND_YOUR_CURRENT_LOCATION": "Send Your Current Location",
        "CHAT_SHARE_CHANNEL": "Share Channel",
        "CHAT_SHARE_CHANNEL_TEXT": "Join \"%@\" channel on OneVibe: %@",
        "CHAT_SHARE_CONTACT": "Share Contact",
        "CHAT_STICKER": "Sticker",
        "CHAT_STORY": "Story",
        "CHAT_SUCCESS_MESSAGE_FORWARDED": "Message forwarded",
        "CHAT_TAP_FOR_CONTACT_INFO": "Tap here for contact info",
        "CHAT_TAP_TO_REMOVE": "Tap to remove",
        "CHAT_TODAY": "Today",
        "CHAT_TRANSLATE": "Translate",
        "CHAT_TRANSLATED": "Translated",
        "CHAT_TYPING": "Typing...",
        "CHAT_UNABLE_GET_LOCATION": "Unable to get current location",
        "CHAT_UNBLOCK": "Unblock",
        "CHAT_UNBLOCK_TO_SEND": "Unblock %@ to send messages",
        "CHAT_UNBLOCK_USER_CONFIRMATION": "Unblock User?",
        "CHAT_UNBLOCK_USER_DESCRIPTION": "Are you sure you want to unblock %@? This user will be able to send you messages again.",
        "CHAT_UNFOLLOW_CHANNEL": "Unfollow Channel",
        "CHAT_UNFOLLOW_CHANNEL_CONFIRMATION": "Are you sure you want to unfollow '%@'? You can follow again anytime.",
        "CHAT_UNMUTE": "Unmute",
        "CHAT_UNMUTE_CONFIRMATION": "Unmute Chat?",
        "CHAT_UNMUTE_DESCRIPTION": "Are you sure you want to unmute %@? You will receive notifications from this chat again.",
        "CHAT_UNPIN": "Unpin",
        "CHAT_USE_MEDIA": "Send",
        "CHAT_USER_BLOCKED": "User Blocked",
        "CHAT_USER_FALLBACK": "User",
        "CHAT_VIDEO": "Video",
        "CHAT_VOTE_DETAILS": "Vote details",
        "CHAT_YESTERDAY": "Yesterday",
        "CHAT_YOU": "You",
        "Delete": "Delete",
        "DONE": "Done",
        "online": "Online",
        "remove": "Remove",
        "SELECT_ALL": "Select All",
        "something_went_wrong": "Something went wrong",
        "View_Profile": "View Profile",
    ]
}

extension String {
    func localizedString() -> String {
        NSLocalizedString(self, comment: "")
    }
}
