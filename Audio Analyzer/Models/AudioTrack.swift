import Foundation

struct AudioTrack: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var metadataTitle: String?
    var artist: String?
    var artwork: Data?
    var analysis: BPMAnalysisResult?
    var keyAnalysis: KeyAnalysisResult?
    var replayGainAnalysis: ReplayGainResult?
    var persistedBPM: Double?
    var persistedKey: String?
    var persistedReplayGain: Double?
    var analysisStatus: TrackAnalysisStatus = .queued
    var hasManuallyAdjustedBPM = false

    init(
            id: UUID = UUID(),
            url: URL,
            metadataTitle: String? = nil,
            artist: String? = nil,
            artwork: Data? = nil,
            analysis: BPMAnalysisResult? = nil,
            keyAnalysis: KeyAnalysisResult? = nil,
            replayGainAnalysis: ReplayGainResult? = nil,
            persistedBPM: Double? = nil,
            persistedKey: String? = nil,
            persistedReplayGain: Double? = nil,
            analysisStatus: TrackAnalysisStatus = .queued,
            hasManuallyAdjustedBPM: Bool = false) {
        self.id = id
        self.url = url
        self.metadataTitle = metadataTitle
        self.artist = artist
        self.artwork = artwork
        self.analysis = analysis
        self.keyAnalysis = keyAnalysis
        self.replayGainAnalysis = replayGainAnalysis
        self.persistedBPM = persistedBPM
        self.persistedKey = persistedKey
        self.persistedReplayGain = persistedReplayGain
        self.analysisStatus = analysisStatus
        self.hasManuallyAdjustedBPM = hasManuallyAdjustedBPM
    }

    var title: String {
        metadataTitle?.isEmpty == false
                ? metadataTitle!
                : url.deletingPathExtension().lastPathComponent
    }

    var artistName: String {
        artist ?? ""
    }

    var sampleRateValue: Double {
        analysis?.sampleRate ?? 0
    }

    var bpmValue: Double {
        guard let analysis, analysis.hasDetectedBPM else { return 0 }
        return analysis.bpm
    }

    var keyValue: String {
        keyAnalysis?.hasDetectedKey == true ? keyAnalysis!.keyText : ""
    }

    var replayGainValue: Double {
        guard let replayGainAnalysis, replayGainAnalysis.hasDetectedGain else { return 0 }
        return replayGainAnalysis.gainDB
    }

    var artworkSortValue: String {
        artwork == nil ? "" : "Artwork"
    }

    var isProcessing: Bool {
        switch analysisStatus {
        case .queued, .analyzing:
            true
        case .completed, .failed:
            false
        }
    }

    var hasUnsavedBPM: Bool {
        guard analysisStatus == .completed,
              let analysis,
              analysis.hasDetectedBPM else { return false }
        guard let persistedBPM, persistedBPM.isFinite, persistedBPM > 0 else { return true }
        return hasPersistedBPMConflict
    }

    var hasPersistedBPMConflict: Bool {
        guard analysisStatus == .completed,
              let analysis,
              analysis.hasDetectedBPM,
              let persistedBPM,
              persistedBPM.isFinite,
              persistedBPM > 0 else { return false }
        return abs(persistedBPM - analysis.bpm) > 0.05
    }

    var hasPersistedKeyConflict: Bool {        guard analysisStatus == .completed,
              let keyAnalysis,
              keyAnalysis.hasDetectedKey,
              let persistedKey,
              !persistedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return persistedKey.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(keyAnalysis.keyText) != .orderedSame
    }

    var hasUnsavedReplayGain: Bool {
        guard analysisStatus == .completed,
              let replayGainAnalysis,
              replayGainAnalysis.hasDetectedGain else { return false }
        guard let persistedReplayGain, persistedReplayGain.isFinite else { return true }
        return hasPersistedReplayGainConflict
    }

    var hasPersistedReplayGainConflict: Bool {
        guard analysisStatus == .completed,
              let replayGainAnalysis,
              replayGainAnalysis.hasDetectedGain,
              let persistedReplayGain,
              persistedReplayGain.isFinite else { return false }
        // ponytail: tags store 2 decimals; 0.01 absorbs formatting residue.
        return abs(persistedReplayGain - replayGainAnalysis.gainDB) > 0.01
    }
}
