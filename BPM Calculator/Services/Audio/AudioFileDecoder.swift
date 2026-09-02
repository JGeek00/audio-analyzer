import AVFoundation
import Foundation

struct AudioFileMetadata: Sendable {
    let title: String?
    let artist: String?
    let artwork: Data?
}

struct AudioFileDescription: Sendable {
    let sampleRate: Double
    let frameCount: AVAudioFramePosition
}

enum AudioFileDecoderError: LocalizedError {
    case invalidFormat
    case converterUnavailable
    case bufferUnavailable
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "The file does not contain a valid PCM audio format."
        case .converterUnavailable:
            return "macOS cannot convert this file to stereo float32 PCM."
        case .bufferUnavailable:
            return "The PCM buffer could not be allocated."
        case .conversionFailed(let message):
            return "Audio decoding failed: \(message)"
        }
    }
}

final class AudioFileDecoder {
    static let framesPerChunk: AVAudioFrameCount = 4_096

    func metadata(for url: URL) async -> AudioFileMetadata {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let metadata = try? await AVAsset(url: url).load(.commonMetadata) else {
            return AudioFileMetadata(title: nil, artist: nil, artwork: nil)
        }

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
        return AudioFileMetadata(
            title: title ?? nil,
            artist: artist ?? nil,
            artwork: artwork ?? nil
        )
    }

    func forEachStereoChunk(
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

    private func interleavedFloat32Data(from buffer: AVAudioPCMBuffer) throws -> Data {
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
}
