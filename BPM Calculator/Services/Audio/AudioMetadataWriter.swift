import AVFoundation
import Foundation

enum AudioMetadataWriterError: LocalizedError {
    case noDetectedBPM
    case exportSessionUnavailable
    case unsupportedFileType(String)
    case replacementFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDetectedBPM:
            return "BPM analysis has not completed for this track."
        case .exportSessionUnavailable:
            return "This audio file cannot be exported with metadata."
        case .unsupportedFileType(let fileExtension):
            return "Metadata writing is not supported for .\(fileExtension) files."
        case .replacementFailed(let message):
            return "The original file could not be replaced: \(message)"
        }
    }
}

final class AudioMetadataWriter {
    func save(title: String, artist: String?, bpm: Double, to url: URL) async throws {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: url)
        let metadata = try await asset.load(.commonMetadata)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw AudioMetadataWriterError.exportSessionUnavailable
        }

        guard let fileType = fileType(for: url, supported: exportSession.supportedFileTypes) else {
            throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
        }

        var outputMetadata = metadata
        outputMetadata.removeAll { item in
            item.identifier == .commonIdentifierTitle || item.identifier == .commonIdentifierArtist
        }
        outputMetadata.append(metadataItem(identifier: .commonIdentifierTitle, value: title))
        if let artist, !artist.isEmpty {
            outputMetadata.append(metadataItem(identifier: .commonIdentifierArtist, value: artist))
        }

        let bpmItem = AVMutableMetadataItem()
        bpmItem.identifier = fileType == .mp3
                ? .id3MetadataBeatsPerMinute
                : .iTunesMetadataBeatsPerMin
        bpmItem.value = NSNumber(value: bpm)
        outputMetadata.append(bpmItem)
        exportSession.metadata = outputMetadata

        let temporaryURL = url.deletingLastPathComponent()
                .appendingPathComponent(".bpm-\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        try await exportSession.export(to: temporaryURL, as: fileType)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } catch {
            throw AudioMetadataWriterError.replacementFailed(error.localizedDescription)
        }
    }

    private func metadataItem(
        identifier: AVMetadataIdentifier,
        value: String
    ) -> AVMutableMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        return item
    }

    private func fileType(for url: URL, supported: [AVFileType]) -> AVFileType? {
        let candidate: AVFileType?
        switch url.pathExtension.lowercased() {
        case "aif", "aiff":
            candidate = .aiff
        case "aifc":
            candidate = .aifc
        case "caf":
            candidate = .caf
        case "m4a":
            candidate = .m4a
        case "mp3":
            candidate = .mp3
        case "mp4":
            candidate = .mp4
        case "wav":
            candidate = .wav
        default:
            candidate = nil
        }
        guard let candidate, supported.contains(candidate) else { return nil }
        return candidate
    }
}
