import AVFoundation
import Foundation

final class AudioMetadataWriter {
    func save(
            bpm: Double? = nil,
            key: String? = nil,
            to url: URL,
            scope: TrackValueScope = .all) async throws {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = valuesToWrite(bpm: bpm, key: key, scope: scope)
        switch url.pathExtension.lowercased() {
        case "mp3":
            try ID3MetadataWriter.write(to: url, bpm: values.bpm, key: values.key)
        case "aif", "aiff", "aifc":
            try AIFFMetadataWriter.write(to: url, bpm: values.bpm, key: values.key)
        case "flac":
            try FLACMetadataWriter.write(to: url, bpm: values.bpm, key: values.key)
        case "ogg", "oga", "opus":
            try OggMetadataWriter.write(to: url, bpm: values.bpm, key: values.key)
        default:
            try await AVFoundationMetadataWriter.write(to: url, bpm: values.bpm, key: values.key)
        }
    }

    private func valuesToWrite(
            bpm: Double?,
            key: String?,
            scope: TrackValueScope) -> (bpm: Double?, key: String?) {
        switch scope {
        case .all:
            (bpm, key)
        case .bpm:
            (bpm, nil)
        case .key:
            (nil, key)
        }
    }
}
