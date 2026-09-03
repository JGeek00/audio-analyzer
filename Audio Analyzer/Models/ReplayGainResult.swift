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

    // Tag wire formats (rsgain-compatible). POSIX locale: tags always use '.'.
    var trackGainTag: String {
        String(format: "%.2f dB", locale: Locale(identifier: "en_US_POSIX"), gainDB)
    }

    var trackPeakTag: String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), peak)
    }

    // RFC 7845 Q7.8 fixed-point gain for Opus R128_*_GAIN tags.
    var r128TrackGainTag: String {
        String(Int((gainDB * 256).rounded()))
    }
}
