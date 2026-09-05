import AVFoundation
import Foundation

final class AudioMetadataWriter {
    // ponytail: sync writers block for seconds, so they run on a dedicated
    // queue off the cooperative pool (like TrackAnalysisService). Counts come
    // from the user setting; tag rewrites are disk-bound, so Fast caps at 4.
    static var maxConcurrentWrites: Int {
        MetadataWriteConcurrency.current.maxConcurrentWrites
    }

    private static let writeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.jgeek00.BPM-Calculator.metadata-write"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = maxConcurrentWrites
        return queue
    }()

    static func runBlocking(_ work: @Sendable @escaping () throws -> Void) async throws {
        // ponytail: re-read here so a prefs change applies without relaunch.
        writeQueue.maxConcurrentOperationCount = maxConcurrentWrites
        try await withCheckedThrowingContinuation { continuation in
            writeQueue.addOperation {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func save(
            bpm: Double? = nil,
            key: String? = nil,
            replayGain: ReplayGainTagRequest? = nil,
            to url: URL,
            scope: TrackValueScope = .all,
            onProgress: @Sendable @escaping (Double) -> Void = { _ in }) async throws {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = valuesToWrite(bpm: bpm, key: key, replayGain: replayGain, scope: scope)
        switch url.pathExtension.lowercased() {
        case "mp3":
            try await Self.runBlocking {
                try ID3MetadataWriter.write(
                    to: url, bpm: values.bpm, key: values.key, replayGain: values.replayGain,
                    onProgress: onProgress)
            }
        case "aif", "aiff", "aifc":
            try await Self.runBlocking {
                try AIFFMetadataWriter.write(
                    to: url, bpm: values.bpm, key: values.key, replayGain: values.replayGain,
                    onProgress: onProgress)
            }
        case "flac":
            try await Self.runBlocking {
                try FLACMetadataWriter.write(
                    to: url, bpm: values.bpm, key: values.key, replayGain: values.replayGain,
                    onProgress: onProgress)
            }
        case "wav":
            try await Self.runBlocking {
                try WAVMetadataWriter.write(
                    to: url, bpm: values.bpm, key: values.key, replayGain: values.replayGain,
                    onProgress: onProgress)
            }
        case "ogg", "oga", "opus":
            try await Self.runBlocking {
                try OggMetadataWriter.write(
                    to: url, bpm: values.bpm, key: values.key, replayGain: values.replayGain,
                    onProgress: onProgress)
            }
        default:
            try await AVFoundationMetadataWriter.write(
                to: url, bpm: values.bpm, key: values.key, replayGain: values.replayGain,
                onProgress: onProgress)
        }
    }

    private func valuesToWrite(
            bpm: Double?,
            key: String?,
            replayGain: ReplayGainTagRequest?,
            scope: TrackValueScope) -> (bpm: Double?, key: String?, replayGain: ReplayGainTagRequest?) {
        switch scope {
        case .all:
            (bpm, key, replayGain)
        case .bpm:
            (bpm, nil, nil)
        case .key:
            (nil, key, nil)
        case .replayGain:
            (nil, nil, replayGain)
        }
    }
}
