//
//  VoiceIntroModel.swift
//  FlirttimeNew
//
//  The signed-in user's recorded voice intro, a local copy for immediate playback, and the
//  upload / fetch / delete calls.
//

import Foundation
import RxSwift
import Swinject

struct UserVoiceIntro: Codable {
    /// Server URL or path, or the name of a file in `VoiceIntroFileStore`.
    let audioURL: String?
    let duration: Double?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case audioURL = "audio_url"
        case duration
        case updatedAt = "updated_at"
    }

    var playableURL: URL? {
        guard let path = audioURL, !path.isEmpty else { return nil }
        if let local = VoiceIntroFileStore.shared.url(named: path) {
            return local
        }
        return URL(string: path.hasPrefix("http") ? path : ApiName.imgBaseURL + path)
    }

    /// The shape `VoiceIntroPlayer` plays; `nil` when there is no audio file.
    var playerIntro: MomentsVoiceIntro? {
        guard let url = playableURL else { return nil }
        return MomentsVoiceIntro(transcript: "", duration: duration ?? 0, audioURL: url)
    }
}

extension UserVoiceIntro {
    /// Reads a voice-prompt response body (`data`, or `data.audio` / `data.voiceIntro` / `data.voicePrompt`).
    /// `nil` when no audio URL is present.
    init?(json: [String: Any]) {
        let data = json["data"] as? [String: Any] ?? json
        let candidates = ["audio", "voiceIntro", "voicePrompt", "voice_intro"].compactMap { data[$0] as? [String: Any] } + [data]
        let urlKeys = ["playbackUrl", "voicePromptUrl", "audioUrl", "url", "fileUrl", "audio_url"]
        for source in candidates {
            guard let url = urlKeys.lazy.compactMap({ source[$0] as? String }).first(where: { !$0.isEmpty }) else { continue }
            let rawDuration = source["durationSeconds"] ?? source["duration"]
            let duration = (rawDuration as? NSNumber)?.doubleValue ?? (rawDuration as? String).flatMap(Double.init)
            self.init(audioURL: url, duration: duration,
                      updatedAt: source["updatedAt"] as? String ?? source["createdAt"] as? String)
            return
        }
        return nil
    }
}

struct VoiceIntroResponse: Codable {
    let status: Bool
    let message: String?
    let data: UserVoiceIntro?
}

/// Recorded voice intros kept on disk when the upload response has no URL to play yet.
final class VoiceIntroFileStore {

    static let shared = VoiceIntroFileStore()
    private static let prefix = "voice_"

    private let directory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("VoiceIntros", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Copies a finished recording into the store and returns its file name.
    func save(recordingAt source: URL) -> String? {
        let name = "\(Self.prefix)\(UUID().uuidString).m4a"
        do {
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    func url(named name: String) -> URL? {
        guard name.hasPrefix(Self.prefix) else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func remove(named name: String?) {
        guard let name, name.hasPrefix(Self.prefix) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    func removeAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

/// POST / GET / DELETE `onboarding/audio`.
enum VoiceIntroService {

    private static var sessionManager: AppSessionManager { Container.appContainer.resolve(AppSessionManager.self)! }
    private static let disposeBag = DisposeBag()

    static func upload(recordingAt fileURL: URL, duration: TimeInterval, completion: @escaping (Result<UserVoiceIntro, MomentsError>) -> Void) {
        let seconds = max(Int(duration.rounded()), 1)
        Single<Data>.create { single in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    single(.success(try Data(contentsOf: fileURL)))
                } catch {
                    single(.failure(APIError.apiError("Couldn't read your recording.")))
                }
            }
            return Disposables.create()
        }
        .flatMap { sessionManager.uploadVoiceIntro(audio: $0, duration: seconds) }
        .observe(on: MainScheduler.instance)
        .subscribe(onSuccess: { intro in
            if let intro {
                completion(.success(intro))
            } else if let name = VoiceIntroFileStore.shared.save(recordingAt: fileURL) {
                // The recorder deletes its temp file after saving, so keep a copy to play until the next profile load.
                completion(.success(UserVoiceIntro(audioURL: name, duration: Double(seconds), updatedAt: nil)))
            } else {
                completion(.failure(MomentsError(message: "Unable to save your voice intro")))
            }
        }, onFailure: { error in
            completion(.failure(MomentsError(message: parseError(error) ?? "Unable to save your voice intro")))
        })
        .disposed(by: disposeBag)
    }

    /// `nil` when the user hasn't recorded one (including a 404).
    static func fetch(completion: @escaping (Result<UserVoiceIntro?, MomentsError>) -> Void) {
        sessionManager.voiceIntro()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { completion(.success($0)) }, onFailure: { error in
                if (error as? APIHTTPError)?.statusCode == 404 {
                    completion(.success(nil))
                } else {
                    completion(.failure(MomentsError(message: parseError(error) ?? "Unable to load your voice intro")))
                }
            })
            .disposed(by: disposeBag)
    }

    static func delete(completion: @escaping (Result<Void, MomentsError>) -> Void) {
        sessionManager.deleteVoiceIntro()
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: {
                VoiceIntroFileStore.shared.removeAll()
                completion(.success(()))
            }, onFailure: { error in
                completion(.failure(MomentsError(message: parseError(error) ?? "Unable to delete your voice intro")))
            })
            .disposed(by: disposeBag)
    }
}
