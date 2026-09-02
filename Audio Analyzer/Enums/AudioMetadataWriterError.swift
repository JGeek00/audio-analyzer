import Foundation

enum AudioMetadataWriterError: LocalizedError {
    case noDetectedBPM
    case exportSessionUnavailable
    case unsupportedFileType(String)
    case replacementFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDetectedBPM:
            return "BPM analysis has not completed for this track."
        case .exportSessionUnavailable:
            return "This audio file cannot be exported with metadata."
        case .unsupportedFileType(let fileExtension):
            return "Metadata writing is not supported for .\(fileExtension) files."
        case .replacementFailed(let message):
            return "The original file could not be replaced: \(message)"
        }
    }
}
