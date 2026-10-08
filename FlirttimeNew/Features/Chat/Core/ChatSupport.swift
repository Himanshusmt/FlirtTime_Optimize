//
//  ChatSupport.swift
//  FlirttimeNew
//

import UIKit
import Alamofire
import Swinject

/// Reacts to the chat backend rejecting the session (401 after a failed refresh).
final class SessionExpiredManager {
    static let shared = SessionExpiredManager()

    private(set) var isHandling = false

    /// Returns true when the error is an expired session and has been handled.
    @discardableResult
    func handleIfNeeded(_ error: Error) -> Bool {
        guard httpStatusCode(from: error) == 401 else { return false }
        handleSessionExpired()
        return true
    }

    func handleSessionExpired() {
        guard !isHandling else { return }
        isHandling = true
        NotificationCenter.default.post(name: .chatSessionExpired, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.isHandling = false
        }
    }

    func resetAfterSuccessfulLogin() {
        isHandling = false
    }
}

extension Container {
    func require<Service>(_ serviceType: Service.Type) -> Service {
        guard let service = resolve(serviceType) else {
            fatalError("Chat dependency \(serviceType) is not registered")
        }
        return service
    }
}

extension UIApplication {
    class func isRTL() -> Bool {
        UIView.userInterfaceLayoutDirection(for: .unspecified) == .rightToLeft
    }

    class func getLanguageCode() -> String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}

func httpStatusCode(from error: Error) -> Int? {
    if let httpError = error as? APIHTTPError {
        return httpError.statusCode
    }
    if let afError = error.asAFError {
        switch afError {
        case .responseValidationFailed(let reason):
            if case .unacceptableStatusCode(let code) = reason {
                return code
            }
        case .sessionTaskFailed(let underlying):
            return httpStatusCode(from: underlying)
        default:
            break
        }
        return afError.responseCode
    }
    return nil
}

func parseError(_ error: Error) -> String? {
    if let httpError = error as? APIHTTPError {
        return httpError.message
    }
    if let apiError = error as? APIError, case .apiError(let message) = apiError {
        return message
    }
    return error.localizedDescription
}

extension String {
    /// Strips HTML tags and decodes common entities for plain-text display.
    var htmlToString: String {
        var text = trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains("<") || text.contains("&") else { return text }
        text = text
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</(p|div|li)>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    var containsHTMLMarkup: Bool {
        range(of: #"</?[a-zA-Z][^>]*>"#, options: .regularExpression) != nil
            || range(of: #"&(#\d+|#x[0-9a-fA-F]+|\w+);"#, options: .regularExpression) != nil
    }
}

/// Language code used for chat translation and localized API responses.
func getSelectedLanguage() -> String {
    UIApplication.getLanguageCode()
}

extension Notification.Name {
    static let conversationIconUpdated = Notification.Name("ConversationIconUpdated")
    static let agoraGroupCallRejoinDidChange = Notification.Name("agoraGroupCallRejoinDidChange")
}

extension String {
    var isNotEmpty: Bool { !isEmpty }
}

extension Date {
    func timeAgoDisplay() -> String {
        if Date().timeIntervalSince(self) < 60 {
            return "Just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
