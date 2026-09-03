import Foundation

enum CAFMetadataWriter {
    // ponytail: ReplayGain lives in the standard 'info' chunk (uppercase keys
    // are app-defined per spec); AVFoundation exports cannot carry it.
    static func writeReplayGain(_ replayGain: ReplayGainTagRequest, to url: URL) throws {
        let input = [UInt8](try Data(contentsOf: url))
        guard input.count >= 8,
              String(decoding: input[0..<4], as: UTF8.self) == "caff" else {
            throw AudioMetadataWriterError.unsupportedFileType("caf")
        }

        var chunks: [(type: String, payload: [UInt8], unknownSize: Bool)] = []
        var offset = 8
        while offset < input.count {
            guard offset + 12 <= input.count else {
                throw AudioMetadataWriterError.unsupportedFileType("caf")
            }
            let type = String(decoding: input[offset..<offset + 4], as: UTF8.self)
            let size = uint64BE(at: offset + 4, in: input)
            let payloadStart = offset + 12
            if size == UInt64.max {
                // Unknown-size data chunk must be last.
                guard type == "data", payloadStart <= input.count else {
                    throw AudioMetadataWriterError.unsupportedFileType("caf")
                }
                chunks.append((type, Array(input[payloadStart...]), true))
                offset = input.count
            } else {
                guard size <= UInt64(input.count),
                      payloadStart + Int(size) <= input.count else {
                    throw AudioMetadataWriterError.unsupportedFileType("caf")
                }
                chunks.append((type, Array(input[payloadStart..<payloadStart + Int(size)]), false))
                offset = payloadStart + Int(size)
            }
        }

        var entries: [(key: String, value: String)] = []
        if let infoIndex = chunks.firstIndex(where: { $0.type == "info" }) {
            entries = try parseInfo(chunks[infoIndex].payload, fileExtension: "caf")
            chunks.remove(at: infoIndex)
        }
        entries.removeAll {
            $0.key == "REPLAYGAIN_TRACK_GAIN" || $0.key == "REPLAYGAIN_TRACK_PEAK"
        }
        if let standard = replayGain.standard {
            entries.append(("REPLAYGAIN_TRACK_GAIN", standard.gain))
            entries.append(("REPLAYGAIN_TRACK_PEAK", standard.peak))
        }
        let infoPayload = makeInfo(entries: entries)
        // ponytail: unknown-size data stays last; anything else appends at end.
        if let dataIndex = chunks.firstIndex(where: { $0.unknownSize }) {
            chunks.insert(("info", infoPayload, false), at: dataIndex)
        } else {
            chunks.append(("info", infoPayload, false))
        }

        var output = Array(input[0..<8])
        for chunk in chunks {
            output.append(contentsOf: Array(chunk.type.utf8))
            if chunk.unknownSize {
                output.append(contentsOf: [UInt8](repeating: 0xff, count: 8))
            } else {
                let size = UInt64(chunk.payload.count)
                for shift in stride(from: 56, through: 0, by: -8) {
                    output.append(UInt8((size >> UInt64(shift)) & 0xff))
                }
            }
            output.append(contentsOf: chunk.payload)
        }
        try Data(output).write(to: url, options: .atomic)
    }

    static func replayGain(in fileData: [UInt8]) -> Double? {
        guard fileData.count >= 8,
              String(decoding: fileData[0..<4], as: UTF8.self) == "caff" else { return nil }
        var offset = 8
        while offset + 12 <= fileData.count {
            let type = String(decoding: fileData[offset..<offset + 4], as: UTF8.self)
            let size = uint64BE(at: offset + 4, in: fileData)
            let payloadStart = offset + 12
            guard size != UInt64.max,
                  size <= UInt64(fileData.count),
                  payloadStart + Int(size) <= fileData.count else { return nil }
            if type == "info",
               let entries = try? parseInfo(
                Array(fileData[payloadStart..<payloadStart + Int(size)]), fileExtension: "caf"),
               let match = entries.first(where: { $0.key == "REPLAYGAIN_TRACK_GAIN" }) {
                return Double(match.value.split(separator: " ").first.map(String.init) ?? "")
            }
            offset = payloadStart + Int(size)
        }
        return nil
    }

    private static func parseInfo(
            _ payload: [UInt8], fileExtension: String) throws -> [(key: String, value: String)] {
        guard payload.count >= 4 else {
            throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
        }
        let count = Int(payload[0]) << 24 | Int(payload[1]) << 16
            | Int(payload[2]) << 8 | Int(payload[3])
        var entries: [(key: String, value: String)] = []
        var offset = 4
        for _ in 0..<count {
            guard let (key, afterKey) = readCString(payload, from: offset),
                  let (value, afterValue) = readCString(payload, from: afterKey) else {
                throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
            }
            entries.append((key, value))
            offset = afterValue
        }
        guard offset <= payload.count else {
            throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
        }
        return entries
    }

    private static func readCString(_ bytes: [UInt8], from offset: Int) -> (String, Int)? {
        var end = offset
        while end < bytes.count, bytes[end] != 0 {
            end += 1
        }
        guard end < bytes.count else { return nil }
        return (String(decoding: bytes[offset..<end], as: UTF8.self), end + 1)
    }

    private static func makeInfo(entries: [(key: String, value: String)]) -> [UInt8] {
        var payload: [UInt8] = []
        let count = UInt32(entries.count)
        for shift in stride(from: 24, through: 0, by: -8) {
            payload.append(UInt8((count >> UInt32(shift)) & 0xff))
        }
        for entry in entries {
            payload.append(contentsOf: Array(entry.key.utf8) + [0])
            payload.append(contentsOf: Array(entry.value.utf8) + [0])
        }
        return payload
    }

    private static func uint64BE(at offset: Int, in bytes: [UInt8]) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = value << 8 | UInt64(bytes[offset + index])
        }
        return value
    }
}
