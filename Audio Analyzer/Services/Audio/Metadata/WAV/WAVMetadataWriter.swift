import Foundation

enum WAVMetadataWriter {
    // ponytail: ReplayGain lives in an ID3 chunk (loudgain-style); AVFoundation
    // exports cannot carry it, same reason writeInitialKey exists.
    static func writeReplayGain(_ replayGain: ReplayGainTagRequest, to url: URL) throws {
        let input = [UInt8](try Data(contentsOf: url))
        guard input.count >= 12,
              String(decoding: input[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: input[8..<12], as: UTF8.self) == "WAVE" else {
            throw AudioMetadataWriterError.unsupportedFileType("wav")
        }

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
            if String(decoding: input[offset..<offset + 4], as: UTF8.self) != "id3 " {
                output.append(contentsOf: input[offset..<chunkEnd])
            }
            offset = chunkEnd
        }
        guard offset == input.count else {
            throw AudioMetadataWriterError.unsupportedFileType("wav")
        }

        let tag = try ID3MetadataWriter.makeTag(
            existing: [],
            bpm: nil,
            key: nil,
            replayGain: replayGain)
        output.append(contentsOf: chunk("id3 ", payload: tag))

        let riffSize = UInt32(output.count - 8)
        for index in 0..<4 {
            output[4 + index] = UInt8((riffSize >> UInt32(index * 8)) & 0xff)
        }
        try Data(output).write(to: url, options: .atomic)
    }

    static func writeInitialKey(_ key: String, to url: URL) throws {
        let input = [UInt8](try Data(contentsOf: url))
        guard input.count >= 12,
              String(decoding: input[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: input[8..<12], as: UTF8.self) == "WAVE" else {
            throw AudioMetadataWriterError.unsupportedFileType("wav")
        }

        let keyChunk = chunk("IKEY", payload: Array(key.utf8) + [0])
        var output = Array(input[0..<12])
        var offset = 12
        var foundInfoList = false
        var insertedKey = false

        while offset + 8 <= input.count {
            let size = uint32LE(at: offset + 4, in: input)
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + size
            let chunkEnd = payloadEnd + size % 2
            guard payloadEnd <= input.count, chunkEnd <= input.count else { break }

            let type = String(decoding: input[offset..<offset + 4], as: UTF8.self)
            let isInfoList = type == "LIST"
                && size >= 4
                && String(decoding: input[payloadStart..<payloadStart + 4], as: UTF8.self) == "INFO"
            if !isInfoList {
                output.append(contentsOf: input[offset..<chunkEnd])
                offset = chunkEnd
                continue
            }

            var infoPayload = Array(input[payloadStart..<payloadStart + 4])
            var subOffset = payloadStart + 4
            var valid = true
            while subOffset + 8 <= payloadEnd {
                let subSize = uint32LE(at: subOffset + 4, in: input)
                let subPayloadStart = subOffset + 8
                let subPayloadEnd = subPayloadStart + subSize
                let subChunkEnd = subPayloadEnd + subSize % 2
                guard subPayloadEnd <= payloadEnd, subChunkEnd <= payloadEnd else {
                    valid = false
                    break
                }
                let subType = String(decoding: input[subOffset..<subOffset + 4], as: UTF8.self)
                if subType != "IKEY" {
                    infoPayload.append(contentsOf: input[subOffset..<subChunkEnd])
                }
                subOffset = subChunkEnd
            }
            guard valid, subOffset == payloadEnd else {
                output.append(contentsOf: input[offset..<chunkEnd])
                offset = chunkEnd
                continue
            }

            if !foundInfoList {
                infoPayload.append(contentsOf: keyChunk)
                foundInfoList = true
                insertedKey = true
            }
            output.append(contentsOf: chunk("LIST", payload: infoPayload))
            offset = chunkEnd
        }

        guard offset == input.count else {
            throw AudioMetadataWriterError.unsupportedFileType("wav")
        }
        if !insertedKey {
            output.append(contentsOf: chunk("LIST", payload: Array("INFO".utf8) + keyChunk))
        }

        let riffSize = UInt32(output.count - 8)
        for index in 0..<4 {
            output[4 + index] = UInt8((riffSize >> UInt32(index * 8)) & 0xff)
        }
        try Data(output).write(to: url, options: .atomic)
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
