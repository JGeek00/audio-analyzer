import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class WorkspaceModel {
    var tracks: [AudioTrack] = []
    var selectedTrackID: AudioTrack.ID?
    var isImporting = false

    private let analysisService = TrackAnalysisService()

    var selectedTrack: AudioTrack? {
        tracks.first { $0.id == selectedTrackID }
    }

    var hasUnsavedBPMValues: Bool {
        tracks.contains(where: \.hasUnsavedBPM)
    }

    var canSaveMetadata: Bool {
        !tracks.isEmpty && tracks.allSatisfy {
            $0.analysisStatus == .completed && $0.analysis?.hasDetectedBPM == true
        }
    }

    var closeWarningMessage: String? {
        let processingCount = tracks.filter(\.isProcessing).count
        let unsavedBPMCount = tracks.filter(\.hasUnsavedBPM).count
        guard processingCount > 0 || unsavedBPMCount > 0 else { return nil }

        var messages: [String] = []
        if processingCount > 0 {
            messages.append("\(processingCount) track(s) are still being processed.")
        }
        if unsavedBPMCount > 0 {
            messages.append("\(unsavedBPMCount) track(s) have BPM values that are not saved in metadata.")
        }
        return messages.joined(separator: "\n")
    }

    func removeTrack(id: AudioTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks.remove(at: index)
        if selectedTrackID == id {
            selectedTrackID = nil
        }
    }

    func clearTracks() {
        tracks.removeAll()
        selectedTrackID = nil
    }

    func adjustBPM(for trackID: AudioTrack.ID, using adjustment: BPMAdjustment) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }),
              tracks[index].analysisStatus == .completed,
              let analysis = tracks[index].analysis,
              analysis.hasDetectedBPM else { return }

        tracks[index].analysis = BPMAnalysisResult(
            bpm: analysis.bpm * adjustment.multiplier,
            firstBeatFrame: analysis.firstBeatFrame,
            sampleRate: analysis.sampleRate,
            rawBeatFrames: analysis.rawBeatFrames
        )
        tracks[index].hasManuallyAdjustedBPM = true
    }

    func saveMetadata(for trackID: AudioTrack.ID, scope: TrackValueScope = .all) async throws {
        guard let track = tracks.first(where: { $0.id == trackID }) else { return }
        guard track.analysisStatus == .completed,
              let analysis = track.analysis,
              analysis.hasDetectedBPM else {
            throw AudioMetadataWriterError.noDetectedBPM
        }
        try await AudioMetadataWriter().save(
            bpm: analysis.bpm,
            to: track.url,
            scope: scope
        )
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].persistedBPM = analysis.bpm
    }

    func saveMetadata(for scope: TrackValueScope) async throws {
        for trackID in tracks.map(\.id) {
            try await saveMetadata(for: trackID, scope: scope)
        }
    }

    func recalculate(for trackID: AudioTrack.ID, scope: TrackValueScope) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }),
              tracks[index].analysisStatus != .analyzing else { return }

        // ponytail: BPM is the only calculation today; both scopes share the existing analyzer.
        tracks[index].hasManuallyAdjustedBPM = false
        switch scope {
        case .all, .bpm:
            analyze(trackID: trackID)
        }
    }

    func importTracks(from urls: [URL]) {
        var existingPaths = Set(
                tracks.map { $0.url.resolvingSymlinksInPath().standardizedFileURL.path })
        let newURLs = urls.filter { url in
            guard url.isFileURL else { return false }
            guard let contentType = UTType(filenameExtension: url.pathExtension),
                  contentType.conforms(to: .audio) else { return false }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard existingPaths.insert(path).inserted else { return false }
            return true
        }
        guard !newURLs.isEmpty else { return }

        let newTracks = newURLs.map { AudioTrack(url: $0) }
        tracks.append(contentsOf: newTracks)
        if selectedTrackID == nil {
            selectedTrackID = newTracks.first?.id
        }

        for track in newTracks {
            analyze(trackID: track.id)
            loadMetadata(trackID: track.id)
        }
    }

    private func loadMetadata(trackID: AudioTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let url = tracks[index].url

        Task { [weak self] in
            let metadata = await AudioFileDecoder().metadata(for: url)
            guard let self,
                  let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
            tracks[index].metadataTitle = metadata.title
            tracks[index].artist = metadata.artist
            tracks[index].artwork = metadata.artwork
            if tracks[index].persistedBPM == nil {
                tracks[index].persistedBPM = metadata.bpm
            }
        }
    }

    private func analyze(trackID: AudioTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let url = tracks[index].url
        tracks[index].analysisStatus = .analyzing

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await analysisService.analyze(url: url)
                guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
                tracks[index].analysis = result
                tracks[index].analysisStatus = .completed
            } catch is CancellationError {
                guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
                tracks[index].analysisStatus = .queued
            } catch {
                guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
                tracks[index].analysisStatus = .failed(error.localizedDescription)
            }
        }
    }
}
