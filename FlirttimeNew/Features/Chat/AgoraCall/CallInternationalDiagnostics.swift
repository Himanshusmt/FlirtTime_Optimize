//
//  CallInternationalDiagnostics.swift
//  FlirttimeNew
//
//  Classifies India ↔ UAE/KZ call failures (API / signaling / Agora media)
//  and records Cloud Proxy mode for field tests.
//

import Foundation
import os.log
import CoreTelephony
import AgoraRtcKit

enum CallFailureLayer: String {
    case api
    case signaling
    case agoraMedia
    case unknown
}

enum CallCloudProxyStage: String {
    case auto = "none/auto"
    case udp = "udp"
    case tcp = "tcp"
}

/// Always-on diagnostics for international calling field tests (Dubai / Kazakhstan).
enum CallInternationalDiagnostics {

    private static let osLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.onevibe.live",
        category: "IntlCall"
    )

    private(set) static var lastCloudProxyStage: CallCloudProxyStage = .auto
    private(set) static var lastAgoraJoinAt: Date?
    private(set) static var lastAgoraConnectedAt: Date?
    private(set) static var lastRemoteMediaAt: Date?
    private(set) static var lastSignalingLatencyMs: Int?
    private(set) static var lastFailureLayer: CallFailureLayer?

    // MARK: - Environment

    /// ISO region from Locale (e.g. AE, KZ, IN).
    static var localeRegionCode: String {
        if #available(iOS 16, *) {
            return Locale.current.region?.identifier.uppercased() ?? ""
        }
        return Locale.current.regionCode?.uppercased() ?? ""
    }

    /// Mobile country codes currently attached (UAE=424, KZ=401).
    static var cellularMCCs: [String] {
        let info = CTTelephonyNetworkInfo()
        let providers = info.serviceSubscriberCellularProviders ?? [:]
        return providers.values.compactMap { carrier -> String? in
            let mcc = carrier.mobileCountryCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return mcc.isEmpty ? nil : mcc
        }
    }

    /// Locale or SIM suggests Middle East / Central Asia carriers that often block raw UDP VoIP.
    static var isRestrictedVoIPRegion: Bool {
        let region = localeRegionCode
        let restrictedRegions: Set<String> = [
            "AE", "KZ", "SA", "QA", "BH", "OM", "KW", "IQ", "IR", "PK"
        ]
        if restrictedRegions.contains(region) { return true }
        let mccs = Set(cellularMCCs)
        // UAE 424, Kazakhstan 401, Saudi 420, Qatar 427, Bahrain 426, Oman 422, Kuwait 419
        let restrictedMCCs: Set<String> = ["424", "401", "420", "427", "426", "422", "419"]
        return !mccs.isDisjoint(with: restrictedMCCs)
    }

    /// Force TCP Cloud Proxy only on restricted-region **cellular**. Wi-Fi stays UDP/auto for faster connect.
    static var prefersForcedTCPCloudProxy: Bool {
        guard isRestrictedVoIPRegion else { return false }
        return NetworkMonitor.shared.usesCellular
    }

    /// 720p upgrade is only safe on non-cellular, non-TCP paths.
    static var isExcellentWifiUpgradeAllowed: Bool {
        !NetworkMonitor.shared.usesCellular && !prefersForcedTCPCloudProxy
    }

    static var networkPathSummary: String {
        var parts: [String] = []
        parts.append("region=\(localeRegionCode.isEmpty ? "?" : localeRegionCode)")
        let mccs = cellularMCCs
        if !mccs.isEmpty {
            parts.append("mcc=\(mccs.joined(separator: ","))")
        }
        parts.append("cellular=\(NetworkMonitor.shared.usesCellular)")
        parts.append("preferTCP=\(prefersForcedTCPCloudProxy)")
        return parts.joined(separator: " ")
    }

    // MARK: - Logging

    static func log(_ message: String) {
        let text = message
        print("[IntlCall] \(text)")
        os_log("%{public}@", log: osLog, type: .info, text)
        AppLogger.debug("[IntlCall] \(text)")
    }

    static func logSessionStart(reason: String) {
        lastFailureLayer = nil
        lastAgoraJoinAt = nil
        lastAgoraConnectedAt = nil
        lastRemoteMediaAt = nil
        lastSignalingLatencyMs = nil
        log("sessionStart reason=\(reason) \(networkPathSummary) proxy=\(lastCloudProxyStage.rawValue)")
    }

    static func noteIncomingPresented(source: String, callId: String) {
        log("incomingUI source=\(source) callId=\(callId) \(networkPathSummary)")
    }

    static func noteCloudProxy(_ stage: CallCloudProxyStage) {
        lastCloudProxyStage = stage
        log("cloudProxy=\(stage.rawValue) \(networkPathSummary)")
    }

    static func noteSignaling(event: String, success: Bool, latencyMs: Int?) {
        if let latencyMs {
            lastSignalingLatencyMs = latencyMs
        }
        if !success {
            lastFailureLayer = .signaling
        }
        let lat = latencyMs.map(String.init) ?? "?"
        log("signaling event=\(event) ok=\(success) latencyMs=\(lat)")
    }

    static func noteAPI(event: String, success: Bool, detail: String = "") {
        if !success {
            lastFailureLayer = .api
        }
        log("api event=\(event) ok=\(success) \(detail)")
    }

    static func noteAgoraJoinStarted(channel: String, proxy: CallCloudProxyStage) {
        lastAgoraJoinAt = Date()
        noteCloudProxy(proxy)
        log("agoraJoinStart channel=\(channel) proxy=\(proxy.rawValue)")
    }

    static func noteAgoraConnected() {
        lastAgoraConnectedAt = Date()
        let elapsed: String
        if let start = lastAgoraJoinAt {
            elapsed = String(Int(Date().timeIntervalSince(start) * 1000))
        } else {
            elapsed = "?"
        }
        log("agoraConnected elapsedMs=\(elapsed) proxy=\(lastCloudProxyStage.rawValue)")
    }

    static func noteAgoraConnection(
        state: AgoraConnectionState,
        reason: AgoraConnectionChangedReason
    ) {
        log(
            "agoraConnection state=\(state.rawValue) reason=\(reason.rawValue) proxy=\(lastCloudProxyStage.rawValue)"
        )
        if state == .failed {
            lastFailureLayer = .agoraMedia
        }
        if state == .connected {
            noteAgoraConnected()
        }
    }

    static func noteRemoteMedia(kind: String) {
        if lastRemoteMediaAt == nil {
            lastRemoteMediaAt = Date()
            let elapsed: String
            if let start = lastAgoraConnectedAt ?? lastAgoraJoinAt {
                elapsed = String(Int(Date().timeIntervalSince(start) * 1000))
            } else {
                elapsed = "?"
            }
            log("firstRemoteMedia kind=\(kind) sinceJoinMs=\(elapsed) proxy=\(lastCloudProxyStage.rawValue)")
        }
    }

    static func noteFailure(layer: CallFailureLayer, detail: String) {
        lastFailureLayer = layer
        log("FAIL layer=\(layer.rawValue) \(detail) proxy=\(lastCloudProxyStage.rawValue) \(networkPathSummary)")
    }

    static func classifySnapshot() -> String {
        let layer = lastFailureLayer?.rawValue ?? "none"
        return [
            "layer=\(layer)",
            "proxy=\(lastCloudProxyStage.rawValue)",
            "signalingMs=\(lastSignalingLatencyMs.map(String.init) ?? "?")",
            "joined=\(lastAgoraJoinAt != nil)",
            "connected=\(lastAgoraConnectedAt != nil)",
            "remoteMedia=\(lastRemoteMediaAt != nil)",
            networkPathSummary
        ].joined(separator: " ")
    }
}
