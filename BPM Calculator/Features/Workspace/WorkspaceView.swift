import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    @State private var isImporting = false
    @State private var isShowingImportError = false
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
                    isImporting = true
                } label: {
                    Label("Add tracks", systemImage: "plus")
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            TrackListView(
                tracks: model.tracks,
                selection: $model.selectedTrackID
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
