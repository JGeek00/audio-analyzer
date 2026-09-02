@preconcurrency import AVFoundation
import Foundation

struct AudioFileMetadata: Sendable {
    let title: String?
    let artist: String?
    let artwork: Data?
    let bpm: Double?
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
            return AudioFileMetadata(title: nil, artist: nil, artwork: nil, bpm: nil)
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
        let bpmItem = metadata.first {
            $0.identifier == .id3MetadataBeatsPerMinute
                || $0.identifier == .iTunesMetadataBeatsPerMin
        }
        let bpm: Double? = if let bpmItem {
            (try? await bpmItem.load(.numberValue))?.doubleValue
        } else {
            nil
        }
        return AudioFileMetadata(
            title: title ?? nil,
            artist: artist ?? nil,
            artwork: artwork ?? nil,
            bpm: bpm
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
