//
//  VideoCompressor.swift
//  FlirttimeNew
//

import Foundation
import AVFoundation

struct CompressionResult {
    let url: URL
    let fileSize: Int64
    let isCompressedCopy: Bool
}

private actor CompressionSemaphore {
    private let maxConcurrent: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) { self.maxConcurrent = maxConcurrent }

    func acquire() async {
        if running < maxConcurrent {
            running += 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            running -= 1
        }
    }
}

final class VideoCompressor: Sendable {

    static let shared = VideoCompressor()
    private let semaphore = CompressionSemaphore(maxConcurrent: 2)
    private init() {}

    // MARK: - Public API

    func compress(_ sourceURL: URL, cropAspect: CGFloat? = nil) async throws -> CompressionResult {

        await semaphore.acquire()
        defer { Task { await semaphore.release() } }

        let originalSize = fileSizeBytes(at: sourceURL)
        if originalSize > 0 && originalSize < 5_000_000 && cropAspect == nil {
            return CompressionResult(url: sourceURL, fileSize: originalSize, isCompressedCopy: false)
        }

        let asset = AVAsset(url: sourceURL)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else { throw CompressionError.failed }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw CompressionError.noVideoTrack }

        let naturalSize       = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let audioTracks       = try await asset.loadTracks(withMediaType: .audio)

        let useCrop: Bool = {
            guard let aspect = cropAspect, aspect > 0 else { return false }
            let transformed = naturalSize.applying(preferredTransform)
            let displayW = abs(transformed.width)
            let displayH = abs(transformed.height)
            guard displayW > 0, displayH > 0 else { return false }
            return true
        }()

        let outputSize: CGSize
        let renderSize: CGSize
        let cropTransform: CGAffineTransform?

        if useCrop, let aspect = cropAspect {
            let transformed = naturalSize.applying(preferredTransform)
            let displaySize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
            let videoAspect = displaySize.width / displaySize.height

            let cropTarget: CGSize
            if videoAspect > aspect {
                cropTarget = CGSize(width: displaySize.height * aspect, height: displaySize.height)
            } else {
                cropTarget = CGSize(width: displaySize.width, height: displaySize.width / aspect)
            }

            outputSize = scaledSize(source: cropTarget, maxSize: CGSize(width: 1280, height: 1280))
            renderSize = outputSize

            let scale = outputSize.width / cropTarget.width
            let offsetX = (displaySize.width - cropTarget.width) / 2
            let offsetY = (displaySize.height - cropTarget.height) / 2
            cropTransform = preferredTransform
                .concatenating(CGAffineTransform(translationX: -offsetX, y: -offsetY))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        } else {
            outputSize = scaledSize(source: naturalSize, maxSize: CGSize(width: 1280, height: 1280))
            renderSize = outputSize
            cropTransform = nil
        }

        let bitrate    = targetBitrate(for: duration)
        let outputURL  = tempOutputURL()

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoOut: AVAssetReaderOutput
        if let cropTransform = cropTransform {
            let composition = AVMutableVideoComposition()
            composition.renderSize = renderSize
            composition.frameDuration = CMTime(value: 1, timescale: 30)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInstruction.setTransform(cropTransform, at: .zero)

            instruction.layerInstructions = [layerInstruction]
            composition.instructions = [instruction]

            let compositionOut = AVAssetReaderVideoCompositionOutput(
                videoTracks: [videoTrack],
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            )
            compositionOut.videoComposition = composition
            compositionOut.alwaysCopiesSampleData = false
            reader.add(compositionOut)
            videoOut = compositionOut
        } else {
            let plainOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ])
            plainOut.alwaysCopiesSampleData = false
            reader.add(plainOut)
            videoOut = plainOut
        }

        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        videoIn.expectsMediaDataInRealTime = false
        if cropTransform == nil {
            videoIn.transform = preferredTransform
        }
        writer.add(videoIn)

        var audioOut: AVAssetReaderTrackOutput?
        var audioIn: AVAssetWriterInput?
        if let audioTrack = audioTracks.first {
            let out = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ])
            out.alwaysCopiesSampleData = false
            reader.add(out)
            audioOut = out

            let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ])
            aIn.expectsMediaDataInRealTime = false
            writer.add(aIn)
            audioIn = aIn
        }

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        do {
            async let videoDrain: Void = VideoCompressor.drainTrack(output: videoOut, input: videoIn)
            if let aOut = audioOut, let aIn = audioIn {
                async let audioDrain: Void = VideoCompressor.drainTrack(output: aOut, input: aIn)
                _ = try await (videoDrain, audioDrain)
            } else {
                try await videoDrain
            }
        } catch {
            reader.cancelReading()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }

        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw writer.error ?? CompressionError.failed
        }

        let compressedSize = fileSizeBytes(at: outputURL)

        if originalSize > 0 && compressedSize >= originalSize {
            try? FileManager.default.removeItem(at: outputURL)
            return CompressionResult(url: sourceURL, fileSize: originalSize, isCompressedCopy: false)
        }

        let finalURL = moveToStableTemp(outputURL)
        return CompressionResult(url: finalURL, fileSize: compressedSize, isCompressedCopy: true)
    }

    // MARK: - Track drainer

    private static func drainTrack(
        output: AVAssetReaderOutput,
        input: AVAssetWriterInput
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in

        let queue = DispatchQueue(label: "com.onevibe.compressor.drain", qos: .utility)
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    input.append(sample)
                }
            }
        }
    }

    // MARK: - Helpers

    private func targetBitrate(for duration: TimeInterval) -> Int {
        switch duration {
        case 0..<30:    return 2_500_000
        case 30..<120:  return 2_000_000
        case 120..<300: return 1_500_000
        default:        return 1_000_000
        }
    }

    private func scaledSize(source: CGSize, maxSize: CGSize) -> CGSize {
        guard source.width > maxSize.width || source.height > maxSize.height else { return source }
        let ratio = min(maxSize.width / source.width, maxSize.height / source.height)
        return CGSize(width: round(source.width * ratio), height: round(source.height * ratio))
    }

    private func tempOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("compressed_\(UUID().uuidString).mp4")
    }

    private func fileSizeBytes(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private func moveToStableTemp(_ url: URL) -> URL {
        let stable = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload_\(UUID().uuidString).mp4")
        try? FileManager.default.moveItem(at: url, to: stable)
        return stable
    }

    // MARK: - Errors

    enum CompressionError: LocalizedError {
        case failed
        case noVideoTrack
        var errorDescription: String? {
            switch self {
            case .failed:       return "Video compression failed"
            case .noVideoTrack: return "No video track found"
            }
        }
    }
}
