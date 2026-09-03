import Foundation

enum TrackValueScope: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case bpm = "BPM"
    case key = "Key"
    case replayGain = "ReplayGain"

    var id: Self { self }
}
