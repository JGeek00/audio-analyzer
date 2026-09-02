import SwiftUI

struct WaveformView: View {
    let track: AudioTrack?

    var body: some View {
        if let track {
            VStack(spacing: 20) {
                Label(track.title, systemImage: "waveform")
                    .font(.title2)
                    .lineLimit(1)

                if let analysis = track.analysis {
                    HStack(spacing: 32) {
                        metric(title: "BPM", value: analysis.hasDetectedBPM
                                ? analysis.bpm.formatted(.number.precision(.fractionLength(1)))
                                : "—")
                        metric(title: "First beat", value: analysis.firstBeatSeconds.map {
                            $0.formatted(.number.precision(.fractionLength(3))) + " s"
                        } ?? "—")
                        metric(title: "Sample rate", value: analysis.sampleRate.formatted() + " Hz")
                    }
                }

                ContentUnavailableView(
                    "Waveform pending",
                    systemImage: "waveform.path",
                    description: Text("BPM analysis is separate from waveform rendering.")
                )
            }
            .padding()
        } else {
            ContentUnavailableView(
                "Select a track",
                systemImage: "waveform",
                description: Text("Select a track to view its analysis.")
            )
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    WaveformView(track: nil)
        .frame(width: 700, height: 500)
}
