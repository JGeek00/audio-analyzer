import Foundation

enum ReplayGainClipMode: String, CaseIterable, Identifiable, Sendable {
    case disabled = "Disabled"
    case positiveOnly = "PositiveOnly"
    case always = "Always"

    var id: Self { self }

    var label: String {
        switch self {
        case .disabled:
            "Disabled"
        case .positiveOnly:
            "Enabled for positive gain values only"
        case .always:
            "Enabled for all tracks"
        }
    }
}
