import Foundation

enum TrackAnalysisStatus: Hashable, Sendable {
    case queued
    case analyzing
    case completed
    case failed(String)

    var label: String {
        switch self {
        case .queued:
            return "Queued"
        case .analyzing:
            return "Analyzing…"
        case .completed:
            return "Completed"
        case .failed(let message):
            return message
        }
    }
}

struct AudioTrack: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var metadataTitle: String?
    var artist: String?
    var artwork: Data?
    var analysis: BPMAnalysisResult?
    var analysisStatus: TrackAnalysisStatus = .queued

    init(
            id: UUID = UUID(),
            url: URL,
            metadataTitle: String? = nil,
            artist: String? = nil,
            artwork: Data? = nil,
            analysis: BPMAnalysisResult? = nil,
            analysisStatus: TrackAnalysisStatus = .queued) {
        self.id = id
        self.url = url
        self.metadataTitle = metadataTitle
        self.artist = artist
        self.artwork = artwork
        self.analysis = analysis
        self.analysisStatus = analysisStatus
    }

    var title: String {
        metadataTitle?.isEmpty == false
                ? metadataTitle!
                : url.deletingPathExtension().lastPathComponent
    }
}
