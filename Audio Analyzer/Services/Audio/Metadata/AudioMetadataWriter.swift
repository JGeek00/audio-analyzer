import AVFoundation
import Foundation

final class AudioMetadataWriter {
    func save(
            bpm: Double? = nil,
            key: String? = nil,
            replayGain: ReplayGainTagRequest? = nil,
            to url: URL,
            scope: TrackValueScope = .all,
            progress: @Sendable (Double) -> Void = { _ in }) async throws {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = valuesToWrite(bpm: bpm, key: key, replayGain: replayGain, scope: scope)
        switch url.pathExtension.lowercased() {
        case "mp3":
            try ID3MetadataWriter.write(
                to: url, bpm: values.bpm, key: values.key, replayGain: values.replayGain)
        case "aif", "aiff", "aifc":
            try AIFFMetadataWriter.write(
                to: url, bpm: values.bpm, key: values.key, replayGain: values.replayGain)
        case "flac":
            try FLACMetadataWriter.write(
                to: url, bpm: values.bpm, key: values.key, replayGain: values.replayGain)
        case "ogg", "oga", "opus":
            try OggMetadataWriter.write(
                to: url, bpm: values.bpm, key: values.key, replayGain: values.replayGain,
                onProgress: progress)
        default:
            try await AVFoundationMetadataWriter.write(
                to: url, bpm: values.bpm, key: values.key, replayGain: values.replayGain)
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
