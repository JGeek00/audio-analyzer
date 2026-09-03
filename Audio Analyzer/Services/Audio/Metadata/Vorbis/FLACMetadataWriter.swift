import Foundation

enum FLACMetadataWriter {
    static func write(
            to url: URL, bpm: Double?, key: String?, replayGain: ReplayGainTagRequest? = nil) throws {
        let input = [UInt8](try Data(contentsOf: url))
        guard input.count >= 4, Array(input[0..<4]) == Array("fLaC".utf8) else {
            throw AudioMetadataWriterError.unsupportedFileType("flac")
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
                payload = try VorbisCommentWriter.replacing(
                    in: payload,
                    bpm: bpm,
                    key: key,
                    replayGain: replayGain,
                    fileExtension: "flac"
                )
                hasVorbisComments = true
            }
            blocks.append((type, payload))
            isLast = header & 0x80 != 0
            offset = payloadEnd
        }

        if !hasVorbisComments {
            blocks.append((4, VorbisCommentWriter.newPayload(bpm: bpm, key: key, replayGain: replayGain)))
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
}
