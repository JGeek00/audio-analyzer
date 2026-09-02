import Foundation

enum AudioFileDecoderError: LocalizedError {
    case invalidFormat
    case converterUnavailable
    case bufferUnavailable
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "The file does not contain a valid PCM audio format."
        case .converterUnavailable:
            return "macOS cannot convert this file to stereo float32 PCM."
        case .bufferUnavailable:
            return "The PCM buffer could not be allocated."
        case .conversionFailed(let message):
            return "Audio decoding failed: \(message)"
        }
    }
}
