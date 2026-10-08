//
//  AgoraCallViewController.swift
//  FlirttimeNew
//
//  Full-screen call overlay (outgoing / incoming / active).
//

import UIKit

@MainActor
final class AgoraCallViewController: UIViewController {

    private weak var service: AgoraCallService?

    /// Full-bleed video surface (remote by default; local after WhatsApp-style swap).
    let remoteVideoView = UIView()
    /// Agora remote canvas target for 1:1 — respects tap-to-swap.
    var primaryRemoteVideoView: UIView {
        isLocalVideoPrimary ? localVideoView : remoteVideoView
    }
    /// Agora local canvas target — respects tap-to-swap and grid embedding.
    var activeLocalVideoSurface: UIView {
        if isLocalInVideoGrid {
            return localGridTile.videoContainer
        }
        return isLocalVideoPrimary ? remoteVideoView : localVideoView
    }

    /// Edge-to-edge WhatsApp group video grid (remote participants only).
    private let remoteGridScrollView = UIScrollView()
    private let remoteGridContainer = UIView()
    private var remoteTiles: [UInt: AgoraCallVideoTileView] = [:]

    /// WhatsApp-style avatar grid for group audio (and video fallback).
    private let participantAvatarScrollView = UIScrollView()
    private let participantAvatarGrid = UIView()
    private var participantTiles: [String: AgoraCallParticipantTileView] = [:]

    /// Nested in floating PiP chrome (non-interactive so drag/tap work).
    let localVideoView = UIView()
    /// Draggable WhatsApp-style floating PiP (never joins the remote grid).
    private let localPreviewContainer = UIView()
    /// Shown inside floating PiP when local camera is off.
    private let localPipAvatarView = UIImageView()
    private let localMuteBadge = UIImageView()
    /// Self mute overlay while local is full-screen after PiP swap.
    private let fullScreenSelfMuteBadge = UIImageView()
    /// Flip while local is full-screen after PiP swap (PiP flip stays on the bubble).
    private let fullScreenFlipCameraButton = UIButton(type: .custom)
    /// Column under minimize: flip + mute (hidden arranged views collapse).
    private let fullScreenLocalControlsStack = UIStackView()
    /// Self tile inside the group video grid (used when remotes ≥ 3).
    private let localGridTile = AgoraCallVideoTileView()
    private var configuredLocalPipAvatarURL: String?

    /// WhatsApp 1:1: tap PiP to put local full-screen and remote in the small view.
    private(set) var isLocalVideoPrimary = false
    private var localPreviewDidDrag = false

    /// True while self is a cell in the multi-remote video grid (not floating PiP).
    private(set) var isLocalInVideoGrid = false

    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let remoteMuteBadge = UIImageView()
    private let statusLabel = UILabel()
    private let errorLabel = UILabel()
    private let networkBarsView = AgoraCallNetworkBarsView()
    private let qualityTitleLabel = UILabel()
    private let qualityRowStack = UIStackView()
    private let callBannerLabel = UILabel()
    /// Dim + avatar when remote peer network is weak / unreachable (1:1 video).
    private let peerOfflineOverlay = UIView()
    private let peerOfflineAvatarView = UIImageView()
    private let peerOfflineStatusLabel = UILabel()
    private var configuredPeerOfflineAvatarURL: String?
    /// WhatsApp-style second-call Accept / Decline strip.
    private let swapIncomingBanner = UIView()
    private let swapTitleLabel = UILabel()
    private let swapSubtitleLabel = UILabel()
    private let swapDeclineButton = UIButton(type: .system)
    private let swapAcceptButton = UIButton(type: .system)

    /// Ringing (incoming/outgoing): blurred caller/peer photo behind chrome.
    private let incomingBackgroundImageView = UIImageView()
    private let incomingBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let incomingDimView = UIView()
    private let incomingNameLabel = UILabel()
    private let incomingStatusLabel = UILabel()
    private let avatarRippleHost = AgoraCallRippleHostView()
    private let acceptRippleHost = AgoraCallRippleHostView()
    private let declineRippleHost = AgoraCallRippleHostView()
    private let hangUpRippleHost = AgoraCallRippleHostView()
    private var isRingAnimating = false
    private var avatarCenterYConstraint: NSLayoutConstraint?
    private var avatarRingTopConstraint: NSLayoutConstraint?
    private var ringNameCenterYConstraint: NSLayoutConstraint?
    private var ringNameClearAvatarConstraint: NSLayoutConstraint?

    private let hangUpButton = UIButton(type: .custom)
    private let acceptButton = UIButton(type: .custom)
    private let declineButton = UIButton(type: .custom)
    private let outgoingEndButton = UIButton(type: .custom)
    private let muteButton = UIButton(type: .custom)
    private let speakerButton = UIButton(type: .custom)
    private let videoButton = UIButton(type: .custom)
    /// Small flip control on the floating local PiP (not in the bottom call bar).
    private let flipCameraButton = UIButton(type: .custom)
    private let screenShareButton = UIButton(type: .custom)
    private let pipButton = UIButton(type: .custom)

    private let muteTitleLabel = UILabel()
    private let speakerTitleLabel = UILabel()
    private let videoTitleLabel = UILabel()
    private let screenShareTitleLabel = UILabel()
    private let endTitleLabel = UILabel()
    private let acceptTitleLabel = UILabel()
    private let declineTitleLabel = UILabel()
    private let outgoingEndTitleLabel = UILabel()

    private var muteControlColumn: UIStackView!
    private var speakerControlColumn: UIStackView!
    private var videoControlColumn: UIStackView!
    private var screenShareControlColumn: UIStackView!
    private var hangUpControlColumn: UIStackView!
    private var acceptControlColumn: UIStackView!
    private var declineControlColumn: UIStackView!
    private var outgoingEndControlColumn: UIStackView!

    private let controlsBarView = UIView()
    private let controlsStack = UIStackView()
    private let incomingStack = UIStackView()
    private let outgoingStack = UIStackView()
    private let topInfoStack = UIStackView()

    /// Dim + WhatsApp-style audio route card (Speaker / Earpiece / Bluetooth).
    private var audioRoutePickerContainer: UIView?

    private let localPreviewSize = CGSize(width: 110, height: 160)
    private var localPreviewPanStart: CGPoint = .zero
    private var didPlaceLocalPreview = false
    /// User tapped the call surface to hide controls / hang-up / PiP / top labels.
    private var areChromeHiddenByUser = false
    private let controlButtonNormalFill = UIColor(white: 0.25, alpha: 1)
    private let controlButtonSelectedIcon = UIColor(white: 0.15, alpha: 1)

    init(service: AgoraCallService) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        setupViews()
        setupChromeToggleGesture()
        reloadFromService()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopRingAnimations()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Push / tab navigation often dismisses this VC without going through hang-up or PiP.
        // Recover into floating PiP so the live call does not vanish under the next screen.
        guard isBeingDismissed else { return }
        service?.handleCallUIDidDismissUnexpectedly(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didPlaceLocalPreview, view.bounds.width > 0 {
            didPlaceLocalPreview = true
            placeLocalPreviewInDefaultCorner()
        }
        if !remoteGridScrollView.isHidden {
            layoutRemoteGridIfNeeded()
        }
        if !participantAvatarScrollView.isHidden {
            layoutParticipantAvatarGrid()
        }
        syncRingRippleHostFrames()
        if !localPreviewContainer.isHidden {
            view.bringSubviewToFront(localPreviewContainer)
        }
        if !incomingBackgroundImageView.isHidden {
            view.bringSubviewToFront(incomingBackgroundImageView)
            view.bringSubviewToFront(incomingBlurView)
            view.bringSubviewToFront(incomingDimView)
            view.bringSubviewToFront(avatarRippleHost)
            view.bringSubviewToFront(avatarImageView)
            view.bringSubviewToFront(incomingNameLabel)
            view.bringSubviewToFront(incomingStatusLabel)
        }
        view.bringSubviewToFront(topInfoStack)
        view.bringSubviewToFront(pipButton)
        view.bringSubviewToFront(controlsBarView)
        view.bringSubviewToFront(declineRippleHost)
        view.bringSubviewToFront(acceptRippleHost)
        view.bringSubviewToFront(hangUpRippleHost)
        view.bringSubviewToFront(incomingStack)
        view.bringSubviewToFront(outgoingStack)
        localVideoView.isUserInteractionEnabled = false
        localVideoView.subviews.forEach { $0.isUserInteractionEnabled = false }
    }

    /// Call-timer tick — update status text only (no grid layout / video rebind).
    func updateElapsedDisplay() {
        guard let service, service.phase == .active else { return }
        if let ended = service.errorMessage, !ended.isEmpty { return }

        let timer = formatElapsed(service.elapsedSec)
        let isGroup = service.isGroupCall
        let call = service.call
        statusLabel.textColor = .white
        if service.isScreenSharing {
            statusLabel.text = service.hasStartedCallTimer
                ? "\(timer) · You are sharing your screen"
                : Self.outgoingCallingStatusText(isGroup: isGroup, isVideo: call?.type == .video)
        } else if isGroup {
            statusLabel.text = groupActiveStatusText(service: service)
        } else if service.hasRemoteVideo, !service.isScreenSharing, call?.type != .video {
            statusLabel.text = "\(timer) · Screen share"
        } else {
            statusLabel.text = timer
        }
        applyNetworkQualityChrome(service: service)
    }

    private func applyNetworkQualityChrome(service: AgoraCallService) {
        let active = service.phase == .active
        // 1:1 keeps signal bars. Group audio/video hides them.
        qualityRowStack.isHidden = !active || service.isGroupCall

        // Unreachable → empty bars + Not in network; weak → Poor; else normal quality.
        let barLevel: AgoraCallNetworkQualityLevel
        switch service.peerNetworkState {
        case .unreachable:
            barLevel = .reconnecting
        case .weak:
            barLevel = .poor
        case .ok:
            barLevel = service.networkQualityLevel
        }
        networkBarsView.setLevel(barLevel)

        let banner = service.activeCallBannerText
        let qualityTitle: String
        switch service.peerNetworkState {
        case .unreachable:
            qualityTitle = "Not in network"
        case .weak:
            // Bars + "Poor" next to signal is enough; do not also show "Poor connection" below.
            qualityTitle = AgoraCallNetworkQualityLevel.poor.title
        case .ok:
            // WhatsApp: good/fair call = bars only. Never show Excellent/Good/Fair/Poor here.
            qualityTitle = ""
        }
        let orange = service.peerNetworkState != .ok || service.networkQualityLevel.prefersOrangeStatus
        qualityTitleLabel.textColor = orange ? ChatTheme.warning : UIColor(white: 0.9, alpha: 1)

        // Prefer status next to signal bars — don't duplicate Poor / Not in network under the timer.
        let hidePeerNetworkBanner = banner == "Poor connection" || banner == "Not in network"
        if hidePeerNetworkBanner || Self.isDuplicateCallStatus(banner: banner, qualityTitle: qualityTitle) {
            if qualityTitle.isEmpty {
                qualityTitleLabel.text = nil
                qualityTitleLabel.isHidden = true
            } else {
                qualityTitleLabel.text = qualityTitle
                qualityTitleLabel.isHidden = false
            }
            callBannerLabel.text = nil
            callBannerLabel.isHidden = true
        } else if active, let banner, !banner.isEmpty {
            qualityTitleLabel.text = qualityTitle
            qualityTitleLabel.isHidden = true
            callBannerLabel.text = banner
            callBannerLabel.isHidden = false
            callBannerLabel.textColor = ChatTheme.warning
        } else {
            qualityTitleLabel.text = qualityTitle
            qualityTitleLabel.isHidden = qualityTitle.isEmpty
            callBannerLabel.text = banner
            callBannerLabel.isHidden = true
        }

        applyPeerOfflineOverlay(service: service)
    }

    /// "Reconnecting…" vs quality title "Reconnecting" (and Lost Connection) are the same status.
    private static func isDuplicateCallStatus(banner: String?, qualityTitle: String) -> Bool {
        guard let banner, !banner.isEmpty, !qualityTitle.isEmpty else { return false }
        let normalizedBanner = banner
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespaces)
        if normalizedBanner.caseInsensitiveCompare(qualityTitle) == .orderedSame {
            return true
        }
        // "Poor connection" vs quality "Poor"
        if qualityTitle.caseInsensitiveCompare("Poor") == .orderedSame,
           normalizedBanner.localizedCaseInsensitiveContains("poor") {
            return true
        }
        return false
    }

    /// Dim + peer avatar overlay disabled — status is shown via banner / bars only.
    private func applyPeerOfflineOverlay(service: AgoraCallService) {
        peerOfflineOverlay.isHidden = true
    }

    private func applyPendingIncomingSwapBanner(service: AgoraCallService) {
        guard let pending = service.pendingIncomingCall else {
            swapIncomingBanner.isHidden = true
            return
        }
        let name = pending.caller?.displayName
            ?? pending.conversationTitle
            ?? "Someone"
        let kind = pending.type == .video ? "video call" : "call"
        swapTitleLabel.text = "\(name) is calling"
        swapSubtitleLabel.text = "Accept to end your current \(kind) and answer"
        swapIncomingBanner.isHidden = false
        view.bringSubviewToFront(swapIncomingBanner)
    }

    /// Mute / name / hasVideo badges without relayout (used on high-frequency video-state ticks).
    func refreshRemoteTileMetadataOnly() {
        refreshRemoteTileStates(relayout: false)
        updateOneToOneRemoteMuteBadge()
    }

    /// PiP maximize: hide video surfaces (alpha 0) so rebind black frames are invisible under the cover.
    func setVideoSurfacesAlpha(_ alpha: CGFloat) {
        remoteVideoView.alpha = alpha
        remoteGridScrollView.alpha = alpha
        remoteGridContainer.alpha = alpha
        localPreviewContainer.alpha = alpha
        localVideoView.alpha = alpha
        localGridTile.alpha = alpha
        peerOfflineOverlay.alpha = alpha
        for tile in remoteTiles.values {
            tile.alpha = alpha
        }
    }

    /// Animate video surfaces 0 → 1 (crossfade with PiP handoff cover).
    func fadeInVideoSurfaces(duration: TimeInterval = 0.28, completion: (() -> Void)? = nil) {
        setVideoSurfacesAlpha(0)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.setVideoSurfacesAlpha(1)
        } completion: { _ in
            completion?()
        }
    }

    func reloadFromService() {
        guard let service else { return }
        let call = service.call
        let peer = call?.peer(relativeTo: service.meId)
        let isGroup = service.isGroupCall
        let isIncomingPhase = service.phase == .incoming
        let isOutgoingPhase = service.phase == .outgoing
        let isRingingPhase = isIncomingPhase || isOutgoingPhase
        let caller = call?.caller

        nameLabel.text = service.callDisplayTitle
        updateOneToOneRemoteMuteBadge()

        let avatarURLString: String? = {
            if isIncomingPhase {
                return caller?.profilePicture ?? peer?.profilePicture ?? service.avatarURLOverride
            }
            if isOutgoingPhase {
                return peer?.profilePicture ?? call?.callee?.profilePicture ?? service.avatarURLOverride
            }
            if isGroup { return service.avatarURLOverride }
            return peer?.profilePicture ?? service.avatarURLOverride
        }()

        if isRingingPhase {
            applyCallAvatar(
                urlString: avatarURLString,
                placeholder: UIImage(systemName: isGroup ? "person.3.fill" : "person.circle.fill")
            )
            updateRingBackgroundImage(urlString: avatarURLString)
            incomingNameLabel.text = {
                if isIncomingPhase, isGroup {
                    return caller?.displayName ?? "Someone"
                }
                return service.callDisplayTitle
            }()
        } else if isGroup {
            applyCallAvatar(
                urlString: service.avatarURLOverride,
                placeholder: UIImage(systemName: "person.3.fill")
            )
            clearRingBackgroundImage()
        } else {
            applyCallAvatar(
                urlString: peer?.profilePicture ?? service.avatarURLOverride,
                placeholder: UIImage(systemName: "person.circle.fill")
            )
            clearRingBackgroundImage()
        }

        if service.connectionStatusText == nil, !service.isAudioOnHold, service.thermalBannerText == nil {
            statusLabel.textColor = .white
        }

        switch service.phase {
        case .idle:
            statusLabel.text = ""
            incomingStatusLabel.text = ""
        case .outgoing:
            if let ended = service.errorMessage, !ended.isEmpty {
                statusLabel.text = ended
                statusLabel.textColor = .systemRed
                incomingStatusLabel.text = ended
                incomingStatusLabel.textColor = .systemRed
            } else if let net = service.connectionStatusText,
                      net == "No internet" || net == "Lost Connection" || net == "Reconnecting…" {
                statusLabel.text = net
                statusLabel.textColor = ChatTheme.warning
                incomingStatusLabel.text = net
                incomingStatusLabel.textColor = ChatTheme.warning
            } else {
                // WhatsApp-style: Calling… until callee reports `call:ringing`, then Ringing…
                let text: String
                if service.outgoingDialState == .ringing {
                    text = "Ringing…"
                } else {
                    text = Self.outgoingCallingStatusText(
                        isGroup: isGroup,
                        isVideo: call?.type == .video
                    )
                }
                statusLabel.text = text
                incomingStatusLabel.text = text
                incomingStatusLabel.textColor = UIColor(white: 0.92, alpha: 1)
            }
        case .incoming:
            if let ended = service.errorMessage, !ended.isEmpty {
                statusLabel.text = ended
                statusLabel.textColor = .systemRed
                incomingStatusLabel.text = ended
                incomingStatusLabel.textColor = .systemRed
            } else if isGroup {
                let callerName = caller?.displayName ?? "Someone"
                statusLabel.text = call?.type == .video
                    ? "\(callerName) started a group video call"
                    : "\(callerName) started a group call"
                incomingStatusLabel.text = call?.type == .video
                    ? "Incoming group video call"
                    : "Incoming group voice call"
                incomingStatusLabel.textColor = UIColor(white: 0.92, alpha: 1)
            } else {
                let text = call?.type == .video ? "Incoming video call" : "Incoming voice call"
                statusLabel.text = text
                incomingStatusLabel.text = text
                incomingStatusLabel.textColor = UIColor(white: 0.92, alpha: 1)
            }
        case .active:
            if let ended = service.errorMessage, !ended.isEmpty {
                statusLabel.text = ended
                statusLabel.textColor = .systemRed
            } else {
                statusLabel.textColor = .white
                let timer = formatElapsed(service.elapsedSec)
                if isGroup {
                    statusLabel.text = groupActiveStatusText(service: service)
                } else if service.hasRemoteVideo, !service.isScreenSharing, call?.type != .video {
                    statusLabel.text = "\(timer) · Screen share"
                } else {
                    statusLabel.text = timer
                }
            }
        }

        applyNetworkQualityChrome(service: service)
        applyPendingIncomingSwapBanner(service: service)

        let endMessage = service.errorMessage ?? ""
        errorLabel.text = endMessage
        // status / ringing status already show the same feedback — keep one line only.
        let shownInStatus = !endMessage.isEmpty
            && (statusLabel.text == endMessage || incomingStatusLabel.text == endMessage)
        errorLabel.isHidden = endMessage.isEmpty || shownInStatus

        let isVideo = call?.type == .video
        let isActive = service.phase == .active
        let isIncoming = isIncomingPhase
        let isOutgoing = isOutgoingPhase
        let isRingingUI = isRingingPhase
        let sharingLocally = service.isScreenSharing
        // Camera or remote screen share both arrive as remote video tracks.
        let showRemoteVideo = isActive && service.hasRemoteVideo
        // WhatsApp: 2+ remotes → video grid. 1 remote stays full-bleed; self is PiP until remotes ≥ 3.
        let remoteCount = max(service.remoteParticipantUids.count, service.remoteVideoUids.count)
        let useVideoGrid = isGroup
            && isActive
            && isVideo
            && remoteCount > 1
            && !sharingLocally
        // Remotes ≥ 3 (total people ≥ 4): self joins the grid; floating PiP hides.
        let localInGrid = useVideoGrid && remoteCount >= 3
        isLocalInVideoGrid = localInGrid
        // Group audio (and before remotes join video) → WhatsApp avatar grid.
        let useAvatarGrid = isGroup
            && !service.gridParticipants.isEmpty
            && !useVideoGrid
            && !showRemoteVideo

        if useAvatarGrid {
            syncParticipantAvatarGrid(service.gridParticipants)
        }
        if useVideoGrid {
            // Metadata only — full layout runs when tile count / viewport changes.
            refreshRemoteTileStates(relayout: false)
            updateLocalGridTile(service: service, visible: localInGrid)
        } else {
            localGridTile.isHidden = true
            localGridTile.removeFromSuperview()
        }

        remoteGridScrollView.isHidden = !useVideoGrid
        participantAvatarScrollView.isHidden = sharingLocally || !useAvatarGrid
        participantAvatarGrid.isHidden = sharingLocally || !useAvatarGrid
        // Self floats as PiP by default; tap-swap puts remote in PiP (WhatsApp 1:1).
        let showLocalPipChrome = isVideo && isActive && !sharingLocally
        let showLocalCamera = showLocalPipChrome && service.videoEnabled && !service.isCameraUnavailable
        // Allow swap even when either side has camera off — PiP still shows avatar + mute.
        let canUseOneToOneSwap = !useVideoGrid && !useAvatarGrid && !sharingLocally
            && showLocalPipChrome
            && remoteCount == 1
        if isLocalVideoPrimary && !canUseOneToOneSwap {
            isLocalVideoPrimary = false
            // Defer so we don't re-enter reload via syncRemoteVideoTiles.
            DispatchQueue.main.async { [weak self] in
                self?.service?.rebindActiveCallVideoSurfaces()
            }
        }
        // Who is in the floating PiP after optional swap.
        let pipShowsRemote = isLocalVideoPrimary && canUseOneToOneSwap
        let pipHasVideo = pipShowsRemote ? showRemoteVideo : showLocalCamera
        let pipMuted = pipShowsRemote ? isOneToOneRemoteMuted(service) : service.muted

        let showFullBleedVideo: Bool
        let showFloatingPip: Bool
        if localInGrid {
            showFullBleedVideo = false
            showFloatingPip = false
        } else if pipShowsRemote {
            // Local full-bleed (camera or avatar), remote stays in floating PiP.
            showFullBleedVideo = showLocalCamera
            showFloatingPip = showLocalPipChrome
        } else {
            showFullBleedVideo = showRemoteVideo
            // Keep PiP chrome when camera is off so self profile picture stays visible.
            showFloatingPip = showLocalPipChrome
        }
        remoteVideoView.isHidden = sharingLocally || useVideoGrid || useAvatarGrid || !showFullBleedVideo
        if localInGrid {
            // Local canvas lives on the grid tile — don't keep a nested PiP surface.
            localPreviewContainer.isHidden = true
            localVideoView.isHidden = true
            localPipAvatarView.isHidden = true
        } else {
            ensureLocalPreviewIsFloating()
            // WhatsApp group video (2 remotes): remotes fill the grid; self stays as floating PiP.
            localPreviewContainer.isHidden = useAvatarGrid || !showFloatingPip
            let pipHidden = localPreviewContainer.isHidden
            // Canvas holds whoever is bound into the PiP surface (local or remote after swap).
            localVideoView.isHidden = pipHidden || !pipHasVideo
            localPipAvatarView.isHidden = pipHidden || pipHasVideo
            if !localPipAvatarView.isHidden {
                let avatarURL = pipShowsRemote
                    ? remotePeerAvatarURL(from: service)
                    : service.localAvatarURL
                updatePipAvatar(urlString: avatarURL)
            }
        }
        // Mute badge follows whoever is currently in the floating PiP.
        localMuteBadge.isHidden = localInGrid
            || localPreviewContainer.isHidden
            || !pipMuted
        // When self is full-screen after swap, show own mute on the main surface.
        fullScreenSelfMuteBadge.isHidden = !pipShowsRemote || !service.muted
        // Peer mute beside name only while peer is full-screen (not in PiP).
        updateOneToOneRemoteMuteBadge()
        // Ringing uses centered name/status; active video grid hides top chrome.
        topInfoStack.isHidden = useVideoGrid || isRingingUI
        avatarImageView.isHidden = sharingLocally
            ? false
            : (showFullBleedVideo || useVideoGrid || useAvatarGrid)
        if sharingLocally {
            avatarImageView.image = UIImage(systemName: "rectangle.on.rectangle")
            avatarImageView.tintColor = .systemGreen
        } else if !avatarImageView.isHidden, isVideo, isActive, !useVideoGrid, !useAvatarGrid {
            // Full-bleed placeholder matches whoever is full-screen after swap.
            let fullBleedAvatar = pipShowsRemote
                ? service.localAvatarURL
                : (peer?.profilePicture ?? service.avatarURLOverride)
            applyCallAvatar(
                urlString: fullBleedAvatar,
                placeholder: UIImage(systemName: "person.circle.fill")
            )
        }

        // Fresh call / ringing must always show chrome.
        if service.phase == .idle || isRingingUI {
            areChromeHiddenByUser = false
        }

        incomingStack.isHidden = !isIncoming
        outgoingStack.isHidden = !isOutgoing
        incomingBackgroundImageView.isHidden = !isRingingUI
        incomingBlurView.isHidden = !isRingingUI
        incomingDimView.isHidden = !isRingingUI
        incomingNameLabel.isHidden = !isRingingUI
        incomingStatusLabel.isHidden = !isRingingUI
        avatarRippleHost.isHidden = !isRingingUI
        acceptRippleHost.isHidden = !isIncoming
        declineRippleHost.isHidden = !isIncoming
        hangUpRippleHost.isHidden = !isOutgoing
        applyRingCallerLayout(isRinging: isRingingUI)
        if isRingingUI {
            startRingAnimationsIfNeeded()
        } else {
            stopRingAnimations()
        }

        // Active-only control row (outgoing uses dedicated End button).
        let showControlRow = isActive
        controlsBarView.isHidden = !showControlRow
        // Share is hidden for both audio and video calls.
        screenShareControlColumn.isHidden = true
        if isActive {
            muteControlColumn.isHidden = false
            speakerControlColumn.isHidden = false
            videoControlColumn.isHidden = !(isVideo) || sharingLocally || service.isCameraUnavailable
            hangUpControlColumn.isHidden = false
        }

        // Flip: on PiP while self is in the bubble; on main screen after swap.
        let showPipFlip = !localPreviewContainer.isHidden
            && showLocalCamera
            && !pipShowsRemote
        flipCameraButton.isHidden = !showPipFlip
        let showFullScreenFlip = pipShowsRemote && showLocalCamera
        fullScreenFlipCameraButton.isHidden = !showFullScreenFlip
        fullScreenLocalControlsStack.isHidden = fullScreenFlipCameraButton.isHidden
            && fullScreenSelfMuteBadge.isHidden
        if !fullScreenLocalControlsStack.isHidden {
            view.bringSubviewToFront(fullScreenLocalControlsStack)
        }

        // Keep PiP available while sharing so user can leave call UI and share other apps.
        pipButton.isHidden = !isActive

        muteButton.isSelected = service.muted
        // Selected = loudspeaker off (or headset active without forced speaker).
        speakerButton.isSelected = !service.speakerOn || service.audioRoute.isExternalHeadset
        videoButton.isSelected = !service.videoEnabled
        screenShareButton.isSelected = sharingLocally
        applyToggleButtonAppearance(muteButton)
        applyToggleButtonAppearance(speakerButton)
        applyToggleButtonAppearance(videoButton)
        applyToggleButtonAppearance(screenShareButton, selectedFill: .systemGreen)
        applyAudioRouteAppearance(service.audioRoute, speakerOn: service.speakerOn, hasExternal: service.hasExternalAudioDevice)
        updateControlTitles(
            muted: service.muted,
            speakerOn: service.speakerOn,
            videoEnabled: service.videoEnabled,
            sharing: sharingLocally,
            audioRoute: service.audioRoute,
            hasExternal: service.hasExternalAudioDevice
        )
        if sharingLocally, service.phase == .active {
            if service.hasStartedCallTimer {
                statusLabel.text = "\(formatElapsed(service.elapsedSec)) · You are sharing your screen"
            } else if isGroup {
                statusLabel.text = Self.outgoingCallingStatusText(isGroup: true, isVideo: isVideo)
            } else {
                statusLabel.text = "\(formatElapsed(service.elapsedSec)) · You are sharing your screen"
            }
            nameLabel.text = "Screen sharing"
        }

        // User chrome hide wins after phase rules (never applied while ringing).
        if areChromeHiddenByUser {
            dismissAudioRoutePicker(animated: false)
            controlsBarView.isHidden = true
            pipButton.isHidden = true
            topInfoStack.isHidden = true
        }

        if !localPreviewContainer.isHidden {
            view.bringSubviewToFront(localPreviewContainer)
            localVideoView.isUserInteractionEnabled = false
            localVideoView.subviews.forEach { $0.isUserInteractionEnabled = false }
        }
    }

    /// Keep local camera / avatar inside the floating PiP chrome (WhatsApp self-view).
    private func ensureLocalPreviewIsFloating() {
        if localVideoView.superview !== localPreviewContainer {
            localVideoView.removeFromSuperview()
            localVideoView.backgroundColor = .clear
            localVideoView.translatesAutoresizingMaskIntoConstraints = true
            localVideoView.frame = localPreviewContainer.bounds
            localVideoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            localPreviewContainer.addSubview(localVideoView)
        }
        // Circular avatar / flip stay pinned via Auto Layout — only re-order above the canvas.
        localPreviewContainer.bringSubviewToFront(localPipAvatarView)
        localPreviewContainer.bringSubviewToFront(localMuteBadge)
        localPreviewContainer.bringSubviewToFront(flipCameraButton)
    }

    private func updatePipAvatar(urlString: String?) {
        let urlKey = urlString ?? ""
        guard configuredLocalPipAvatarURL != urlKey else { return }
        configuredLocalPipAvatarURL = urlKey
        if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
            localPipAvatarView.setChatImage(
                with: url,
                placeholderImage: UIImage(systemName: "person.circle.fill")
            )
        } else {
            localPipAvatarView.cancelChatImageLoad()
            localPipAvatarView.image = UIImage(systemName: "person.circle.fill")
        }
    }

    private func remotePeerAvatarURL(from service: AgoraCallService) -> String? {
        let peer = service.call?.peer(relativeTo: service.meId)
        return peer?.profilePicture ?? service.avatarURLOverride
    }

    private func isOneToOneRemoteMuted(_ service: AgoraCallService) -> Bool {
        let remoteUid = service.remoteParticipantUids.first
        return remoteUid.map { service.isRemoteMuted(uid: $0) }
            ?? !service.remoteMutedUids.isEmpty
    }

    /// Embed / refresh the local "You" tile when remotes ≥ 3.
    private func updateLocalGridTile(service: AgoraCallService, visible: Bool) {
        guard visible else {
            localGridTile.isHidden = true
            if localGridTile.superview != nil {
                localGridTile.removeFromSuperview()
                lastRemoteGridTileCount = -1
            }
            return
        }
        let selfPerson = service.gridParticipants.first(where: \.isSelf)
        localGridTile.configure(
            name: "You",
            avatarURL: selfPerson?.avatarURL ?? service.localAvatarURL,
            hasVideo: service.videoEnabled
        )
        localGridTile.setMuted(service.muted)
        localGridTile.isHidden = false
        if localGridTile.superview !== remoteGridContainer {
            remoteGridContainer.addSubview(localGridTile)
            lastRemoteGridTileCount = -1
        }
        // Local canvas must stay non-interactive so taps toggle chrome.
        localGridTile.videoContainer.isUserInteractionEnabled = false
        localGridTile.videoContainer.subviews.forEach { $0.isUserInteractionEnabled = false }
    }

    /// 1:1: show mute icon beside the peer name when they muted — only while peer is full-screen.
    private func updateOneToOneRemoteMuteBadge() {
        guard let service else {
            remoteMuteBadge.isHidden = true
            return
        }
        guard !service.isGroupCall, service.phase == .active, !isLocalVideoPrimary else {
            // When peer is in the floating PiP, mute is shown on the PiP badge instead.
            remoteMuteBadge.isHidden = true
            return
        }
        remoteMuteBadge.isHidden = !isOneToOneRemoteMuted(service)
    }

    /// Update each remote tile for video on/off + profile (WhatsApp video-off state).
    private func refreshRemoteTileStates(relayout: Bool = true) {
        guard let service else { return }
        for (uid, tile) in remoteTiles {
            let profile = service.profile(forRemoteUid: uid)
            tile.configure(
                name: profile.name,
                avatarURL: profile.avatarURL,
                hasVideo: service.hasRemoteVideo(uid: uid)
            )
            tile.setMuted(service.isRemoteMuted(uid: uid))
        }
        if isLocalInVideoGrid {
            updateLocalGridTile(service: service, visible: true)
        }
        if relayout {
            layoutRemoteGridIfNeeded(force: true)
        }
    }

    private func syncParticipantAvatarGrid(_ participants: [AgoraCallGridParticipant]) {
        let ids = Set(participants.map(\.userId))
        let stale = participantTiles.keys.filter { !ids.contains($0) }
        for id in stale {
            participantTiles[id]?.removeFromSuperview()
            participantTiles.removeValue(forKey: id)
        }
        for person in participants {
            let muted = service?.isMuted(userId: person.userId) ?? false
            if let tile = participantTiles[person.userId] {
                tile.configure(with: person)
                tile.setMuted(muted)
            } else {
                let tile = AgoraCallParticipantTileView()
                tile.configure(with: person)
                tile.setMuted(muted)
                participantTiles[person.userId] = tile
                participantAvatarGrid.addSubview(tile)
            }
        }
        layoutParticipantAvatarGrid()
    }

    private func layoutParticipantAvatarGrid() {
        let ordered = service.map { svc in
            svc.gridParticipants.compactMap { participantTiles[$0.userId] }
        } ?? participantTiles.sorted { $0.key < $1.key }.map(\.value)
        guard !ordered.isEmpty else { return }
        participantAvatarScrollView.layoutIfNeeded()
        let viewport = participantAvatarScrollView.bounds
        guard viewport.width > 0, viewport.height > 0 else {
            DispatchQueue.main.async { [weak self] in self?.layoutParticipantAvatarGrid() }
            return
        }

        let count = ordered.count
        let rowCounts = Self.whatsAppRowCounts(for: count)
        let scrollable = rowCounts.count > 3
        let spacing: CGFloat = 8
        let layout = Self.whatsAppGridLayout(
            count: count,
            viewport: viewport,
            spacing: spacing,
            maxTileAspect: scrollable ? nil : 1.2,
            centerVertically: !scrollable,
            scrollable: scrollable
        )
        participantAvatarGrid.frame = CGRect(x: 0, y: 0, width: viewport.width, height: layout.contentHeight)
        participantAvatarScrollView.contentSize = participantAvatarGrid.frame.size
        participantAvatarScrollView.isScrollEnabled = scrollable
        participantAvatarScrollView.showsVerticalScrollIndicator = scrollable
        if !scrollable {
            participantAvatarScrollView.contentOffset = .zero
        }
        for (tile, frame) in zip(ordered, layout.frames) {
            tile.frame = frame
        }
    }

    /// Keep remote video tiles in sync with Agora remotes (group calls).
    /// - Parameter reloadChromeIfNeeded: when false (PiP maximize handoff), skip full `reloadFromService`
    ///   so we don't flash under the snapshot cover.
    func syncRemoteVideoTiles(
        uids: [UInt],
        binder: (UInt, UIView) -> Void,
        reloadChromeIfNeeded: Bool = true
    ) {
        let uidSet = Set(uids)
        let previousCount = remoteTiles.count
        var addedUids: Set<UInt> = []
        let stale = remoteTiles.keys.filter { !uidSet.contains($0) }
        for uid in stale {
            remoteTiles[uid]?.removeFromSuperview()
            remoteTiles.removeValue(forKey: uid)
        }
        for uid in uids {
            let profile = service?.profile(forRemoteUid: uid)
                ?? (name: "Participant", avatarURL: nil)
            let hasVideo = service?.hasRemoteVideo(uid: uid) ?? false
            if let tile = remoteTiles[uid] {
                tile.configure(name: profile.name, avatarURL: profile.avatarURL, hasVideo: hasVideo)
            } else {
                let tile = AgoraCallVideoTileView()
                tile.configure(name: profile.name, avatarURL: profile.avatarURL, hasVideo: hasVideo)
                remoteTiles[uid] = tile
                remoteGridContainer.addSubview(tile)
                addedUids.insert(uid)
            }
        }
        let structureChanged = !stale.isEmpty || !addedUids.isEmpty || previousCount != remoteTiles.count
        let wasLocalInGrid = isLocalInVideoGrid
        let shouldEmbedLocal = uids.count >= 3
        isLocalInVideoGrid = shouldEmbedLocal
        if shouldEmbedLocal {
            if let service {
                updateLocalGridTile(service: service, visible: true)
            }
        } else {
            if let service {
                updateLocalGridTile(service: service, visible: false)
            } else {
                localGridTile.isHidden = true
                localGridTile.removeFromSuperview()
            }
            ensureLocalPreviewIsFloating()
        }
        if structureChanged || wasLocalInGrid != shouldEmbedLocal {
            layoutRemoteGridIfNeeded(force: true)
        }
        if uids.count <= 1, let uid = uids.first {
            binder(uid, primaryRemoteVideoView)
        } else {
            // Multi-remote grid — reset any 1:1 swap.
            if isLocalVideoPrimary {
                isLocalVideoPrimary = false
            }
            for uid in uids {
                if let tile = remoteTiles[uid] {
                    // bindRemoteVideo no-ops when already on the same surface.
                    binder(uid, tile.videoContainer)
                }
            }
        }
        // Only full chrome reload when grid membership changes (1↔many / join / leave).
        // Calling reload every bind was re-laying out video every state tick → iOS flash.
        if reloadChromeIfNeeded, structureChanged || wasLocalInGrid != shouldEmbedLocal {
            reloadFromService()
        }
        // Local canvas target changes when self enters/leaves the grid (2↔3 remotes).
        if wasLocalInGrid != shouldEmbedLocal {
            service?.bindLocalToActiveCallSurface()
        }
    }

    private var lastRemoteGridLayoutSize: CGSize = .zero
    private var lastRemoteGridTileCount: Int = -1

    private func layoutRemoteGrid() {
        layoutRemoteGridIfNeeded(force: true)
    }

    private func layoutRemoteGridIfNeeded(force: Bool = false) {
        // Remotes (+ self when remotes ≥ 3). Self is last so row recipes match total people.
        var tiles: [UIView] = remoteTiles.sorted { $0.key < $1.key }.map(\.value)
        let includeLocal = isLocalInVideoGrid && !localGridTile.isHidden
        if includeLocal {
            tiles.append(localGridTile)
        }
        guard !tiles.isEmpty else { return }
        remoteGridScrollView.layoutIfNeeded()
        let viewport = remoteGridScrollView.bounds
        guard viewport.width > 0, viewport.height > 0 else {
            DispatchQueue.main.async { [weak self] in self?.layoutRemoteGridIfNeeded(force: force) }
            return
        }

        if !force,
           viewport.size == lastRemoteGridLayoutSize,
           tiles.count == lastRemoteGridTileCount {
            return
        }
        lastRemoteGridLayoutSize = viewport.size
        lastRemoteGridTileCount = tiles.count

        let count = tiles.count
        // 9+ remotes (10+ tiles / more than 3 rows): scroll to see everyone.
        let rowCounts = Self.whatsAppRowCounts(for: count)
        let scrollable = rowCounts.count > 3
        let spacing: CGFloat = 6
        let layout = Self.whatsAppGridLayout(
            count: count,
            viewport: viewport,
            spacing: spacing,
            maxTileAspect: nil,
            centerVertically: false,
            scrollable: scrollable
        )
        remoteGridContainer.frame = CGRect(x: 0, y: 0, width: viewport.width, height: layout.contentHeight)
        remoteGridScrollView.contentSize = remoteGridContainer.frame.size
        remoteGridScrollView.isScrollEnabled = scrollable
        remoteGridScrollView.showsVerticalScrollIndicator = scrollable
        if !scrollable {
            remoteGridScrollView.contentOffset = .zero
        }
        for (tile, frame) in zip(tiles, layout.frames) {
            tile.translatesAutoresizingMaskIntoConstraints = true
            // Skip no-op frame writes — assigning identical frames still dirties layout on iOS.
            if tile.frame != frame {
                tile.frame = frame
            }
        }
    }

    private struct WhatsAppGridLayout {
        let frames: [CGRect]
        let contentHeight: CGFloat
    }

    /// WhatsApp / OneVibe tile frames for group video.
    /// Tile count includes self when remotes ≥ 3 (total people ≥ 4).
    /// 9+ people: tile height fits ~3 rows; content scrolls.
    private static func whatsAppGridLayout(
        count: Int,
        viewport: CGRect,
        spacing: CGFloat,
        maxTileAspect: CGFloat?,
        centerVertically: Bool,
        scrollable: Bool
    ) -> WhatsAppGridLayout {
        guard count > 0, viewport.width > 0, viewport.height > 0 else {
            return WhatsAppGridLayout(frames: [], contentHeight: 0)
        }

        let rowCounts = whatsAppRowCounts(for: count)
        let rows = rowCounts.count
        let visibleRowsForScroll: CGFloat = 3

        var tileH: CGFloat
        if scrollable {
            tileH = (viewport.height - spacing * (visibleRowsForScroll - 1)) / visibleRowsForScroll
        } else {
            tileH = (viewport.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        }

        var originY: CGFloat = 0
        if !scrollable, let maxAspect = maxTileAspect {
            let widestCols = rowCounts.max() ?? 1
            let baseW = (viewport.width - spacing * CGFloat(widestCols - 1)) / CGFloat(widestCols)
            let cappedH = min(tileH, baseW * maxAspect)
            let gridH = CGFloat(rows) * cappedH + CGFloat(max(0, rows - 1)) * spacing
            if centerVertically {
                originY = max(0, (viewport.height - gridH) / 2)
            }
            tileH = cappedH
        }

        let gridH = CGFloat(rows) * tileH + CGFloat(max(0, rows - 1)) * spacing
        let contentHeight = scrollable ? gridH : max(gridH + originY, viewport.height)

        var frames: [CGRect] = []
        frames.reserveCapacity(count)
        for (row, itemsInRow) in rowCounts.enumerated() {
            let rowTileW = (viewport.width - spacing * CGFloat(itemsInRow - 1)) / CGFloat(itemsInRow)
            let y = originY + CGFloat(row) * (tileH + spacing)
            for col in 0..<itemsInRow {
                let x = CGFloat(col) * (rowTileW + spacing)
                frames.append(CGRect(x: x, y: y, width: rowTileW, height: tileH))
            }
        }
        return WhatsAppGridLayout(frames: frames, contentHeight: contentHeight)
    }

    /// Row recipe by **tile count** (remotes, or remotes + you when remotes ≥ 3).
    /// Remotes → rows (total incl. you): 1→full-bleed, 2→[1,1], 3→[2,2], 4→[2,2,1], …
    private static func whatsAppRowCounts(for count: Int) -> [Int] {
        switch count {
        case 1: return [1]
        case 2: return [1, 1]      // 2 remotes — self stays floating PiP
        case 3: return [2, 1]
        case 4: return [2, 2]      // 3 remotes + you
        case 5: return [2, 2, 1]   // 4 remotes + you
        case 6: return [2, 2, 2]   // 5 remotes + you
        case 7: return [3, 2, 2]   // 6 remotes + you
        case 8: return [3, 2, 3]   // 7 remotes + you
        case 9: return [3, 3, 3]   // 8 remotes + you
        default:
            // 9+ remotes (10+ tiles): rows of up to 3; UI scrolls with no cap.
            var rows: [Int] = []
            var left = count
            while left > 0 {
                let n = min(3, left)
                rows.append(n)
                left -= n
            }
            return rows
        }
    }

    // MARK: - Layout

    private func setupViews() {
        remoteVideoView.backgroundColor = .black
        remoteVideoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(remoteVideoView)

        peerOfflineOverlay.isHidden = true
        peerOfflineOverlay.isUserInteractionEnabled = false
        peerOfflineOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(peerOfflineOverlay)

        peerOfflineAvatarView.contentMode = .scaleAspectFill
        peerOfflineAvatarView.clipsToBounds = true
        peerOfflineAvatarView.tintColor = .white
        peerOfflineAvatarView.layer.cornerRadius = 56
        peerOfflineAvatarView.layer.borderWidth = 2
        peerOfflineAvatarView.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        peerOfflineAvatarView.translatesAutoresizingMaskIntoConstraints = false
        peerOfflineOverlay.addSubview(peerOfflineAvatarView)

        peerOfflineStatusLabel.font = UIFont(name: "Fredoka-Medium", size: 15) ?? UIFont.chat(.medium, size: 15)
        peerOfflineStatusLabel.textColor = ChatTheme.warning
        peerOfflineStatusLabel.textAlignment = .center
        peerOfflineStatusLabel.numberOfLines = 2
        peerOfflineStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        peerOfflineOverlay.addSubview(peerOfflineStatusLabel)

        incomingBackgroundImageView.contentMode = .scaleAspectFill
        incomingBackgroundImageView.clipsToBounds = true
        incomingBackgroundImageView.isHidden = true
        incomingBackgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(incomingBackgroundImageView)

        incomingBlurView.isHidden = true
        incomingBlurView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(incomingBlurView)

        incomingDimView.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        incomingDimView.isHidden = true
        incomingDimView.isUserInteractionEnabled = false
        incomingDimView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(incomingDimView)

        remoteGridScrollView.backgroundColor = .black
        remoteGridScrollView.isHidden = true
        remoteGridScrollView.clipsToBounds = true
        remoteGridScrollView.translatesAutoresizingMaskIntoConstraints = false
        remoteGridScrollView.showsHorizontalScrollIndicator = false
        remoteGridScrollView.alwaysBounceVertical = false
        remoteGridScrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(remoteGridScrollView)

        remoteGridContainer.backgroundColor = .black
        remoteGridContainer.translatesAutoresizingMaskIntoConstraints = true
        remoteGridContainer.clipsToBounds = true
        remoteGridScrollView.addSubview(remoteGridContainer)

        participantAvatarScrollView.backgroundColor = .clear
        participantAvatarScrollView.isHidden = true
        participantAvatarScrollView.translatesAutoresizingMaskIntoConstraints = false
        participantAvatarScrollView.showsHorizontalScrollIndicator = false
        participantAvatarScrollView.alwaysBounceVertical = false
        participantAvatarScrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(participantAvatarScrollView)

        participantAvatarGrid.backgroundColor = .clear
        participantAvatarGrid.isHidden = true
        participantAvatarGrid.translatesAutoresizingMaskIntoConstraints = true
        participantAvatarScrollView.addSubview(participantAvatarGrid)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.tintColor = .white
        avatarImageView.layer.cornerRadius = 64
        avatarImageView.layer.borderWidth = 3
        avatarImageView.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false

        avatarRippleHost.isHidden = true
        avatarRippleHost.configure(ringColor: UIColor.white.withAlphaComponent(0.55), ringCount: 3)
        avatarRippleHost.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(avatarRippleHost)
        view.addSubview(avatarImageView)

        incomingNameLabel.font = UIFont(name: "Fredoka-SemiBold", size: 24) ?? UIFont.chat(.bold, size: 24)
        incomingNameLabel.textColor = .white
        incomingNameLabel.textAlignment = .center
        incomingNameLabel.numberOfLines = 2
        incomingNameLabel.isHidden = true
        incomingNameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(incomingNameLabel)

        incomingStatusLabel.font = UIFont(name: "Fredoka-Regular", size: 16) ?? UIFont.chat(size: 16)
        incomingStatusLabel.textColor = UIColor(white: 0.92, alpha: 1)
        incomingStatusLabel.textAlignment = .center
        incomingStatusLabel.numberOfLines = 2
        incomingStatusLabel.isHidden = true
        incomingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(incomingStatusLabel)

        nameLabel.font = UIFont(name: "Fredoka-SemiBold", size: 18) ?? UIFont.chat(.bold, size: 18)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        remoteMuteBadge.image = UIImage(systemName: "mic.slash.fill")
        remoteMuteBadge.tintColor = .white
        remoteMuteBadge.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        remoteMuteBadge.contentMode = .center
        remoteMuteBadge.layer.cornerRadius = 11
        remoteMuteBadge.clipsToBounds = true
        remoteMuteBadge.isHidden = true
        remoteMuteBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        remoteMuteBadge.setContentHuggingPriority(.required, for: .horizontal)
        remoteMuteBadge.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = UIFont(name: "Fredoka-Regular", size: 14) ?? UIFont.chat(size: 14)
        statusLabel.textColor = UIColor(white: 0.9, alpha: 1)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        networkBarsView.translatesAutoresizingMaskIntoConstraints = false
        networkBarsView.setContentHuggingPriority(.required, for: .horizontal)

        qualityTitleLabel.font = UIFont(name: "Fredoka-Medium", size: 12) ?? UIFont.chat(.medium, size: 12)
        qualityTitleLabel.textColor = UIColor(white: 0.9, alpha: 1)
        qualityTitleLabel.setContentHuggingPriority(.required, for: .horizontal)

        qualityRowStack.axis = .horizontal
        qualityRowStack.alignment = .center
        qualityRowStack.spacing = 6
        qualityRowStack.translatesAutoresizingMaskIntoConstraints = false
        qualityRowStack.addArrangedSubview(networkBarsView)
        qualityRowStack.addArrangedSubview(qualityTitleLabel)
        qualityRowStack.isHidden = true

        callBannerLabel.font = UIFont(name: "Fredoka-Medium", size: 12) ?? UIFont.chat(.medium, size: 12)
        callBannerLabel.textColor = ChatTheme.warning
        callBannerLabel.textAlignment = .center
        callBannerLabel.numberOfLines = 1
        callBannerLabel.translatesAutoresizingMaskIntoConstraints = false
        callBannerLabel.isHidden = true
        let nameRowStack = UIStackView(arrangedSubviews: [nameLabel, remoteMuteBadge])
        nameRowStack.axis = .horizontal
        nameRowStack.alignment = .center
        nameRowStack.spacing = 8
        nameRowStack.translatesAutoresizingMaskIntoConstraints = false

        topInfoStack.axis = .vertical
        topInfoStack.alignment = .center
        topInfoStack.spacing = 4
        topInfoStack.translatesAutoresizingMaskIntoConstraints = false
        topInfoStack.addArrangedSubview(nameLabel)
        topInfoStack.addArrangedSubview(qualityRowStack)
        topInfoStack.addArrangedSubview(nameRowStack)
        topInfoStack.addArrangedSubview(statusLabel)
        topInfoStack.addArrangedSubview(callBannerLabel)
        view.addSubview(topInfoStack)

        NSLayoutConstraint.activate([
            remoteMuteBadge.widthAnchor.constraint(equalToConstant: 22),
            remoteMuteBadge.heightAnchor.constraint(equalToConstant: 22)
        ])

        errorLabel.font = UIFont(name: "Fredoka-Regular", size: 13) ?? UIFont.chat(size: 13)
        errorLabel.textColor = ChatTheme.warning
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 2
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorLabel)

        setupSwapIncomingBanner()

        // Frame-based draggable chrome; Agora renders into nested localVideoView.
        localPreviewContainer.backgroundColor = UIColor(white: 0.15, alpha: 1)
        localPreviewContainer.layer.cornerRadius = 10
        localPreviewContainer.clipsToBounds = true
        localPreviewContainer.layer.borderWidth = 1
        localPreviewContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        localPreviewContainer.translatesAutoresizingMaskIntoConstraints = true
        localPreviewContainer.isUserInteractionEnabled = true
        localPreviewContainer.frame = CGRect(origin: .zero, size: localPreviewSize)
        view.addSubview(localPreviewContainer)

        localVideoView.backgroundColor = .clear
        localVideoView.isUserInteractionEnabled = false
        localVideoView.translatesAutoresizingMaskIntoConstraints = true
        localVideoView.frame = localPreviewContainer.bounds
        localVideoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        localPreviewContainer.addSubview(localVideoView)

        localPipAvatarView.contentMode = .scaleAspectFill
        localPipAvatarView.clipsToBounds = true
        localPipAvatarView.backgroundColor = UIColor(white: 0.28, alpha: 1)
        localPipAvatarView.tintColor = .white
        localPipAvatarView.image = UIImage(systemName: "person.circle.fill")
        localPipAvatarView.isUserInteractionEnabled = false
        localPipAvatarView.isHidden = true
        // WhatsApp self-view: centered circular avatar on dark PiP chrome (not full-bleed).
        localPipAvatarView.translatesAutoresizingMaskIntoConstraints = false
        localPreviewContainer.addSubview(localPipAvatarView)
        let localPipAvatarSide: CGFloat = 52
        localPipAvatarView.layer.cornerRadius = localPipAvatarSide / 2
        NSLayoutConstraint.activate([
            localPipAvatarView.centerXAnchor.constraint(equalTo: localPreviewContainer.centerXAnchor),
            localPipAvatarView.centerYAnchor.constraint(equalTo: localPreviewContainer.centerYAnchor),
            localPipAvatarView.widthAnchor.constraint(equalToConstant: localPipAvatarSide),
            localPipAvatarView.heightAnchor.constraint(equalToConstant: localPipAvatarSide)
        ])

        localMuteBadge.image = UIImage(systemName: "mic.slash.fill")
        localMuteBadge.tintColor = .white
        localMuteBadge.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        localMuteBadge.contentMode = .center
        localMuteBadge.layer.cornerRadius = 12
        localMuteBadge.clipsToBounds = true
        localMuteBadge.isHidden = true
        localMuteBadge.translatesAutoresizingMaskIntoConstraints = false
        localPreviewContainer.addSubview(localMuteBadge)

        let flipConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        flipCameraButton.setImage(
            UIImage(systemName: "camera.rotate.fill", withConfiguration: flipConfig),
            for: .normal
        )
        flipCameraButton.tintColor = .white
        flipCameraButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        flipCameraButton.layer.cornerRadius = 12
        flipCameraButton.clipsToBounds = true
        flipCameraButton.isHidden = true
        flipCameraButton.accessibilityLabel = "Flip camera"
        flipCameraButton.translatesAutoresizingMaskIntoConstraints = false
        flipCameraButton.addTarget(self, action: #selector(flipCameraTapped), for: .touchUpInside)
        localPreviewContainer.addSubview(flipCameraButton)

        NSLayoutConstraint.activate([
            localMuteBadge.bottomAnchor.constraint(equalTo: localPreviewContainer.bottomAnchor, constant: -6),
            localMuteBadge.leadingAnchor.constraint(equalTo: localPreviewContainer.leadingAnchor, constant: 6),
            localMuteBadge.widthAnchor.constraint(equalToConstant: 24),
            localMuteBadge.heightAnchor.constraint(equalToConstant: 24),

            flipCameraButton.topAnchor.constraint(equalTo: localPreviewContainer.topAnchor, constant: 6),
            flipCameraButton.trailingAnchor.constraint(equalTo: localPreviewContainer.trailingAnchor, constant: -6),
            flipCameraButton.widthAnchor.constraint(equalToConstant: 24),
            flipCameraButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        localPreviewContainer.bringSubviewToFront(localMuteBadge)
        localPreviewContainer.bringSubviewToFront(flipCameraButton)

        fullScreenSelfMuteBadge.image = UIImage(systemName: "mic.slash.fill")
        fullScreenSelfMuteBadge.tintColor = .white
        fullScreenSelfMuteBadge.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        fullScreenSelfMuteBadge.contentMode = .center
        fullScreenSelfMuteBadge.layer.cornerRadius = 20
        fullScreenSelfMuteBadge.clipsToBounds = true
        fullScreenSelfMuteBadge.isHidden = true
        fullScreenSelfMuteBadge.translatesAutoresizingMaskIntoConstraints = false

        let fullScreenFlipConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        fullScreenFlipCameraButton.setImage(
            UIImage(systemName: "camera.rotate.fill", withConfiguration: fullScreenFlipConfig),
            for: .normal
        )
        fullScreenFlipCameraButton.tintColor = .white
        fullScreenFlipCameraButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        fullScreenFlipCameraButton.layer.cornerRadius = 20
        fullScreenFlipCameraButton.clipsToBounds = true
        fullScreenFlipCameraButton.isHidden = true
        fullScreenFlipCameraButton.accessibilityLabel = "Flip camera"
        fullScreenFlipCameraButton.translatesAutoresizingMaskIntoConstraints = false
        fullScreenFlipCameraButton.addTarget(self, action: #selector(flipCameraTapped), for: .touchUpInside)

        fullScreenLocalControlsStack.axis = .vertical
        fullScreenLocalControlsStack.alignment = .center
        fullScreenLocalControlsStack.spacing = 10
        fullScreenLocalControlsStack.isHidden = true
        fullScreenLocalControlsStack.translatesAutoresizingMaskIntoConstraints = false
        fullScreenLocalControlsStack.addArrangedSubview(fullScreenFlipCameraButton)
        fullScreenLocalControlsStack.addArrangedSubview(fullScreenSelfMuteBadge)
        view.addSubview(fullScreenLocalControlsStack)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleLocalPreviewPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        localPreviewContainer.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleLocalPreviewTap))
        tap.numberOfTapsRequired = 1
        tap.delegate = self
        localPreviewContainer.addGestureRecognizer(tap)

        configureCircleButton(hangUpButton, systemName: "phone.down.fill", color: .systemRed, size: 56, symbolPointSize: 22)
        hangUpButton.addTarget(self, action: #selector(hangUpTapped), for: .touchUpInside)

        configureCircleButton(acceptButton, systemName: "phone.fill", color: .systemGreen, size: 68, symbolPointSize: 28)
        acceptButton.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)

        configureCircleButton(declineButton, systemName: "phone.down.fill", color: .systemRed, size: 68, symbolPointSize: 28)
        declineButton.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)

        configureCircleButton(outgoingEndButton, systemName: "phone.down.fill", color: .systemRed, size: 68, symbolPointSize: 28)
        outgoingEndButton.addTarget(self, action: #selector(hangUpTapped), for: .touchUpInside)

        configureCircleButton(muteButton, systemName: "mic.fill", selectedName: "mic.slash.fill", color: controlButtonNormalFill)
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)

        configureCircleButton(speakerButton, systemName: "speaker.wave.2.fill", selectedName: "speaker.slash.fill", color: controlButtonNormalFill)
        speakerButton.addTarget(self, action: #selector(speakerTapped), for: .touchUpInside)

        configureCircleButton(videoButton, systemName: "video.fill", selectedName: "video.slash.fill", color: controlButtonNormalFill)
        videoButton.addTarget(self, action: #selector(videoTapped), for: .touchUpInside)

        configureCircleButton(
            screenShareButton,
            systemName: "rectangle.on.rectangle",
            selectedName: "rectangle.badge.xmark",
            color: controlButtonNormalFill
        )
        screenShareButton.addTarget(self, action: #selector(screenShareTapped), for: .touchUpInside)

        muteControlColumn = makeControlColumn(button: muteButton, titleLabel: muteTitleLabel, title: "Mute")
        speakerControlColumn = makeControlColumn(button: speakerButton, titleLabel: speakerTitleLabel, title: "Speaker")
        videoControlColumn = makeControlColumn(button: videoButton, titleLabel: videoTitleLabel, title: "Video")
        screenShareControlColumn = makeControlColumn(button: screenShareButton, titleLabel: screenShareTitleLabel, title: "Share")
        hangUpControlColumn = makeControlColumn(
            button: hangUpButton,
            titleLabel: endTitleLabel,
            title: "End",
            titleFontSize: 14,
            titleWeight: .semibold
        )
        declineControlColumn = makeControlColumn(
            button: declineButton,
            titleLabel: declineTitleLabel,
            title: "Reject",
            titleFontSize: 14,
            titleWeight: .semibold
        )
        declineControlColumn.spacing = 26
        acceptControlColumn = makeControlColumn(
            button: acceptButton,
            titleLabel: acceptTitleLabel,
            title: "Accept",
            titleFontSize: 14,
            titleWeight: .semibold
        )
        acceptControlColumn.spacing = 26
        outgoingEndControlColumn = makeControlColumn(
            button: outgoingEndButton,
            titleLabel: outgoingEndTitleLabel,
            title: "End",
            titleFontSize: 14,
            titleWeight: .semibold
        )
        outgoingEndControlColumn.spacing = 26

        pipButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        pipButton.tintColor = .white
        pipButton.setImage(UIImage(systemName: "pip.enter") ?? UIImage(systemName: "arrow.down.right.and.arrow.up.left"), for: .normal)
        pipButton.layer.cornerRadius = 20
        pipButton.translatesAutoresizingMaskIntoConstraints = false
        pipButton.addTarget(self, action: #selector(pipTapped), for: .touchUpInside)
        view.addSubview(pipButton)

        incomingStack.axis = .horizontal
        incomingStack.spacing = 120
        incomingStack.alignment = .center
        incomingStack.translatesAutoresizingMaskIntoConstraints = false
        incomingStack.addArrangedSubview(declineControlColumn)
        incomingStack.addArrangedSubview(acceptControlColumn)
        view.addSubview(incomingStack)

        outgoingStack.axis = .horizontal
        outgoingStack.alignment = .center
        outgoingStack.isHidden = true
        outgoingStack.translatesAutoresizingMaskIntoConstraints = false
        outgoingStack.addArrangedSubview(outgoingEndControlColumn)
        view.addSubview(outgoingStack)

        declineRippleHost.isHidden = true
        declineRippleHost.configure(ringColor: UIColor.systemRed.withAlphaComponent(0.7), ringCount: 3)
        declineRippleHost.translatesAutoresizingMaskIntoConstraints = true
        view.insertSubview(declineRippleHost, belowSubview: incomingStack)

        acceptRippleHost.isHidden = true
        acceptRippleHost.configure(ringColor: UIColor.systemGreen.withAlphaComponent(0.7), ringCount: 3)
        acceptRippleHost.translatesAutoresizingMaskIntoConstraints = true
        view.insertSubview(acceptRippleHost, belowSubview: incomingStack)

        hangUpRippleHost.isHidden = true
        hangUpRippleHost.configure(ringColor: UIColor.systemRed.withAlphaComponent(0.7), ringCount: 3)
        hangUpRippleHost.translatesAutoresizingMaskIntoConstraints = true
        view.insertSubview(hangUpRippleHost, belowSubview: outgoingStack)

        controlsBarView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        controlsBarView.isHidden = true
        controlsBarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsBarView)

        controlsStack.axis = .horizontal
        controlsStack.spacing = 8
        controlsStack.alignment = .top
        controlsStack.distribution = .equalSpacing
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.addArrangedSubview(muteControlColumn)
        controlsStack.addArrangedSubview(speakerControlColumn)
        controlsStack.addArrangedSubview(videoControlColumn)
        controlsStack.addArrangedSubview(screenShareControlColumn)
        controlsStack.addArrangedSubview(hangUpControlColumn)
        controlsBarView.addSubview(controlsStack)

        NSLayoutConstraint.activate([
            remoteVideoView.topAnchor.constraint(equalTo: view.topAnchor),
            remoteVideoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            remoteVideoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            remoteVideoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            peerOfflineOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            peerOfflineOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            peerOfflineOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            peerOfflineOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            peerOfflineAvatarView.centerXAnchor.constraint(equalTo: peerOfflineOverlay.centerXAnchor),
            peerOfflineAvatarView.centerYAnchor.constraint(equalTo: peerOfflineOverlay.centerYAnchor, constant: -24),
            peerOfflineAvatarView.widthAnchor.constraint(equalToConstant: 112),
            peerOfflineAvatarView.heightAnchor.constraint(equalToConstant: 112),

            peerOfflineStatusLabel.topAnchor.constraint(equalTo: peerOfflineAvatarView.bottomAnchor, constant: 16),
            peerOfflineStatusLabel.leadingAnchor.constraint(equalTo: peerOfflineOverlay.leadingAnchor, constant: 32),
            peerOfflineStatusLabel.trailingAnchor.constraint(equalTo: peerOfflineOverlay.trailingAnchor, constant: -32),

            incomingBackgroundImageView.topAnchor.constraint(equalTo: view.topAnchor),
            incomingBackgroundImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            incomingBackgroundImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            incomingBackgroundImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            incomingBlurView.topAnchor.constraint(equalTo: view.topAnchor),
            incomingBlurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            incomingBlurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            incomingBlurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            incomingDimView.topAnchor.constraint(equalTo: view.topAnchor),
            incomingDimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            incomingDimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            incomingDimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            remoteGridScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            remoteGridScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            remoteGridScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            remoteGridScrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            participantAvatarScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 64),
            participantAvatarScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            participantAvatarScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            participantAvatarScrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -150),

            avatarImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 128),
            avatarImageView.heightAnchor.constraint(equalToConstant: 128),

            incomingNameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            incomingNameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            incomingStatusLabel.topAnchor.constraint(equalTo: incomingNameLabel.bottomAnchor, constant: 10),
            incomingStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            incomingStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            incomingStatusLabel.bottomAnchor.constraint(lessThanOrEqualTo: incomingStack.topAnchor, constant: -56),
            incomingStatusLabel.bottomAnchor.constraint(lessThanOrEqualTo: outgoingStack.topAnchor, constant: -56),

            topInfoStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            topInfoStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            topInfoStack.leadingAnchor.constraint(greaterThanOrEqualTo: pipButton.trailingAnchor, constant: 8),
            topInfoStack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            errorLabel.topAnchor.constraint(equalTo: topInfoStack.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            pipButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            pipButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            pipButton.widthAnchor.constraint(equalToConstant: 40),
            pipButton.heightAnchor.constraint(equalToConstant: 40),

            // Under minimize (pip.enter): flip + mute, same column.
            fullScreenLocalControlsStack.centerXAnchor.constraint(equalTo: pipButton.centerXAnchor),
            fullScreenLocalControlsStack.topAnchor.constraint(equalTo: pipButton.bottomAnchor, constant: 10),

            fullScreenFlipCameraButton.widthAnchor.constraint(equalToConstant: 40),
            fullScreenFlipCameraButton.heightAnchor.constraint(equalToConstant: 40),
            fullScreenSelfMuteBadge.widthAnchor.constraint(equalToConstant: 40),
            fullScreenSelfMuteBadge.heightAnchor.constraint(equalToConstant: 40),

            incomingStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            incomingStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),

            outgoingStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            outgoingStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),

            controlsBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            controlsStack.topAnchor.constraint(equalTo: controlsBarView.topAnchor, constant: 6),
            controlsStack.leadingAnchor.constraint(equalTo: controlsBarView.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            controlsStack.trailingAnchor.constraint(equalTo: controlsBarView.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            controlsStack.bottomAnchor.constraint(equalTo: controlsBarView.safeAreaLayoutGuide.bottomAnchor, constant: -5),

            swapIncomingBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            swapIncomingBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            swapIncomingBanner.bottomAnchor.constraint(equalTo: controlsBarView.topAnchor, constant: -12)
        ])

        let avatarCenterY = avatarImageView.centerYAnchor.constraint(
            equalTo: view.centerYAnchor,
            constant: -56
        )
        let avatarRingTop = avatarImageView.topAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.topAnchor,
            constant: 58
        )
        let nameCenterY = incomingNameLabel.centerYAnchor.constraint(
            equalTo: view.centerYAnchor,
            constant: -32
        )
        let nameClearAvatar = incomingNameLabel.topAnchor.constraint(
            greaterThanOrEqualTo: avatarImageView.bottomAnchor,
            constant: 36
        )
        avatarCenterYConstraint = avatarCenterY
        avatarRingTopConstraint = avatarRingTop
        ringNameCenterYConstraint = nameCenterY
        ringNameClearAvatarConstraint = nameClearAvatar
        avatarCenterY.isActive = true
        avatarRingTop.isActive = false
        nameCenterY.isActive = false
        nameClearAvatar.isActive = false
    }

    private func setupSwapIncomingBanner() {
        swapIncomingBanner.backgroundColor = UIColor(white: 0.12, alpha: 0.95)
        swapIncomingBanner.layer.cornerRadius = 14
        swapIncomingBanner.clipsToBounds = true
        swapIncomingBanner.isHidden = true
        swapIncomingBanner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(swapIncomingBanner)

        swapTitleLabel.font = UIFont(name: "Fredoka-SemiBold", size: 15) ?? UIFont.chat(.bold, size: 15)
        swapTitleLabel.textColor = .white
        swapTitleLabel.numberOfLines = 1

        swapSubtitleLabel.font = UIFont(name: "Fredoka-Regular", size: 12) ?? UIFont.chat(size: 12)
        swapSubtitleLabel.textColor = UIColor(white: 0.75, alpha: 1)
        swapSubtitleLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [swapTitleLabel, swapSubtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        swapDeclineButton.setTitle("Decline", for: .normal)
        swapDeclineButton.setTitleColor(.white, for: .normal)
        swapDeclineButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        swapDeclineButton.titleLabel?.font = UIFont.chat(.semibold, size: 14)
        swapDeclineButton.layer.cornerRadius = 18
        swapDeclineButton.addTarget(self, action: #selector(swapDeclineTapped), for: .touchUpInside)

        swapAcceptButton.setTitle("Accept", for: .normal)
        swapAcceptButton.setTitleColor(.white, for: .normal)
        swapAcceptButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.95)
        swapAcceptButton.titleLabel?.font = UIFont.chat(.semibold, size: 14)
        swapAcceptButton.layer.cornerRadius = 18
        swapAcceptButton.addTarget(self, action: #selector(swapAcceptTapped), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [swapDeclineButton, swapAcceptButton])
        buttons.axis = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fillEqually
        buttons.translatesAutoresizingMaskIntoConstraints = false

        swapIncomingBanner.addSubview(textStack)
        swapIncomingBanner.addSubview(buttons)

        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: swapIncomingBanner.topAnchor, constant: 12),
            textStack.leadingAnchor.constraint(equalTo: swapIncomingBanner.leadingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: swapIncomingBanner.trailingAnchor, constant: -14),

            buttons.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: 10),
            buttons.leadingAnchor.constraint(equalTo: swapIncomingBanner.leadingAnchor, constant: 14),
            buttons.trailingAnchor.constraint(equalTo: swapIncomingBanner.trailingAnchor, constant: -14),
            buttons.bottomAnchor.constraint(equalTo: swapIncomingBanner.bottomAnchor, constant: -12),
            buttons.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func placeLocalPreviewInDefaultCorner() {
        let inset: CGFloat = 12
        let safe = view.safeAreaInsets
        // WhatsApp self-view: bottom-right floating PiP.
        localPreviewContainer.frame = CGRect(
            x: view.bounds.width - localPreviewSize.width - inset - safe.right,
            y: view.bounds.height - localPreviewSize.height - inset - safe.bottom - 96,
            width: localPreviewSize.width,
            height: localPreviewSize.height
        )
    }

    private func localPreviewDragBounds() -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let inset: CGFloat = 8
        let safe = view.safeAreaInsets
        let halfW = localPreviewSize.width / 2
        let halfH = localPreviewSize.height / 2
        return (
            minX: safe.left + inset + halfW,
            maxX: view.bounds.width - safe.right - inset - halfW,
            minY: safe.top + inset + halfH,
            maxY: view.bounds.height - safe.bottom - inset - halfH
        )
    }

    @objc private func handleLocalPreviewPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            localPreviewDidDrag = false
            localPreviewPanStart = localPreviewContainer.center
            view.bringSubviewToFront(localPreviewContainer)
        case .changed:
            let moved = hypot(translation.x, translation.y) > 8
            if moved, !localPreviewDidDrag {
                localPreviewDidDrag = true
                UIView.animate(withDuration: 0.12) {
                    self.localPreviewContainer.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
                }
            }
            guard localPreviewDidDrag else { return }
            var next = CGPoint(
                x: localPreviewPanStart.x + translation.x,
                y: localPreviewPanStart.y + translation.y
            )
            let b = localPreviewDragBounds()
            next.x = min(max(b.minX, next.x), b.maxX)
            next.y = min(max(b.minY, next.y), b.maxY)
            localPreviewContainer.center = next
        case .ended, .cancelled:
            UIView.animate(withDuration: 0.12) {
                self.localPreviewContainer.transform = .identity
            }
            if localPreviewDidDrag {
                snapLocalPreviewToNearestEdge()
            }
        default:
            break
        }
    }

    /// WhatsApp 1:1: tap the floating preview to swap full-screen ↔ PiP.
    @objc private func handleLocalPreviewTap() {
        guard canSwapPrimaryVideo else { return }
        isLocalVideoPrimary.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        service?.rebindActiveCallVideoSurfaces()
        reloadFromService()
    }

    private var canSwapPrimaryVideo: Bool {
        guard let service else { return false }
        let remoteCount = max(service.remoteParticipantUids.count, service.remoteVideoUids.count)
        // WhatsApp: allow tap-swap in 1:1 video even if either camera is off.
        return service.phase == .active
            && service.call?.type == .video
            && !service.isScreenSharing
            && remoteCount == 1
    }

    /// WhatsApp-style: keep your Y, snap only to left or right edge.
    private func snapLocalPreviewToNearestEdge() {
        let b = localPreviewDragBounds()
        let current = localPreviewContainer.center
        let targetX = current.x < view.bounds.midX ? b.minX : b.maxX
        let targetY = min(max(b.minY, current.y), b.maxY)

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.4,
            options: [.curveEaseOut]
        ) {
            self.localPreviewContainer.center = CGPoint(x: targetX, y: targetY)
        }
    }

    private func configureCircleButton(
        _ button: UIButton,
        systemName: String,
        selectedName: String? = nil,
        color: UIColor,
        size: CGFloat = 56,
        symbolPointSize: CGFloat? = nil
    ) {
        button.backgroundColor = color
        button.tintColor = .white
        let symbolConfig = symbolPointSize.map {
            UIImage.SymbolConfiguration(pointSize: $0, weight: .semibold)
        }
        button.setImage(UIImage(systemName: systemName, withConfiguration: symbolConfig), for: .normal)
        if let selectedName {
            button.setImage(UIImage(systemName: selectedName, withConfiguration: symbolConfig), for: .selected)
        }
        button.adjustsImageWhenHighlighted = false
        button.clipsToBounds = true
        button.layer.cornerRadius = size / 2
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size)
        ])
    }

    private func makeControlColumn(
        button: UIButton,
        titleLabel: UILabel,
        title: String,
        titleFontSize: CGFloat = 11,
        titleWeight: UIFont.Weight = .medium
    ) -> UIStackView {
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: titleFontSize, weight: titleWeight)
        titleLabel.textColor = UIColor(white: 0.92, alpha: 1)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let column = UIStackView(arrangedSubviews: [button, titleLabel])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        let minWidth: CGFloat = titleFontSize > 11 ? 64 : 52
        let maxWidth: CGFloat = titleFontSize > 11 ? 80 : 68
        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
        ])
        return column
    }

    private func updateControlTitles(
        muted: Bool,
        speakerOn: Bool,
        videoEnabled: Bool,
        sharing: Bool,
        audioRoute: AgoraCallAudioRoute,
        hasExternal: Bool
    ) {
        muteTitleLabel.text = muted ? "Unmute" : "Mute"
        // WhatsApp: when headset connected, label is "Audio" under the ⋯ button.
        if hasExternal {
            speakerTitleLabel.text = "Audio"
        } else {
            speakerTitleLabel.text = audioRoute.title
        }
        videoTitleLabel.text = videoEnabled ? "Video" : "Video off"
        screenShareTitleLabel.text = sharing ? "Stop share" : "Share"
        endTitleLabel.text = "End"
    }

    /// Icon + selected style for Speaker / Earpiece / Headphones / Bluetooth / ⋯ picker.
    private func applyAudioRouteAppearance(
        _ route: AgoraCallAudioRoute,
        speakerOn: Bool,
        hasExternal: Bool
    ) {
        let imageName: String
        if hasExternal {
            // WhatsApp-style: three dots opens Speaker / Earpiece / Bluetooth sheet.
            imageName = "ellipsis"
        } else {
            imageName = route.systemImageName
        }
        let image = UIImage(systemName: imageName)
        speakerButton.setImage(image, for: .normal)
        speakerButton.setImage(image, for: .selected)

        let highlight: Bool
        if hasExternal {
            highlight = true
        } else {
            highlight = route.isExternalHeadset || !speakerOn
        }
        speakerButton.isSelected = highlight
        if highlight {
            speakerButton.backgroundColor = .white
            speakerButton.tintColor = controlButtonSelectedIcon
        } else {
            speakerButton.backgroundColor = controlButtonNormalFill
            speakerButton.tintColor = .white
        }
    }

    @objc private func speakerTapped() {
        guard let service else { return }
        if service.hasExternalAudioDevice {
            presentAudioOutputPicker(from: service)
        } else {
            service.toggleSpeaker()
        }
    }

    /// WhatsApp-style dark card: icon + label + white checkmark on selected row.
    private func presentAudioOutputPicker(from service: AgoraCallService) {
        dismissAudioRoutePicker(animated: false)

        let selected = service.selectedAudioOutput
        let externalTitle = service.externalAudioDeviceTitle
        let externalIcon: String
        if AgoraRtcManager.hasWiredHeadsetOutput(), AgoraRtcManager.externalBluetoothDisplayName() == nil {
            externalIcon = "headphones"
        } else {
            externalIcon = "wave.3.right"
        }

        let options: [(AgoraCallAudioOutputChoice, String, String, Bool)] = [
            (.speaker, "speaker.wave.2.fill", "Speaker", selected == .speaker),
            (.earpiece, "iphone", "Earpiece", selected == .earpiece),
            (.external, externalIcon, externalTitle, selected == .external)
        ]

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        audioRoutePickerContainer = container

        let dim = UIButton(type: .custom)
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        dim.translatesAutoresizingMaskIntoConstraints = false
        dim.addTarget(self, action: #selector(dismissAudioRoutePickerTapped), for: .touchUpInside)
        container.addSubview(dim)

        let card = AgoraCallAudioRoutePickerCard()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.configure(options: options) { [weak self] choice in
            service.selectAudioOutput(choice)
            self?.dismissAudioRoutePicker(animated: true)
        }
        container.addSubview(card)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dim.topAnchor.constraint(equalTo: container.topAnchor),
            dim.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            dim.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            card.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 48),
            card.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -48),
            card.widthAnchor.constraint(equalToConstant: 260),
            card.bottomAnchor.constraint(equalTo: controlsBarView.topAnchor, constant: -16)
        ])

        view.bringSubviewToFront(container)
        container.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.96, y: 0.96)
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            container.alpha = 1
            card.transform = .identity
        }
    }

    @objc private func dismissAudioRoutePickerTapped() {
        dismissAudioRoutePicker(animated: true)
    }

    private func dismissAudioRoutePicker(animated: Bool) {
        guard let container = audioRoutePickerContainer else { return }
        audioRoutePickerContainer = nil
        let animations = {
            container.alpha = 0
        }
        let finish = {
            container.removeFromSuperview()
        }
        if animated {
            UIView.animate(withDuration: 0.18, animations: animations, completion: { _ in finish() })
        } else {
            finish()
        }
    }

    /// Full white circle when selected (no iOS system rounded-rect). Screen share can pass green fill.
    private func applyToggleButtonAppearance(_ button: UIButton, selectedFill: UIColor? = nil) {
        if button.isSelected {
            if let selectedFill {
                button.backgroundColor = selectedFill
                button.tintColor = .white
            } else {
                button.backgroundColor = .white
                button.tintColor = controlButtonSelectedIcon
            }
        } else {
            button.backgroundColor = controlButtonNormalFill
            button.tintColor = .white
        }
    }

    private func setupChromeToggleGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCallChromeTap(_:)))
        tap.cancelsTouchesInView = false
        tap.numberOfTapsRequired = 1
        view.addGestureRecognizer(tap)
    }

    private var canToggleCallChrome: Bool {
        guard let service else { return false }
        switch service.phase {
        case .active:
            return true
        case .outgoing, .incoming, .idle:
            return false
        }
    }

    @objc private func handleCallChromeTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, canToggleCallChrome else { return }
        // Prefer dismissing audio picker over hiding call chrome.
        if audioRoutePickerContainer != nil {
            dismissAudioRoutePicker(animated: true)
            return
        }
        let point = gesture.location(in: view)
        if let hit = view.hitTest(point, with: nil), shouldIgnoreChromeToggle(for: hit) {
            return
        }
        areChromeHiddenByUser.toggle()
        animateCallChromeVisibility()
    }

    private func shouldIgnoreChromeToggle(for hit: UIView) -> Bool {
        if hit is UIControl { return true }
        if let picker = audioRoutePickerContainer, hit.isDescendant(of: picker) || hit === picker {
            return true
        }
        if hit.isDescendant(of: controlsBarView) { return true }
        if !swapIncomingBanner.isHidden, hit.isDescendant(of: swapIncomingBanner) { return true }
        if hit.isDescendant(of: hangUpButton) { return true }
        if hit.isDescendant(of: incomingStack) { return true }
        if hit.isDescendant(of: outgoingStack) { return true }
        if hit.isDescendant(of: pipButton) { return true }
        if hit.isDescendant(of: fullScreenLocalControlsStack) { return true }
        if hit.isDescendant(of: localPreviewContainer) { return true }
        return false
    }

    private func animateCallChromeVisibility() {
        let hiding = areChromeHiddenByUser
        let chrome: [UIView] = [controlsBarView, pipButton, topInfoStack]
        // Keep swap Accept/Decline visible even when chrome is hidden.

        if hiding {
            UIView.animate(withDuration: 0.22, animations: {
                chrome.forEach { $0.alpha = 0 }
            }, completion: { _ in
                self.reloadFromService()
                chrome.forEach { $0.alpha = 1 }
            })
        } else {
            reloadFromService()
            chrome.forEach { $0.alpha = 0 }
            UIView.animate(withDuration: 0.22) {
                chrome.forEach { $0.alpha = 1 }
            }
        }
    }

    private func applyCallAvatar(urlString: String?, placeholder: UIImage?) {
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
            avatarImageView.image = placeholder
            return
        }
        avatarImageView.setChatImage(with: url, placeholderImage: placeholder)
    }

    private func updateRingBackgroundImage(urlString: String?) {
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
            incomingBackgroundImageView.image = nil
            incomingBackgroundImageView.backgroundColor = UIColor(white: 0.12, alpha: 1)
            return
        }
        incomingBackgroundImageView.backgroundColor = .clear
        incomingBackgroundImageView.setChatImage(with: url, placeholderImage: nil, options: [.retryFailed])
    }

    private func clearRingBackgroundImage() {
        incomingBackgroundImageView.cancelChatImageLoad()
        incomingBackgroundImageView.image = nil
    }

    private func applyRingCallerLayout(isRinging: Bool) {
        avatarCenterYConstraint?.isActive = !isRinging
        avatarRingTopConstraint?.isActive = isRinging
        ringNameCenterYConstraint?.isActive = isRinging
        ringNameClearAvatarConstraint?.isActive = isRinging
        view.layoutIfNeeded()
    }

    private func syncRingRippleHostFrames() {
        let ringingVisible = !incomingStack.isHidden || !outgoingStack.isHidden
        guard ringingVisible else { return }

        let avatarSide: CGFloat = 260
        avatarRippleHost.bounds = CGRect(x: 0, y: 0, width: avatarSide, height: avatarSide)
        avatarRippleHost.center = avatarImageView.center

        let buttonRippleSide: CGFloat = 136
        if !incomingStack.isHidden {
            let acceptCenter = acceptButton.convert(
                CGPoint(x: acceptButton.bounds.midX, y: acceptButton.bounds.midY),
                to: view
            )
            let declineCenter = declineButton.convert(
                CGPoint(x: declineButton.bounds.midX, y: declineButton.bounds.midY),
                to: view
            )
            acceptRippleHost.bounds = CGRect(x: 0, y: 0, width: buttonRippleSide, height: buttonRippleSide)
            acceptRippleHost.center = acceptCenter
            declineRippleHost.bounds = CGRect(x: 0, y: 0, width: buttonRippleSide, height: buttonRippleSide)
            declineRippleHost.center = declineCenter
        }
        if !outgoingStack.isHidden {
            let endCenter = outgoingEndButton.convert(
                CGPoint(x: outgoingEndButton.bounds.midX, y: outgoingEndButton.bounds.midY),
                to: view
            )
            hangUpRippleHost.bounds = CGRect(x: 0, y: 0, width: buttonRippleSide, height: buttonRippleSide)
            hangUpRippleHost.center = endCenter
        }
    }

    private func startRingAnimationsIfNeeded() {
        syncRingRippleHostFrames()
        if !isRingAnimating {
            isRingAnimating = true
            avatarRippleHost.startAnimating()
        }
        if !incomingStack.isHidden {
            acceptRippleHost.startAnimating()
            declineRippleHost.startAnimating()
        } else {
            acceptRippleHost.stopAnimating()
            declineRippleHost.stopAnimating()
        }
        if !outgoingStack.isHidden {
            hangUpRippleHost.startAnimating()
        } else {
            hangUpRippleHost.stopAnimating()
        }
    }

    private func stopRingAnimations() {
        isRingAnimating = false
        avatarRippleHost.stopAnimating()
        acceptRippleHost.stopAnimating()
        declineRippleHost.stopAnimating()
        hangUpRippleHost.stopAnimating()
    }

    /// Status while dialing out, before callee reports `call:ringing`.
    private static func outgoingCallingStatusText(isGroup: Bool, isVideo: Bool) -> String {
        if isGroup {
            return isVideo ? "Group video calling…" : "Group calling…"
        }
        return isVideo ? "Video calling…" : "Calling…"
    }

    /// Group active chrome: wait with Calling… until the first peer attends, then duration.
    private func groupActiveStatusText(service: AgoraCallService) -> String {
        if !service.hasStartedCallTimer {
            return Self.outgoingCallingStatusText(isGroup: true, isVideo: service.call?.type == .video)
        }
        let timer = formatElapsed(service.elapsedSec)
        let count = max(1, service.gridParticipants.count)
        if service.hasRemoteVideo, !service.isScreenSharing, service.call?.type != .video {
            return "\(timer) · Screen share · \(count) in call"
        }
        return "\(timer) · \(count) in call"
    }

    private func formatElapsed(_ sec: Int) -> String {
        let m = sec / 60
        let s = sec % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Actions

    @objc private func hangUpTapped() {
        stopRingAnimations()
        service?.hangUp()
    }

    @objc private func acceptTapped() {
        stopRingAnimations()
        Task { await service?.acceptIncoming() }
    }

    @objc private func declineTapped() {
        stopRingAnimations()
        service?.declineIncoming()
    }

    @objc private func swapDeclineTapped() {
        service?.declinePendingIncoming()
    }

    @objc private func swapAcceptTapped() {
        Task { await service?.acceptPendingIncoming() }
    }

    @objc private func muteTapped() {
        service?.toggleMute()
    }

    @objc private func videoTapped() {
        service?.toggleVideo()
    }

    @objc private func flipCameraTapped() {
        service?.flipCamera()
    }

    @objc private func screenShareTapped() {
        service?.toggleScreenShare()
    }

    @objc private func pipTapped() {
        service?.enterPictureInPicture()
    }
}

extension AgoraCallViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Let the PiP flip control receive taps without triggering drag / swap.
        if let view = touch.view, view.isDescendant(of: flipCameraButton) || view === flipCameraButton {
            return false
        }
        return true
    }
}

// MARK: - Expanding ripple rings (incoming / outgoing)

@MainActor
private final class AgoraCallRippleHostView: UIView {

    private var ringViews: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(ringColor: UIColor, ringCount: Int = 3) {
        stopAnimating()
        ringViews.forEach { $0.removeFromSuperview() }
        ringViews.removeAll()
        for _ in 0..<ringCount {
            let ring = UIView()
            ring.backgroundColor = .clear
            ring.layer.borderColor = ringColor.cgColor
            ring.layer.borderWidth = 2.5
            ring.alpha = 0
            addSubview(ring)
            ringViews.append(ring)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height) * 0.38
        for ring in ringViews {
            ring.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            ring.center = CGPoint(x: bounds.midX, y: bounds.midY)
            ring.layer.cornerRadius = side / 2
        }
    }

    func startAnimating() {
        stopAnimating()
        layoutIfNeeded()
        let duration: CFTimeInterval = 2.4
        for (index, ring) in ringViews.enumerated() {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.0
            scale.toValue = 2.35

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.65
            fade.toValue = 0.0

            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = duration
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.55
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.isRemovedOnCompletion = false
            group.fillMode = .forwards
            ring.layer.add(group, forKey: "agora.ripple")
        }
    }

    func stopAnimating() {
        for ring in ringViews {
            ring.layer.removeAnimation(forKey: "agora.ripple")
            ring.layer.transform = CATransform3DIdentity
            ring.alpha = 0
        }
    }
}

// MARK: - Video tile (group video grid)

@MainActor
final class AgoraCallVideoTileView: UIView {

    /// Surface Agora binds into (aspect-fill crop, like WhatsApp).
    let videoContainer = UIView()
    private let placeholderView = UIView()
    private let avatarView = UIImageView()
    /// Always-on overlay — bottom leading (visible with video on; clears notch/safe area).
    private let nameLabel = UILabel()
    private let muteBadge = UIImageView()
    private var avatarWidthConstraint: NSLayoutConstraint?
    private var avatarHeightConstraint: NSLayoutConstraint?
    private var nameTrailingToMute: NSLayoutConstraint?
    private var nameTrailingToEdge: NSLayoutConstraint?
    private var nameFontBase: CGFloat = 13

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.12, alpha: 1)
        clipsToBounds = true
        layer.cornerRadius = 14

        videoContainer.backgroundColor = .black
        videoContainer.clipsToBounds = true
        videoContainer.isUserInteractionEnabled = false
        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(videoContainer)

        placeholderView.backgroundColor = UIColor(white: 0.14, alpha: 1)
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderView)

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.backgroundColor = UIColor(white: 0.28, alpha: 1)
        avatarView.tintColor = .white
        avatarView.image = UIImage(systemName: "person.circle.fill")
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.addSubview(avatarView)

        nameLabel.font = UIFont.chat(.semibold, size: nameFontBase)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .left
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.layer.shadowColor = UIColor.black.cgColor
        nameLabel.layer.shadowOpacity = 0.75
        nameLabel.layer.shadowRadius = 2
        nameLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(nameLabel)

        muteBadge.image = UIImage(systemName: "mic.slash.fill")
        muteBadge.tintColor = .white
        muteBadge.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        muteBadge.contentMode = .center
        muteBadge.layer.cornerRadius = 10
        muteBadge.clipsToBounds = true
        muteBadge.isHidden = true
        muteBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        muteBadge.setContentHuggingPriority(.required, for: .horizontal)
        muteBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(muteBadge)

        let avatarW = avatarView.widthAnchor.constraint(equalToConstant: 88)
        let avatarH = avatarView.heightAnchor.constraint(equalToConstant: 88)
        avatarWidthConstraint = avatarW
        avatarHeightConstraint = avatarH

        let nameToMute = nameLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: muteBadge.leadingAnchor,
            constant: -6
        )
        let nameToEdge = nameLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingAnchor,
            constant: -8
        )
        nameTrailingToMute = nameToMute
        nameTrailingToEdge = nameToEdge
        nameToMute.isActive = false
        nameToEdge.isActive = true

        NSLayoutConstraint.activate([
            videoContainer.topAnchor.constraint(equalTo: topAnchor),
            videoContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderView.topAnchor.constraint(equalTo: topAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: bottomAnchor),

            avatarView.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            avatarView.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor),
            avatarW,
            avatarH,

            // Bottom chrome — name truncates before mute so long names never overlap.
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            muteBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            muteBadge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            muteBadge.widthAnchor.constraint(equalToConstant: 22),
            muteBadge.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Scale avatar for full-screen tiles and tiny PiP tiles.
        let side = min(bounds.width, bounds.height)
        let avatarSize = min(88, max(28, side * 0.42))
        avatarWidthConstraint?.constant = avatarSize
        avatarHeightConstraint?.constant = avatarSize
        nameLabel.font = UIFont.chat(.semibold, size: side < 160 ? 10 : nameFontBase)
        avatarView.layer.cornerRadius = avatarSize / 2
        bringSubviewToFront(nameLabel)
        bringSubviewToFront(muteBadge)
    }

    private var configuredName: String?
    private var configuredAvatarURL: String?
    private var configuredHasVideo: Bool?

    func configure(name: String, avatarURL: String?, hasVideo: Bool) {
        if configuredName != name {
            configuredName = name
            nameLabel.text = name
            nameLabel.isHidden = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        // Only flip visibility when camera truly changes — avoids flash on repeated configure.
        if configuredHasVideo != hasVideo {
            configuredHasVideo = hasVideo
            videoContainer.isHidden = !hasVideo
            placeholderView.isHidden = hasVideo
        }

        let urlKey = avatarURL ?? ""
        guard configuredAvatarURL != urlKey else { return }
        configuredAvatarURL = urlKey
        if let avatarURL, !avatarURL.isEmpty, let url = URL(string: avatarURL) {
            avatarView.setChatImage(
                with: url,
                placeholderImage: UIImage(systemName: "person.circle.fill")
            )
        } else {
            avatarView.image = UIImage(systemName: "person.circle.fill")
        }
    }

    func setMuted(_ muted: Bool) {
        muteBadge.isHidden = !muted
        nameTrailingToMute?.isActive = muted
        nameTrailingToEdge?.isActive = !muted
    }
}

// MARK: - Participant tile (group audio grid)

@MainActor
final class AgoraCallParticipantTileView: UIView {

    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let youBadge = UILabel()
    private let muteBadge = UIImageView()
    private var nameTrailingToMute: NSLayoutConstraint?
    private var nameTrailingToEdge: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.14, alpha: 1)
        layer.cornerRadius = 16
        clipsToBounds = true

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.backgroundColor = UIColor(white: 0.25, alpha: 1)
        avatarView.tintColor = .white
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarView)

        nameLabel.font = UIFont.chat(.semibold, size: 13)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        youBadge.text = "You"
        youBadge.font = UIFont.chat(.bold, size: 10)
        youBadge.textColor = .white
        youBadge.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
        youBadge.textAlignment = .center
        youBadge.layer.cornerRadius = 8
        youBadge.clipsToBounds = true
        youBadge.isHidden = true
        youBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(youBadge)

        muteBadge.image = UIImage(systemName: "mic.slash.fill")
        muteBadge.tintColor = .white
        muteBadge.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        muteBadge.contentMode = .center
        muteBadge.layer.cornerRadius = 11
        muteBadge.clipsToBounds = true
        muteBadge.isHidden = true
        muteBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        muteBadge.setContentHuggingPriority(.required, for: .horizontal)
        muteBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(muteBadge)

        let nameToMute = nameLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: muteBadge.leadingAnchor,
            constant: -6
        )
        let nameToEdge = nameLabel.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -8
        )
        nameTrailingToMute = nameToMute
        nameTrailingToEdge = nameToEdge
        nameToMute.isActive = false
        nameToEdge.isActive = true

        NSLayoutConstraint.activate([
            avatarView.centerXAnchor.constraint(equalTo: centerXAnchor),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
            avatarView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.48),
            avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            youBadge.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            youBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            youBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            youBadge.heightAnchor.constraint(equalToConstant: 18),

            muteBadge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            muteBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            muteBadge.widthAnchor.constraint(equalToConstant: 22),
            muteBadge.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        avatarView.layer.cornerRadius = avatarView.bounds.width / 2
        bringSubviewToFront(muteBadge)
    }

    func configure(with person: AgoraCallGridParticipant) {
        let title = person.isSelf ? (person.displayName == "You" ? "You" : person.displayName) : person.displayName
        nameLabel.text = title
        youBadge.isHidden = !person.isSelf
        alpha = person.isConnected ? 1.0 : 0.55
        layer.borderWidth = person.isConnected ? 2 : 0
        layer.borderColor = person.isConnected
            ? UIColor.systemGreen.withAlphaComponent(0.85).cgColor
            : UIColor.clear.cgColor

        if let url = person.avatarURL, !url.isEmpty, let imageURL = URL(string: url) {
            avatarView.setChatImage(
                with: imageURL,
                placeholderImage: UIImage(systemName: "person.circle.fill")
            )
        } else {
            avatarView.image = UIImage(systemName: "person.circle.fill")
        }
    }

    func setMuted(_ muted: Bool) {
        muteBadge.isHidden = !muted
        nameTrailingToMute?.isActive = muted
        nameTrailingToEdge?.isActive = !muted
    }
}

// MARK: - WhatsApp-style audio route picker card

@MainActor
private final class AgoraCallAudioRoutePickerCard: UIView {

    private let stack = UIStackView()
    private var onSelect: ((AgoraCallAudioOutputChoice) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 0.96)
        layer.cornerRadius = 14
        clipsToBounds = true

        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        options: [(AgoraCallAudioOutputChoice, String, String, Bool)],
        onSelect: @escaping (AgoraCallAudioOutputChoice) -> Void
    ) {
        self.onSelect = onSelect
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for option in options {
            let (choice, icon, title, selected) = option
            let row = makeRow(icon: icon, title: title, selected: selected)
            row.accessibilityIdentifier = choiceKey(choice)
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 52)
            ])
        }
    }

    private func choiceKey(_ choice: AgoraCallAudioOutputChoice) -> String {
        switch choice {
        case .speaker: return "speaker"
        case .earpiece: return "earpiece"
        case .external: return "external"
        }
    }

    private func choice(from key: String?) -> AgoraCallAudioOutputChoice? {
        switch key {
        case "speaker": return .speaker
        case "earpiece": return .earpiece
        case "external": return .external
        default: return nil
        }
    }

    private func makeRow(icon: String, title: String, selected: Bool) -> UIButton {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false

        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = UIFont.chat(.regular, size: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false

        let checkConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let check = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: checkConfig))
        check.tintColor = .white
        check.contentMode = .scaleAspectFit
        check.translatesAutoresizingMaskIntoConstraints = false
        check.isHidden = !selected
        check.isUserInteractionEnabled = false
        // Keep layout space so rows stay aligned; only the mark itself hides.
        check.alpha = selected ? 1 : 0

        button.addSubview(iconView)
        button.addSubview(label)
        button.addSubview(check)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 18),
            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -8),

            check.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -18),
            check.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 18),
            check.heightAnchor.constraint(equalToConstant: 18)
        ])

        return button
    }

    @objc private func rowTapped(_ sender: UIButton) {
        guard let choice = choice(from: sender.accessibilityIdentifier) else { return }
        onSelect?(choice)
    }
}

// MARK: - Network bars (WhatsApp-style)

private final class AgoraCallNetworkBarsView: UIView {
    private let bars: [UIView] = (0..<4).map { _ in
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        v.layer.cornerRadius = 1.5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let heights: [CGFloat] = [6, 9, 12, 15]
        var previous: UIView?
        for (i, bar) in bars.enumerated() {
            addSubview(bar)
            NSLayoutConstraint.activate([
                bar.widthAnchor.constraint(equalToConstant: 3.5),
                bar.heightAnchor.constraint(equalToConstant: heights[i]),
                bar.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            if let previous {
                bar.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 2).isActive = true
            } else {
                bar.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
            }
            previous = bar
        }
        bars.last?.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        heightAnchor.constraint(equalToConstant: 16).isActive = true
        widthAnchor.constraint(equalToConstant: 20).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setLevel(_ level: AgoraCallNetworkQualityLevel) {
        let filled = level.filledBars
        let color: UIColor
        switch level {
        case .excellent, .good:
            color = .systemGreen
        case .fair:
            color = .systemYellow
        case .poor, .reconnecting, .lost:
            color = ChatTheme.warning
        case .unknown:
            color = UIColor.white.withAlphaComponent(0.35)
        }
        for (i, bar) in bars.enumerated() {
            bar.backgroundColor = i < filled ? color : UIColor.white.withAlphaComponent(0.28)
        }
    }
}

