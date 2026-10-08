//
//  ChatDetailSharedHelpers.swift
//  FlirttimeNew
//
//  Created by Awais on 23/01/26.
//

import SwiftUI

extension Notification.Name {
    static let chatDetailRefreshHeader = Notification.Name("ChatDetailRefreshHeader")
    static let chatDetailSetBlocked = Notification.Name("ChatDetailSetBlocked")
    static let dismissChatDetail = Notification.Name("DismissChatDetail")
    static let conversationRemovedByServer = Notification.Name("ConversationRemovedByServer")
}

extension View {
    @ViewBuilder
    func applyIf<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

func safeAreaTopInset() -> CGFloat {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = windowScene.windows.first else { return 0 }
    return window.safeAreaInsets.top
}

// MARK: - UIApplication Top View Controller

extension UIApplication {
    func topViewController() -> UIViewController? {
        guard let windowScene = connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        guard let root = window.rootViewController else { return nil }
        return deepestViewController(from: root)
    }

    /// Finds the actual visible controller by walking through nav, tab, and presented hierarchies.
    func deepestViewController(from controller: UIViewController) -> UIViewController {
        if let nav = controller as? UINavigationController, let visible = nav.visibleViewController {
            return deepestViewController(from: visible)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return deepestViewController(from: selected)
        }
        if let presented = controller.presentedViewController {
            return deepestViewController(from: presented)
        }
        return controller
    }

    /// Safely presents a view controller by finding the topmost controller with a valid presentation context.
    func safelyPresent(_ vc: UIViewController, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let top = topViewController() else { return }
        top.present(vc, animated: animated, completion: completion)
    }

    /// Safely pushes a view controller by finding the nearest navigation controller.
    func safelyPush(_ vc: UIViewController, animated: Bool = false) {
        guard let top = topViewController() else { return }
        if let nav = top.navigationController {
            nav.pushViewController(vc, animated: animated)
        } else {
            top.present(UINavigationController(rootViewController: vc), animated: animated)
        }
    }
}

// MARK: - Date Formatter Cache

enum DateFormatterCache {
    static let isoParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        f.timeZone = TimeZone(abbreviation: "UTC")
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

func formatMessageTime(_ dateString: String) -> String {
    if let date = DateFormatterCache.isoParser.date(from: dateString) {
        return DateFormatterCache.timeFormatter.string(from: date)
    }
    return ""
}

func formatSeenTime(_ dateString: String?) -> String {
    guard let dateString = dateString else { return "" }
    if let date = DateFormatterCache.isoParser.date(from: dateString) {
        return DateFormatterCache.timeFormatter.string(from: date)
    }
    return ""
}

// MARK: - Audio Helpers

func getAudioDuration(from message: ConversationMessage) -> String {
    if let seconds = audioDurationSeconds(from: message), seconds > 0 {
        return formatAudioDuration(seconds)
    }
    return "00:00"
}

private func audioDurationValue(from raw: Any?) -> Double? {
    guard let raw else { return nil }
    if let d = raw as? Double, d > 0.05 { return d }
    if let i = raw as? Int, i > 0 { return Double(i) }
    if let n = raw as? NSNumber, n.doubleValue > 0.05 { return n.doubleValue }
    if let s = raw as? String, !s.isEmpty {
        if s.contains(":") {
            let parts = s.split(separator: ":")
            if parts.count == 2,
               let minutes = Double(parts[0]),
               let secs = Double(parts[1]) {
                let total = minutes * 60 + secs
                if total > 0.05 { return total }
            }
        } else if let d = Double(s), d > 0.05 {
            return d
        }
    }
    return nil
}

/// Shared numeric duration extractor used by bubbles and playback countdown.
func audioDurationSeconds(from message: ConversationMessage) -> Double? {
    let metaKeys = ["audioDuration", "audio_duration", "duration", "file_duration", "length", "audioLength"]
    if let metadata = message.metadata {
        for key in metaKeys {
            if let seconds = audioDurationValue(from: metadata[key]?.value) {
                return seconds
            }
        }
    }
    if let media = message.media?.first {
        if let duration = media.duration, duration > 0.05 {
            return duration
        }
        if let raw = media.raw {
            for key in metaKeys {
                if let seconds = audioDurationValue(from: raw[key]?.value) {
                    return seconds
                }
            }
        }
    }
    return nil
}

/// Local audio file may be stored under server id, stableId, or clientTempId.
func localAudioFileURL(for message: ConversationMessage) -> URL? {
    var candidateIds: [String] = []
    let add: (String?) -> Void = { value in
        guard let value, !value.isEmpty, !candidateIds.contains(value) else { return }
        candidateIds.append(value)
    }
    add(message.id)
    add(message.stableId)
    add(message.metadata?["clientTempId"]?.value as? String)

    for id in candidateIds {
        if let url = MediaStorageManager.shared.getMediaURL(messageId: id, type: .audio) {
            return url
        }
    }
    if let resolved = message.resolvedMediaURL, resolved.isFileURL,
       FileManager.default.fileExists(atPath: resolved.path) {
        return resolved
    }
    return nil
}

func formatAudioDuration(_ seconds: Double) -> String {
    let totalSeconds = Int(seconds.rounded())
    let minutes = totalSeconds / 60
    let remainingSeconds = totalSeconds % 60
    return String(format: "%02d:%02d", minutes, remainingSeconds)
}

func generateWaveAmplitudes(from seed: String, length: Int = 32) -> [CGFloat] {
    var value: UInt64 = 1469598103934665603
    for byte in seed.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
    var rng = value
    var result: [CGFloat] = []
    result.reserveCapacity(length)
    for _ in 0..<length {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        let normalized = CGFloat((rng % 100) + 10) / 110.0
        result.append(normalized)
    }
    return result
}

// MARK: - SwiftUI Corner Radius Helper

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }

    @ViewBuilder
    func rtlMirror() -> some View {
        if UIApplication.isRTL() {
            self.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        } else {
            self
        }
    }

    @ViewBuilder
    func applyRTLEnvironment() -> some View {
        if UIApplication.isRTL() {
            self.environment(\.layoutDirection, .rightToLeft)
        } else {
            self
        }
    }

    /// Dismisses the keyboard when tapping outside text input fields.
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        )
    }
}

// MARK: - RTL TextField
struct RTLTextField: View {
    let placeholder: String
    @Binding var text: String
    var fontSize: CGFloat = 14
    var isFocused: Binding<Bool>? = nil
    var onReturn: (() -> Void)? = nil

    init(_ placeholder: String, text: Binding<String>, fontSize: CGFloat = 14, isFocused: Binding<Bool>? = nil, onReturn: (() -> Void)? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.fontSize = fontSize
        self.isFocused = isFocused
        self.onReturn = onReturn
    }

    var body: some View {
        _RTLTextFieldRep(
            placeholder: placeholder,
            text: $text,
            font: UIFont(name: "Fredoka-Regular", size: fontSize) ?? UIFont.chat(size: fontSize),
            isFocused: isFocused,
            onReturn: onReturn
        )
//        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct _RTLTextFieldRep: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let font: UIFont
    let isFocused: Binding<Bool>?
    let onReturn: (() -> Void)?

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.font = font
        tf.textColor = ChatTheme.textPrimary
        tf.placeholder = placeholder
        tf.textAlignment = UIApplication.isRTL() ? .right : .left
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)      // ← add this
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) // ← add this
        tf.setContentHuggingPriority(.required, for: .vertical)
        tf.setContentCompressionResistancePriority(.required, for: .vertical)
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        if tf.text != text { tf.text = text }
        tf.placeholder = placeholder
        tf.textAlignment = UIApplication.isRTL() ? .right : .left
        tf.font = font
        if let focused = isFocused, focused.wrappedValue {
            tf.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onReturn: onReturn) }

    class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        let onReturn: (() -> Void)?

        init(text: Binding<String>, onReturn: (() -> Void)?) {
            self.text = text
            self.onReturn = onReturn
        }

        @objc func textChanged(_ tf: UITextField) { text.wrappedValue = tf.text ?? "" }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            onReturn?()
            tf.resignFirstResponder()
            return true
        }
    }
}

// MARK: - RTL-Aware Text Alignment (UIKit)

extension NSTextAlignment {
    static var leading: NSTextAlignment {
        UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft ? .right : .left
    }

    static var trailing: NSTextAlignment {
        UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft ? .left : .right
    }
}

// MARK: - RTL Layout Direction Enforcement

extension UIView {
    func enforceRTLIfNeeded() {
        guard UIApplication.isRTL() else { return }
        semanticContentAttribute = .forceRightToLeft
        for subview in subviews {
            subview.enforceRTLIfNeeded()
        }
    }
}

// MARK: - Map Snapshot Cache

import MapKit
import CoreLocation

final class MapSnapshotCache {
    static let shared = MapSnapshotCache()
    private let memCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        return cache
    }()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    private static let cacheVersion = 3
    private static let cacheVersionKey = "MapSnapshotCacheVersion"

    private let diskCacheDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("MapSnapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        let stored = ChatUserDefaultsStore.shared.getInteger(forKey: Self.cacheVersionKey)
        if stored != Self.cacheVersion {
            if let files = try? FileManager.default.contentsOfDirectory(
                at: diskCacheDir, includingPropertiesForKeys: nil
            ) {
                for file in files { try? FileManager.default.removeItem(at: file) }
            }
            ChatUserDefaultsStore.shared.setInteger(Self.cacheVersion, forKey: Self.cacheVersionKey)
        }
    }

    func key(lat: Double, lng: Double) -> String {
        String(format: "%.6f_%.6f", lat, lng)
    }

    func memGet(lat: Double, lng: Double) -> UIImage? {
        let k = key(lat: lat, lng: lng)
        lock.lock(); defer { lock.unlock() }
        return memCache.object(forKey: k as NSString)
    }

    func diskGet(lat: Double, lng: Double) -> UIImage? {
        let k = key(lat: lat, lng: lng)
        let url = diskCacheDir.appendingPathComponent("\(k).jpg")
        guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return nil }
        lock.lock(); memCache.setObject(img, forKey: k as NSString); lock.unlock()
        return img
    }

    private func storeToDisk(key k: String, image: UIImage) {
        let url = diskCacheDir.appendingPathComponent("\(k).jpg")
        DispatchQueue.global(qos: .utility).async {
            guard let data = image.jpegData(compressionQuality: 0.88) else { return }
            try? data.write(to: url)
        }
    }

    private func checkOrRegisterTask(key k: String, lat: Double, lng: Double) -> (task: Task<UIImage?, Never>, isNew: Bool) {
        lock.lock(); defer { lock.unlock() }
        if let existing = inFlightTasks[k] { return (existing, false) }
        let task = Task<UIImage?, Never> {
            if let img = MapSnapshotCache.shared.diskGet(lat: lat, lng: lng) { return img }
            return await MapSnapshotCache.shared._runSnapshotter(lat: lat, lng: lng)
        }
        inFlightTasks[k] = task
        return (task, true)
    }

    private func commitResult(key k: String, image: UIImage) {
        lock.lock(); defer { lock.unlock() }
        memCache.setObject(image, forKey: k as NSString)
        inFlightTasks.removeValue(forKey: k)
    }

    private func removeInFlight(key k: String) {
        lock.lock(); defer { lock.unlock() }
        inFlightTasks.removeValue(forKey: k)
    }

    func generate(lat: Double, lng: Double) async -> UIImage? {
        let k = key(lat: lat, lng: lng)
        if let img = memGet(lat: lat, lng: lng) { return img }
        let (task, isNew) = checkOrRegisterTask(key: k, lat: lat, lng: lng)
        let result = await task.value
        if isNew {
            if let result {
                commitResult(key: k, image: result)
                storeToDisk(key: k, image: result)
            } else {
                removeInFlight(key: k)
            }
        }
        return result
    }

    func prewarmNow(lat: Double, lng: Double) {
        guard memGet(lat: lat, lng: lng) == nil else { return }
        Task(priority: .userInitiated) {
            _ = await MapSnapshotCache.shared.generate(lat: lat, lng: lng)
        }
    }

    func prewarm(lat: Double, lng: Double) {
        guard memGet(lat: lat, lng: lng) == nil else { return }
        Task(priority: .utility) {
            _ = await MapSnapshotCache.shared.generate(lat: lat, lng: lng)
        }
    }

    fileprivate func _runSnapshotter(lat: Double, lng: Double) async -> UIImage? {
        let bubbleWidth = (UIScreen.main.bounds.width * 0.70).rounded()
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        )
        options.size = CGSize(width: bubbleWidth, height: 180)
        options.scale = UIScreen.main.scale
        options.mapType = .standard
        options.showsBuildings = true
        guard let result = try? await MKMapSnapshotter(options: options).start() else { return nil }
        return result.image
    }
}

// MARK: - Group Participants Helper

func extractGroupParticipants(from chat: ChatMessageRow) -> [GroupParticipant] {
    guard let participants = chat.participants else { return [] }
    return participants.compactMap { participant in
        guard let userId = participant.userId ?? participant.user?.userId ?? participant.user?.id,
              participant.isActive != false else { return nil }
        let details = participant.user?.userDetails?.first
        let userName = GroupParticipantDisplay.cleanName(
            details?.userName ?? participant.user?.username
        ) ?? ""
        let fullName = GroupParticipantDisplay.cleanName(
            details?.fullName ?? participant.user?.fullName
        ) ?? userName
        let profilePicture = details?.profilePictureDetails?.filePath
            ?? details?.profilePicture
            ?? participant.user?.profileImage
        return GroupParticipant(
            id: participant.id ?? userId,
            userId: userId,
            role: participant.role ?? "member",
            userName: userName,
            fullName: fullName,
            profilePicture: profilePicture,
            isVerified: participant.resolvedIsVerified
        )
    }
}

/// Shared helpers so group UI never shows raw user UUIDs as “names”.
enum GroupParticipantDisplay {
    /// Returns a trimmed human name, or nil if empty / looks like a user id.
    static func cleanName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeUserId(trimmed) else { return nil }
        return trimmed
    }

    static func looksLikeUserId(_ value: String) -> Bool {
        // UUID (with/without dashes) or long hex-ish ids
        let compact = value.replacingOccurrences(of: "-", with: "")
        if compact.count >= 32, compact.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil {
            return true
        }
        if value.count >= 20, value.range(of: "^[0-9a-fA-F-]+$", options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// FE: `fullName?.trim() || username` — never the raw id.
    static func displayName(fullName: String, userName: String, fallback: String = "Member") -> String {
        if let name = cleanName(fullName) { return name }
        if let name = cleanName(userName) { return name }
        return fallback
    }
}
