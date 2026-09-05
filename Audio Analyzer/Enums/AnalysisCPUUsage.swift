import Foundation

enum AnalysisCPUUsage: String, CaseIterable, Identifiable {
    case quarter
    case half
    case threeQuarters
    case all

    var id: Self { self }

    var label: String {
        switch self {
        case .quarter:
            "25%"
        case .half:
            "50%"
        case .threeQuarters:
            "75%"
        case .all:
            "100%"
        }
    }

    var fraction: Double {
        switch self {
        case .quarter:
            0.25
        case .half:
            0.5
        case .threeQuarters:
            0.75
        case .all:
            1.0
        }
    }

    // ponytail: Int() truncates, so odd core counts round down as specified.
    var maxConcurrentOperations: Int {
        max(1, Int(Double(ProcessInfo.processInfo.activeProcessorCount) * fraction))
    }

    static var current: AnalysisCPUUsage {
        AnalysisCPUUsage(
            rawValue: UserDefaults.standard.string(forKey: AppStorageKeys.analysisCPUUsage) ?? "")
            ?? AppConfiguration.defaultAnalysisCPUUsage
    }
}
