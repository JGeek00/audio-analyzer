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

    func saveMetadata(for trackID: AudioTrack.ID) async throws {
        guard let track = tracks.first(where: { $0.id == trackID }) else { return }
        guard track.analysisStatus == .completed,
              let analysis = track.analysis,
              analysis.hasDetectedBPM else {
            throw AudioMetadataWriterError.noDetectedBPM
        }
        try await AudioMetadataWriter().save(
            title: track.title,
            artist: track.artist,
            bpm: analysis.bpm,
            to: track.url
        )
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].persistedBPM = analysis.bpm
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
