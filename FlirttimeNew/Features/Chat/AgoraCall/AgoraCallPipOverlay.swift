//
//  AgoraCallPipOverlay.swift
//  FlirttimeNew
//
//  Floating in-app Picture-in-Picture for active Agora calls.
//  Group video: same WhatsApp layout as full-screen — remotes in grid, self as tiny inset.
//

import UIKit

@MainActor
final class AgoraCallPipOverlay: UIView {

    /// 1:1 / single-remote surface (also used when grid is off).
    let remoteVideoView = UIView()
    let localVideoView = UIView()
    /// Chrome around local camera / avatar inset (WhatsApp self-view).
    private let localPipContainer = UIView()
    private let localPipAvatarView = UIImageView()

    private let remoteGridContainer = UIView()
    private var remoteTiles: [UInt: AgoraCallVideoTileView] = [:]

    private let avatarImageView = UIImageView()
    /// WhatsApp-style green circle + screen icon while you are sharing.
    private let screenShareBadgeView = UIView()
    private let screenShareIconView = UIImageView()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let expandButton = UIButton(type: .system)
    private let hangUpButton = UIButton(type: .system)
    private let flipCameraButton = UIButton(type: .system)
    private let trailingControlsStack = UIStackView()
    private let localMuteBadge = UIImageView()
    private var configuredLocalPipAvatarURL: String?

    private weak var service: AgoraCallService?
    private var panStart: CGPoint = .zero
    private var usesRemoteGrid = false
    /// Visible keyboard height overlapping this window (0 when hidden).
    private var keyboardBottomInset: CGFloat = 0
    private var keyboardObservers: [NSObjectProtocol] = []
    /// Auto-hides the center maximize control after idle.
    private var maximizeHideWorkItem: DispatchWorkItem?
    private var isMaximizeVisible = false

    private static let whatsAppGreen = UIColor(red: 0.15, green: 0.68, blue: 0.38, alpha: 1)
    private static let maximizeAutoHideDelay: TimeInterval = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(service: AgoraCallService) {
        self.service = service
        startKeyboardObserversIfNeeded()
        reload()
    }

    func stopKeyboardObservers() {
        let center = NotificationCenter.default
        for token in keyboardObservers {
            center.removeObserver(token)
        }
        keyboardObservers.removeAll()
        keyboardBottomInset = 0
        hideMaximizeControl(animated: false)
    }

    /// Bind surfaces for every remote in a group PiP (WhatsApp mini grid).
    func syncRemoteVideoTiles(uids: [UInt], binder: (UInt, UIView) -> Void) {
        let uidSet = Set(uids)
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
                tile.setMuted(service?.isRemoteMuted(uid: uid) ?? false)
            } else {
                let tile = AgoraCallVideoTileView()
                tile.configure(name: profile.name, avatarURL: profile.avatarURL, hasVideo: hasVideo)
                tile.setMuted(service?.isRemoteMuted(uid: uid) ?? false)
                remoteTiles[uid] = tile
                remoteGridContainer.addSubview(tile)
            }
        }
        usesRemoteGrid = uids.count > 1
        remoteGridContainer.isHidden = !usesRemoteGrid
        remoteVideoView.isHidden = usesRemoteGrid
        layoutRemoteGrid()
        if uids.count <= 1, let uid = uids.first {
            binder(uid, remoteVideoView)
        } else {
            for uid in uids {
                if let tile = remoteTiles[uid] {
                    binder(uid, tile.videoContainer)
                }
            }
        }
    }

    /// Mute / name / hasVideo only — no grid re-layout (avoids PiP remote flash).
    func refreshTileMetadataOnly() {
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
        localMuteBadge.isHidden = localPipContainer.isHidden || !service.muted
    }

    func reload() {
        guard let service else { return }
        nameLabel.text = service.callDisplayTitle

        if service.isScreenSharing {
            applyWhatsAppScreenShareStyle(elapsed: service.elapsedSec)
            return
        }

        // Restore default chrome after screen share.
        backgroundColor = UIColor(white: 0.1, alpha: 0.96)
        layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        screenShareBadgeView.isHidden = true
        avatarImageView.tintColor = .white
        avatarImageView.layer.cornerRadius = avatarImageView.bounds.width / 2
        nameLabel.textAlignment = .natural
        statusLabel.textAlignment = .natural
        nameLabel.font = UIFont.chat(.semibold, size: 13)
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = UIColor(white: 0.85, alpha: 1)
        let isGroup = service.isGroupCall
        let isVideo = service.call?.type == .video
        let remoteCount = max(service.remoteParticipantUids.count, service.remoteVideoUids.count)

        applyElapsedStatusText(service: service, isGroup: isGroup)

        if isGroup {
            if let pic = service.avatarURLOverride, !pic.isEmpty {
                avatarImageView.setChatImage(
                    with: URL(string: pic),
                    placeholderImage: UIImage(systemName: "person.3.fill")
                )
            } else {
                avatarImageView.image = UIImage(systemName: "person.3.fill")
            }
        } else {
            let peer = service.call?.peer(relativeTo: service.meId)
            if let pic = peer?.profilePicture ?? service.avatarURLOverride, !pic.isEmpty {
                avatarImageView.setChatImage(
                    with: URL(string: pic),
                    placeholderImage: UIImage(systemName: "person.circle.fill")
                )
            } else {
                avatarImageView.image = UIImage(systemName: "person.circle.fill")
            }
        }

        // Group video with 2+ remotes → mini WhatsApp grid (same as full-screen).
        let showGrid = isGroup && isVideo && remoteCount > 1
        usesRemoteGrid = showGrid
        if showGrid {
            // Ensure a tile exists for every remote (bind happens in service.rebindRtcToPipViews).
            let uids = service.remoteParticipantUids
            let uidSet = Set(uids)
            var structureChanged = false
            for uid in remoteTiles.keys where !uidSet.contains(uid) {
                remoteTiles[uid]?.removeFromSuperview()
                remoteTiles.removeValue(forKey: uid)
                structureChanged = true
            }
            for uid in uids where remoteTiles[uid] == nil {
                let tile = AgoraCallVideoTileView()
                remoteTiles[uid] = tile
                remoteGridContainer.addSubview(tile)
                structureChanged = true
            }
            for (uid, tile) in remoteTiles {
                let profile = service.profile(forRemoteUid: uid)
                tile.configure(
                    name: profile.name,
                    avatarURL: profile.avatarURL,
                    hasVideo: service.hasRemoteVideo(uid: uid)
                )
                tile.setMuted(service.isRemoteMuted(uid: uid))
            }
            if structureChanged {
                layoutRemoteGrid()
            }
        }

        let showRemote = service.hasRemoteVideo || showGrid
        remoteGridContainer.isHidden = !showGrid
        remoteVideoView.isHidden = showGrid || !service.hasRemoteVideo
        avatarImageView.isHidden = showRemote
        // Labels clutter the mini grid — hide when video tiles are visible.
        nameLabel.isHidden = showGrid
        statusLabel.isHidden = showGrid

        let showLocalPip = isVideo
        let showLocalCamera = showLocalPip && service.videoEnabled
        localPipContainer.isHidden = !showLocalPip
        localVideoView.isHidden = !showLocalCamera
        localPipAvatarView.isHidden = showLocalCamera || !showLocalPip
        if !localPipAvatarView.isHidden {
            updateLocalPipAvatar(from: service)
        }
        localMuteBadge.isHidden = !showLocalPip || !service.muted

        // Same visibility as full-screen call Flip control.
        let showFlip = showLocalCamera
            && !service.isScreenSharing
            && !service.isCameraUnavailable
        flipCameraButton.isHidden = !showFlip

        bringSubviewToFront(localPipContainer)
        bringSubviewToFront(localMuteBadge)
        bringSubviewToFront(expandButton)
        bringSubviewToFront(trailingControlsStack)
        if !nameLabel.isHidden {
            bringSubviewToFront(nameLabel)
            bringSubviewToFront(statusLabel)
        }
    }

    /// Timer tick — status text only (no remote grid re-layout).
    func updateElapsedDisplay() {
        guard let service else { return }
        if service.isScreenSharing {
            statusLabel.text = formatElapsed(service.elapsedSec)
            return
        }
        applyElapsedStatusText(service: service, isGroup: service.isGroupCall)
    }

    private func applyElapsedStatusText(service: AgoraCallService, isGroup: Bool) {
        if let banner = service.activeCallBannerText, !banner.isEmpty {
            statusLabel.text = banner
            statusLabel.textColor = ChatTheme.warning
        } else if service.peerNetworkState == .weak {
            statusLabel.text = "Poor connection"
            statusLabel.textColor = ChatTheme.warning
        } else if service.peerNetworkState == .unreachable {
            statusLabel.text = "Not in network"
            statusLabel.textColor = ChatTheme.warning
        } else if isGroup {
            if service.hasStartedCallTimer {
                let count = max(1, service.remoteParticipantUids.count + 1)
                statusLabel.text = "\(formatElapsed(service.elapsedSec)) · \(count)"
            } else {
                statusLabel.text = service.call?.type == .video ? "Group video calling…" : "Group calling…"
            }
            statusLabel.textColor = UIColor(white: 0.85, alpha: 1)
        } else {
            statusLabel.text = formatElapsed(service.elapsedSec)
            statusLabel.textColor = UIColor(white: 0.85, alpha: 1)
        }
    }

    private func updateLocalPipAvatar(from service: AgoraCallService) {
        let urlKey = service.localAvatarURL ?? ""
        guard configuredLocalPipAvatarURL != urlKey else { return }
        configuredLocalPipAvatarURL = urlKey
        if let urlString = service.localAvatarURL, !urlString.isEmpty, let url = URL(string: urlString) {
            localPipAvatarView.setChatImage(
                with: url,
                placeholderImage: UIImage(systemName: "person.circle.fill")
            )
        } else {
            localPipAvatarView.cancelChatImageLoad()
            localPipAvatarView.image = UIImage(systemName: "person.circle.fill")
        }
    }

    /// Compact WhatsApp-like “You are sharing” bubble (green badge + Sharing + timer).
    private func applyWhatsAppScreenShareStyle(elapsed: Int) {
        backgroundColor = UIColor(red: 0.07, green: 0.12, blue: 0.10, alpha: 0.98)
        layer.borderColor = Self.whatsAppGreen.withAlphaComponent(0.55).cgColor

        remoteVideoView.isHidden = true
        remoteGridContainer.isHidden = true
        localPipContainer.isHidden = true
        localVideoView.isHidden = true
        localPipAvatarView.isHidden = true
        localMuteBadge.isHidden = true
        flipCameraButton.isHidden = true
        avatarImageView.isHidden = true
        avatarImageView.cancelChatImageLoad()
        avatarImageView.image = nil

        screenShareBadgeView.isHidden = false
        nameLabel.isHidden = false
        statusLabel.isHidden = false
        nameLabel.text = "Sharing"
        nameLabel.textAlignment = .natural
        nameLabel.font = UIFont.chat(.semibold, size: 13)
        nameLabel.textColor = .white
        statusLabel.text = formatElapsed(elapsed)
        statusLabel.textAlignment = .natural
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = Self.whatsAppGreen

        bringSubviewToFront(screenShareBadgeView)
        bringSubviewToFront(nameLabel)
        bringSubviewToFront(statusLabel)
        bringSubviewToFront(expandButton)
        bringSubviewToFront(trailingControlsStack)
    }

    private func setup() {
        backgroundColor = UIColor(white: 0.1, alpha: 0.96)
        layer.cornerRadius = 14
        clipsToBounds = true
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor

        remoteVideoView.backgroundColor = .black
        remoteVideoView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(remoteVideoView)

        remoteGridContainer.backgroundColor = .black
        remoteGridContainer.isHidden = true
        remoteGridContainer.translatesAutoresizingMaskIntoConstraints = false
        remoteGridContainer.clipsToBounds = true
        addSubview(remoteGridContainer)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.tintColor = .white
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarImageView)

        screenShareBadgeView.backgroundColor = Self.whatsAppGreen
        screenShareBadgeView.layer.cornerRadius = 28
        screenShareBadgeView.clipsToBounds = true
        screenShareBadgeView.isHidden = true
        screenShareBadgeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(screenShareBadgeView)

        let shareConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        screenShareIconView.image = UIImage(systemName: "rectangle.inset.filled", withConfiguration: shareConfig)
            ?? UIImage(systemName: "rectangle.on.rectangle", withConfiguration: shareConfig)
        screenShareIconView.tintColor = .white
        screenShareIconView.contentMode = .scaleAspectFit
        screenShareIconView.translatesAutoresizingMaskIntoConstraints = false
        screenShareBadgeView.addSubview(screenShareIconView)

        localPipContainer.backgroundColor = UIColor(white: 0.2, alpha: 1)
        localPipContainer.layer.cornerRadius = 6
        localPipContainer.clipsToBounds = true
        localPipContainer.layer.borderWidth = 1
        localPipContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        localPipContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(localPipContainer)

        localVideoView.backgroundColor = .clear
        localVideoView.translatesAutoresizingMaskIntoConstraints = false
        localPipContainer.addSubview(localVideoView)

        localPipAvatarView.contentMode = .scaleAspectFill
        localPipAvatarView.clipsToBounds = true
        localPipAvatarView.backgroundColor = UIColor(white: 0.28, alpha: 1)
        localPipAvatarView.tintColor = .white
        localPipAvatarView.image = UIImage(systemName: "person.circle.fill")
        localPipAvatarView.isHidden = true
        localPipAvatarView.layer.cornerRadius = 14
        localPipAvatarView.translatesAutoresizingMaskIntoConstraints = false
        localPipContainer.addSubview(localPipAvatarView)

        localMuteBadge.image = UIImage(systemName: "mic.slash.fill")
        localMuteBadge.tintColor = .white
        localMuteBadge.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        localMuteBadge.contentMode = .center
        localMuteBadge.layer.cornerRadius = 8
        localMuteBadge.clipsToBounds = true
        localMuteBadge.isHidden = true
        localMuteBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(localMuteBadge)

        nameLabel.font = UIFont.chat(.semibold, size: 13)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = UIColor(white: 0.85, alpha: 1)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        let expandConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        expandButton.setImage(
            UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: expandConfig),
            for: .normal
        )
        expandButton.tintColor = .white
        expandButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        expandButton.layer.cornerRadius = 22
        expandButton.translatesAutoresizingMaskIntoConstraints = false
        expandButton.alpha = 0
        expandButton.isHidden = true
        expandButton.isUserInteractionEnabled = false
        expandButton.accessibilityLabel = "Maximize call"
        expandButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        addSubview(expandButton)

        hangUpButton.setImage(UIImage(systemName: "phone.down.fill"), for: .normal)
        hangUpButton.tintColor = .white
        hangUpButton.backgroundColor = .systemRed
        hangUpButton.layer.cornerRadius = 14
        hangUpButton.translatesAutoresizingMaskIntoConstraints = false
        hangUpButton.accessibilityLabel = "Hang up"
        hangUpButton.addTarget(self, action: #selector(hangUpTapped), for: .touchUpInside)

        let flipConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        flipCameraButton.setImage(
            UIImage(systemName: "camera.rotate.fill", withConfiguration: flipConfig),
            for: .normal
        )
        flipCameraButton.tintColor = .white
        flipCameraButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        flipCameraButton.layer.cornerRadius = 14
        flipCameraButton.translatesAutoresizingMaskIntoConstraints = false
        flipCameraButton.isHidden = true
        flipCameraButton.accessibilityLabel = "Flip camera"
        flipCameraButton.addTarget(self, action: #selector(flipCameraTapped), for: .touchUpInside)

        trailingControlsStack.axis = .horizontal
        trailingControlsStack.alignment = .center
        trailingControlsStack.spacing = 6
        trailingControlsStack.translatesAutoresizingMaskIntoConstraints = false
        trailingControlsStack.addArrangedSubview(flipCameraButton)
        trailingControlsStack.addArrangedSubview(hangUpButton)
        addSubview(trailingControlsStack)

        NSLayoutConstraint.activate([
            remoteVideoView.topAnchor.constraint(equalTo: topAnchor),
            remoteVideoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            remoteVideoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            remoteVideoView.bottomAnchor.constraint(equalTo: bottomAnchor),

            remoteGridContainer.topAnchor.constraint(equalTo: topAnchor),
            remoteGridContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            remoteGridContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            remoteGridContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            avatarImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            avatarImageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),
            avatarImageView.widthAnchor.constraint(equalToConstant: 56),
            avatarImageView.heightAnchor.constraint(equalToConstant: 56),

            screenShareBadgeView.centerXAnchor.constraint(equalTo: centerXAnchor),
            screenShareBadgeView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18),
            screenShareBadgeView.widthAnchor.constraint(equalToConstant: 56),
            screenShareBadgeView.heightAnchor.constraint(equalToConstant: 56),

            screenShareIconView.centerXAnchor.constraint(equalTo: screenShareBadgeView.centerXAnchor),
            screenShareIconView.centerYAnchor.constraint(equalTo: screenShareBadgeView.centerYAnchor),
            screenShareIconView.widthAnchor.constraint(equalToConstant: 26),
            screenShareIconView.heightAnchor.constraint(equalToConstant: 26),

            // WhatsApp self-view: small inset bottom-trailing over the remote grid.
            localPipContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            localPipContainer.bottomAnchor.constraint(equalTo: trailingControlsStack.topAnchor, constant: -8),
            localPipContainer.widthAnchor.constraint(equalToConstant: 48),
            localPipContainer.heightAnchor.constraint(equalToConstant: 68),

            localVideoView.topAnchor.constraint(equalTo: localPipContainer.topAnchor),
            localVideoView.leadingAnchor.constraint(equalTo: localPipContainer.leadingAnchor),
            localVideoView.trailingAnchor.constraint(equalTo: localPipContainer.trailingAnchor),
            localVideoView.bottomAnchor.constraint(equalTo: localPipContainer.bottomAnchor),

            // WhatsApp: small centered circular avatar (not full-bleed) when camera is off.
            localPipAvatarView.centerXAnchor.constraint(equalTo: localPipContainer.centerXAnchor),
            localPipAvatarView.centerYAnchor.constraint(equalTo: localPipContainer.centerYAnchor),
            localPipAvatarView.widthAnchor.constraint(equalToConstant: 28),
            localPipAvatarView.heightAnchor.constraint(equalToConstant: 28),

            localMuteBadge.topAnchor.constraint(equalTo: localPipContainer.topAnchor, constant: 4),
            localMuteBadge.leadingAnchor.constraint(equalTo: localPipContainer.leadingAnchor, constant: 4),
            localMuteBadge.widthAnchor.constraint(equalToConstant: 16),
            localMuteBadge.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            nameLabel.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -2),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingControlsStack.leadingAnchor, constant: -8),

            statusLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingControlsStack.leadingAnchor, constant: -8),

            flipCameraButton.widthAnchor.constraint(equalToConstant: 28),
            flipCameraButton.heightAnchor.constraint(equalToConstant: 28),
            hangUpButton.widthAnchor.constraint(equalToConstant: 28),
            hangUpButton.heightAnchor.constraint(equalToConstant: 28),

            trailingControlsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            trailingControlsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            // Center maximize — shown on PiP tap, auto-hides after idle.
            expandButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            expandButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            expandButton.widthAnchor.constraint(equalToConstant: 44),
            expandButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(pipBodyTapped))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        avatarImageView.layer.cornerRadius = avatarImageView.bounds.width / 2
        if usesRemoteGrid {
            layoutRemoteGrid()
        }
    }

    private func layoutRemoteGrid() {
        let tiles = remoteTiles.sorted { $0.key < $1.key }.map(\.value)
        guard !tiles.isEmpty else { return }
        remoteGridContainer.layoutIfNeeded()
        let bounds = remoteGridContainer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let frames = Self.pipGridFrames(count: tiles.count, in: bounds, spacing: 6)
        for (tile, frame) in zip(tiles, frames) {
            tile.translatesAutoresizingMaskIntoConstraints = true
            tile.frame = frame
        }
    }

    /// Same recipes as full-screen grid (remotes only in PiP mini window).
    private static func pipGridFrames(count: Int, in bounds: CGRect, spacing: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let rowCounts: [Int]
        switch count {
        case 1: rowCounts = [1]
        case 2: rowCounts = [1, 1]
        case 3: rowCounts = [2, 1]
        case 4: rowCounts = [2, 2]
        case 5: rowCounts = [2, 2, 1]
        case 6: rowCounts = [2, 2, 2]
        case 7: rowCounts = [3, 2, 2]
        case 8: rowCounts = [3, 2, 3]
        case 9: rowCounts = [3, 3, 3]
        default:
            var rows: [Int] = []
            var left = count
            while left > 0 {
                let n = min(3, left)
                rows.append(n)
                left -= n
            }
            rowCounts = rows
        }

        let rows = rowCounts.count
        let tileH = (bounds.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        var frames: [CGRect] = []
        frames.reserveCapacity(count)
        for (row, itemsInRow) in rowCounts.enumerated() {
            let rowTileW = (bounds.width - spacing * CGFloat(itemsInRow - 1)) / CGFloat(itemsInRow)
            let y = CGFloat(row) * (tileH + spacing)
            for col in 0..<itemsInRow {
                let x = CGFloat(col) * (rowTileW + spacing)
                frames.append(CGRect(x: x, y: y, width: rowTileW, height: tileH))
            }
        }
        return frames
    }

    /// Hide PiP chrome while the overlay is mid shrink/expand (looks like full call UI).
    func setChromeHiddenForTransition(_ hidden: Bool) {
        if hidden {
            cancelMaximizeAutoHide()
            expandButton.alpha = 0
            expandButton.isHidden = true
            expandButton.isUserInteractionEnabled = false
            isMaximizeVisible = false
        }
        hangUpButton.alpha = hidden ? 0 : 1
        flipCameraButton.alpha = hidden ? 0 : 1
        localMuteBadge.alpha = hidden ? 0 : 1
        nameLabel.alpha = hidden ? 0 : 1
        statusLabel.alpha = hidden ? 0 : 1
        layer.borderWidth = hidden ? 0 : 1
    }

    private func formatElapsed(_ sec: Int) -> String {
        String(format: "%02d:%02d", sec / 60, sec % 60)
    }

    @objc private func pipBodyTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        // Let hang-up / flip / maximize handle their own taps.
        if trailingControlsStack.alpha > 0.01, trailingControlsStack.frame.contains(point) {
            return
        }
        if isMaximizeVisible, expandButton.frame.contains(point) {
            return
        }
        showMaximizeControl()
    }

    @objc private func expandTapped() {
        cancelMaximizeAutoHide()
        service?.exitPictureInPicture()
    }

    @objc private func hangUpTapped() {
        notePipUserAction()
        service?.hangUp()
    }

    @objc private func flipCameraTapped() {
        notePipUserAction()
        service?.flipCamera()
    }

    /// Show center maximize; restart 3s auto-hide.
    private func showMaximizeControl() {
        cancelMaximizeAutoHide()
        isMaximizeVisible = true
        expandButton.isHidden = false
        expandButton.isUserInteractionEnabled = true
        bringSubviewToFront(expandButton)
        bringSubviewToFront(trailingControlsStack)
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.expandButton.alpha = 1
        }
        scheduleMaximizeAutoHide()
    }

    private func hideMaximizeControl(animated: Bool = true) {
        cancelMaximizeAutoHide()
        isMaximizeVisible = false
        expandButton.isUserInteractionEnabled = false
        let apply: () -> Void = {
            self.expandButton.alpha = 0
        }
        let finish: () -> Void = {
            self.expandButton.isHidden = true
        }
        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseIn, .beginFromCurrentState],
                animations: apply,
                completion: { _ in finish() }
            )
        } else {
            apply()
            finish()
        }
    }

    private func scheduleMaximizeAutoHide() {
        cancelMaximizeAutoHide()
        let work = DispatchWorkItem { [weak self] in
            self?.hideMaximizeControl(animated: true)
        }
        maximizeHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maximizeAutoHideDelay, execute: work)
    }

    private func cancelMaximizeAutoHide() {
        maximizeHideWorkItem?.cancel()
        maximizeHideWorkItem = nil
    }

    /// Any interaction while maximize is up resets the 3s idle timer.
    private func notePipUserAction() {
        guard isMaximizeVisible else { return }
        scheduleMaximizeAutoHide()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        let translation = gesture.translation(in: superview)
        switch gesture.state {
        case .began:
            panStart = center
            notePipUserAction()
        case .changed:
            var next = CGPoint(x: panStart.x + translation.x, y: panStart.y + translation.y)
            let bounds = dragBounds(in: superview)
            next.x = min(max(bounds.minX, next.x), bounds.maxX)
            next.y = min(max(bounds.minY, next.y), bounds.maxY)
            center = next
        case .ended, .cancelled:
            snapToNearestCorner(in: superview)
            notePipUserAction()
        default:
            break
        }
    }

    private func dragBounds(in superview: UIView) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let inset: CGFloat = 8
        let halfW = bounds.width / 2
        let halfH = bounds.height / 2
        let bottomPad = keyboardBottomInset > 0
            ? keyboardBottomInset + 12
            : (superview.safeAreaInsets.bottom + inset)
        return (
            minX: halfW + inset,
            maxX: superview.bounds.width - halfW - inset,
            minY: halfH + inset + superview.safeAreaInsets.top,
            maxY: superview.bounds.height - halfH - bottomPad
        )
    }

    private func snapToNearestCorner(in superview: UIView) {
        let b = dragBounds(in: superview)
        let targetX = center.x < superview.bounds.midX ? b.minX : b.maxX
        let targetY = min(max(b.minY, center.y), b.maxY)
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            self.center = CGPoint(x: targetX, y: targetY)
        }
    }

    // MARK: - Keyboard (keep PiP above chat keyboard)

    private func startKeyboardObserversIfNeeded() {
        guard keyboardObservers.isEmpty else { return }
        let center = NotificationCenter.default
        keyboardObservers.append(
            center.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                Task { @MainActor in
                    self?.handleKeyboardFrameChange(note)
                }
            }
        )
        keyboardObservers.append(
            center.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                Task { @MainActor in
                    self?.handleKeyboardHide(note)
                }
            }
        )
    }

    private func handleKeyboardFrameChange(_ notification: Notification) {
        guard let superview,
              let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        let frameInView = superview.convert(endFrame, from: nil)
        // Keyboard covering the bottom of our window → lift PiP above it.
        let inset = max(0, superview.bounds.maxY - frameInView.minY)
        keyboardBottomInset = (frameInView.minY < superview.bounds.maxY - 1) ? inset : 0

        animateWithKeyboard(userInfo) {
            self.liftAboveKeyboardIfNeeded(in: superview)
        }
    }

    private func handleKeyboardHide(_ notification: Notification) {
        keyboardBottomInset = 0
        guard let superview else { return }
        animateWithKeyboard(notification.userInfo) {
            self.liftAboveKeyboardIfNeeded(in: superview)
        }
    }

    private func animateWithKeyboard(_ userInfo: [AnyHashable: Any]?, animations: @escaping () -> Void) {
        let duration = (userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRaw = (userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue
            ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)
        UIView.animate(withDuration: duration, delay: 0, options: options, animations: animations)
    }

    /// If PiP is in the lower half (or would sit under the keyboard), lift it above.
    private func liftAboveKeyboardIfNeeded(in superview: UIView) {
        let b = dragBounds(in: superview)
        var next = center
        next.x = min(max(b.minX, next.x), b.maxX)
        if keyboardBottomInset > 0 {
            // Always keep clear of the keyboard; if it was near bottom, park on the bottom-above-keyboard edge.
            if frame.maxY > (superview.bounds.height - keyboardBottomInset - 8) || center.y > superview.bounds.midY {
                next.y = b.maxY
                next.x = center.x < superview.bounds.midX ? b.minX : b.maxX
            } else {
                next.y = min(max(b.minY, next.y), b.maxY)
            }
        } else {
            next.y = min(max(b.minY, next.y), b.maxY)
        }
        center = next
    }
}

/// Full-screen window that only captures touches on the floating PiP bubble.
@MainActor
private final class AgoraCallPipPassThroughWindow: UIWindow {
    weak var passthroughTarget: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let target = passthroughTarget, !target.isHidden, target.alpha > 0.01 else {
            return nil
        }
        let pointInTarget = convert(point, to: target)
        guard target.point(inside: pointInTarget, with: event) else {
            // Outside the PiP bubble → let the app UI underneath receive the touch.
            return nil
        }
        return target.hitTest(pointInTarget, with: event)
    }
}

@MainActor
final class AgoraCallPipWindowController {

    static let shared = AgoraCallPipWindowController()

    private static let transitionDuration: TimeInterval = 0.15

    private var pipWindow: AgoraCallPipPassThroughWindow?
    private(set) var overlay: AgoraCallPipOverlay?
    /// Resting bubble frame after shrink (used as expand start).
    private var pipRestingFrame: CGRect = .zero
    /// Snapshot cover above the live overlay during canvas handoff (prevents black flash).
    private var handoffCover: UIView?
    private weak var hostView: UIView?

    var isVisible: Bool { pipWindow != nil }

    /// - Parameter startFullScreen: place overlay full-screen so caller can bind video then shrink.
    func show(service: AgoraCallService, startFullScreen: Bool = false) {
        hide()

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        guard let scene else { return }

        let overlay = AgoraCallPipOverlay(frame: .zero)
        overlay.attach(service: service)
        overlay.isUserInteractionEnabled = true
        self.overlay = overlay

        let window = AgoraCallPipPassThroughWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = true

        let host = PassThroughRootViewController()
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = true
        window.rootViewController = host
        hostView = host.view
        host.view.addSubview(overlay)

        // Slightly taller for group mini-grid so stacked remotes stay readable.
        let isGroupVideo = service.isGroupCall && service.call?.type == .video
            && service.remoteParticipantUids.count > 1
        let width: CGFloat = isGroupVideo ? 140 : 150
        let height: CGFloat = isGroupVideo ? 240 : 220
        let bounds = scene.coordinateSpace.bounds
        let pipFrame = CGRect(
            x: bounds.width - width - 12,
            y: bounds.height - height - 100,
            width: width,
            height: height
        )
        pipRestingFrame = pipFrame

        if startFullScreen {
            overlay.frame = bounds
            overlay.layer.cornerRadius = 0
            overlay.setChromeHiddenForTransition(true)
            overlay.isUserInteractionEnabled = false
        } else {
            overlay.frame = pipFrame
            overlay.layer.cornerRadius = 14
            overlay.setChromeHiddenForTransition(false)
        }

        window.passthroughTarget = overlay
        window.isHidden = false
        window.makeKeyAndVisible()
        // Return key window to the main app so text fields / navigation keep working.
        DispatchQueue.main.async {
            Self.resignPipKeyWindowIfNeeded(pipWindow: window)
        }

        pipWindow = window
    }

    /// Pin a snapshot above the live overlay so canvas rebind never shows black.
    func installHandoffCover(_ cover: UIView) {
        removeHandoffCover()
        guard let host = hostView else { return }
        // Match the expanded PiP / full window — must cover the entire alert-level window.
        let bounds = pipWindow?.bounds ?? host.bounds
        cover.frame = bounds
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.clipsToBounds = true
        cover.isUserInteractionEnabled = false
        cover.alpha = 1
        host.addSubview(cover)
        host.bringSubviewToFront(cover)
        handoffCover = cover
    }

    func removeHandoffCover() {
        handoffCover?.removeFromSuperview()
        handoffCover = nil
    }

    func snapshotOverlay() -> UIView? {
        // Prefer a fresh layout snapshot of the expanded live video.
        guard let overlay else { return nil }
        overlay.layoutIfNeeded()
        if let snap = overlay.snapshotView(afterScreenUpdates: true) {
            return snap
        }
        if let snap = overlay.snapshotView(afterScreenUpdates: false) {
            return snap
        }
        // Last resort — layer render (still better than a black maximize flash).
        let bounds = overlay.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { ctx in
            overlay.layer.render(in: ctx.cgContext)
        }
        let imageView = UIImageView(image: image)
        imageView.frame = bounds
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        return imageView
    }

    /// Maximize handoff: fade the last-good-frame cover, then tear down the PiP window
    /// so the full-screen call UI (already painted underneath) is revealed without a black flash.
    func fadeOutHandoffAndHide(completion: (() -> Void)? = nil) {
        revealFullScreenHidingCover(fadeInVideo: nil, completion: completion)
    }

    /// Crossfade: PiP snapshot cover α 1→0 while full-screen video surfaces α 0→1.
    func crossfadeRevealFullScreen(
        fadeInVideo: (() -> Void)?,
        completion: (() -> Void)? = nil
    ) {
        revealFullScreenHidingCover(fadeInVideo: fadeInVideo, completion: completion)
    }

    /// Keep thumbnail/live cover on top until video is ready behind, then hide cover + PiP.
    func revealFullScreenHidingCover(
        fadeInVideo: (() -> Void)?,
        completion: (() -> Void)? = nil
    ) {
        let cover = handoffCover
        // Prefer fading the still cover; also fade live overlay so nothing black peeks through.
        overlay?.isHidden = false
        pipWindow?.backgroundColor = .clear

        let duration: TimeInterval = 0.15

        if cover == nil {
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState]
            ) {
                self.overlay?.alpha = 0
                fadeInVideo?()
            } completion: { _ in
                self.hide()
                completion?()
            }
            return
        }

        // Only the thumbnail stays visible on the PiP window; live overlay blanked.
        overlay?.alpha = 0
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            cover?.alpha = 0
            fadeInVideo?()
        } completion: { _ in
            self.hide()
            completion?()
        }
    }

    /// Animate full-screen overlay (+ optional cover) down to the resting PiP bubble.
    func animateShrinkToPip(completion: (() -> Void)? = nil) {
        guard let overlay else {
            removeHandoffCover()
            completion?()
            return
        }
        let target = pipRestingFrame
        guard target.width > 0, target.height > 0 else {
            removeHandoffCover()
            completion?()
            return
        }
        overlay.isUserInteractionEnabled = false
        overlay.setChromeHiddenForTransition(true)
        overlay.alpha = 1
        let cover = handoffCover
        cover?.clipsToBounds = true
        cover?.alpha = cover == nil ? 0 : 1

        UIView.animate(
            withDuration: Self.transitionDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            overlay.frame = target
            overlay.layer.cornerRadius = 14
            if let cover {
                cover.frame = target
                cover.layer.cornerRadius = 14
                // Fade thumbnail away in the second half of the shrink → reveal live PiP.
                cover.alpha = 0
            }
        } completion: { _ in
            self.removeHandoffCover()
            overlay.setChromeHiddenForTransition(false)
            overlay.isUserInteractionEnabled = true
            self.pipWindow?.backgroundColor = .clear
            completion?()
        }
    }

    /// Animate PiP bubble up to full screen (video stays on overlay until completion).
    func animateExpandToFullScreen(completion: (() -> Void)? = nil) {
        guard let overlay, let window = pipWindow else {
            completion?()
            return
        }
        removeHandoffCover()
        overlay.isHidden = false
        overlay.alpha = 1
        overlay.isUserInteractionEnabled = false
        overlay.setChromeHiddenForTransition(true)
        pipRestingFrame = overlay.frame
        let fullFrame = window.bounds
        // Solid backdrop so chat UI never peeks through during expand.
        window.backgroundColor = UIColor(white: 0.08, alpha: 1)
        UIView.animate(
            withDuration: Self.transitionDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            overlay.frame = fullFrame
            overlay.layer.cornerRadius = 0
        } completion: { _ in
            overlay.layoutIfNeeded()
            completion?()
        }
    }

    private static func resignPipKeyWindowIfNeeded(pipWindow: UIWindow) {
        guard pipWindow.isKeyWindow else { return }
        mainAppWindows(excluding: pipWindow).first?.makeKey()
    }

    /// Top VC in the main app window — never the PiP host (presenting there is destroyed on hide).
    static func mainAppTopViewController() -> UIViewController? {
        let pip = shared.pipWindow
        for window in mainAppWindows(excluding: pip) {
            if let top = topViewController(from: window.rootViewController) {
                return top
            }
        }
        // Fallback: scene key window if it isn't the PiP window.
        let keyRoot = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .compactMap(\.keyWindow)
            .first { $0 !== pip }?
            .rootViewController
        return topViewController(from: keyRoot)
    }

    private static func mainAppWindows(excluding pip: UIWindow?) -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0 !== pip && !$0.isHidden && $0.windowLevel == .normal }
            .sorted { lhs, rhs in
                // Prefer the key window when both are normal.
                if lhs.isKeyWindow != rhs.isKeyWindow { return lhs.isKeyWindow }
                return false
            }
    }

    private static func topViewController(from base: UIViewController?) -> UIViewController? {
        guard let base else { return nil }
        if let nav = base as? UINavigationController {
            return topViewController(from: nav.visibleViewController) ?? base
        }
        if let tab = base as? UITabBarController {
            return topViewController(from: tab.selectedViewController) ?? base
        }
        if let presented = base.presentedViewController {
            return topViewController(from: presented)
        }
        return base
    }

    func reload() {
        overlay?.reload()
    }

    func updateElapsedDisplay() {
        overlay?.updateElapsedDisplay()
    }

    func hide() {
        overlay?.layer.removeAllAnimations()
        handoffCover?.layer.removeAllAnimations()
        removeHandoffCover()
        overlay?.stopKeyboardObservers()
        overlay?.removeFromSuperview()
        overlay = nil
        hostView = nil
        pipRestingFrame = .zero
        let window = pipWindow
        pipWindow?.passthroughTarget = nil
        pipWindow = nil
        window?.isHidden = true
        // Ensure the main app regains key after tearing down the overlay window.
        if let window {
            Self.mainAppWindows(excluding: window).first?.makeKey()
        }
    }
}

/// Root VC whose view never eats touches outside the PiP bubble.
@MainActor
private final class PassThroughRootViewController: UIViewController {
    override func loadView() {
        view = PassThroughHostView()
    }
}

@MainActor
private final class PassThroughHostView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // If the hit is this empty host view itself, pass through.
        return hit === self ? nil : hit
    }
}
