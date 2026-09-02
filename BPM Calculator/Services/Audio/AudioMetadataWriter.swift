import AVFoundation
import Foundation

final class AudioMetadataWriter {
    func save(bpm: Double, to url: URL) async throws {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: url)
        let metadata: [AVMetadataItem]
        do {
            metadata = try await asset.load(.metadata)
        } catch {
            metadata = try await asset.load(.commonMetadata)
        }
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
            item.identifier == .id3MetadataBeatsPerMinute
                || item.identifier == .iTunesMetadataBeatsPerMin
        }

        let bpmItem = AVMutableMetadataItem()
        bpmItem.identifier = fileType == .mp3
                ? .id3MetadataBeatsPerMinute
                : .iTunesMetadataBeatsPerMin
        bpmItem.value = NSNumber(value: bpm)
        outputMetadata.append(bpmItem)
        exportSession.metadata = outputMetadata

        let replacementDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        )
        let temporaryURL = replacementDirectory
                .appendingPathComponent(".bpm-\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: replacementDirectory) }

        try await exportSession.export(to: temporaryURL, as: fileType)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } catch {
            throw AudioMetadataWriterError.replacementFailed(error.localizedDescription)
        }
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
