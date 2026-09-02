import AVFoundation
import Foundation

struct TrackAnalysisError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

final class TrackAnalysisService {
    // ponytail: OperationQueue gives the required CPU/2 limit without a custom scheduler.
    private let queue: OperationQueue

    init(maxConcurrentOperations: Int = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)) {
        queue = OperationQueue()
        queue.name = "com.jgeek00.BPM-Calculator.track-analysis"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(1, maxConcurrentOperations)
    }

    func analyze(url: URL) async throws -> BPMAnalysisResult {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<BPMAnalysisResult, Error>) in
            queue.addOperation {
                do {
                    continuation.resume(returning: try Self.analyzeSynchronously(url: url))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func analyzeSynchronously(url: URL) throws -> BPMAnalysisResult {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw TrackAnalysisError(message: "Could not open \(url.lastPathComponent): \(error.localizedDescription)")
        }

        let sampleRate = file.processingFormat.sampleRate
        guard let analyzer = MixxxBPMAnalyzerBridge(sampleRate: sampleRate) else {
            throw TrackAnalysisError(message: "Invalid sample rate for \(url.lastPathComponent).")
        }

        _ = try AudioFileDecoder().forEachStereoChunk(in: file) { data, _ in
            guard analyzer.processSamples(data) else {
                throw TrackAnalysisError(
                        message: analyzer.lastErrorMessage.isEmpty
                                ? "Could not process a PCM block from \(url.lastPathComponent)."
                                : analyzer.lastErrorMessage)
            }
        }

        guard let result = analyzer.finish() else {
            throw TrackAnalysisError(
                    message: analyzer.lastErrorMessage.isEmpty
                            ? "The analyzer could not finish \(url.lastPathComponent)."
                            : analyzer.lastErrorMessage)
        }

        return BPMAnalysisResult(
                bpm: result.bpm,
                firstBeatFrame: result.firstBeatFrame >= 0 ? result.firstBeatFrame : nil,
                sampleRate: result.sampleRate,
                rawBeatFrames: result.rawBeatFrames.map(\.doubleValue))
    }
}
