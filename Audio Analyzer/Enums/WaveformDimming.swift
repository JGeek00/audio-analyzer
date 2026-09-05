import Foundation

enum WaveformDimming: String, CaseIterable, Identifiable {
    case listened
    case unlistened

    var id: Self { self }

    var label: String {
        switch self {
        case .listened:
            String(localized: "Listened part")
        case .unlistened:
            String(localized: "Unlistened part")
        }
    }

    var dimsPlayed: Bool {
        self == .listened
    }
}
