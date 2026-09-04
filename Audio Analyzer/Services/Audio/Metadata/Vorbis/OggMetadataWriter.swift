import Foundation

enum OggMetadataWriter {
    static func write(
            to url: URL, bpm: Double?, key: String?, replayGain: ReplayGainTagRequest? = nil) throws {
        let fileExtension = url.pathExtension
        let input = [UInt8](try Data(contentsOf: url))
        var pages: [[UInt8]] = []
        var offset = 0
        while offset < input.count {
            guard offset + 27 <= input.count,
                  Array(input[offset..<offset + 4]) == Array("OggS".utf8),
                  input[offset + 4] == 0 else {
                throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
            }
            let segmentCount = Int(input[offset + 26])
            let segmentTableEnd = offset + 27 + segmentCount
            guard segmentTableEnd <= input.count else {
                throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
            }
            let payloadSize = input[offset + 27..<segmentTableEnd]
                .reduce(0) { $0 + Int($1) }
            let pageEnd = segmentTableEnd + payloadSize
            guard pageEnd <= input.count else {
                throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
            }
            pages.append(Array(input[offset..<pageEnd]))
            offset = pageEnd
        }

        var packet: [UInt8] = []
        var packetStartPage = 0
        var packetStartSegment = 0
        var commentStartPage: Int?
        var commentStartSegment = 0
        var commentEndPage = 0
        var commentEndSegment = 0
        var commentPacket: [UInt8]?
        for pageIndex in pages.indices {
            let page = pages[pageIndex]
            let segmentCount = Int(page[26])
            var payloadOffset = 27 + segmentCount
            for segmentIndex in 0..<segmentCount {
                let segmentSize = Int(page[27 + segmentIndex])
                if packet.isEmpty {
                    packetStartPage = pageIndex
                    packetStartSegment = segmentIndex
                }
                packet.append(contentsOf: page[payloadOffset..<payloadOffset + segmentSize])
                payloadOffset += segmentSize
                if segmentSize < 255 {
                    let isVorbisComments = packet.starts(with: Array("OpusTags".utf8))
                        || packet.starts(with: [3] + Array("vorbis".utf8))
                    if commentStartPage == nil, isVorbisComments {
                        commentStartPage = packetStartPage
                        commentStartSegment = packetStartSegment
                        commentEndPage = pageIndex
                        commentEndSegment = segmentIndex
                        commentPacket = packet
                    }
                    packet.removeAll(keepingCapacity: true)
                }
            }
        }

        guard let commentStartPage, let commentPacket else {
            throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
        }
        let isOpus = commentPacket.starts(with: Array("OpusTags".utf8))
        let header: [UInt8] = isOpus ? Array("OpusTags".utf8) : [3] + Array("vorbis".utf8)
        var payload = Array(commentPacket[header.count...])
        // ponytail: Vorbis comment packets end with a framing byte that is not
        // part of the comment list; OpusTags has none.
        var framing: [UInt8] = []
        if !isOpus {
            // ponytail: zero padding follows the framing byte (mutagen).
            while payload.last == 0x00 {
                payload.removeLast()
            }
            guard payload.last == 0x01 else {
                throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
            }
            framing = [payload.removeLast()]
        }
        let replaced = try VorbisCommentWriter.replacing(
            in: payload,
            bpm: bpm,
            key: key,
            replayGain: replayGain,
            fileExtension: fileExtension
        )
        let newPacket = header + replaced + framing

        // ponytail: the comment may share pages with other packets (OpusHead
        // before it, Vorbis setup or audio after it) and may span several
        // pages (cover art); the page run is rebuilt preserving neighbors.
        let firstPage = pages[commentStartPage]
        let firstSegmentCount = Int(firstPage[26])
        let firstPayloadStart = 27 + firstSegmentCount
        let prefixSegments = Array(firstPage[27..<27 + commentStartSegment])
        let prefixLength = prefixSegments.reduce(0) { $0 + Int($1) }
        let prefixBytes = Array(firstPage[firstPayloadStart..<firstPayloadStart + prefixLength])

        let lastPage = pages[commentEndPage]
        let lastSegmentCount = Int(lastPage[26])
        let lastPayloadStart = 27 + lastSegmentCount
        let suffixSegments = Array(lastPage[27 + commentEndSegment + 1..<27 + lastSegmentCount])
        let suffixLength = suffixSegments.reduce(0) { $0 + Int($1) }
        let headLength = lastPage[27..<27 + commentEndSegment + 1].reduce(0) { $0 + Int($1) }
        let suffixStart = lastPayloadStart + headLength
        let suffixBytes = Array(lastPage[suffixStart..<suffixStart + suffixLength])

        let serial = Array(firstPage[14..<18])
        for page in pages[(commentEndPage + 1)...] {
            guard Array(page[14..<18]) == serial else {
                throw AudioMetadataWriterError.unsupportedFileType(fileExtension)
            }
        }

        var commentSegments: [UInt8] = []
        var packetOffset = 0
        while newPacket.count - packetOffset >= 255 {
            commentSegments.append(255)
            packetOffset += 255
        }
        commentSegments.append(UInt8(newPacket.count - packetOffset))

        let runSegments = prefixSegments + commentSegments + suffixSegments
        let runData = prefixBytes + newPacket + suffixBytes
        let suffixStartIndex = prefixSegments.count + commentSegments.count

        var chunks: [(segStart: Int, table: [UInt8], body: [UInt8])] = []
        var segmentIndex = 0
        var dataIndex = 0
        while segmentIndex < runSegments.count {
            var count = 0
            var length = 0
            while segmentIndex + count < runSegments.count, count < 255,
                  length + Int(runSegments[segmentIndex + count]) <= 65_025 {
                length += Int(runSegments[segmentIndex + count])
                count += 1
            }
            chunks.append((
                segStart: segmentIndex,
                table: Array(runSegments[segmentIndex..<segmentIndex + count]),
                body: Array(runData[dataIndex..<dataIndex + length])
            ))
            segmentIndex += count
            dataIndex += length
        }

        let firstSequence = UInt32(firstPage[18])
            | UInt32(firstPage[19]) << 8
            | UInt32(firstPage[20]) << 16
            | UInt32(firstPage[21]) << 24
        var rebuilt: [[UInt8]] = []
        for (pageNumber, chunk) in chunks.enumerated() {
            let isLast = pageNumber == chunks.count - 1
            let containsSuffix = chunk.segStart + chunk.table.count > suffixStartIndex
            var header: [UInt8]
            var flags: UInt8
            if pageNumber == 0 {
                header = Array(firstPage[0..<27])
                flags = firstPage[5]
            } else {
                header = Array("OggS".utf8) + [firstPage[4], 0]
                    + [UInt8](repeating: 0, count: 8) + serial
                    + [UInt8](repeating: 0, count: 9)
                // ponytail: a page starting mid-packet continues it, like
                // mutagen-written headers.
                flags = runSegments[chunk.segStart - 1] == 255 ? 0x01 : 0x00
            }
            if isLast {
                flags |= lastPage[5] & 0x04
            }
            let granule: [UInt8]
            if containsSuffix, isLast {
                granule = Array(lastPage[6..<14])
            } else if containsSuffix {
                granule = [UInt8](repeating: 0xff, count: 8)
            } else {
                granule = [UInt8](repeating: 0, count: 8)
            }
            let sequence = firstSequence &+ UInt32(pageNumber)
            header[5] = flags
            header.replaceSubrange(6..<14, with: granule)
            header[18] = UInt8(sequence & 0xff)
            header[19] = UInt8((sequence >> 8) & 0xff)
            header[20] = UInt8((sequence >> 16) & 0xff)
            header[21] = UInt8((sequence >> 24) & 0xff)
            header[22] = 0
            header[23] = 0
            header[24] = 0
            header[25] = 0
            header[26] = UInt8(chunk.table.count)
            var page = header + chunk.table + chunk.body
            let checksum = oggCRC(page)
            for index in 0..<4 {
                page[22 + index] = UInt8((checksum >> UInt32(index * 8)) & 0xff)
            }
            rebuilt.append(page)
        }

        pages.replaceSubrange(commentStartPage...commentEndPage, with: rebuilt)
        let delta = rebuilt.count - (commentEndPage - commentStartPage + 1)
        if delta != 0 {
            for index in (commentStartPage + rebuilt.count)..<pages.count {
                var page = pages[index]
                let sequence = UInt32(page[18])
                    | UInt32(page[19]) << 8
                    | UInt32(page[20]) << 16
                    | UInt32(page[21]) << 24
                let shifted = UInt32(truncatingIfNeeded: Int64(sequence) + Int64(delta))
                page[18] = UInt8(shifted & 0xff)
                page[19] = UInt8((shifted >> 8) & 0xff)
                page[20] = UInt8((shifted >> 16) & 0xff)
                page[21] = UInt8((shifted >> 24) & 0xff)
                page[22] = 0
                page[23] = 0
                page[24] = 0
                page[25] = 0
                let checksum = oggCRC(page)
                for byte in 0..<4 {
                    page[22 + byte] = UInt8((checksum >> UInt32(byte * 8)) & 0xff)
                }
                pages[index] = page
            }
        }

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
