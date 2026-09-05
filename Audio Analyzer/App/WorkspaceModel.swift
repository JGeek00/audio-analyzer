import Foundation
import Observation

@Observable
@MainActor
final class WorkspaceModel {
    var tracks: [AudioTrack] = []
    var selectedTrackID: AudioTrack.ID?
    var isImporting = false
    var autoSaveErrorMessage: String?
    var unsupportedFormatMessage: String?

    // Open windows: the extra "Open with" instance dismisses itself (shared list).
    var openWindowCount = 0

    /// Registers an appearing window; returns true for extras.
    func registerWindow() -> Bool {
        openWindowCount += 1
        return openWindowCount > 1
    }

    func unregisterWindow() {
        openWindowCount = max(0, openWindowCount - 1)
    }

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

    var hasUnsavedReplayGainValues: Bool {
        tracks.contains(where: \.hasUnsavedReplayGain)
    }

    func canSaveMetadata(for scope: TrackValueScope) -> Bool {
        !tracks.isEmpty && tracks.allSatisfy { track in
            guard track.analysisStatus == .completed else { return false }
            switch scope {
            case .all:
                return track.analysis?.hasDetectedBPM == true || track.keyAnalysis?.hasDetectedKey == true
                    || track.replayGainAnalysis?.hasDetectedGain == true
            case .bpm:
                return track.analysis?.hasDetectedBPM == true
            case .key:
                return track.keyAnalysis?.hasDetectedKey == true
            case .replayGain:
                return track.replayGainAnalysis?.hasDetectedGain == true
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
        let unsavedReplayGainCount = tracks.filter(\.hasUnsavedReplayGain).count
        guard processingCount > 0 || unsavedBPMCount > 0 || unsavedReplayGainCount > 0 else { return nil }

        var messages: [String] = []
        if processingCount > 0 {
            messages.append(String(localized: "\(processingCount) track(s) are still being processed."))
        }
        if unsavedBPMCount > 0 {
            messages.append(String(localized: "\(unsavedBPMCount) track(s) have BPM values that are not saved in metadata."))
        }
        if unsavedReplayGainCount > 0 {
            messages.append(String(localized: "\(unsavedReplayGainCount) track(s) have ReplayGain values that are not saved in metadata."))
        }
        return messages.joined(separator: "\n")
    }

    func removeTrack(id: AudioTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }),
              !tracks[index].isSavingMetadata else { return }
        tracks.remove(at: index)
        if selectedTrackID == id {
            selectedTrackID = nil
        }
    }

    /// Removes every track except those currently saving metadata.
    /// - Returns: the number of saving tracks that were kept.
    @discardableResult
    func clearTracks() -> Int {
        let skipped = tracks.filter(\.isSavingMetadata).count
        tracks.removeAll { !$0.isSavingMetadata }
        if let selectedTrackID, !tracks.contains(where: { $0.id == selectedTrackID }) {
            self.selectedTrackID = nil
        }
        return skipped
    }

    func adjustBPM(for trackID: AudioTrack.ID, using adjustment: BPMAdjustment) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }),
              tracks[index].analysisStatus == .completed,
              !tracks[index].isSavingMetadata,
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
        guard !track.isSavingMetadata else { return }

        let bpm = track.analysis?.hasDetectedBPM == true ? track.analysis?.bpm : nil
        let key = track.keyAnalysis?.hasDetectedKey == true ? track.keyAnalysis?.keyText : nil
        // ponytail: re-apply current settings so saved tags match prefs even if
        // the analysis ran before the user changed target/clipping.
        let replayGainAnalysis = track.replayGainAnalysis?.hasDetectedGain == true
            ? track.replayGainAnalysis?.applying(ReplayGainSettings.current(), for: track.url)
            : nil
        let replayGain = replayGainAnalysis.flatMap {
            ReplayGainSettings.current().tagRequest(for: track.url, result: $0)
        }
        switch scope {
        case .all:
            guard bpm != nil || key != nil || replayGain != nil else {
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
        case .replayGain:
            guard replayGain != nil else {
                throw AudioMetadataWriterError.noDetectedReplayGain
            }
        }
        let url = track.url
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].isSavingMetadata = true
        tracks[index].saveProgress = 0
        tracks[index].showSaveConfirmation = false
        tracks[index].showSaveFailure = false
        defer {
            if let index = tracks.firstIndex(where: { $0.id == trackID }) {
                tracks[index].isSavingMetadata = false
                tracks[index].saveProgress = nil
            }
        }
        // ponytail: the write blocks for seconds on large Ogg files; keep it
        // off the main actor like analysis work.
        do {
            try await Task.detached(priority: .userInitiated) {
                try await AudioMetadataWriter().save(
                    bpm: bpm,
                    key: key,
                    replayGain: replayGain,
                    to: url,
                    scope: scope
                ) { progress in
                    Task { [weak self] in
                        await self?.setSaveProgress(progress, for: trackID)
                    }
                }
            }.value
            guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
            if scope == .all || scope == .bpm, let bpm {
                tracks[index].persistedBPM = bpm
            }
            if scope == .all || scope == .key, let key {
                tracks[index].persistedKey = key
            }
            if scope == .all || scope == .replayGain, let replayGainAnalysis {
                tracks[index].persistedReplayGain = replayGainAnalysis.gainDB
                tracks[index].replayGainAnalysis = replayGainAnalysis
            }
            flashSaveOutcome(for: trackID, success: true)
        } catch {
            flashSaveOutcome(for: trackID, success: false)
            throw error
        }
    }

    func saveMetadata(for scope: TrackValueScope) async throws {
        // ponytail: on error stop feeding but let in-flight saves finish; rethrow the first.
        let ids = tracks.map(\.id)
        let limit = AudioMetadataWriter.maxConcurrentWrites
        var iterator = ids.makeIterator()
        var firstError: Error?
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<limit {
                guard let trackID = iterator.next() else { break }
                group.addTask { @MainActor in
                    try await self.saveMetadata(for: trackID, scope: scope)
                }
            }
            while !group.isEmpty {
                do {
                    try await group.next()
                } catch {
                    if firstError == nil { firstError = error }
                }
                if firstError == nil, let trackID = iterator.next() {
                    group.addTask { @MainActor in
                        try await self.saveMetadata(for: trackID, scope: scope)
                    }
                }
            }
            if let firstError { throw firstError }
        }
    }

    private func saveAutomatically(for trackID: AudioTrack.ID, scope: TrackValueScope) {
        guard isAutoSaveEnabled,
              let track = tracks.first(where: { $0.id == trackID }),
              track.analysisStatus == .completed else { return }

        switch scope {
        case .all:
            guard track.analysis?.hasDetectedBPM == true || track.keyAnalysis?.hasDetectedKey == true
                || track.replayGainAnalysis?.hasDetectedGain == true else {
                return
            }
        case .bpm:
            guard track.analysis?.hasDetectedBPM == true else { return }
        case .key:
            guard track.keyAnalysis?.hasDetectedKey == true else { return }
        case .replayGain:
            guard track.replayGainAnalysis?.hasDetectedGain == true else { return }
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
              tracks[index].analysisStatus != .analyzing,
              !tracks[index].isSavingMetadata else { return }

        if scope == .all || scope == .bpm {
            tracks[index].hasManuallyAdjustedBPM = false
        }
        analyze(trackID: trackID, scope: scope)
    }

    func importTracks(from urls: [URL]) {
        var existingPaths = Set(
                tracks.map { $0.url.resolvingSymlinksInPath().standardizedFileURL.path })
        let unsupported = urls.filter {
            $0.isFileURL
                && !AppConfiguration.supportedAudioExtensions.contains($0.pathExtension.lowercased())
        }
        if !unsupported.isEmpty {
            let extensions = Set(unsupported.map { $0.pathExtension.lowercased() })
                .subtracting([""]).sorted()
            let detail = extensions.isEmpty
                ? ""
                : " (\(extensions.map { ".\($0)" }.joined(separator: ", ")))"
            unsupportedFormatMessage = String(
                localized: "\(unsupported.count) file(s) with an unsupported format\(detail) were skipped. Supported formats: MP3, FLAC, ALAC, OGG, Opus, WAV.")
        }
        let newURLs = urls.filter { url in
            guard url.isFileURL else { return false }
            guard AppConfiguration.supportedAudioExtensions.contains(url.pathExtension.lowercased()) else {
                return false
            }
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
            if tracks[index].persistedReplayGain == nil {
                tracks[index].persistedReplayGain = metadata.replayGain
            }
        }
    }

    private func analyze(trackID: AudioTrack.ID, scope: TrackValueScope = .all) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let url = tracks[index].url
        tracks[index].analysisStatus = .analyzing
        tracks[index].analysisProgress = 0

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await analysisService.analyze(url: url) { progress in
                    Task { [weak self] in
                        await self?.setAnalysisProgress(progress, for: trackID)
                    }
                }
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
                case .replayGain:
                    tracks[index].replayGainAnalysis = result.replayGain
                }
                tracks[index].analysisStatus = .completed
                tracks[index].analysisProgress = nil
                saveAutomatically(for: trackID, scope: scope)
            } catch is CancellationError {
                guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
                tracks[index].analysisStatus = .queued
                tracks[index].analysisProgress = nil
            } catch {
                guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
                tracks[index].analysisStatus = .failed(error.localizedDescription)
                tracks[index].analysisProgress = nil
            }
        }
    }

    private func flashSaveOutcome(for trackID: AudioTrack.ID, success: Bool) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].showSaveConfirmation = success
        tracks[index].showSaveFailure = !success
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self,
                  let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
            tracks[index].showSaveConfirmation = false
            tracks[index].showSaveFailure = false
        }
    }

    private func setSaveProgress(_ progress: Double, for trackID: AudioTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }),
              tracks[index].isSavingMetadata else { return }
        tracks[index].saveProgress = progress
    }

    private func setAnalysisProgress(_ progress: Double, for trackID: AudioTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }),
              tracks[index].analysisStatus == .analyzing else { return }
        tracks[index].analysisProgress = progress
    }
}
