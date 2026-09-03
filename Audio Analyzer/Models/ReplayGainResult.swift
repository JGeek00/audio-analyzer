import Foundation

struct ReplayGainResult: Hashable, Sendable {
    let loudnessLUFS: Double
    let peak: Double
    let gainDB: Double
    let clipped: Bool

    var hasDetectedGain: Bool {
        loudnessLUFS.isFinite
    }

    func applying(_ settings: ReplayGainSettings, for url: URL) -> ReplayGainResult {
        settings.result(loudnessLUFS: loudnessLUFS, peak: peak, url: url)
    }
}
