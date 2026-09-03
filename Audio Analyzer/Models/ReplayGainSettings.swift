import Foundation

struct ReplayGainSettings: Hashable, Sendable {
    var targetLUFS: Double
    var clipMode: ReplayGainClipMode
    var maxPeakDB: Double
    var opusMode: OpusGainMode
    var opusForce23: Bool

    static var defaults: ReplayGainSettings {
        ReplayGainSettings(
            targetLUFS: AppConfiguration.defaultReplayGainTargetLUFS,
            clipMode: AppConfiguration.defaultReplayGainClipMode,
            maxPeakDB: AppConfiguration.defaultReplayGainMaxPeakDB,
            opusMode: AppConfiguration.defaultOpusGainMode,
            opusForce23: AppConfiguration.defaultOpusForce23
        )
    }

    static func current() -> ReplayGainSettings {
        let store = UserDefaults.standard
        return ReplayGainSettings(
            targetLUFS: store.object(forKey: AppStorageKeys.replayGainTargetLUFS) as? Double
                ?? AppConfiguration.defaultReplayGainTargetLUFS,
            clipMode: ReplayGainClipMode(
                rawValue: store.string(forKey: AppStorageKeys.replayGainClipMode) ?? "")
                ?? AppConfiguration.defaultReplayGainClipMode,
            maxPeakDB: store.object(forKey: AppStorageKeys.replayGainMaxPeakDB) as? Double
                ?? AppConfiguration.defaultReplayGainMaxPeakDB,
            opusMode: OpusGainMode(
                rawValue: store.string(forKey: AppStorageKeys.opusGainMode) ?? "")
                ?? AppConfiguration.defaultOpusGainMode,
            opusForce23: store.object(forKey: AppStorageKeys.opusForce23) as? Bool
                ?? AppConfiguration.defaultOpusForce23
        )
    }

    func effectiveTarget(for url: URL) -> Double {
        guard opusForce23,
              url.pathExtension.lowercased() == "opus",
              opusMode.usesR128 else { return targetLUFS }
        return -23.0
    }

    func result(loudnessLUFS: Double, peak: Double, url: URL) -> ReplayGainResult {
        guard loudnessLUFS.isFinite else {
            return ReplayGainResult(loudnessLUFS: loudnessLUFS, peak: 0, gainDB: 0, clipped: false)
        }
        var gain = effectiveTarget(for: url) - loudnessLUFS
        var clipped = false
        if clipMode != .disabled, peak > 0, clipMode == .always || gain > 0 {
            let maxPeak = pow(10.0, maxPeakDB / 20.0)
            let newPeak = peak * pow(10.0, gain / 20.0)
            if newPeak > maxPeak {
                // ponytail: positive-only never drives gain negative, like rsgain -c p.
                let adjustment = clipMode == .positiveOnly
                    ? min(20.0 * log10(newPeak / maxPeak), gain)
                    : 20.0 * log10(newPeak / maxPeak)
                gain -= adjustment
                clipped = true
            }
        }
        return ReplayGainResult(
            loudnessLUFS: loudnessLUFS, peak: peak, gainDB: gain, clipped: clipped)
    }

    // Resolves which tag flavors to write. Standard REPLAYGAIN_* tags always
    // apply; Opus files additionally honor the R128 setting (RFC 7845).
    func tagRequest(for url: URL, result: ReplayGainResult) -> ReplayGainTagRequest? {
        guard result.hasDetectedGain else { return nil }
        let standard = ReplayGainTagRequest.Standard(
            gain: result.trackGainTag, peak: result.trackPeakTag)
        guard url.pathExtension.lowercased() == "opus", opusMode.usesR128 else {
            return ReplayGainTagRequest(standard: standard, r128Gain: nil)
        }
        switch opusMode {
        case .standard:
            return ReplayGainTagRequest(standard: standard, r128Gain: nil)
        case .r128:
            return ReplayGainTagRequest(standard: nil, r128Gain: result.r128TrackGainTag)
        case .both:
            return ReplayGainTagRequest(standard: standard, r128Gain: result.r128TrackGainTag)
        }
    }
}

struct ReplayGainTagRequest: Sendable {
    struct Standard: Sendable {
        let gain: String
        let peak: String
    }

    // ponytail: one resolved request beats threading settings+result through writers.
    let standard: Standard?
    let r128Gain: String?
}
