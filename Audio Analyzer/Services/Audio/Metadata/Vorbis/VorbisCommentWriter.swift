import Foundation

enum VorbisCommentWriter {
    static func replacing(
            in payload: [UInt8],
            bpm: Double?,
            key: String?,
            replayGain: ReplayGainTagRequest? = nil,
            fileExtension: String) throws -> [UInt8] {
        guard payload.count >= 8 else {
            throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
        }
        let vendorLength = uint32LE(at: 0, in: payload)
        let vendorEnd = 4 + vendorLength
        guard vendorEnd + 4 <= payload.count else {
            throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
        }
        let commentCount = uint32LE(at: vendorEnd, in: payload)
        var offset = vendorEnd + 4
        var comments: [[UInt8]] = []
        for _ in 0..<commentCount {
            guard offset + 4 <= payload.count else {
                throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
            }
            let length = uint32LE(at: offset, in: payload)
            let commentStart = offset + 4
            let commentEnd = commentStart + length
            guard commentEnd <= payload.count else {
                throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
            }
            let comment = Array(payload[commentStart..<commentEnd])
            let name = String(decoding: comment, as: UTF8.self)
                .split(separator: "=", maxSplits: 1)
                .first?
                .uppercased()
            let replacesBPM = bpm != nil && (name == "BPM" || name == "TEMPO")
            let replacesKey = key != nil && (name == "KEY" || name == "INITIALKEY")
            let replacesReplayGain = replayGain != nil
                && (name == "REPLAYGAIN_TRACK_GAIN" || name == "REPLAYGAIN_TRACK_PEAK"
                    || name == "R128_TRACK_GAIN")
            if !replacesBPM && !replacesKey && !replacesReplayGain {
                comments.append(comment)
            }
            offset = commentEnd
        }
        guard payload[offset...].allSatisfy({ $0 == 0 }) else {
            throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
        }

        if let bpm { comments.append(Array("BPM=\(bpm)".utf8)) }
        if let key { comments.append(Array("KEY=\(key)".utf8)) }
        if let standard = replayGain?.standard {
            comments.append(Array("REPLAYGAIN_TRACK_GAIN=\(standard.gain)".utf8))
            comments.append(Array("REPLAYGAIN_TRACK_PEAK=\(standard.peak)".utf8))
        }
        if let r128 = replayGain?.r128Gain {
            comments.append(Array("R128_TRACK_GAIN=\(r128)".utf8))
        }
        return makePayload(vendor: Array(payload[4..<vendorEnd]), comments: comments)
    }

    static func newPayload(
            bpm: Double?, key: String?, replayGain: ReplayGainTagRequest? = nil) -> [UInt8] {
        makePayload(
            vendor: Array("Audio Analyzer".utf8),
            comments: comments(bpm: bpm, key: key, replayGain: replayGain))
    }

    private static func uint32LE(at offset: Int, in bytes: [UInt8]) -> Int {
        Int(bytes[offset])
            | Int(bytes[offset + 1]) << 8
            | Int(bytes[offset + 2]) << 16
            | Int(bytes[offset + 3]) << 24
    }

    private static func littleEndian(_ value: Int) -> [UInt8] {
        [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ]
    }

    private static func comments(
            bpm: Double?, key: String?, replayGain: ReplayGainTagRequest?) -> [[UInt8]] {
        var comments: [[UInt8]] = []
        if let bpm { comments.append(Array("BPM=\(bpm)".utf8)) }
        if let key { comments.append(Array("KEY=\(key)".utf8)) }
        if let standard = replayGain?.standard {
            comments.append(Array("REPLAYGAIN_TRACK_GAIN=\(standard.gain)".utf8))
            comments.append(Array("REPLAYGAIN_TRACK_PEAK=\(standard.peak)".utf8))
        }
        if let r128 = replayGain?.r128Gain {
            comments.append(Array("R128_TRACK_GAIN=\(r128)".utf8))
        }
        return comments
    }

    private static func makePayload(vendor: [UInt8], comments: [[UInt8]]) -> [UInt8] {
        var result = littleEndian(vendor.count)
        result.append(contentsOf: vendor)
        result.append(contentsOf: littleEndian(comments.count))
        for comment in comments {
            result.append(contentsOf: littleEndian(comment.count))
            result.append(contentsOf: comment)
        }
        return result
    }
}
