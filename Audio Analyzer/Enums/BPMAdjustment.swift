import Foundation

enum BPMAdjustment: CaseIterable, Identifiable {
    case half
    case twoThirds
    case threeFourths
    case fourThirds
    case threeHalves
    case doubleBPM

    var id: Self { self }

    var multiplier: Double {
        switch self {
        case .half:
            0.5
        case .twoThirds:
            2.0 / 3.0
        case .threeFourths:
            0.75
        case .fourThirds:
            4.0 / 3.0
        case .threeHalves:
            1.5
        case .doubleBPM:
            2.0
        }
    }

    // ponytail: pre-localized String so menus show es without view changes.
    var label: String {
        switch self {
        case .half:
            String(localized: "Halve BPM")
        case .twoThirds:
            String(localized: "2/3 BPM")
        case .threeFourths:
            String(localized: "3/4 BPM")
        case .fourThirds:
            String(localized: "4/3 BPM")
        case .threeHalves:
            String(localized: "3/2 BPM")
        case .doubleBPM:
            String(localized: "Double BPM")
        }
    }

    func menuTitle(for bpm: Double) -> String {
        let adjustedBPM = bpm * multiplier
        let formattedBPM = adjustedBPM.formatted(.number.precision(.fractionLength(0...2)))
        return "\(label) | \(formattedBPM) BPM"
    }
}
