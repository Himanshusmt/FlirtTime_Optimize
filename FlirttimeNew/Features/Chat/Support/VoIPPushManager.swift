//
//  VoIPPushManager.swift
//  FlirttimeNew
//
//  Matches OneVibe: retain PKPushRegistry on a long-lived object and install it
//  before Firebase/UI work so kill-state VoIP is delivered.
//

import Foundation
import PushKit
import UIKit

final class VoIPPushManager: NSObject {

    static let shared = VoIPPushManager()

    /// Must be retained — a local PKPushRegistry is released and VoIP stops delivering.
    private var voipPushRegistry: PKPushRegistry?
    private var didStart = false

    private override init() {
        super.init()
    }

    /// Call FIRST in `didFinishLaunching` — before Firebase / chat / UI.
    func start() {
        guard !didStart else { return }
        didStart = true
        let voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [.voIP]
        voipPushRegistry = voipRegistry
        let bundleId = Bundle.main.bundleIdentifier ?? "?"
        AppLogger.killCall("PushKit registry installed (desiredPushTypes=voIP) bundleId=\(bundleId)")
        AppLogger.killCall("Backend APNS_VOIP_TOPIC MUST be exactly: \(bundleId).voip")
    }
}

extension VoIPPushManager: PKPushRegistryDelegate {

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        AppLogger.killCall("VoIP token UPDATED len=\(token.count) tokenPrefix=\(token.prefix(16))…")
        AppLogger.killCall("Backend MUST send PushKit VoIP (push type voip) to this token for killed-app CallKit")
        #if DEBUG
        print("VoIP token: \(token)")
        #endif
        DeviceTokenManager.shared.update(voipToken: token)
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        AppLogger.killCall("VoIP token INVALIDATED")
        DeviceTokenManager.shared.clearVoIPToken()
        DeviceTokenManager.shared.registerIfNeeded(force: true)
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }
        let root = IncomingCallPushRouter.normalizeUserInfo(payload.dictionaryPayload)
        IncomingCallPushRouter.handleVoIPPush(root: root, completion: completion)
    }
}
