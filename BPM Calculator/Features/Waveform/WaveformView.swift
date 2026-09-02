import SwiftUI

struct WaveformView: View {
    let track: AudioTrack?

    var body: some View {
        ContentUnavailableView(
            track == nil ? "Select a track" : "Waveform pending",
            systemImage: "waveform.path",
            description: Text(track == nil
                    ? "Select a track to view its waveform."
                    : "Waveform rendering is not available yet.")
        )
    }
}

#Preview {
    WaveformView(track: nil)
        .frame(width: 700, height: 200)
}
