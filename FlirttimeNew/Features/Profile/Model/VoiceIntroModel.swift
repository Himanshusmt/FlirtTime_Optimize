//
//  VoiceIntroModel.swift
//  FlirttimeNew
//
//  The signed-in user's recorded voice intro (`voice_intro` on the user payload), the local
//  file store used by the mock backend, and the upload / delete calls.
//

import Foundation

struct UserVoiceIntro: Codable {
    /// Server path, or the name of a file in `VoiceIntroFileStore` while the backend is mocked.
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

struct VoiceIntroResponse: Codable {
    let status: Bool
    let message: String?
    let data: UserVoiceIntro?
}

/// Recorded voice intros kept on disk while the upload endpoint is mocked.
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

// TODO: replace with a multipart upload to the voice-intro endpoint and DELETE for removal.
enum VoiceIntroService {

    static func upload(recordingAt fileURL: URL, duration: TimeInterval, completion: @escaping (Result<UserVoiceIntro, MomentsError>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) {
            let response = MockDataStore.shared.setVoiceIntro(recordingAt: fileURL, duration: duration)
            if response.status, let intro = response.data {
                completion(.success(intro))
            } else {
                completion(.failure(MomentsError(message: response.message ?? "Unable to save your voice intro")))
            }
        }
    }

    static func delete(completion: @escaping (Result<Void, MomentsError>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + MockDataStore.responseDelay) {
            let response = MockDataStore.shared.deleteVoiceIntro()
            if response.status {
                completion(.success(()))
            } else {
                completion(.failure(MomentsError(message: response.message ?? "Unable to delete your voice intro")))
            }
        }
    }
}
