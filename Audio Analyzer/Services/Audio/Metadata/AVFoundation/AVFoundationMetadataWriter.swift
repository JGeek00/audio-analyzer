import AVFoundation
import Foundation

enum AVFoundationMetadataWriter {
    static func write(to url: URL, bpm: Double?, key: String?) async throws {
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

        let sourceHasGaplessMetadata = (try? Data(contentsOf: url))?.range(
            of: Data("iTunSMPB".utf8)
        ) != nil
        let keyIdentifier = keyIdentifier(for: fileType)
        let legacyMP4KeyIdentifier = AVMetadataIdentifier(rawValue: "itsk/%A9key")
        var outputMetadata = metadata

        if let bpm {
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
        }

        if let key {
            outputMetadata.removeAll { item in
                item.identifier == .id3MetadataInitialKey
                    || item.identifier == keyIdentifier
                    || item.identifier == legacyMP4KeyIdentifier
            }

            let keyItem = AVMutableMetadataItem()
            keyItem.identifier = keyIdentifier
            keyItem.value = key as NSString
            outputMetadata.append(keyItem)
        }
        exportSession.metadata = outputMetadata

        let replacementDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        )
        let temporaryURL = replacementDirectory
                .appendingPathComponent(".metadata-\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: replacementDirectory) }

        try await exportSession.export(to: temporaryURL, as: fileType)
        if fileType == .wav, let key {
            try WAVMetadataWriter.writeInitialKey(key, to: temporaryURL)
        }
        if (fileType == .m4a || fileType == .mp4), !sourceHasGaplessMetadata {
            try MP4GaplessMetadataCleaner.removeGeneratedMetadata(from: temporaryURL)
        }

        do {
            _ = try FileManager.default.replaceItem(
                at: url,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [],
                resultingItemURL: nil
            )
        } catch {
            throw AudioMetadataWriterError.replacementFailed(error.localizedDescription)
        }
    }

    private static func keyIdentifier(for fileType: AVFileType) -> AVMetadataIdentifier {
        switch fileType {
        case .m4a, .mp4:
            AVMetadataIdentifier(rawValue: "itlk/com.apple.iTunes.initialkey")
        case .wav:
            AVMetadataIdentifier(rawValue: "caaf/IKEY")
        default:
            .id3MetadataInitialKey
        }
    }

    private static func fileType(for url: URL, supported: [AVFileType]) -> AVFileType? {
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
