import AppKit
import SwiftUI

struct TrackListView: View {
    let tracks: [AudioTrack]
    @Binding var selection: AudioTrack.ID?
    let onRemove: (AudioTrack.ID) -> Void
    let onAdjustBPM: (AudioTrack.ID, BPMAdjustment) -> Void
    let onSaveMetadata: (AudioTrack.ID) -> Void
    @State private var sortOrder: [KeyPathComparator<AudioTrack>] = []

    var body: some View {
        Table(sortedTracks, selection: $selection, sortOrder: $sortOrder) {
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
            .width(min: 48, ideal: 48, max: 48)

            TableColumn("Title", value: \.title)

            TableColumn("Artist", value: \.artistName) { track in
                Text(track.artist ?? "—")
                    .lineLimit(1)
            }

            TableColumn("Sample rate", value: \.sampleRateValue) { track in
                Text(sampleRate(for: track))
                    .monospacedDigit()
            }

            TableColumn("BPM", value: \.bpmValue) { track in
                HStack(spacing: 6) {
                    Text(bpm(for: track))
                        .monospacedDigit()

                    if track.hasUnsavedBPM && !track.hasManuallyAdjustedBPM {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("Calculated BPM differs from metadata")
                            .accessibilityLabel("Calculated BPM differs from metadata")
                    }

                    if track.hasManuallyAdjustedBPM {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.blue)
                            .help("BPM manually adjusted")
                            .accessibilityLabel("BPM manually adjusted")
                    }
                }
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
        .onDeleteCommand {
            if let selection {
                onRemove(selection)
            }
        }
        .contextMenu(forSelectionType: AudioTrack.ID.self) { selectedIDs in
            if let trackID = selectedIDs.first,
               let track = tracks.first(where: { $0.id == trackID }) {
                Section {
                    Button(role: .destructive) {
                        onRemove(trackID)
                    } label: {
                        Label("Remove", systemImage: "xmark")
                    }
                }
                Section {
                    Menu("Modificar BPM") {
                        ForEach(BPMAdjustment.allCases) { adjustment in
                            Button(adjustment.menuTitle(for: track.bpmValue)) {
                                onAdjustBPM(trackID, adjustment)
                            }
                        }
                    }
                    .disabled(track.analysisStatus != .completed || track.analysis?.hasDetectedBPM != true)
                }
                Section {
                    Button {
                        onSaveMetadata(trackID)
                    } label: {
                        Label("Save values to metadata", systemImage: "square.and.arrow.down")
                    }
                    .disabled(track.analysisStatus != .completed || track.analysis?.hasDetectedBPM != true)
                }
            }
        }
        .navigationTitle("Audio Analyzer")
    }

    private var sortedTracks: [AudioTrack] {
        tracks.sorted(using: sortOrder)
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
    TrackListView(
        tracks: [],
        selection: .constant(nil),
        onRemove: { _ in },
        onAdjustBPM: { _, _ in },
        onSaveMetadata: { _ in }
    )
        .frame(width: 900, height: 500)
}
