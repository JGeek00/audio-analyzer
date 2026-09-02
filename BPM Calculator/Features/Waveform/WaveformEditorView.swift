import AVFoundation
import SwiftUI

struct WaveformEditorView: View {
    let waveform: [WaveformPeak]
    let player: AVAudioPlayer?
    let isPlaying: Bool
    @Binding var zoom: Double
    let onSeek: (Double) -> Void

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { _ in
            let progress = livePlaybackProgress

            VStack(spacing: 8) {
                WaveformCanvas(
                    peaks: waveform,
                    visibleRange: zoomedRange(for: progress),
                    progress: progress,
                    accessibilityLabel: "Zoomed waveform",
                    onSeek: onSeek
                )
                .frame(maxWidth: .infinity)
                .frame(height: 116)
                .background(.black.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                WaveformCanvas(
                    peaks: waveform,
                    visibleRange: 0...1,
                    progress: progress,
                    accessibilityLabel: "Track overview",
                    onSeek: onSeek
                )
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(.black.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 8) {
                    Button {
                        zoom = max(4, zoom - 0.5)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .disabled(zoom <= 4)
                    .accessibilityLabel("Zoom out")

                    Slider(value: $zoom, in: 4...32, step: 0.5)
                        .frame(maxWidth: 220)
                        .accessibilityLabel("Waveform zoom")

                    Button {
                        zoom = min(32, zoom + 0.5)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .disabled(zoom >= 32)
                    .accessibilityLabel("Zoom in")

                    Text(String(format: "%.1f×", zoom))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
        }
    }

    private var livePlaybackProgress: Double {
        guard let player, player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }

    private func zoomedRange(for progress: Double) -> ClosedRange<Double> {
        let span = 1 / zoom
        let start = min(max(progress - span / 2, 0), 1 - span)
        return start...(start + span)
    }
}
