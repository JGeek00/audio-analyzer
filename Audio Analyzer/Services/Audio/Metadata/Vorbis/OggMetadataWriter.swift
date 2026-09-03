import Foundation

enum OggMetadataWriter {
    static func write(to url: URL, bpm: Double?, key: String?) throws {
        let input = [UInt8](try Data(contentsOf: url))
        var pages: [[UInt8]] = []
        var packet: [UInt8] = []
        var packetStartPage = 0
        var packetStartSegment = 0
        var commentPageIndex: Int?
        var commentPacket: [UInt8]?
        var offset = 0

        while offset < input.count {
            guard offset + 27 <= input.count,
                  Array(input[offset..<offset + 4]) == Array("OggS".utf8),
                  input[offset + 4] == 0 else {
                throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
            }
            let segmentCount = Int(input[offset + 26])
            let segmentTableEnd = offset + 27 + segmentCount
            guard segmentTableEnd <= input.count else {
                throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
            }
            let payloadSize = input[offset + 27..<segmentTableEnd]
                .reduce(0) { $0 + Int($1) }
            let pageEnd = segmentTableEnd + payloadSize
            guard pageEnd <= input.count else {
                throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
            }

            let pageIndex = pages.count
            pages.append(Array(input[offset..<pageEnd]))
            var payloadOffset = segmentTableEnd
            for segmentIndex in 0..<segmentCount {
                let segmentSize = Int(input[offset + 27 + segmentIndex])
                if packet.isEmpty {
                    packetStartPage = pageIndex
                    packetStartSegment = segmentIndex
                }
                packet.append(contentsOf: input[payloadOffset..<payloadOffset + segmentSize])
                payloadOffset += segmentSize

                if segmentSize < 255 {
                    let isVorbisComments = packet.starts(with: Array("OpusTags".utf8))
                        || packet.starts(with: [3] + Array("vorbis".utf8))
                    if commentPageIndex == nil, isVorbisComments {
                        // ponytail: only rewrite a comment packet contained in one page.
                        guard packetStartPage == pageIndex,
                              packetStartSegment == 0,
                              segmentIndex == segmentCount - 1 else {
                            throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
                        }
                        commentPageIndex = pageIndex
                        commentPacket = packet
                    }
                    packet.removeAll(keepingCapacity: true)
                }
            }
            offset = pageEnd
        }

        guard let commentPageIndex, let commentPacket else {
            throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
        }
        let header: [UInt8]
        if commentPacket.starts(with: Array("OpusTags".utf8)) {
            header = Array("OpusTags".utf8)
        } else {
            header = [3] + Array("vorbis".utf8)
        }
        let payload = try VorbisCommentWriter.replacing(
            in: Array(commentPacket[header.count...]),
            bpm: bpm,
            key: key,
            fileExtension: "ogg"
        )
        let newPacket = header + payload
        guard newPacket.count <= 255 * 255 else {
            throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
        }

        var segments: [UInt8] = []
        var payloadOffset = 0
        while newPacket.count - payloadOffset >= 255 {
            segments.append(255)
            payloadOffset += 255
        }
        segments.append(UInt8(newPacket.count - payloadOffset))
        guard segments.count <= 255 else {
            throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
        }

        var page = Array(pages[commentPageIndex][0..<27])
        page[26] = UInt8(segments.count)
        page.append(contentsOf: segments)
        page.append(contentsOf: newPacket)
        page[22] = 0
        page[23] = 0
        page[24] = 0
        page[25] = 0
        let checksum = oggCRC(page)
        for index in 0..<4 {
            page[22 + index] = UInt8((checksum >> UInt32(index * 8)) & 0xff)
        }
        pages[commentPageIndex] = page

        var output: [UInt8] = []
        for page in pages {
            output.append(contentsOf: page)
        }
        try Data(output).write(to: url, options: .atomic)
    }

    private static func oggCRC(_ page: [UInt8]) -> UInt32 {
        var checksum: UInt32 = 0
        for byte in page {
            checksum ^= UInt32(byte) << 24
            for _ in 0..<8 {
                checksum = checksum & 0x8000_0000 == 0
                    ? checksum << 1
                    : (checksum << 1) ^ 0x04C1_1DB7
            }
        }
        return checksum
    }
}
