import Foundation

enum ReplayGainClipMode: String, CaseIterable, Identifiable, Sendable {
    case disabled = "Disabled"
    case positiveOnly = "PositiveOnly"
    case always = "Always"

    var id: Self { self }

    var label: String {
        switch self {
        case .disabled:
            String(localized: "Disabled")
        case .positiveOnly:
            String(localized: "Enabled for positive gain values only")
        case .always:
            String(localized: "Enabled for all tracks")
        }
    }
}
