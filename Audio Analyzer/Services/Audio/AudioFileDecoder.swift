@preconcurrency import AVFoundation
import Foundation

struct AudioFileMetadata: Sendable {
    let title: String?
    let artist: String?
    let artwork: Data?
    let bpm: Double?
    let key: String?
    let replayGain: Double?
}

struct AudioFileDescription: Sendable {
    let sampleRate: Double
    let frameCount: AVAudioFramePosition
}

struct WaveformPeak: Hashable, Sendable {
    let min: Float
    let max: Float
    let rms: Float
}

final class AudioFileDecoder {
    nonisolated static let framesPerChunk: AVAudioFrameCount = 4_096

    nonisolated init() {}

    func waveform(for url: URL, bucketCount: Int = 120_000) async throws -> [WaveformPeak] {
        try await Task.detached(priority: .userInitiated) {
            try Self.waveformSynchronously(for: url, bucketCount: bucketCount)
        }.value
    }

    func metadata(for url: URL) async -> AudioFileMetadata {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVAsset(url: url)
        guard let commonMetadata = try? await asset.load(.commonMetadata) else {
            return AudioFileMetadata(
                title: nil, artist: nil, artwork: nil, bpm: nil, key: nil, replayGain: nil)
        }
        let metadata = (try? await asset.load(.metadata)) ?? commonMetadata

        func item(for key: AVMetadataKey) -> AVMetadataItem? {
            AVMetadataItem.metadataItems(
                from: metadata,
                withKey: key,
                keySpace: .common
            ).first
        }

        let title = try? await item(for: .commonKeyTitle)?.load(.stringValue)
        let artist = try? await item(for: .commonKeyArtist)?.load(.stringValue)
        let artwork = try? await item(for: .commonKeyArtwork)?.load(.dataValue)
        let bpmIdentifiers = [
            AVMetadataIdentifier.id3MetadataBeatsPerMinute,
            AVMetadataIdentifier.iTunesMetadataBeatsPerMin,
            AVMetadataIdentifier(rawValue: "vorb/BPM"),
            AVMetadataIdentifier(rawValue: "vorb/TEMPO"),
            AVMetadataIdentifier(rawValue: "vorbis/BPM"),
            AVMetadataIdentifier(rawValue: "vorbis/TEMPO")
        ]
        let bpmItem = metadata.first { item in
            if let identifier = item.identifier, bpmIdentifiers.contains(identifier) {
                return true
            }
            return false
        }
        // ponytail: Vorbis BPM arrives as text ("128.5"), not a number.
        let bpm: Double? = if let bpmItem {
            if let number = try? await bpmItem.load(.numberValue) {
                number.doubleValue
            } else if let text = try? await bpmItem.load(.stringValue) {
                Double(text)
            } else {
                nil
            }
        } else {
            nil
        }
        let keyIdentifiers = [
            AVMetadataIdentifier(rawValue: "id3/TKEY"),
            AVMetadataIdentifier(rawValue: "itlk/com.apple.iTunes.initialkey"),
            AVMetadataIdentifier(rawValue: "itsk/%A9key"),
            AVMetadataIdentifier(rawValue: "caaf/IKEY"),
            AVMetadataIdentifier(rawValue: "vorb/KEY"),
            AVMetadataIdentifier(rawValue: "vorb/INITIALKEY"),
            AVMetadataIdentifier(rawValue: "vorbis/KEY"),
            AVMetadataIdentifier(rawValue: "vorbis/INITIALKEY")
        ]
        let directKeyItem = metadata.first { item in
            if let identifier = item.identifier, keyIdentifiers.contains(identifier) {
                return true
            }
            return false
        }
        let keyItem: AVMetadataItem?
        if let directKeyItem {
            keyItem = directKeyItem
        } else {
            var customKeyItem: AVMetadataItem?
            for item in metadata where item.identifier == AVMetadataIdentifier(rawValue: "id3/TXXX") {
                guard let attributes = try? await item.load(.extraAttributes),
                      let info = attributes[.info] as? String,
                      ["KEY", "INITIALKEY"].contains(info.uppercased()) else { continue }
                customKeyItem = item
                break
            }
            keyItem = customKeyItem
        }
        let key: String? = if let keyItem {
            (try? await keyItem.load(.stringValue)) ?? nil
        } else {
            nil
        }
        let replayGainIdentifiers = [
            AVMetadataIdentifier(rawValue: "itlk/com.apple.iTunes.REPLAYGAIN_TRACK_GAIN"),
            AVMetadataIdentifier(rawValue: "vorb/REPLAYGAIN_TRACK_GAIN"),
            AVMetadataIdentifier(rawValue: "vorbis/REPLAYGAIN_TRACK_GAIN")
        ]
        let r128Identifiers = [
            AVMetadataIdentifier(rawValue: "vorb/R128_TRACK_GAIN"),
            AVMetadataIdentifier(rawValue: "vorbis/R128_TRACK_GAIN")
        ]
        func firstItem(matching identifiers: [AVMetadataIdentifier]) -> AVMetadataItem? {
            metadata.first { item in
                if let identifier = item.identifier, identifiers.contains(identifier) {
                    return true
                }
                return false
            }
        }
        func txxxItem(descriptions: Set<String>) async -> AVMetadataItem? {
            for item in metadata where item.identifier == AVMetadataIdentifier(rawValue: "id3/TXXX") {
                guard let attributes = try? await item.load(.extraAttributes),
                      let info = attributes[.info] as? String,
                      descriptions.contains(info.uppercased()) else { continue }
                return item
            }
            return nil
        }
        // ponytail: tags always use '.', so Double parses locale-independently.
        func gainValue(from item: AVMetadataItem?) async -> Double? {
            guard let item,
                  let text = try? await item.load(.stringValue) else { return nil }
            return Double(text.split(separator: " ").first.map(String.init) ?? "")
        }
        var replayGain: Double?
        if let item = firstItem(matching: replayGainIdentifiers) {
            replayGain = await gainValue(from: item)
        } else if let item = firstItem(matching: r128Identifiers),
                  let text = try? await item.load(.stringValue),
                  let q78 = Double(text) {
            replayGain = q78 / 256.0
        } else {
            replayGain = await gainValue(
                from: await txxxItem(descriptions: ["REPLAYGAIN_TRACK_GAIN"]))
        }
        if replayGain == nil, url.pathExtension.lowercased() == "caf",
           let data = try? Data(contentsOf: url) {
            // ponytail: AVAsset doesn't surface CAF info entries; parse them.
            replayGain = CAFMetadataWriter.replayGain(in: [UInt8](data))
        }
        return AudioFileMetadata(
            title: title ?? nil,
            artist: artist ?? nil,
            artwork: artwork ?? nil,
            bpm: bpm,
            key: key,
            replayGain: replayGain
        )
    }

    nonisolated func forEachStereoChunk(
            in file: AVAudioFile,
            onChunk: (Data, Double) throws -> Void) throws -> AudioFileDescription {
        let sourceFormat = file.processingFormat
        let sampleRate = sourceFormat.sampleRate
        guard sampleRate.isFinite && sampleRate > 0 && sourceFormat.channelCount > 0 else {
            throw AudioFileDecoderError.invalidFormat
        }

        guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: false) else {
            throw AudioFileDecoderError.converterUnavailable
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
              let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: sourceFormat,
                    frameCapacity: Self.framesPerChunk) else {
            throw AudioFileDecoderError.converterUnavailable
        }

        var reachedEnd = false
        var inputError: Error?
        let totalFrames = file.length
        if totalFrames == 0 {
            return AudioFileDescription(sampleRate: sampleRate, frameCount: totalFrames)
        }

        while !reachedEnd {
            guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: Self.framesPerChunk) else {
                throw AudioFileDecoderError.bufferUnavailable
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) {
                _, inputStatus in
                if reachedEnd || (totalFrames > 0 && file.framePosition >= totalFrames) {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }

                do {
                    try file.read(into: inputBuffer, frameCount: Self.framesPerChunk)
                } catch {
                    inputError = error
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }

                guard inputBuffer.frameLength > 0 else {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }

                inputStatus.pointee = .haveData
                return inputBuffer
            }

            if let inputError {
                throw inputError
            }
            if let conversionError {
                throw AudioFileDecoderError.conversionFailed(conversionError.localizedDescription)
            }

            switch status {
            case .haveData:
                if outputBuffer.frameLength > 0 {
                    let data = try interleavedFloat32Data(from: outputBuffer)
                    let progress = totalFrames > 0
                            ? min(max(Double(file.framePosition) / Double(totalFrames), 0), 1)
                            : 0
                    try onChunk(data, progress)
                }
            case .inputRanDry:
                continue
            case .endOfStream:
                reachedEnd = true
            case .error:
                throw AudioFileDecoderError.conversionFailed("Unknown AVAudioConverter error.")
            @unknown default:
                throw AudioFileDecoderError.conversionFailed("Unknown AVAudioConverter state.")
            }
        }

        return AudioFileDescription(sampleRate: sampleRate, frameCount: totalFrames)
    }

    nonisolated private func interleavedFloat32Data(from buffer: AVAudioPCMBuffer) throws -> Data {
        guard buffer.format.channelCount >= 2,
              let channelData = buffer.floatChannelData else {
            throw AudioFileDecoderError.invalidFormat
        }
        let left = channelData[0]
        let right = channelData[1]

        let frameCount = Int(buffer.frameLength)
        var samples: [Float] = []
        samples.reserveCapacity(frameCount * 2)
        for frame in 0..<frameCount {
            samples.append(left[frame])
            samples.append(right[frame])
        }
        return samples.withUnsafeBytes { Data($0) }
    }

    nonisolated private static func waveformSynchronously(
            for url: URL,
            bucketCount: Int) throws -> [WaveformPeak] {
        guard bucketCount > 0 else { return [] }

        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let file = try AVAudioFile(forReading: url)
        let totalFrames = max(file.length, 1)
        var minimums = Array(repeating: Float.infinity, count: bucketCount)
        var maximums = Array(repeating: -Float.infinity, count: bucketCount)
        var squaredSums = Array(repeating: Float.zero, count: bucketCount)
        var sampleCounts = Array(repeating: 0, count: bucketCount)
        var frameOffset: Int64 = 0

        _ = try AudioFileDecoder().forEachStereoChunk(in: file) { data, _ in
            data.withUnsafeBytes { rawBuffer in
                let samples = rawBuffer.bindMemory(to: Float.self)
                let frameCount = samples.count / 2

                for frame in 0..<frameCount {
                    let left = samples[frame * 2]
                    let right = samples[frame * 2 + 1]
                    guard left.isFinite, right.isFinite else { continue }

                    let bucket = min(
                        bucketCount - 1,
                        Int(
                            Double(frameOffset + Int64(frame))
                                / Double(totalFrames)
                                * Double(bucketCount)
                        )
                    )
                    minimums[bucket] = min(minimums[bucket], left, right)
                    maximums[bucket] = max(maximums[bucket], left, right)
                    squaredSums[bucket] += (left * left + right * right) / 2
                    sampleCounts[bucket] += 1
                }
                frameOffset += Int64(frameCount)
            }
        }

        return (0..<bucketCount).map { bucket in
            guard minimums[bucket].isFinite,
                  maximums[bucket].isFinite,
                  sampleCounts[bucket] > 0 else {
                return WaveformPeak(min: 0, max: 0, rms: 0)
            }
            return WaveformPeak(
                min: minimums[bucket],
                max: maximums[bucket],
                rms: sqrt(squaredSums[bucket] / Float(sampleCounts[bucket]))
            )
        }
    }
}
