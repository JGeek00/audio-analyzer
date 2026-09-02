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
    var analysis: BPMAnalysisResult?
    var analysisStatus: TrackAnalysisStatus = .queued

    init(
            id: UUID = UUID(),
            url: URL,
            analysis: BPMAnalysisResult? = nil,
            analysisStatus: TrackAnalysisStatus = .queued) {
        self.id = id
        self.url = url
        self.analysis = analysis
        self.analysisStatus = analysisStatus
    }

    var title: String {
        url.deletingPathExtension().lastPathComponent
    }
}
