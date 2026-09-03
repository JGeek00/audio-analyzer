import AVFoundation
import Foundation

final class AudioMetadataWriter {
    func save(
            bpm: Double? = nil,
            key: String? = nil,
            to url: URL,
            scope: TrackValueScope = .all) async throws {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        switch url.pathExtension.lowercased() {
        case "mp3":
            try writeID3Metadata(to: url, bpm: bpm, key: key)
            return
        case "aif", "aiff", "aifc":
            try writeAIFFMetadata(to: url, bpm: bpm, key: key)
            return
        case "flac":
            try writeFLACMetadata(to: url, bpm: bpm, key: key)
            return
        case "ogg", "oga", "opus":
            try writeOggMetadata(to: url, bpm: bpm, key: key)
            return
        default:
            break
        }

        let asset = AVURLAsset(url: url)
        let metadata: [AVMetadataItem]
        do {
            metadata = try await asset.load(.metadata)
        } catch {
            metadata = try await asset.load(.commonMetadata)
        }
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw AudioMetadataWriterError.exportSessionUnavailable
        }

        guard let fileType = fileType(for: url, supported: exportSession.supportedFileTypes) else {
            throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
        }

        let sourceHasGaplessMetadata = (try? Data(contentsOf: url))?.range(
            of: Data("iTunSMPB".utf8)
        ) != nil
        let keyIdentifier = keyIdentifier(for: fileType)
        let legacyMP4KeyIdentifier = AVMetadataIdentifier(rawValue: "itsk/%A9key")
        var outputMetadata = metadata
        if (scope == .all || scope == .bpm), let bpm {
            outputMetadata.removeAll { item in
                item.identifier == .id3MetadataBeatsPerMinute
                    || item.identifier == .iTunesMetadataBeatsPerMin
            }

            let bpmItem = AVMutableMetadataItem()
            bpmItem.identifier = fileType == .mp3
                    ? .id3MetadataBeatsPerMinute
                    : .iTunesMetadataBeatsPerMin
            bpmItem.value = NSNumber(value: bpm)
            outputMetadata.append(bpmItem)
        }

        if (scope == .all || scope == .key), let key {
            outputMetadata.removeAll { item in
                item.identifier == .id3MetadataInitialKey
                    || item.identifier == keyIdentifier
                    || item.identifier == legacyMP4KeyIdentifier
            }

            let keyItem = AVMutableMetadataItem()
            keyItem.identifier = keyIdentifier
            keyItem.value = key as NSString
            outputMetadata.append(keyItem)
        }
        exportSession.metadata = outputMetadata

        let replacementDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: url,
            create: true
        )
        let temporaryURL = replacementDirectory
                .appendingPathComponent(".metadata-\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: replacementDirectory) }

        try await exportSession.export(to: temporaryURL, as: fileType)
        if fileType == .wav, (scope == .all || scope == .key), let key {
            try writeWAVInitialKey(key, to: temporaryURL)
        }
        if (fileType == .m4a || fileType == .mp4), !sourceHasGaplessMetadata {
            try removeGeneratedGaplessMetadata(from: temporaryURL)
        }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } catch {
            throw AudioMetadataWriterError.replacementFailed(error.localizedDescription)
        }
    }

    private func writeID3Metadata(to url: URL, bpm: Double?, key: String?) throws {
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

        let tag = try makeID3Tag(
            existing: Array(input[0..<tagEnd]),
            bpm: bpm,
            key: key
        )
        try Data(tag + Array(input[tagEnd...])).write(to: url, options: .atomic)
    }

    private func makeID3Tag(existing: [UInt8], bpm: Double?, key: String?) throws -> [UInt8] {
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
                if !replacingBPM && !replacingKey {
                    frames.append(contentsOf: existing[offset..<frameEnd])
                }
                offset = frameEnd
            }
            existingBody = frames
        }

        func textFrame(_ id: String, value: String) -> [UInt8] {
            let encoding: UInt8 = version == 4 ? 3 : 0
            let payload = [encoding] + Array(value.utf8)
            var frame = Array(id.utf8)
            if version == 4 {
                frame.append(contentsOf: [
                    UInt8((payload.count >> 21) & 0x7f),
                    UInt8((payload.count >> 14) & 0x7f),
                    UInt8((payload.count >> 7) & 0x7f),
                    UInt8(payload.count & 0x7f)
                ])
            } else {
                let size = UInt32(payload.count)
                frame.append(contentsOf: [
                    UInt8((size >> 24) & 0xff),
                    UInt8((size >> 16) & 0xff),
                    UInt8((size >> 8) & 0xff),
                    UInt8(size & 0xff)
                ])
            }
            frame.append(contentsOf: [0, 0])
            frame.append(contentsOf: payload)
            return frame
        }

        var body = existingBody
        if let bpm {
            body.append(contentsOf: textFrame("TBPM", value: String(bpm)))
        }
        if let key {
            body.append(contentsOf: textFrame("TKEY", value: key))
        }

        var tag = Array("ID3".utf8) + [version, 0, 0]
        tag.append(contentsOf: [
            UInt8((body.count >> 21) & 0x7f),
            UInt8((body.count >> 14) & 0x7f),
            UInt8((body.count >> 7) & 0x7f),
            UInt8(body.count & 0x7f)
        ])
        tag.append(contentsOf: body)
        return tag
    }

    private func writeAIFFMetadata(to url: URL, bpm: Double?, key: String?) throws {
        let input = [UInt8](try Data(contentsOf: url))
        guard input.count >= 12,
              String(decoding: input[0..<4], as: UTF8.self) == "FORM",
              ["AIFF", "AIFC"].contains(String(decoding: input[8..<12], as: UTF8.self)) else {
            throw AudioMetadataWriterError.unsupportedFileType(url.pathExtension)
        }

        func uint32BE(at offset: Int, in bytes: [UInt8]) -> Int {
            Int(bytes[offset]) << 24
                | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8
                | Int(bytes[offset + 3])
        }

        func chunk(_ type: String, payload: [UInt8]) -> [UInt8] {
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
            payload: try makeID3Tag(existing: existingID3, bpm: bpm, key: key)
        ))
        let formSize = UInt32(output.count - 8)
        for index in 0..<4 {
            output[4 + index] = UInt8((formSize >> UInt32((3 - index) * 8)) & 0xff)
        }
        try Data(output).write(to: url, options: .atomic)
    }

    private func writeFLACMetadata(to url: URL, bpm: Double?, key: String?) throws {
        let input = [UInt8](try Data(contentsOf: url))
        guard input.count >= 4, Array(input[0..<4]) == Array("fLaC".utf8) else {
            throw AudioMetadataWriterError.unsupportedFileType("flac")
        }

        func uint32LE(at offset: Int, in bytes: [UInt8]) -> Int {
            Int(bytes[offset])
                | Int(bytes[offset + 1]) << 8
                | Int(bytes[offset + 2]) << 16
                | Int(bytes[offset + 3]) << 24
        }

        func littleEndian(_ value: Int) -> [UInt8] {
            [
                UInt8(value & 0xff),
                UInt8((value >> 8) & 0xff),
                UInt8((value >> 16) & 0xff),
                UInt8((value >> 24) & 0xff)
            ]
        }

        func commentBlock(
                from payload: [UInt8],
                bpm: Double?,
                key: String?) throws -> [UInt8] {
            guard payload.count >= 8 else {
                throw AudioMetadataWriterError.unsupportedFileType("flac")
            }
            let vendorLength = uint32LE(at: 0, in: payload)
            let vendorEnd = 4 + vendorLength
            guard vendorEnd + 4 <= payload.count else {
                throw AudioMetadataWriterError.unsupportedFileType("flac")
            }
            let commentCount = uint32LE(at: vendorEnd, in: payload)
            var offset = vendorEnd + 4
            var comments: [[UInt8]] = []
            for _ in 0..<commentCount {
                guard offset + 4 <= payload.count else {
                    throw AudioMetadataWriterError.unsupportedFileType("flac")
                }
                let length = uint32LE(at: offset, in: payload)
                let commentStart = offset + 4
                let commentEnd = commentStart + length
                guard commentEnd <= payload.count else {
                    throw AudioMetadataWriterError.unsupportedFileType("flac")
                }
                let comment = Array(payload[commentStart..<commentEnd])
                let name = String(decoding: comment, as: UTF8.self)
                    .split(separator: "=", maxSplits: 1)
                    .first?
                    .uppercased()
                let replacesBPM = bpm != nil && (name == "BPM" || name == "TEMPO")
                let replacesKey = key != nil && (name == "KEY" || name == "INITIALKEY")
                if !replacesBPM && !replacesKey {
                    comments.append(comment)
                }
                offset = commentEnd
            }
            guard offset == payload.count else {
                throw AudioMetadataWriterError.unsupportedFileType("flac")
            }

            if let bpm {
                comments.append(Array("BPM=\(bpm)".utf8))
            }
            if let key {
                comments.append(Array("KEY=\(key)".utf8))
            }

            var result = Array(payload[0..<vendorEnd])
            result.insert(contentsOf: littleEndian(comments.count), at: result.count)
            for comment in comments {
                result.append(contentsOf: littleEndian(comment.count))
                result.append(contentsOf: comment)
            }
            return result
        }

        var blocks: [(type: UInt8, payload: [UInt8])] = []
        var offset = 4
        var hasVorbisComments = false
        var isLast = false
        while !isLast {
            guard offset + 4 <= input.count else {
                throw AudioMetadataWriterError.unsupportedFileType("flac")
            }
            let header = input[offset]
            let type = header & 0x7f
            let size = Int(input[offset + 1]) << 16
                | Int(input[offset + 2]) << 8
                | Int(input[offset + 3])
            let payloadStart = offset + 4
            let payloadEnd = payloadStart + size
            guard payloadEnd <= input.count else {
                throw AudioMetadataWriterError.unsupportedFileType("flac")
            }
            var payload = Array(input[payloadStart..<payloadEnd])
            if type == 4 {
                payload = try commentBlock(from: payload, bpm: bpm, key: key)
                hasVorbisComments = true
            }
            blocks.append((type, payload))
            isLast = header & 0x80 != 0
            offset = payloadEnd
        }

        if !hasVorbisComments {
            var payload = littleEndian(Array("Audio Analyzer".utf8).count)
            payload.append(contentsOf: Array("Audio Analyzer".utf8))
            var comments: [[UInt8]] = []
            if let bpm { comments.append(Array("BPM=\(bpm)".utf8)) }
            if let key { comments.append(Array("KEY=\(key)".utf8)) }
            payload.append(contentsOf: littleEndian(comments.count))
            for comment in comments {
                payload.append(contentsOf: littleEndian(comment.count))
                payload.append(contentsOf: comment)
            }
            blocks.append((4, payload))
        }

        var output = Array("fLaC".utf8)
        for index in blocks.indices {
            let header = UInt8(index == blocks.index(before: blocks.endIndex) ? 0x80 : 0)
                | blocks[index].type
            let size = blocks[index].payload.count
            guard size <= 0xFF_FFFF else {
                throw AudioMetadataWriterError.unsupportedFileType("flac")
            }
            output.append(header)
            output.append(UInt8((size >> 16) & 0xff))
            output.append(UInt8((size >> 8) & 0xff))
            output.append(UInt8(size & 0xff))
            output.append(contentsOf: blocks[index].payload)
        }
        output.append(contentsOf: input[offset...])
        try Data(output).write(to: url, options: .atomic)
    }

    private func writeOggMetadata(to url: URL, bpm: Double?, key: String?) throws {
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
        let payload = try makeVorbisCommentPayload(
            from: Array(commentPacket[header.count...]),
            bpm: bpm,
            key: key
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

    private func makeVorbisCommentPayload(
            from payload: [UInt8], bpm: Double?, key: String?) throws -> [UInt8] {
        func uint32LE(at offset: Int) -> Int {
            Int(payload[offset])
                | Int(payload[offset + 1]) << 8
                | Int(payload[offset + 2]) << 16
                | Int(payload[offset + 3]) << 24
        }

        func littleEndian(_ value: Int) -> [UInt8] {
            [
                UInt8(value & 0xff),
                UInt8((value >> 8) & 0xff),
                UInt8((value >> 16) & 0xff),
                UInt8((value >> 24) & 0xff)
            ]
        }

        guard payload.count >= 8 else {
            throw AudioMetadataWriterError.unsupportedFileType("ogg")
        }
        let vendorLength = uint32LE(at: 0)
        let vendorEnd = 4 + vendorLength
        guard vendorEnd + 4 <= payload.count else {
            throw AudioMetadataWriterError.unsupportedFileType("ogg")
        }
        let commentCount = uint32LE(at: vendorEnd)
        var offset = vendorEnd + 4
        var comments: [[UInt8]] = []
        for _ in 0..<commentCount {
            guard offset + 4 <= payload.count else {
                throw AudioMetadataWriterError.unsupportedFileType("ogg")
            }
            let length = uint32LE(at: offset)
            let commentStart = offset + 4
            let commentEnd = commentStart + length
            guard commentEnd <= payload.count else {
                throw AudioMetadataWriterError.unsupportedFileType("ogg")
            }
            let comment = Array(payload[commentStart..<commentEnd])
            let name = String(decoding: comment, as: UTF8.self)
                .split(separator: "=", maxSplits: 1)
                .first?
                .uppercased()
            let replacesBPM = bpm != nil && (name == "BPM" || name == "TEMPO")
            let replacesKey = key != nil && (name == "KEY" || name == "INITIALKEY")
            if !replacesBPM && !replacesKey {
                comments.append(comment)
            }
            offset = commentEnd
        }
        guard offset == payload.count else {
            throw AudioMetadataWriterError.unsupportedFileType("ogg")
        }

        if let bpm { comments.append(Array("BPM=\(bpm)".utf8)) }
        if let key { comments.append(Array("KEY=\(key)".utf8)) }

        var result = Array(payload[0..<vendorEnd])
        result.append(contentsOf: littleEndian(comments.count))
        for comment in comments {
            result.append(contentsOf: littleEndian(comment.count))
            result.append(contentsOf: comment)
        }
        return result
    }

    private func oggCRC(_ page: [UInt8]) -> UInt32 {
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

    private func writeWAVInitialKey(_ key: String, to url: URL) throws {
        let input = [UInt8](try Data(contentsOf: url))
        guard input.count >= 12,
              String(decoding: input[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: input[8..<12], as: UTF8.self) == "WAVE" else {
            throw AudioMetadataWriterError.unsupportedFileType("wav")
        }

        func uint32LE(at offset: Int, in bytes: [UInt8]) -> Int {
            Int(bytes[offset])
                | Int(bytes[offset + 1]) << 8
                | Int(bytes[offset + 2]) << 16
                | Int(bytes[offset + 3]) << 24
        }

        func chunk(_ type: String, payload: [UInt8]) -> [UInt8] {
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

    private func keyIdentifier(for fileType: AVFileType) -> AVMetadataIdentifier {
        switch fileType {
        case .m4a, .mp4:
            return AVMetadataIdentifier(rawValue: "itlk/com.apple.iTunes.initialkey")
        case .wav:
            return AVMetadataIdentifier(rawValue: "caaf/IKEY")
        default:
            return .id3MetadataInitialKey
        }
    }

    private func removeGeneratedGaplessMetadata(from url: URL) throws {
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

    private func writeUInt32(_ value: UInt32, at offset: Int, to bytes: inout [UInt8]) {
        for index in 0..<4 {
            bytes[offset + index] = UInt8((value >> UInt32((3 - index) * 8)) & 0xff)
        }
    }

    private func writeUInt64(_ value: UInt64, at offset: Int, to bytes: inout [UInt8]) {
        for index in 0..<8 {
            bytes[offset + index] = UInt8((value >> UInt64((7 - index) * 8)) & 0xff)
        }
    }

    private func fileType(for url: URL, supported: [AVFileType]) -> AVFileType? {
        let candidate: AVFileType?
        switch url.pathExtension.lowercased() {
        case "aif", "aiff":
            candidate = .aiff
        case "aifc":
            candidate = .aifc
        case "caf":
            candidate = .caf
        case "m4a":
            candidate = .m4a
        case "mp3":
            candidate = .mp3
        case "mp4":
            candidate = .mp4
        case "wav":
            candidate = .wav
        default:
            candidate = nil
        }
        guard let candidate, supported.contains(candidate) else { return nil }
        return candidate
    }
}
