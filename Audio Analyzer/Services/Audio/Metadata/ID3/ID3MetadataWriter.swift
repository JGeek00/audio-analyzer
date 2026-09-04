import Foundation

enum ID3MetadataWriter {
    static func write(
            to url: URL, bpm: Double?, key: String?, replayGain: ReplayGainTagRequest? = nil,
            onProgress: @Sendable (Double) -> Void = { _ in }) throws {
        let input = [UInt8](try Data(contentsOf: url))
        var tagEnd = 0
        if input.count >= 10, String(decoding: input[0..<3], as: UTF8.self) == "ID3" {
            let size = Int(input[6]) << 21
                | Int(input[7]) << 14
                | Int(input[8]) << 7
                | Int(input[9])
            tagEnd = 10 + size
            guard tagEnd <= input.count else {
                throw AudioMetadataWriterError.unsupportedFileType("mp3")
            }
        }

        let tag = try makeTag(
            existing: Array(input[0..<tagEnd]),
            bpm: bpm,
            key: key,
            replayGain: replayGain
        )
        onProgress(0.5)
        try Data(tag + Array(input[tagEnd...])).write(to: url, options: .atomic)
        onProgress(1)
    }

    static func makeTag(
            existing: [UInt8],
            bpm: Double?,
            key: String?,
            replayGain: ReplayGainTagRequest? = nil) throws -> [UInt8] {
        let version: UInt8
        let existingBody: [UInt8]
        if existing.isEmpty {
            version = 3
            existingBody = []
        } else {
            guard existing.count >= 10,
                  Array(existing[0..<3]) == Array("ID3".utf8),
                  existing[3] == 3 || existing[3] == 4 else {
                throw AudioMetadataWriterError.unsupportedFileType("id3")
            }
            version = existing[3]
            let size = Int(existing[6]) << 21
                | Int(existing[7]) << 14
                | Int(existing[8]) << 7
                | Int(existing[9])
            guard size <= existing.count - 10 else {
                throw AudioMetadataWriterError.unsupportedFileType("id3")
            }

            var frames: [UInt8] = []
            var offset = 10
            let end = 10 + size
            while offset + 10 <= end {
                let frameID = String(decoding: existing[offset..<offset + 4], as: UTF8.self)
                if existing[offset..<offset + 4].allSatisfy({ $0 == 0 }) {
                    break
                }
                let frameSize: Int
                if version == 4 {
                    frameSize = Int(existing[offset + 4]) << 21
                        | Int(existing[offset + 5]) << 14
                        | Int(existing[offset + 6]) << 7
                        | Int(existing[offset + 7])
                } else {
                    frameSize = Int(existing[offset + 4]) << 24
                        | Int(existing[offset + 5]) << 16
                        | Int(existing[offset + 6]) << 8
                        | Int(existing[offset + 7])
                }
                let frameEnd = offset + 10 + frameSize
                guard frameEnd <= end else {
                    throw AudioMetadataWriterError.unsupportedFileType("id3")
                }
                let replacingBPM = frameID == "TBPM" && bpm != nil
                let replacingKey = frameID == "TKEY" && key != nil
                let replacingReplayGain = frameID == "TXXX" && replayGain != nil
                    && isReplayGainFrame(at: offset, size: frameSize, version: version, in: existing)
                if !replacingBPM && !replacingKey && !replacingReplayGain {
                    frames.append(contentsOf: existing[offset..<frameEnd])
                }
                offset = frameEnd
            }
            existingBody = frames
        }

        var body = existingBody
        if let bpm {
            body.append(contentsOf: textFrame("TBPM", value: String(bpm), version: version))
        }
        if let key {
            body.append(contentsOf: textFrame("TKEY", value: key, version: version))
        }
        if let standard = replayGain?.standard {
            body.append(contentsOf: txxxFrame(
                description: "REPLAYGAIN_TRACK_GAIN", value: standard.gain, version: version))
            body.append(contentsOf: txxxFrame(
                description: "REPLAYGAIN_TRACK_PEAK", value: standard.peak, version: version))
        }

        var tag = Array("ID3".utf8) + [version, 0, 0]
        tag.append(contentsOf: synchsafe(body.count))
        tag.append(contentsOf: body)
        return tag
    }

    // ponytail: byte-substring match covers the latin1/UTF-8 descriptions every
    // ReplayGain tool writes; UTF-16 TXXX descriptions don't occur in practice.
    private static func isReplayGainFrame(
            at offset: Int, size: Int, version: UInt8, in bytes: [UInt8]) -> Bool {
        let payloadStart = offset + 10
        let payloadEnd = payloadStart + size
        guard payloadEnd <= bytes.count, size > 1 else { return false }
        // ponytail: materialize so subscripting below is 0-based (slices keep
        // the base indices and trap on 0-based access).
        let payload = Array(bytes[payloadStart + 1..<payloadEnd])
        for name in ["REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK"] {
            let needle = Array(name.utf8)
            if payload.count >= needle.count,
               (0...payload.count - needle.count).contains(where: {
                   Array(payload[$0..<$0 + needle.count]) == needle
               }) {
                return true
            }
        }
        return false
    }

    private static func txxxFrame(description: String, value: String, version: UInt8) -> [UInt8] {
        let encoding: UInt8 = version == 4 ? 3 : 0
        let payload = [encoding] + Array(description.utf8) + [0] + Array(value.utf8)
        var frame = Array("TXXX".utf8)
        frame.append(contentsOf: version == 4 ? synchsafe(payload.count) : bigEndian(payload.count))
        frame.append(contentsOf: [0, 0])
        frame.append(contentsOf: payload)
        return frame
    }

    private static func textFrame(_ id: String, value: String, version: UInt8) -> [UInt8] {        let encoding: UInt8 = version == 4 ? 3 : 0
        let payload = [encoding] + Array(value.utf8)
        var frame = Array(id.utf8)
        frame.append(contentsOf: version == 4 ? synchsafe(payload.count) : bigEndian(payload.count))
        frame.append(contentsOf: [0, 0])
        frame.append(contentsOf: payload)
        return frame
    }

    private static func synchsafe(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 21) & 0x7f),
            UInt8((value >> 14) & 0x7f),
            UInt8((value >> 7) & 0x7f),
            UInt8(value & 0x7f)
        ]
    }

    private static func bigEndian(_ value: Int) -> [UInt8] {
        let value = UInt32(value)
        return [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
    }
}
