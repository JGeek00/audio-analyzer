import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    @State private var isImporting = false
    @State private var isShowingImportError = false
    @State private var importErrorMessage = ""

    var body: some View {
        NavigationSplitView {
            TrackListView(
                tracks: model.tracks,
                selection: $model.selectedTrackID
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            WaveformView(track: model.selectedTrack)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import tracks", systemImage: "plus")
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
        .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                model.importTracks(from: urls)
            case .failure(let error):
                importErrorMessage = error.localizedDescription
                isShowingImportError = true
            }
        }
        .alert("Could not import tracks", isPresented: $isShowingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
    }
}

#Preview {
    WorkspaceView(model: WorkspaceModel())
        .frame(width: 1_100, height: 700)
}
