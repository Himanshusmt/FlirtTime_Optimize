//
//  PhoneOTPProofService.swift
//  FlirttimeNew
//

import Foundation
import RxSwift
import Swinject
import UIKit

/// Firebase iOS phone-auth proof. `verify-client` starts the silent push;
/// `request-otp` must send the receipt + secret from that same push.
final class PhoneOTPProofService {

    static let shared = PhoneOTPProofService()

    private static let firebaseAuthKey = "com.google.firebase.auth"
    private static let secretTimeout: TimeInterval = 20

    private struct PushProof {
        let receipt: String?
        let secret: String
    }

    private let sessionManager: AppSessionManager
    private let lock = NSLock()
    private var proofWaiter: ((PushProof) -> Void)?
    private var bufferedProof: (value: PushProof, date: Date)?

    private init(sessionManager: AppSessionManager = Container.appContainer.resolve(AppSessionManager.self)!) {
        self.sessionManager = sessionManager
    }

    /// Call from AppDelegate when a silent push arrives. Returns true if it was a Firebase auth payload.
    @discardableResult
    func handleSilentPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let proof = Self.proof(from: userInfo) else { return false }
        lock.lock()
        if let waiter = proofWaiter {
            proofWaiter = nil
            bufferedProof = nil
            lock.unlock()
            waiter(proof)
        } else {
            bufferedProof = (proof, Date())
            lock.unlock()
        }
        return true
    }

    /// Secret always comes from the silent push. Receipt prefers the push, then `verify-client`.
    func collectProof() -> Single<(receipt: String, secret: String)> {
        beginProof()
        return ensureAPNsToken()
            .flatMap { [weak self] token -> Single<(PhoneIOSClientVerification, PushProof)> in
                guard let self else { return .error(APIError.apiError("Unable to verify this device")) }
                let verify = self.sessionManager.verifyPhoneIOSClient(
                    apnsToken: token,
                    isSandbox: Self.isSandbox,
                    bundleId: Bundle.main.bundleIdentifier ?? "com.flirttime"
                )
                return Single.zip(verify, self.waitForProof())
            }
            .map { verification, push in
                let receipt = [push.receipt, verification.receipt]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                guard let receipt else {
                    throw APIError.apiError("Couldn't verify this device. Please try again.")
                }
                return (receipt, push.secret)
            }
    }

    // MARK: - APNs

    private func ensureAPNsToken() -> Single<String> {
        if let token = DeviceTokenManager.shared.apnsToken, !token.isEmpty {
            return .just(token)
        }
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return Single.create { observer in
            var attempts = 0
            var work: DispatchWorkItem?
            func poll() {
                if let token = DeviceTokenManager.shared.apnsToken, !token.isEmpty {
                    observer(.success(token))
                    return
                }
                attempts += 1
                if attempts >= 20 {
                    observer(.failure(APIError.apiError("Turn on notifications to send a verification code.")))
                    return
                }
                let next = DispatchWorkItem { poll() }
                work = next
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: next)
            }
            poll()
            return Disposables.create { work?.cancel() }
        }
    }

    // MARK: - Silent push

    private func beginProof() {
        lock.lock()
        proofWaiter = nil
        bufferedProof = nil
        lock.unlock()
    }

    private func waitForProof() -> Single<PushProof> {
        Single.create { [weak self] observer in
            guard let self else {
                observer(.failure(APIError.apiError("Unable to verify this device")))
                return Disposables.create()
            }

            self.lock.lock()
            if let buffered = self.bufferedProof,
               Date().timeIntervalSince(buffered.date) < Self.secretTimeout {
                self.bufferedProof = nil
                self.lock.unlock()
                observer(.success(buffered.value))
                return Disposables.create()
            }

            self.proofWaiter = { proof in
                observer(.success(proof))
            }
            self.lock.unlock()

            let timeout = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let pending = self.proofWaiter != nil
                self.proofWaiter = nil
                self.lock.unlock()
                if pending {
                    observer(.failure(APIError.apiError("Couldn't verify this device. Check notification permission and try again.")))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.secretTimeout, execute: timeout)
            return Disposables.create {
                timeout.cancel()
                self.lock.lock()
                self.proofWaiter = nil
                self.lock.unlock()
            }
        }
    }

    private static func proof(from userInfo: [AnyHashable: Any]) -> PushProof? {
        let value = userInfo[firebaseAuthKey]
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{"),
               let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return proof(fromJSON: json)
            }
            return trimmed.isEmpty ? nil : PushProof(receipt: nil, secret: trimmed)
        }
        if let json = value as? [String: Any] {
            return proof(fromJSON: json)
        }
        return nil
    }

    private static func proof(fromJSON json: [String: Any]) -> PushProof? {
        let secret = text(json["secret"]) ?? text(json["iosSecret"])
        guard let secret else { return nil }
        return PushProof(receipt: text(json["receipt"]) ?? text(json["iosReceipt"]), secret: secret)
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static var isSandbox: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
