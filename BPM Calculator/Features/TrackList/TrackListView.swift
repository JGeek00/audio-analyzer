import AppKit
import SwiftUI

struct TrackListView: View {
    let tracks: [AudioTrack]
    @Binding var selection: AudioTrack.ID?

    var body: some View {
        Table(tracks, selection: $selection) {
            TableColumn("Artwork") { track in
                if let artwork = track.artwork, let image = NSImage(data: artwork) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel("Artwork")
                } else {
                    Image(systemName: "music.note")
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Artwork unavailable")
                }
            }
            .width(min: 48, ideal: 64, max: 80)

            TableColumn("Title", value: \.title)

            TableColumn("Artist") { track in
                Text(track.artist ?? "—")
                    .lineLimit(1)
            }

            TableColumn("Sample rate") { track in
                Text(sampleRate(for: track))
                    .monospacedDigit()
            }

            TableColumn("BPM") { track in
                Text(bpm(for: track))
                    .monospacedDigit()
            }
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

    private func sampleRate(for track: AudioTrack) -> String {
        guard let sampleRate = track.analysis?.sampleRate else { return "—" }
        return sampleRate.formatted() + " Hz"
    }

    private func bpm(for track: AudioTrack) -> String {
        guard let analysis = track.analysis, analysis.hasDetectedBPM else { return "—" }
        return analysis.bpm.formatted(.number.precision(.fractionLength(1)))
    }
}

#Preview {
    TrackListView(tracks: [], selection: .constant(nil))
        .frame(width: 900, height: 500)
}
