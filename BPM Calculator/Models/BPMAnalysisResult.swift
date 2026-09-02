import Foundation

struct BPMAnalysisResult: Hashable, Sendable {
    let bpm: Double
    let firstBeatFrame: Int64?
    let sampleRate: Double
    let rawBeatFrames: [Double]

    init(
            bpm: Double,
            firstBeatFrame: Int64?,
            sampleRate: Double,
            rawBeatFrames: [Double] = []) {
        self.bpm = bpm
        self.firstBeatFrame = firstBeatFrame
        self.sampleRate = sampleRate
        self.rawBeatFrames = rawBeatFrames
    }

    var firstBeatSeconds: Double? {
        guard let firstBeatFrame, sampleRate > 0 else { return nil }
        return Double(firstBeatFrame) / sampleRate
    }

    var hasDetectedBPM: Bool {
        bpm.isFinite && bpm > 0
    }
}
