import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    @State private var isShowingImportError = false
    @State private var isShowingClearConfirmation = false
    @State private var isShowingClearSkippedNotice = false
    @State private var clearSkippedCount = 0
    @State private var isDropTargeted = false
    @State private var errorTitle = ""
    @State private var importErrorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            WaveformView(track: model.selectedTrack)
                .frame(maxWidth: .infinity)
                .frame(height: 260)

            Divider()

            HStack {
                Text("Tracks")
                    .font(.headline)

                Spacer()

                Button {
                    model.isImporting = true
                } label: {
                    Label("Add tracks", systemImage: "plus")
                }

                Button(role: .destructive) {
                    if model.hasUnsavedBPMValues || model.hasUnsavedReplayGainValues {
                        isShowingClearConfirmation = true
                    } else {
                        clearTracks()
                    }
                } label: {
                    Label("Clear tracks", systemImage: "trash")
                }
                .disabled(model.tracks.isEmpty)

                Divider()
                    .frame(height: 20)

                Menu {
                    Section {
                        Button(TrackValueScope.all.rawValue) {
                            saveMetadata(for: .all)
                        }
                    }
                    Section {
                        Button(TrackValueScope.bpm.rawValue) {
                            saveMetadata(for: .bpm)
                        }
                        .disabled(!model.canSaveMetadata(for: .bpm))
                        Button(TrackValueScope.key.rawValue) {
                            saveMetadata(for: .key)
                        }
                        .disabled(!model.canSaveMetadata(for: .key))
                        Button(TrackValueScope.replayGain.rawValue) {
                            saveMetadata(for: .replayGain)
                        }
                        .disabled(!model.canSaveMetadata(for: .replayGain))
                    }
                } label: {
                    Label("Save...", systemImage: "square.and.arrow.down")
                }
                .disabled(!model.canSaveMetadata(for: .all))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .alert("Clear tracks?", isPresented: $isShowingClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear tracks", role: .destructive) {
                    clearTracks()
                }
            } message: {
                Text("Some calculated BPM or ReplayGain values have not been saved to metadata. Are you sure you want to clear all tracks?")
            }
            .alert("Clear tracks", isPresented: $isShowingClearSkippedNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(clearSkippedCount) track(s) are currently saving metadata and were kept in the list.")
            }

            TrackListView(
                tracks: model.tracks,
                selection: $model.selectedTrackID,
                onRemove: { model.removeTrack(id: $0) },
                onAdjustBPM: { trackID, adjustment in
                    model.adjustBPM(for: trackID, using: adjustment)
                },
                onSaveMetadata: { trackID, scope in
                    saveMetadata(for: trackID, scope: scope)
                },
                onRecalculate: { trackID, scope in
                    model.recalculate(for: trackID, scope: scope)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dropDestination(for: URL.self) { urls, _ in
                model.importTracks(from: urls)
                return true
            } isTargeted: {
                isDropTargeted = $0
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.tint, lineWidth: 2)
                        .padding(2)
                        .allowsHitTesting(false)
                }
            }
        }
        .background {
            MainWindowAccessor(model: model)
                .frame(width: 0, height: 0)
        }
        .fileImporter(
                isPresented: $model.isImporting,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                model.importTracks(from: urls)
            case .failure(let error):
                errorTitle = "Could not import tracks"
                importErrorMessage = error.localizedDescription
                isShowingImportError = true
            }
        }
        .alert(errorTitle, isPresented: $isShowingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
        .onChange(of: model.autoSaveErrorMessage) { _, message in
            guard let message else { return }
            errorTitle = "Could not save metadata"
            importErrorMessage = message
            isShowingImportError = true
            model.autoSaveErrorMessage = nil
        }
    }

    private func clearTracks() {
        let skipped = model.clearTracks()
        if skipped > 0 {
            clearSkippedCount = skipped
            isShowingClearSkippedNotice = true
        }
    }

    private func saveMetadata(for trackID: AudioTrack.ID, scope: TrackValueScope) {
        Task {
            do {
                try await model.saveMetadata(for: trackID, scope: scope)
            } catch {
                showSaveError(error)
            }
        }
    }

    private func saveMetadata(for scope: TrackValueScope) {
        Task {
            do {
                try await model.saveMetadata(for: scope)
            } catch {
                showSaveError(error)
            }
        }
    }

    private func showSaveError(_ error: Error) {
        errorTitle = "Could not save metadata"
        importErrorMessage = error.localizedDescription
        isShowingImportError = true
    }
}

#Preview {
    WorkspaceView(model: WorkspaceModel())
        .frame(width: 1_100, height: 700)
}
