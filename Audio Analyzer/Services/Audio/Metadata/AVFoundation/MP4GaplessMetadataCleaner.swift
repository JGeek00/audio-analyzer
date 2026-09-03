import Foundation

enum MP4GaplessMetadataCleaner {
    static func removeGeneratedMetadata(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        let gaplessName = Array("iTunSMPB".utf8)
        let containerTypes = Set([
            "moov", "trak", "mdia", "minf", "stbl", "edts", "dinf", "udta", "meta", "ilst"
        ])

        func uint32(at offset: Int) -> Int {
            Int(bytes[offset]) << 24
                | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8
                | Int(bytes[offset + 3])
        }

        func uint64(at offset: Int) -> Int? {
            let value = bytes[offset..<offset + 8].reduce(UInt64.zero) { result, byte in
                (result << 8) | UInt64(byte)
            }
            return value <= UInt64(Int.max) ? Int(value) : nil
        }

        func contains(_ needle: [UInt8], in range: Range<Int>) -> Bool {
            guard !needle.isEmpty, range.count >= needle.count else { return false }
            for offset in range.lowerBound...(range.upperBound - needle.count) {
                if Array(bytes[offset..<offset + needle.count]) == needle {
                    return true
                }
            }
            return false
        }

        func findGaplessAtom(
                in start: Int,
                end: Int,
                ancestors: [Int] = []) -> (range: Range<Int>, ancestors: [Int])? {
            var offset = start
            while offset + 8 <= end {
                let size32 = uint32(at: offset)
                let type = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
                let headerSize: Int
                let atomSize: Int
                if size32 == 1 {
                    headerSize = 16
                    guard offset + headerSize <= end, let size64 = uint64(at: offset + 8) else {
                        return nil
                    }
                    atomSize = size64
                } else {
                    headerSize = 8
                    atomSize = size32 == 0 ? end - offset : size32
                }
                guard atomSize >= headerSize, offset + atomSize <= end else { return nil }

                let payloadStart = offset + headerSize
                let payloadEnd = offset + atomSize
                if (type == "----" || type == "itlk"),
                   contains(gaplessName, in: payloadStart..<payloadEnd) {
                    return (offset..<payloadEnd, ancestors)
                }
                if containerTypes.contains(type) {
                    let childStart = payloadStart + (type == "meta" ? 4 : 0)
                    if childStart <= payloadEnd,
                       let result = findGaplessAtom(
                            in: childStart,
                            end: payloadEnd,
                            ancestors: ancestors + [offset]) {
                        return result
                    }
                }
                offset += atomSize
            }
            return nil
        }

        guard let result = findGaplessAtom(in: 0, end: bytes.count), result.range.count >= 8 else {
            return
        }

        var outputBytes = bytes
        outputBytes.removeSubrange(result.range)
        for ancestor in result.ancestors {
            let size32 = uint32(at: ancestor)
            if size32 == 1 {
                guard let size64 = uint64(at: ancestor + 8) else { return }
                writeUInt64(
                    UInt64(size64 - result.range.count), at: ancestor + 8, to: &outputBytes
                )
            } else if size32 > 0 {
                writeUInt32(UInt32(size32 - result.range.count), at: ancestor, to: &outputBytes)
            }
        }
        try Data(outputBytes).write(to: url, options: .atomic)
    }

    private static func writeUInt32(_ value: UInt32, at offset: Int, to bytes: inout [UInt8]) {
        for index in 0..<4 {
            bytes[offset + index] = UInt8((value >> UInt32((3 - index) * 8)) & 0xff)
        }
    }

    private static func writeUInt64(_ value: UInt64, at offset: Int, to bytes: inout [UInt8]) {
        for index in 0..<8 {
            bytes[offset + index] = UInt8((value >> UInt64((7 - index) * 8)) & 0xff)
        }
    }
}
