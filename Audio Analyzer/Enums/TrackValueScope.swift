import Foundation

enum TrackValueScope: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case bpm = "BPM"

    var id: Self { self }
}
