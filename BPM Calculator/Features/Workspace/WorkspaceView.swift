import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    @State private var isShowingImportError = false
    @State private var isShowingClearConfirmation = false
    @State private var isDropTargeted = false
    @State private var errorTitle = ""
    @State private var importErrorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            WaveformView(track: model.selectedTrack)
                .frame(maxWidth: .infinity)
                .frame(height: 200)

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
                    if model.hasUnsavedBPMValues {
                        isShowingClearConfirmation = true
                    } else {
                        model.clearTracks()
                    }
                } label: {
                    Label("Clear tracks", systemImage: "trash")
                }
                .disabled(model.tracks.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .alert("Clear tracks?", isPresented: $isShowingClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear tracks", role: .destructive) {
                    model.clearTracks()
                }
            } message: {
                Text("Some calculated or manually adjusted BPM values have not been saved to metadata. Are you sure you want to clear all tracks?")
            }

            TrackListView(
                tracks: model.tracks,
                selection: $model.selectedTrackID,
                onRemove: { model.removeTrack(id: $0) },
                onAdjustBPM: { trackID, adjustment in
                    model.adjustBPM(for: trackID, using: adjustment)
                },
                onSaveMetadata: saveMetadata(for:)
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
    }

    private func saveMetadata(for trackID: AudioTrack.ID) {
        Task {
            do {
                try await model.saveMetadata(for: trackID)
            } catch {
                errorTitle = "Could not save metadata"
                importErrorMessage = error.localizedDescription
                isShowingImportError = true
            }
        }
    }
}

#Preview {
    WorkspaceView(model: WorkspaceModel())
        .frame(width: 1_100, height: 700)
}
