import Foundation

enum WAVMetadataWriter {
    // ponytail: surgical merge like the AIFF writer: every chunk is preserved
    // byte-identical except the id3 chunk, where only TBPM/TKEY/ReplayGain
    // frames are replaced. No remux, no data loss.
    static func write(
            to url: URL, bpm: Double?, key: String?, replayGain: ReplayGainTagRequest? = nil,
            onProgress: @Sendable (Double) -> Void = { _ in }) throws {
        let input = [UInt8](try Data(contentsOf: url))
        guard input.count >= 12,
              String(decoding: input[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: input[8..<12], as: UTF8.self) == "WAVE" else {
            throw AudioMetadataWriterError.unsupportedFileType("wav")
        }

        var existingID3: [UInt8] = []
        var output = Array(input[0..<12])
        var offset = 12
        while offset + 8 <= input.count {
            let size = uint32LE(at: offset + 4, in: input)
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + size
            let chunkEnd = payloadEnd + size % 2
            guard payloadEnd <= input.count, chunkEnd <= input.count else {
                throw AudioMetadataWriterError.unsupportedFileType("wav")
            }
            if String(decoding: input[offset..<offset + 4], as: UTF8.self).lowercased() == "id3 " {
                existingID3 = Array(input[payloadStart..<payloadEnd])
            } else {
                output.append(contentsOf: input[offset..<chunkEnd])
            }
            offset = chunkEnd
        }
        guard offset == input.count else {
            throw AudioMetadataWriterError.unsupportedFileType("wav")
        }

        output.append(contentsOf: chunk("id3 ", payload: try ID3MetadataWriter.makeTag(
            existing: existingID3, bpm: bpm, key: key, replayGain: replayGain)))
        let riffSize = UInt32(output.count - 8)
        for index in 0..<4 {
            output[4 + index] = UInt8((riffSize >> UInt32(index * 8)) & 0xff)
        }
        onProgress(0.5)
        try Data(output).write(to: url, options: .atomic)
        onProgress(1)
    }
    // ponytail: best-effort fallback for id3 chunks AVAsset doesn't surface
    // (e.g. leading the RIFF walk); never throws, never writes.
    static func replayGainText(in fileData: [UInt8]) -> String? {
        guard fileData.count >= 12,
              String(decoding: fileData[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: fileData[8..<12], as: UTF8.self) == "WAVE" else { return nil }
        var offset = 12
        while offset + 8 <= fileData.count {
            let size = uint32LE(at: offset + 4, in: fileData)
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + size
            let chunkEnd = payloadEnd + size % 2
            guard payloadEnd <= fileData.count, chunkEnd <= fileData.count else { return nil }
            if String(decoding: fileData[offset..<offset + 4], as: UTF8.self).uppercased() == "ID3 ",
               let gain = gain(inTag: Array(fileData[payloadStart..<payloadEnd])) {
                return gain
            }
            offset = chunkEnd
        }
        return nil
    }

    private static func gain(inTag tag: [UInt8]) -> String? {
        guard tag.count >= 10,
              String(decoding: tag[0..<3], as: UTF8.self) == "ID3",
              tag[3] == 2 || tag[3] == 3 || tag[3] == 4 else { return nil }
        let size = Int(tag[6]) << 21 | Int(tag[7]) << 14
            | Int(tag[8]) << 7 | Int(tag[9])
        if tag[3] == 2 {
            // ponytail: v2.2 uses 3-char IDs, 3-byte sizes and TXX frames.
            var offset = 10
            let end = min(10 + size, tag.count)
            while offset + 6 <= end {
                if tag[offset..<offset + 3].allSatisfy({ $0 == 0 }) { break }
                let frameSize = Int(tag[offset + 3]) << 16
                    | Int(tag[offset + 4]) << 8 | Int(tag[offset + 5])
                let frameEnd = offset + 6 + frameSize
                guard frameEnd <= end else { return nil }
                if String(decoding: tag[offset..<offset + 3], as: UTF8.self) == "TXX",
                   let gain = gainText(in: Array(tag[offset + 6..<frameEnd])) {
                    return gain
                }
                offset = frameEnd
            }
            return nil
        }
        var offset = 10
        if tag[5] & 0x40 != 0 {
            // Skip the extended header.
            let extSize = tag[3] == 4
                ? Int(tag[10]) << 21 | Int(tag[11]) << 14 | Int(tag[12]) << 7 | Int(tag[13])
                : Int(tag[10]) << 24 | Int(tag[11]) << 16 | Int(tag[12]) << 8 | Int(tag[13])
            offset += tag[3] == 4 ? extSize : 4 + extSize
        }
        let end = min(10 + size, tag.count)
        while offset + 10 <= end {
            if tag[offset..<offset + 4].allSatisfy({ $0 == 0 }) { break }
            let frameSize: Int
            if tag[3] == 4 {
                frameSize = Int(tag[offset + 4]) << 21 | Int(tag[offset + 5]) << 14
                    | Int(tag[offset + 6]) << 7 | Int(tag[offset + 7])
            } else {
                frameSize = Int(tag[offset + 4]) << 24 | Int(tag[offset + 5]) << 16
                    | Int(tag[offset + 6]) << 8 | Int(tag[offset + 7])
            }
            let frameEnd = offset + 10 + frameSize
            guard frameEnd <= end else { return nil }
            if String(decoding: tag[offset..<offset + 4], as: UTF8.self) == "TXXX",
               let gain = gainText(in: Array(tag[offset + 10..<frameEnd])) {
                return gain
            }
            offset = frameEnd
        }
        return nil
    }

    private static func gainText(in frame: [UInt8]) -> String? {
        guard frame.count >= 2 else { return nil }
        let strings: [String]
        switch frame[0] {
        case 0:
            let parts = frame[1...].split(separator: 0, maxSplits: 1)
            guard parts.count == 2 else { return nil }
            strings = [
                String(decoding: parts[0], as: UTF8.self),
                String(decoding: parts[1], as: UTF8.self)
            ]
        case 3:
            let parts = frame[1...].split(separator: 0, maxSplits: 1)
            guard parts.count == 2 else { return nil }
            strings = [
                String(decoding: parts[0], as: UTF8.self),
                String(decoding: parts[1], as: UTF8.self)
            ]
        case 1, 2:
            guard let pair = splitUTF16(Array(frame[1...])) else { return nil }
            strings = [decodeUTF16(pair.0), decodeUTF16(pair.1)]
        default:
            return nil
        }
        guard strings[0].uppercased() == "REPLAYGAIN_TRACK_GAIN" else { return nil }
        return strings[1]
    }

    private static func splitUTF16(_ bytes: [UInt8]) -> ([UInt8], [UInt8])? {
        var index = 0
        while index + 1 < bytes.count {
            if bytes[index] == 0, bytes[index + 1] == 0 {
                return (Array(bytes[0..<index]), Array(bytes[(index + 2)...]))
            }
            index += 2
        }
        return nil
    }

    private static func decodeUTF16(_ bytes: [UInt8]) -> String {
        if bytes.starts(with: [0xff, 0xfe]) {
            return String(bytes: Array(bytes.dropFirst(2)), encoding: .utf16LittleEndian) ?? ""
        }
        if bytes.starts(with: [0xfe, 0xff]) {
            return String(bytes: Array(bytes.dropFirst(2)), encoding: .utf16BigEndian) ?? ""
        }
        return String(bytes: bytes, encoding: .utf16LittleEndian) ?? ""
    }
    private static func uint32LE(at offset: Int, in bytes: [UInt8]) -> Int {
        Int(bytes[offset])
            | Int(bytes[offset + 1]) << 8
            | Int(bytes[offset + 2]) << 16
            | Int(bytes[offset + 3]) << 24
    }

    private static func chunk(_ type: String, payload: [UInt8]) -> [UInt8] {
        let size = UInt32(payload.count)
        var result = Array(type.utf8)
        result.append(contentsOf: [
            UInt8(size & 0xff),
            UInt8((size >> 8) & 0xff),
            UInt8((size >> 16) & 0xff),
            UInt8((size >> 24) & 0xff)
        ])
        result.append(contentsOf: payload)
        if payload.count % 2 != 0 {
            result.append(0)
        }
        return result
    }
}
