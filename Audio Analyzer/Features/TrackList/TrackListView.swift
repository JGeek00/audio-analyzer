import AppKit
import SwiftUI

struct TrackListView: View {
    let tracks: [AudioTrack]
    @Binding var selection: AudioTrack.ID?
    let onRemove: (AudioTrack.ID) -> Void
    let onAdjustBPM: (AudioTrack.ID, BPMAdjustment) -> Void
    let onSaveMetadata: (AudioTrack.ID, TrackValueScope) -> Void
    let onRecalculate: (AudioTrack.ID, TrackValueScope) -> Void
    @State private var sortOrder: [KeyPathComparator<AudioTrack>] = []

    var body: some View {
        Table(sortedTracks, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Artwork") { track in
                ZStack {
                    if let artwork = track.artwork, let image = NSImage(data: artwork) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .accessibilityLabel("Artwork")
                    } else {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Artwork unavailable")
                    }

                    if track.isProcessing {
                        Rectangle()
                            .fill(.black.opacity(0.75))
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .accessibilityLabel("Analyzing track")
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4))
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
                    MetadataValueView(
                        persistedValue: track.persistedBPM,
                        calculatedValue: track.analysis?.hasDetectedBPM == true
                                ? track.analysis?.bpm
                                : nil,
                        hasConflict: track.hasPersistedBPMConflict,
                        format: bpmLabel
                    )
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

            TableColumn("Key", value: \.keyValue) { track in
                HStack(spacing: 6) {
                    MetadataValueView(
                        persistedValue: track.persistedKey,
                        calculatedValue: track.keyAnalysis?.hasDetectedKey == true
                                ? track.keyAnalysis?.keyText
                                : nil,
                        hasConflict: track.hasPersistedKeyConflict,
                        format: { $0 }
                    )

                    if track.hasPersistedKeyConflict {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("Calculated key differs from metadata")
                            .accessibilityLabel("Calculated key differs from metadata")
                    }
                }
            }

            TableColumn("ReplayGain", value: \.replayGainValue) { track in
                HStack(spacing: 6) {
                    MetadataValueView(
                        persistedValue: track.persistedReplayGain,
                        calculatedValue: track.replayGainAnalysis?.hasDetectedGain == true
                                ? track.replayGainAnalysis?.gainDB
                                : nil,
                        hasConflict: track.hasPersistedReplayGainConflict,
                        format: replayGainLabel
                    )
                    .monospacedDigit()

                    if track.hasUnsavedReplayGain {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("Calculated ReplayGain differs from metadata")
                            .accessibilityLabel("Calculated ReplayGain differs from metadata")
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
                    Menu {
                        Section {
                            Button(TrackValueScope.all.rawValue) {
                                onRecalculate(trackID, .all)
                            }
                        }
                        Section {
                            Button(TrackValueScope.bpm.rawValue) {
                                onRecalculate(trackID, .bpm)
                            }
                            Button(TrackValueScope.key.rawValue) {
                                onRecalculate(trackID, .key)
                            }
                            Button(TrackValueScope.replayGain.rawValue) {
                                onRecalculate(trackID, .replayGain)
                            }
                        }
                    } label: {
                        Label("Recalculate...", systemImage: "arrow.circlepath")
                    }
                    .disabled(track.analysisStatus == .analyzing)
                    Menu {
                        Section {
                            Button(TrackValueScope.all.rawValue) {
                                onSaveMetadata(trackID, .all)
                            }
                        }
                        Section {
                            Button(TrackValueScope.bpm.rawValue) {
                                onSaveMetadata(trackID, .bpm)
                            }
                            .disabled(track.analysis?.hasDetectedBPM != true)
                            Button(TrackValueScope.key.rawValue) {
                                onSaveMetadata(trackID, .key)
                            }
                            .disabled(track.keyAnalysis?.hasDetectedKey != true)
                            Button(TrackValueScope.replayGain.rawValue) {
                                onSaveMetadata(trackID, .replayGain)
                            }
                            .disabled(track.replayGainAnalysis?.hasDetectedGain != true)
                        }
                    } label: {
                        Label("Save metadata values...", systemImage: "square.and.arrow.down")
                    }
                    .disabled(
                        track.analysisStatus != .completed
                            || (track.analysis?.hasDetectedBPM != true
                                && track.keyAnalysis?.hasDetectedKey != true
                                && track.replayGainAnalysis?.hasDetectedGain != true))
                }
                Section {
                    Button(role: .destructive) {
                        onRemove(trackID)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
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

    private func bpmLabel(_ bpm: Double) -> String {
        bpm.formatted(.number.precision(.fractionLength(1)))
    }

    private func replayGainLabel(_ gainDB: Double) -> String {
        String(format: "%+.2f dB", gainDB)
    }
}

#Preview {
    TrackListView(
        tracks: [],
        selection: .constant(nil),
        onRemove: { _ in },
        onAdjustBPM: { _, _ in },
        onSaveMetadata: { _, _ in },
        onRecalculate: { _, _ in }
    )
        .frame(width: 900, height: 500)
}
