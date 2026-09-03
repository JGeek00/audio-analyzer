import Foundation

enum AIFFMetadataWriter {
    static func write(
            to url: URL, bpm: Double?, key: String?, replayGain: ReplayGainTagRequest? = nil) throws {
        let input = [UInt8](try Data(contentsOf: url))
        guard input.count >= 12,
              String(decoding: input[0..<4], as: UTF8.self) == "FORM",
              ["AIFF", "AIFC"].contains(String(decoding: input[8..<12], as: UTF8.self)) else {
            throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
        }

        var existingID3: [UInt8] = []
        var output = Array(input[0..<12])
        var offset = 12
        while offset + 8 <= input.count {
            let size = uint32BE(at: offset + 4, in: input)
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + size
            let chunkEnd = payloadEnd + size % 2
            guard payloadEnd <= input.count, chunkEnd <= input.count else {
                throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
            }
            if String(decoding: input[offset..<offset + 4], as: UTF8.self) == "ID3 " {
                existingID3 = Array(input[payloadStart..<payloadEnd])
            } else {
                output.append(contentsOf: input[offset..<chunkEnd])
            }
            offset = chunkEnd
        }
        guard offset == input.count else {
            throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
        }

        output.append(contentsOf: chunk(
            "ID3 ",
            payload: try ID3MetadataWriter.makeTag(
                existing: existingID3, bpm: bpm, key: key, replayGain: replayGain)
        ))
        let formSize = UInt32(output.count - 8)
        for index in 0..<4 {
            output[4 + index] = UInt8((formSize >> UInt32((3 - index) * 8)) & 0xff)
        }
        try Data(output).write(to: url, options: .atomic)
    }

    private static func uint32BE(at offset: Int, in bytes: [UInt8]) -> Int {
        Int(bytes[offset]) << 24
            | Int(bytes[offset + 1]) << 16
            | Int(bytes[offset + 2]) << 8
            | Int(bytes[offset + 3])
    }

    private static func chunk(_ type: String, payload: [UInt8]) -> [UInt8] {
        let size = UInt32(payload.count)
        var result = Array(type.utf8)
        result.append(contentsOf: [
            UInt8((size >> 24) & 0xff),
            UInt8((size >> 16) & 0xff),
            UInt8((size >> 8) & 0xff),
            UInt8(size & 0xff)
        ])
        result.append(contentsOf: payload)
        if payload.count % 2 != 0 {
            result.append(0)
        }
        return result
    }
}
