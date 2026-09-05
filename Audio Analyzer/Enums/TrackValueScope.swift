import Foundation

enum TrackValueScope: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case bpm = "BPM"
    case key = "Key"
    case replayGain = "ReplayGain"

    var id: Self { self }

    // ponytail: pre-localized String so Text/Buttons show es without view changes.
    var label: String {
        switch self {
        case .all:
            String(localized: "All")
        case .bpm:
            String(localized: "BPM")
        case .key:
            String(localized: "Key")
        case .replayGain:
            String(localized: "ReplayGain")
        }
    }
}
