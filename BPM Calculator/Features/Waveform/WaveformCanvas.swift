import SwiftUI

struct WaveformCanvas: View {
    let peaks: [WaveformPeak]
    let visibleRange: ClosedRange<Double>
    let progress: Double
    let accessibilityLabel: String
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let width = max(size.width, 1)
                let height = max(size.height, 1)
                let span = max(visibleRange.upperBound - visibleRange.lowerBound, 0.0001)
                let lineCount = max(Int(width.rounded(.up)), 1)
                let peakCount = max(peaks.count - 1, 1)
                let center = height / 2
                let amplitude = center * 0.9
                let firstPeak = max(0, Int(visibleRange.lowerBound * Double(peakCount)))
                let lastPeak = min(peaks.count - 1, Int(ceil(visibleRange.upperBound * Double(peakCount))))
                let peakStride = max(
                    1,
                    Int(ceil(Double(peakCount) * span / Double(lineCount * 8)))
                )
                let firstDrawnPeak = max(0, firstPeak / peakStride * peakStride - peakStride)
                let lastDrawnPeak = min(
                    peaks.count - 1,
                    (lastPeak + peakStride - 1) / peakStride * peakStride
                )
                let colorBandCount = 18
                var playedPaths = Array(repeating: Path(), count: colorBandCount)
                var unplayedPaths = Array(repeating: Path(), count: colorBandCount)

                var centerLine = Path()
                centerLine.move(to: CGPoint(x: 0, y: center))
                centerLine.addLine(to: CGPoint(x: width, y: center))
                context.stroke(centerLine, with: .color(.white.opacity(0.12)), lineWidth: 1)

                for index in stride(from: firstDrawnPeak, through: lastDrawnPeak, by: peakStride) {
                    let position = Double(index) / Double(peakCount)
                    let peak = peaks[index]
                    let x = CGFloat((position - visibleRange.lowerBound) / span) * width
                    let top = center - CGFloat(max(-1, min(1, peak.max))) * amplitude
                    let bottom = center - CGFloat(max(-1, min(1, peak.min))) * amplitude

                    let band = min(
                        colorBandCount - 1,
                        Int(min(max(Double(peak.rms), 0), 1) * Double(colorBandCount))
                    )
                    if position <= progress {
                        playedPaths[band].move(to: CGPoint(x: x, y: top))
                        playedPaths[band].addLine(to: CGPoint(x: x, y: bottom))
                    } else {
                        unplayedPaths[band].move(to: CGPoint(x: x, y: top))
                        unplayedPaths[band].addLine(to: CGPoint(x: x, y: bottom))
                    }
                }

                let lineWidth = min(
                    max(width * CGFloat(peakStride) / (CGFloat(peakCount) * CGFloat(span)) * 0.72, 0.55),
                    1.25
                )
                for band in 0..<colorBandCount {
                    context.stroke(
                        playedPaths[band],
                        with: .color(peakColor(band: band, count: colorBandCount, played: true)),
                        lineWidth: lineWidth
                    )
                    context.stroke(
                        unplayedPaths[band],
                        with: .color(peakColor(band: band, count: colorBandCount, played: false)),
                        lineWidth: lineWidth
                    )
                }

                if progress >= visibleRange.lowerBound && progress <= visibleRange.upperBound {
                    let progressX = CGFloat((progress - visibleRange.lowerBound) / span) * width
                    context.fill(
                        Path(CGRect(x: progressX - 1, y: 0, width: 2, height: height)),
                        with: .color(.accentColor)
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                        onSeek(visibleRange.lowerBound + fraction * (visibleRange.upperBound - visibleRange.lowerBound))
                    }
            )
            .accessibilityRepresentation {
                Slider(
                    value: Binding(
                        get: { progress },
                        set: onSeek
                    ),
                    in: 0...1
                ) {
                    Text(accessibilityLabel)
                }
            }
        }
    }

    private func peakColor(band: Int, count: Int, played: Bool) -> Color {
        let loudness = (Double(band) + 0.5) / Double(count)
        var hue = (0.72 - loudness * 0.95).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return Color(
            hue: hue,
            saturation: played ? 0.9 : 0.76,
            brightness: played ? 0.98 : 0.72
        )
    }
}
