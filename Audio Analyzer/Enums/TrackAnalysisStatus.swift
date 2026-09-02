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
