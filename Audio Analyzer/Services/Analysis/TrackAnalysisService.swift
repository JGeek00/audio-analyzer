import AVFoundation
import Foundation

struct TrackAnalysisError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

final class TrackAnalysisService {
    // ponytail: OperationQueue gives the required CPU limit without a custom scheduler.
    private let queue: OperationQueue

    init(maxConcurrentOperations: Int = AnalysisCPUUsage.current.maxConcurrentOperations) {
        queue = OperationQueue()
        queue.name = "com.jgeek00.BPM-Calculator.track-analysis"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(1, maxConcurrentOperations)
    }

    func analyze(
            url: URL,
            settings: ReplayGainSettings? = nil,
            onProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> (bpm: BPMAnalysisResult, key: KeyAnalysisResult, replayGain: ReplayGainResult) {
        let settings = settings ?? .current()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<
                    (bpm: BPMAnalysisResult, key: KeyAnalysisResult, replayGain: ReplayGainResult), Error>) in
            // ponytail: re-read here so a prefs change applies without recreating the service.
            queue.maxConcurrentOperationCount = AnalysisCPUUsage.current.maxConcurrentOperations
            queue.addOperation {
                do {
                    continuation.resume(returning: try Self.analyzeSynchronously(
                        url: url, settings: settings, onProgress: onProgress))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func analyzeSynchronously(
            url: URL,
            settings: ReplayGainSettings,
            onProgress: @Sendable (Double) -> Void) throws -> (
            bpm: BPMAnalysisResult, key: KeyAnalysisResult, replayGain: ReplayGainResult) {
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
        guard let analyzer = MixxxBPMAnalyzerBridge(
                sampleRate: sampleRate,
                totalFrameCount: file.length) else {
            throw TrackAnalysisError(message: "Invalid sample rate for \(url.lastPathComponent).")
        }

        // ponytail: integer-percent throttle caps MainActor hops at ~100/file.
        var lastReportedPercent = -1
        _ = try AudioFileDecoder().forEachStereoChunk(in: file) { data, progress in
            let percent = Int((progress * 100).rounded(.down))
            if percent != lastReportedPercent {
                lastReportedPercent = percent
                onProgress(progress)
            }
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

        return (
            bpm: BPMAnalysisResult(
                bpm: result.bpm,
                firstBeatFrame: result.firstBeatFrame >= 0 ? result.firstBeatFrame : nil,
                sampleRate: result.sampleRate,
                rawBeatFrames: result.rawBeatFrames.map(\.doubleValue)),
            key: KeyAnalysisResult(
                globalKeyID: result.keyResult.globalKeyID,
                keyText: result.keyResult.keyText,
                sampleRate: result.keyResult.sampleRate,
                keyChanges: result.keyResult.keyChanges.map {
                    KeyChange(keyID: $0.keyID, frame: $0.frame)
                }),
            replayGain: settings.result(
                loudnessLUFS: result.replayGainLoudnessLUFS,
                peak: result.replayGainPeak,
                url: url))
    }
}
