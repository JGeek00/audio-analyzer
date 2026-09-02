import SwiftUI

struct TrackListView: View {
    let tracks: [AudioTrack]
    @Binding var selection: AudioTrack.ID?

    var body: some View {
        List(tracks, selection: $selection) { track in
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .lineLimit(1)

                Text(detail(for: track))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .tag(track.id)
        }
        .overlay {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "No tracks",
                    systemImage: "music.note.list",
                    description: Text("Use + to import audio files.")
                )
            }
        }
        .navigationTitle("Tracks")
    }

    private func detail(for track: AudioTrack) -> String {
        switch track.analysisStatus {
        case .queued:
            return "Queued"
        case .analyzing:
            return "Analyzing…"
        case .completed:
            guard let analysis = track.analysis, analysis.hasDetectedBPM else {
                return "BPM not detected"
            }
            return "\(analysis.bpm.formatted(.number.precision(.fractionLength(1)))) BPM"
        case .failed(let message):
            return "Error: \(message)"
        }
    }
}

#Preview {
    TrackListView(tracks: [], selection: .constant(nil))
        .frame(width: 300, height: 500)
}
