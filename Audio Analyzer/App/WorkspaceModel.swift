import Foundation
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class WorkspaceModel {
    var tracks: [AudioTrack] = []
    var selectedTrackID: AudioTrack.ID?
    var isImporting = false
    var autoSaveErrorMessage: String?

    private let analysisService = TrackAnalysisService()

    init() {
        observeReplayGainSettings()
    }

    var selectedTrack: AudioTrack? {
        tracks.first { $0.id == selectedTrackID }
    }

    var hasUnsavedBPMValues: Bool {
        tracks.contains(where: \.hasUnsavedBPM)
    }

    func canSaveMetadata(for scope: TrackValueScope) -> Bool {
        !tracks.isEmpty && tracks.allSatisfy { track in
            guard track.analysisStatus == .completed else { return false }
            switch scope {
            case .all:
                return track.analysis?.hasDetectedBPM == true || track.keyAnalysis?.hasDetectedKey == true
            case .bpm:
                return track.analysis?.hasDetectedBPM == true
            case .key:
                return track.keyAnalysis?.hasDetectedKey == true
            }
        }
    }

    private var isAutoSaveEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppStorageKeys.autoSave)
    }

    private func observeReplayGainSettings() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UserDefaults.didChangeNotification) {
                self?.refreshReplayGainGains()
            }
        }
    }

    private func refreshReplayGainGains() {
        let settings = ReplayGainSettings.current()
        for index in tracks.indices {
            guard let analysis = tracks[index].replayGainAnalysis,
                  analysis.hasDetectedGain else { continue }
            let updated = analysis.applying(settings, for: tracks[index].url)
            if updated != tracks[index].replayGainAnalysis {
                tracks[index].replayGainAnalysis = updated
            }
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
        saveAutomatically(for: trackID, scope: .bpm)
    }

    func saveMetadata(for trackID: AudioTrack.ID, scope: TrackValueScope = .all) async throws {
        guard let track = tracks.first(where: { $0.id == trackID }) else { return }
        guard track.analysisStatus == .completed else {
            throw AudioMetadataWriterError.noDetectedMetadata
        }

        let bpm = track.analysis?.hasDetectedBPM == true ? track.analysis?.bpm : nil
        let key = track.keyAnalysis?.hasDetectedKey == true ? track.keyAnalysis?.keyText : nil
        switch scope {
        case .all:
            guard bpm != nil || key != nil else {
                throw AudioMetadataWriterError.noDetectedMetadata
            }
        case .bpm:
            guard bpm != nil else {
                throw AudioMetadataWriterError.noDetectedBPM
            }
        case .key:
            guard key != nil else {
                throw AudioMetadataWriterError.noDetectedKey
            }
        }
        try await AudioMetadataWriter().save(
            bpm: bpm,
            key: key,
            to: track.url,
            scope: scope
        )
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        if scope == .all || scope == .bpm, let bpm {
            tracks[index].persistedBPM = bpm
        }
        if scope == .all || scope == .key, let key {
            tracks[index].persistedKey = key
        }
    }

    func saveMetadata(for scope: TrackValueScope) async throws {
        for trackID in tracks.map(\.id) {
            try await saveMetadata(for: trackID, scope: scope)
        }
    }

    private func saveAutomatically(for trackID: AudioTrack.ID, scope: TrackValueScope) {
        guard isAutoSaveEnabled,
              let track = tracks.first(where: { $0.id == trackID }),
              track.analysisStatus == .completed else { return }

        switch scope {
        case .all:
            guard track.analysis?.hasDetectedBPM == true || track.keyAnalysis?.hasDetectedKey == true else {
                return
            }
        case .bpm:
            guard track.analysis?.hasDetectedBPM == true else { return }
        case .key:
            guard track.keyAnalysis?.hasDetectedKey == true else { return }
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await saveMetadata(for: trackID, scope: scope)
            } catch {
                autoSaveErrorMessage = error.localizedDescription
            }
        }
    }

    func recalculate(for trackID: AudioTrack.ID, scope: TrackValueScope) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }),
              tracks[index].analysisStatus != .analyzing else { return }

        if scope == .all || scope == .bpm {
            tracks[index].hasManuallyAdjustedBPM = false
        }
        analyze(trackID: trackID, scope: scope)
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
            if tracks[index].persistedKey == nil {
                tracks[index].persistedKey = metadata.key
            }
        }
    }

    private func analyze(trackID: AudioTrack.ID, scope: TrackValueScope = .all) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let url = tracks[index].url
        tracks[index].analysisStatus = .analyzing

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await analysisService.analyze(url: url)
                guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
                switch scope {
                case .all:
                    tracks[index].analysis = result.bpm
                    tracks[index].keyAnalysis = result.key
                    tracks[index].replayGainAnalysis = result.replayGain
                case .bpm:
                    tracks[index].analysis = result.bpm
                case .key:
                    tracks[index].keyAnalysis = result.key
                }
                tracks[index].analysisStatus = .completed
                saveAutomatically(for: trackID, scope: scope)
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
