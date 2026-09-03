import Foundation

enum OpusGainMode: String, CaseIterable, Identifiable, Sendable {
    case standard = "Standard"
    case r128 = "R128"
    case both = "Both"

    var id: Self { self }

    var usesR128: Bool { self != .standard }
}
