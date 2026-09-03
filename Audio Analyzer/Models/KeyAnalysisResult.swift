import Foundation

struct KeyChange: Hashable, Sendable {
    let keyID: Int
    let frame: Int64
}

struct KeyAnalysisResult: Hashable, Sendable {
    let globalKeyID: Int
    let keyText: String
    let sampleRate: Double
    let keyChanges: [KeyChange]

    var hasDetectedKey: Bool {
        (1...24).contains(globalKeyID) && !keyText.isEmpty
    }
}
