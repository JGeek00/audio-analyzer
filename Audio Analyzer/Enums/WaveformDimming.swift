import Foundation

enum WaveformDimming: String, CaseIterable, Identifiable {
    case listened
    case unlistened

    var id: Self { self }

    var label: String {
        switch self {
        case .listened:
            "Listened part"
        case .unlistened:
            "Unlistened part"
        }
    }

    var dimsPlayed: Bool {
        self == .listened
    }
}
