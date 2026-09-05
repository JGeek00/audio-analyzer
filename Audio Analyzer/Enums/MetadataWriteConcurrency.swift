import Foundation

enum MetadataWriteConcurrency: String, CaseIterable, Identifiable {
    case responsive
    case balanced
    case fast

    var id: Self { self }

    var label: String {
        switch self {
        case .responsive:
            String(localized: "Responsive")
        case .balanced:
            String(localized: "Balanced")
        case .fast:
            String(localized: "Fast")
        }
    }

    var maxConcurrentWrites: Int {
        switch self {
        case .responsive:
            1
        case .balanced:
            2
        case .fast:
            4
        }
    }

    static var current: MetadataWriteConcurrency {
        MetadataWriteConcurrency(
            rawValue: UserDefaults.standard.string(forKey: AppStorageKeys.metadataWriteConcurrency) ?? "")
            ?? AppConfiguration.defaultMetadataWriteConcurrency
    }
}
