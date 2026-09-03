import Foundation

enum ReplayGainClipMode: String, CaseIterable, Identifiable, Sendable {
    case disabled = "Disabled"
    case positiveOnly = "PositiveOnly"
    case always = "Always"

    var id: Self { self }
}
