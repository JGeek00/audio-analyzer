import Foundation

struct AudioTrack: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var metadataTitle: String?
    var artist: String?
    var artwork: Data?
    var analysis: BPMAnalysisResult?
    var persistedBPM: Double?
    var analysisStatus: TrackAnalysisStatus = .queued
    var hasManuallyAdjustedBPM = false

    init(
            id: UUID = UUID(),
            url: URL,
            metadataTitle: String? = nil,
            artist: String? = nil,
            artwork: Data? = nil,
            analysis: BPMAnalysisResult? = nil,
            persistedBPM: Double? = nil,
            analysisStatus: TrackAnalysisStatus = .queued,
            hasManuallyAdjustedBPM: Bool = false) {
        self.id = id
        self.url = url
        self.metadataTitle = metadataTitle
        self.artist = artist
        self.artwork = artwork
        self.analysis = analysis
        self.persistedBPM = persistedBPM
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
        return abs(persistedBPM - analysis.bpm) > 0.05
    }
}
