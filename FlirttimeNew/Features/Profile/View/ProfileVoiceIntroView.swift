//
//  ProfileVoiceIntroView.swift
//  FlirttimeNew
//
//  The signed-in user's voice intro card. With a recording it's a player (play, waveform,
//  time); without one it invites the user to record. `.editor` adds Re-record / Delete.
//

import UIKit
import AVFoundation

final class ProfileVoiceIntroView: UIView {

    enum Style {
        case profile
        case editor
    }

    /// `VoiceIntroPlayer` keys playback by profile ID; Discover IDs are positive.
    private static let playerID = -1

    var onRecord: (() -> Void)?
    var onDelete: (() -> Void)?

    private let style: Style
    private var intro: UserVoiceIntro?
    /// Length read from the audio file; preferred over the API's `duration`, which can be wrong.
    private var fileDuration: Double?
    private var durationTask: Task<Void, Never>?

    private let stack = UIStackView()
    private let playerCard = UIView()
    private let playButton = UIButton(type: .custom)
    private let waveHolder = UIView()
    private var waveform: VoiceWaveformView?
    private let timeLabel = UILabel.vibeLabel(.medium, 13, style: .caption1, color: AppColor.DoveGray)
    private let editButton = UIButton(type: .system)
    private let actionsRow = UIStackView()
    private lazy var emptyCard = makeEmptyCard()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.spacing = 10
        addSubview(stack)
        stack.pinEdges(to: self)

        stack.addArrangedSubview(makePlayerCard())
        if style == .editor {
            stack.addArrangedSubview(makeActionsRow())
        }
        stack.addArrangedSubview(emptyCard)
        configure(intro: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(playerChanged), name: VoiceIntroPlayer.stateDidChange, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(intro: UserVoiceIntro?) {
        let playable = intro?.playerIntro != nil
        if waveform == nil || intro?.audioURL != self.intro?.audioURL {
            stopIfPlaying()
            let seed = (intro?.audioURL ?? "").unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
            rebuildWaveform(seed: seed)
            loadFileDuration(from: playable ? intro?.playableURL : nil)
        }
        self.intro = playable ? intro : nil
        playerCard.isHidden = !playable
        actionsRow.isHidden = !playable
        emptyCard.isHidden = playable
        playerChanged()
    }

    func stopIfPlaying() {
        if VoiceIntroPlayer.shared.playingProfileID == Self.playerID {
            VoiceIntroPlayer.shared.stop()
        }
    }

    private func loadFileDuration(from url: URL?) {
        durationTask?.cancel()
        fileDuration = nil
        guard let url else { return }
        durationTask = Task { [weak self] in
            guard let time = try? await AVURLAsset(url: url).load(.duration), time.seconds.isFinite, time.seconds > 0,
                  !Task.isCancelled else { return }
            await MainActor.run {
                self?.fileDuration = time.seconds
                self?.playerChanged()
            }
        }
    }

    // MARK: - Player

    private func makePlayerCard() -> UIView {
        playerCard.backgroundColor = AppColor.Lavenderblush
        playerCard.layer.cornerRadius = 30
        playerCard.layer.cornerCurve = .continuous

        playButton.backgroundColor = AppColor.Punch
        playButton.tintColor = .white
        playButton.layer.cornerRadius = 22
        playButton.addAction(UIAction { [weak self] _ in self?.togglePlayback() }, for: .touchUpInside)

        timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        var row = [playButton, waveHolder, timeLabel]
        if style == .profile {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: "pencil", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))
            config.baseForegroundColor = AppColor.Punch
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
            editButton.configuration = config
            editButton.accessibilityLabel = "Record a new voice intro"
            editButton.setContentHuggingPriority(.required, for: .horizontal)
            editButton.addAction(UIAction { [weak self] _ in self?.onRecord?() }, for: .touchUpInside)
            row.append(editButton)
        }
        let rowStack = UIStackView(arrangedSubviews: row)
        rowStack.spacing = 12
        rowStack.alignment = .center
        playerCard.addSubview(rowStack)
        rowStack.pinEdges(to: playerCard, insets: UIEdgeInsets(top: 8, left: 8, bottom: 8, right: style == .profile ? 8 : 18))
        NSLayoutConstraint.activate([
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),
            waveHolder.heightAnchor.constraint(equalToConstant: 30)
        ])
        return playerCard
    }

    private func rebuildWaveform(seed: Int) {
        waveform?.removeFromSuperview()
        let wave = VoiceWaveformView(seed: seed, barCount: 26)
        wave.activeColor = AppColor.Punch
        wave.inactiveColor = AppColor.Punch.withAlphaComponent(0.3)
        waveHolder.addSubview(wave)
        wave.pinEdges(to: waveHolder)
        waveform = wave
    }

    private func togglePlayback() {
        guard let playerIntro = intro?.playerIntro else { return }
        VoiceIntroPlayer.shared.toggle(playerIntro, profileID: Self.playerID)
    }

    @objc private func playerChanged() {
        let player = VoiceIntroPlayer.shared
        let isPlaying = player.playingProfileID == Self.playerID
        let duration = fileDuration ?? intro?.duration ?? 0
        playButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)), for: .normal)
        playButton.accessibilityLabel = isPlaying ? "Pause your voice intro" : "Play your voice intro, \(Int(duration.rounded())) seconds"
        waveform?.setProgress(isPlaying ? player.progress : 0)
        let remaining = isPlaying ? duration * (1 - player.progress) : duration
        timeLabel.text = VoiceIntroRecorderViewController.format(remaining.rounded(.up))
    }

    // MARK: - Editor actions

    private func makeActionsRow() -> UIView {
        let redo = actionButton(title: "Re-record", symbol: "mic.fill", tint: AppColor.Punch, background: AppColor.Lavenderblush)
        redo.addAction(UIAction { [weak self] _ in
            self?.stopIfPlaying()
            self?.onRecord?()
        }, for: .touchUpInside)
        let delete = actionButton(title: "Delete", symbol: "trash", tint: AppColor.MineShaft, background: AppColor.AthensGray)
        delete.addAction(UIAction { [weak self] _ in
            self?.stopIfPlaying()
            self?.onDelete?()
        }, for: .touchUpInside)
        actionsRow.addArrangedSubview(redo)
        actionsRow.addArrangedSubview(delete)
        actionsRow.spacing = 10
        actionsRow.distribution = .fillEqually
        return actionsRow
    }

    private func actionButton(title: String, symbol: String, tint: UIColor, background: UIColor) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = background
        config.baseForegroundColor = tint
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12)
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: MomentsFont.scaled(.medium, 14, style: .subheadline)]))
        return UIButton(configuration: config)
    }

    // MARK: - Empty state

    private func makeEmptyCard() -> UIView {
        let card = UIControl()
        card.backgroundColor = AppColor.Lavenderblush
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColor.Punch.withAlphaComponent(0.25).cgColor
        card.addAction(UIAction { [weak self] _ in self?.onRecord?() }, for: .touchUpInside)

        let mic = UIImageView(image: UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)))
        mic.tintColor = .white
        mic.contentMode = .center
        mic.backgroundColor = AppColor.Punch
        mic.layer.cornerRadius = 22

        let title = UILabel.vibeLabel(.bold, 16, style: .headline, color: AppColor.AppBlack)
        title.text = "Record your voice intro"
        let subtitle = UILabel.vibeLabel(.regular, 13, style: .footnote, color: AppColor.DoveGray, lines: 0)
        subtitle.text = "Let matches hear your vibe. Up to \(Int(VoiceIntroRecorder.maxDuration)) seconds."
        let texts = UIStackView(arrangedSubviews: [title, subtitle])
        texts.axis = .vertical
        texts.spacing = 2

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
        chevron.tintColor = AppColor.Punch
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [mic, texts, chevron])
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        card.addSubview(row)
        row.pinEdges(to: card, insets: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 16))
        NSLayoutConstraint.activate([
            mic.widthAnchor.constraint(equalToConstant: 44),
            mic.heightAnchor.constraint(equalToConstant: 44)
        ])

        card.isAccessibilityElement = true
        card.accessibilityTraits = .button
        card.accessibilityLabel = "Record your voice intro"
        card.accessibilityHint = subtitle.text
        return card
    }
}
