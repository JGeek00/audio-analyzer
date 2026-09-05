import UniformTypeIdentifiers

struct AppConfiguration {
    static let supportedAudioExtensions: Set<String> = [
        "mp3", "flac", "m4a", "ogg", "oga", "opus", "wav"
    ]
    static let supportedAudioContentTypes: [UTType] =
        supportedAudioExtensions.compactMap { UTType(filenameExtension: $0) }

    static let defaultTheme = AppTheme.system
    static let defaultWaveformDimming = WaveformDimming.listened
    static let defaultShowBeatMarkers = true
    static let defaultLowPerformanceMode = false
    static let defaultAutoSave = false
    static let defaultReplayGainTargetLUFS = -18.0
    static let defaultReplayGainClipMode = ReplayGainClipMode.positiveOnly
    static let defaultReplayGainMaxPeakDB = 0.0
    static let defaultOpusGainMode = OpusGainMode.standard
    static let defaultOpusForce23 = false
    static let defaultAnalysisCPUUsage = AnalysisCPUUsage.half
    static let defaultMetadataWriteConcurrency = MetadataWriteConcurrency.balanced

    private init() {}
}
