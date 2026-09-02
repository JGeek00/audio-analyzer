import AVFoundation
import Combine
import SwiftUI

struct WaveformView: View {
    let track: AudioTrack?

    @State private var waveform: [WaveformPeak] = []
    @State private var player: AVAudioPlayer?
    @State private var loadedScopedURL: URL?
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = false
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var zoom = 32.0
    @AppStorage(AppStorageKeys.waveformDimming) private var waveformDimming = AppConfiguration.defaultWaveformDimming.rawValue
    @AppStorage(AppStorageKeys.showBeatMarkers) private var showBeatMarkers = AppConfiguration.defaultShowBeatMarkers

    private let progressTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            if let track {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(track.artist ?? track.url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(timeLabel(currentTime) + " / " + timeLabel(player?.duration ?? 0))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        togglePlayback()
                    } label: {
                        Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(player == nil)
                }

                if isLoading {
                    ProgressView("Loading waveform…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    ContentUnavailableView(
                        "Could not load waveform",
                        systemImage: "waveform.path",
                        description: Text(loadError)
                    )
                } else if waveform.isEmpty {
                    ContentUnavailableView(
                        "No waveform data",
                        systemImage: "waveform.path",
                        description: Text("The selected track has no readable audio frames.")
                    )
                } else {
                    WaveformEditorView(
                        waveform: waveform,
                        player: player,
                        isPlaying: isPlaying,
                        dimPlayed: shouldDimPlayed,
                        showBeatMarkers: showBeatMarkers,
                        beatPositions: beatPositions(for: track),
                        zoom: $zoom,
                        onSeek: seek(to:)
                    )
                }
            } else {
                ContentUnavailableView(
                    "Select a track",
                    systemImage: "waveform.path",
                    description: Text("Select a track to view its waveform.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
        .task(id: track?.id) {
            await load(track: track)
        }
        .onReceive(progressTimer) { _ in
            guard let player else { return }
            currentTime = player.currentTime
            if isPlaying && !player.isPlaying {
                isPlaying = false
            }
        }
        .onDisappear {
            unloadPlayer()
        }
    }

    private func load(track: AudioTrack?) async {
        unloadPlayer()
        waveform = []
        currentTime = 0
        zoom = 32
        loadError = nil
        isLoading = false

        guard let track else { return }
        isLoading = true

        do {
            let peaks = try await AudioFileDecoder().waveform(for: track.url)
            try Task.checkCancellation()
            waveform = peaks

            let hasSecurityScope = track.url.startAccessingSecurityScopedResource()
            do {
                let audioPlayer = try AVAudioPlayer(contentsOf: track.url)
                audioPlayer.prepareToPlay()
                player = audioPlayer
                loadedScopedURL = hasSecurityScope ? track.url : nil
                isLoading = false
            } catch {
                if hasSecurityScope {
                    track.url.stopAccessingSecurityScopedResource()
                }
                throw error
            }
        } catch is CancellationError {
            isLoading = false
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }

    private var shouldDimPlayed: Bool {
        (WaveformDimming(rawValue: waveformDimming) ?? AppConfiguration.defaultWaveformDimming).dimsPlayed
    }

    private func beatPositions(for track: AudioTrack) -> [Double] {
        guard let player,
              player.duration > 0,
              let analysis = track.analysis,
              analysis.sampleRate > 0 else { return [] }

        return analysis.rawBeatFrames.compactMap { frame in
            let position = frame / analysis.sampleRate / player.duration
            guard position.isFinite, position >= 0, position <= 1 else { return nil }
            return position
        }
    }

    private func unloadPlayer() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        if let loadedScopedURL {
            loadedScopedURL.stopAccessingSecurityScopedResource()
            self.loadedScopedURL = nil
        }
    }

    private func togglePlayback() {
        guard let player else { return }

        if player.isPlaying {
            player.pause()
            currentTime = player.currentTime
            isPlaying = false
        } else {
            if player.currentTime >= player.duration {
                player.currentTime = 0
                currentTime = 0
            }
            isPlaying = player.play()
        }
    }

    private func seek(to progress: Double) {
        guard let player, player.duration > 0 else { return }
        let clampedProgress = min(max(progress, 0), 1)
        player.currentTime = clampedProgress * player.duration
        currentTime = player.currentTime
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

#Preview {
    WaveformView(track: nil)
        .frame(width: 700, height: 200)
}
