//
//  LiveStreamingView.swift
//  FlirttimeNew
//
//  Live Streaming Interface with Host / Audience separation & Co-Hosting Request Approval
//

import SwiftUI
import AgoraRtcKit

struct LiveStreamingView: View {
    @ObservedObject var manager = LiveStreamingManager.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var showSettingsSheet = false
    @State private var showEndAlert = false
    @State private var showCoHostRequestsSheet = false
    @State private var isPulsing = false

    var onDismiss: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // MARK: - Video Layer
            videoLayer

            // MARK: - Overlay Controls
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                // Host: Banner for incoming request
                if manager.isHost, let firstReq = manager.incomingCoHostRequests.first {
                    coHostRequestPromptBanner(firstReq)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Temporary Banner notifications
                if let banner = manager.bannerNotification {
                    infoBanner(message: banner)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Spacer()

                if let error = manager.errorMessage {
                    errorBanner(message: error)
                        .padding(.horizontal, 16)
                }

                bottomControls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            isPulsing = true
            if manager.status == .idle {
                // Default mode is viewer unless already configured
                manager.joinLiveStream(asHost: manager.isHost)
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(isPresented: $showSettingsSheet) {
            LiveStreamingSettingsSheet()
        }
        .sheet(isPresented: $showCoHostRequestsSheet) {
            CoHostRequestsListView()
        }
        .alert(isPresented: $showEndAlert) {
            Alert(
                title: Text(manager.isHost ? "End Live Stream" : "Leave Live Stream"),
                message: Text(manager.isHost ? "Are you sure you want to end this live broadcast?" : "Are you sure you want to leave?"),
                primaryButton: .destructive(Text(manager.isHost ? "End" : "Leave")) {
                    manager.leaveLiveStream()
                    presentationMode.wrappedValue.dismiss()
                    onDismiss?()
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Video Layer

    @ViewBuilder
    private var videoLayer: some View {
        if manager.isHost {
            // HOST VIEW: Full screen local camera
            if manager.isVideoEnabled {
                LiveVideoCanvasView(isLocal: true)
                    .ignoresSafeArea()
            } else {
                cameraOffPlaceholder
            }

            // Co-Host Remote Video in top right PiP
            if let coHost = manager.coHostUid {
                coHostPiPView(remoteUid: coHost, title: "Co-Host")
            }
        } else if manager.isCoHosting {
            // VIEWER IS CO-HOSTING: Full screen host video, local video in PiP
            if let host = manager.hostUid ?? manager.activeRemoteUid {
                LiveVideoCanvasView(isLocal: false, remoteUid: host)
                    .ignoresSafeArea()
            } else {
                waitingForHostPlaceholder
            }

            // Local PiP for co-host
            VStack {
                HStack {
                    Spacer()
                    ZStack(alignment: .bottomLeading) {
                        if manager.isVideoEnabled {
                            LiveVideoCanvasView(isLocal: true)
                                .frame(width: 110, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.6), lineWidth: 2)
                                )
                                .shadow(radius: 6)
                        } else {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.gray.opacity(0.4))
                                .frame(width: 110, height: 160)
                                .overlay(
                                    SwiftUI.Image(systemName: "video.slash.fill")
                                        .foregroundColor(.white)
                                )
                        }

                        Text("You (Live)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.85))
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }
                Spacer()
            }
            .padding(.top, 70)
            .padding(.trailing, 16)
        } else {
            // STANDARD AUDIENCE/VIEWER VIEW: Watch host full-screen
            if let host = manager.hostUid ?? manager.activeRemoteUid {
                LiveVideoCanvasView(isLocal: false, remoteUid: host)
                    .ignoresSafeArea()

                // If a co-host is present in the stream, show their PiP to viewers as well
                if let coHost = manager.coHostUid {
                    coHostPiPView(remoteUid: coHost, title: "Guest")
                }
            } else {
                waitingForHostPlaceholder
            }
        }
    }

    private func coHostPiPView(remoteUid: UInt, title: String) -> some View {
        VStack {
            HStack {
                Spacer()
                ZStack(alignment: .bottomLeading) {
                    LiveVideoCanvasView(isLocal: false, remoteUid: remoteUid)
                        .frame(width: 110, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.green.opacity(0.8), lineWidth: 2)
                        )
                        .shadow(radius: 8)

                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.9))
                        .clipShape(Capsule())
                        .padding(6)
                }
            }
            Spacer()
        }
        .padding(.top, 70)
        .padding(.trailing, 16)
    }

    private var cameraOffPlaceholder: some View {
        VStack(spacing: 12) {
            SwiftUI.Image(systemName: "video.slash.fill")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.6))
            Text("Camera Off")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var waitingForHostPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.4)

            Text("Waiting for Host...")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Text("Channel: \(LiveStreamingConfig.currentChannelName)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            // Live indicator badge
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(isPulsing ? 1.0 : 0.3)
                    .animation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

                Text(manager.isHost ? "HOST" : (manager.isCoHosting ? "CO-HOST" : "VIEWER"))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.white)

                Text(formattedDuration(manager.streamDuration))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65))
            .clipShape(Capsule())

            // Channel name pill
            HStack(spacing: 4) {
                SwiftUI.Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                Text(LiveStreamingConfig.currentChannelName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())

            Spacer()

            // Host: Co-Host Requests button with badge
            if manager.isHost && !manager.incomingCoHostRequests.isEmpty {
                Button {
                    showCoHostRequestsSheet = true
                } label: {
                    HStack(spacing: 4) {
                        SwiftUI.Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("\(manager.incomingCoHostRequests.count)")
                            .font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                }
            }

            // Viewers count pill
            HStack(spacing: 4) {
                SwiftUI.Image(systemName: "eye.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                Text("\(max(1, manager.remoteUids.count + 1))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())

            // Close button
            Button {
                showEndAlert = true
            } label: {
                SwiftUI.Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Host Banner for Incoming Request

    private func coHostRequestPromptBanner(_ req: CoHostRequest) -> some View {
        HStack(spacing: 12) {
            SwiftUI.Image(systemName: "video.badge.plus")
                .font(.system(size: 20))
                .foregroundColor(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(req.userName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("Wants to share their video with you")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
            }

            Spacer()

            Button("Decline") {
                withAnimation {
                    manager.rejectCoHostRequest(req)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.18))
            .clipShape(Capsule())

            Button("Accept") {
                withAnimation {
                    manager.acceptCoHostRequest(req)
                }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.85))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow.opacity(0.6), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 6)
    }

    // MARK: - Info / Notification Banner

    private func infoBanner(message: String) -> some View {
        HStack(spacing: 8) {
            SwiftUI.Image(systemName: "info.circle.fill")
                .foregroundColor(.cyan)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Button {
                manager.bannerNotification = nil
            } label: {
                SwiftUI.Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            SwiftUI.Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()
            Button("Settings") {
                showSettingsSheet = true
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.yellow)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 8)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 12) {
            if manager.isHost || manager.isCoHosting {
                // Broadcaster Controls (Camera flip, Mute, Video On/Off)
                controlButton(
                    icon: "camera.rotate.fill",
                    title: "Flip",
                    isActive: false
                ) {
                    manager.switchCamera()
                }

                controlButton(
                    icon: manager.isMuted ? "mic.slash.fill" : "mic.fill",
                    title: manager.isMuted ? "Unmute" : "Mute",
                    isActive: manager.isMuted
                ) {
                    manager.toggleMute()
                }

                controlButton(
                    icon: manager.isVideoEnabled ? "video.fill" : "video.slash.fill",
                    title: manager.isVideoEnabled ? "Cam Off" : "Cam On",
                    isActive: !manager.isVideoEnabled
                ) {
                    manager.toggleVideo()
                }

                // If Co-Host, provide button to stop sharing
                if manager.isCoHosting {
                    Button {
                        manager.stopCoHosting()
                    } label: {
                        HStack(spacing: 4) {
                            SwiftUI.Image(systemName: "video.slash")
                            Text("Stop Share")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .clipShape(Capsule())
                    }
                }
            } else {
                // VIEWER CONTROLS: Request to Share Video with Host
                if manager.coHostStatus == .pendingSent {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Requested...")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.orange.opacity(0.8))
                    .clipShape(Capsule())
                } else {
                    Button {
                        manager.requestToCoHost()
                    } label: {
                        HStack(spacing: 6) {
                            SwiftUI.Image(systemName: "video.badge.plus")
                                .font(.system(size: 14, weight: .bold))
                            Text("Request to Join Live")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                        .background(
                            LinearGradient(
                                colors: [Color.purple, Color.pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color.purple.opacity(0.4), radius: 6, x: 0, y: 3)
                    }
                }
            }

            Spacer()

            // Settings Sheet
            controlButton(
                icon: "gearshape.fill",
                title: "Config",
                isActive: false
            ) {
                showSettingsSheet = true
            }

            // End / Leave Button
            Button {
                showEndAlert = true
            } label: {
                HStack(spacing: 4) {
                    SwiftUI.Image(systemName: "phone.down.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(manager.isHost ? "End" : "Leave")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color.red)
                .clipShape(Capsule())
                .shadow(color: Color.red.opacity(0.4), radius: 4, x: 0, y: 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func controlButton(
        icon: String,
        title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                SwiftUI.Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isActive ? .red : .white)
                    .frame(width: 38, height: 38)
                    .background(isActive ? Color.white : Color.white.opacity(0.2))
                    .clipShape(Circle())

                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Co-Host Requests List View (Host Modal)

struct CoHostRequestsListView: View {
    @ObservedObject var manager = LiveStreamingManager.shared
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                if manager.incomingCoHostRequests.isEmpty {
                    Text("No pending requests.")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 16)
                } else {
                    ForEach(manager.incomingCoHostRequests) { req in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.purple.opacity(0.8))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    SwiftUI.Image(systemName: "person.fill")
                                        .foregroundColor(.white)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(req.userName)
                                    .font(.system(size: 15, weight: .semibold))
                                Text("UID: \(req.uid)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Decline") {
                                manager.rejectCoHostRequest(req)
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())

                            Button("Accept") {
                                manager.acceptCoHostRequest(req)
                                presentationMode.wrappedValue.dismiss()
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .clipShape(Capsule())
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationBarTitle("Join Live Requests", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

// MARK: - Testing Settings Sheet

struct LiveStreamingSettingsSheet: View {
    @ObservedObject var manager = LiveStreamingManager.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var appIdText = LiveStreamingConfig.currentAppId
    @State private var tokenText = LiveStreamingConfig.currentToken
    @State private var channelText = LiveStreamingConfig.currentChannelName
    @State private var isHostSelected: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Role in this Live Stream")) {
                    Picker("Join As", selection: $isHostSelected) {
                        Text("Host (Broadcaster)").tag(true)
                        Text("Viewer (Audience)").tag(false)
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Text(isHostSelected
                         ? "As Host: You broadcast your video & audio. Viewers can only watch, unless they request to join and you accept."
                         : "As Viewer: You watch the live stream in view-only mode. Your camera/mic remain off until the host approves your join request.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Live Streaming Credentials (Agora)")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("App ID")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        TextField("Enter App ID", text: $appIdText)
                            .font(.system(size: 13, design: .monospaced))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Channel Name")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        TextField("Enter Channel Name", text: $channelText)
                            .font(.system(size: 13, design: .monospaced))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("RTC Token")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        TextEditor(text: $tokenText)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 70)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }

                Section(header: Text("Status & Info")) {
                    HStack {
                        Text("Mode")
                        Spacer()
                        Text(manager.isHost ? "Host" : (manager.isCoHosting ? "Co-Host" : "Viewer"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.purple)
                    }

                    HStack {
                        Text("Local UID")
                        Spacer()
                        Text("\(manager.localUid)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Host UID")
                        Spacer()
                        Text(manager.hostUid != nil ? "\(manager.hostUid!)" : "Searching...")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Co-Host UID")
                        Spacer()
                        Text(manager.coHostUid != nil ? "\(manager.coHostUid!)" : "None")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button {
                        applyAndReconnect()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Apply & Reconnect")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.blue)

                    Button {
                        resetDefaults()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset to Default Credentials")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationBarTitle("Live Streaming Config", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                isHostSelected = manager.isHost
            }
        }
    }

    private func applyAndReconnect() {
        LiveStreamingConfig.currentAppId = appIdText
        LiveStreamingConfig.currentToken = tokenText
        LiveStreamingConfig.currentChannelName = channelText

        manager.joinLiveStream(
            appId: appIdText,
            channel: channelText,
            token: tokenText,
            asHost: isHostSelected
        )
        presentationMode.wrappedValue.dismiss()
    }

    private func resetDefaults() {
        LiveStreamingConfig.resetToDefaults()
        appIdText = LiveStreamingConfig.defaultAppId
        tokenText = LiveStreamingConfig.defaultToken
        channelText = LiveStreamingConfig.defaultChannelName
    }
}
