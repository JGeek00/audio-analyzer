import AVFoundation
import Foundation

/// Streaming player with frame-accurate seeking.
///
/// ponytail: AVAudioPlayer cannot play OGG/Opus reliably (play() returns false
/// and seeking restarts from the beginning), so decode through AVAudioFile and
/// schedule the remaining PCM on a player node instead. Progress is derived
/// from the node's rendered sample count: scheduleSegment completions fire up
/// to ~1s before the tail actually renders, so they cannot drive the UI.
@MainActor
final class WaveformAudioPlayer {
    let duration: TimeInterval

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let file: AVAudioFile
    private let sampleRate: Double
    private let totalFrames: AVAudioFramePosition

    private var anchorFrame: AVAudioFramePosition = 0
    private var baseSample: (value: Double, rate: Double)?
    private var playing = false

    var isPlaying: Bool {
        playing && currentPositionFrames() < totalFrames
    }

    var currentTime: TimeInterval {
        get {
            guard sampleRate > 0 else { return 0 }
            return min(max(Double(currentPositionFrames()) / sampleRate, 0), duration)
        }
        set {
            seek(to: newValue / max(duration, .leastNonzeroMagnitude))
        }
    }

    init(contentsOf url: URL) throws {
        file = try AVAudioFile(forReading: url)
        sampleRate = file.processingFormat.sampleRate
        totalFrames = file.length
        duration = sampleRate > 0 ? Double(totalFrames) / sampleRate : 0
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
        try engine.start()
    }

    deinit {
        node.stop()
        engine.stop()
    }

    @discardableResult
    func play() -> Bool {
        if anchorFrame >= totalFrames {
            anchorFrame = 0
        }
        scheduleFromAnchor()
        node.play()
        baseSample = nodeSample()
        playing = true
        return true
    }

    func pause() {
        anchorFrame = currentPositionFrames()
        node.stop()
        baseSample = nil
        playing = false
    }

    func stop() {
        node.stop()
        baseSample = nil
        playing = false
        anchorFrame = 0
    }

    func seek(to progress: Double) {
        let clamped = min(max(progress, 0), 1)
        anchorFrame = min(AVAudioFramePosition(Double(totalFrames) * clamped), totalFrames)
        if playing {
            scheduleFromAnchor()
            node.play()
            baseSample = nodeSample()
        } else {
            baseSample = nil
        }
    }

    private func currentPositionFrames() -> AVAudioFramePosition {
        guard let baseSample, sampleRate > 0 else { return anchorFrame }
        guard let now = nodeSample() else { return anchorFrame }
        let rendered = (now.value - baseSample.value) * sampleRate / now.rate
        guard rendered > 0 else { return anchorFrame }
        return min(anchorFrame + AVAudioFramePosition(rendered), totalFrames)
    }

    private func nodeSample() -> (value: Double, rate: Double)? {
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else {
            return nil
        }
        return (Double(playerTime.sampleTime), playerTime.sampleRate)
    }

    private func scheduleFromAnchor() {
        node.stop()
        baseSample = nil
        let remaining = totalFrames - anchorFrame
        guard remaining > 0 else { return }
        node.scheduleSegment(
            file,
            startingFrame: anchorFrame,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionHandler: {}
        )
    }
}
