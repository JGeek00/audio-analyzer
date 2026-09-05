import Foundation

enum OpusGainMode: String, CaseIterable, Identifiable, Sendable {
    case standard = "Standard"
    case r128 = "R128"
    case both = "Both"

    var id: Self { self }

    var label: String {
        switch self {
        case .standard:
            String(localized: "Write standard ReplayGain tags")
        case .r128:
            String(localized: "Write R128_*_GAIN tags")
        case .both:
            String(localized: "Write both standard and R128 tags")
        }
    }

    var usesR128: Bool { self != .standard }
}
