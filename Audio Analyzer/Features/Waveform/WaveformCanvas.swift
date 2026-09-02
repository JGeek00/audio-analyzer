import SwiftUI

struct WaveformCanvas: View {
    let peaks: [WaveformPeak]
    let dimPlayed: Bool
    let amplitudeScale: Float
    let resolutionMultiplier: Int
    let beatPositions: [Double]
    let visibleRange: ClosedRange<Double>
    let progress: Double
    let accessibilityLabel: String
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            Canvas(rendersAsynchronously: true) { context, size in
                let width = max(size.width, 1)
                let height = max(size.height, 1)
                let span = max(visibleRange.upperBound - visibleRange.lowerBound, 0.0001)
                let lineCount = max(Int((width * CGFloat(resolutionMultiplier)).rounded(.up)), 1)
                let peakCount = max(peaks.count - 1, 1)
                let center = height / 2
                let amplitude = center * 0.9
                let firstPeak = max(0, Int(visibleRange.lowerBound * Double(peakCount)))
                let lastPeak = min(peaks.count - 1, Int(ceil(visibleRange.upperBound * Double(peakCount))))
                let peakStride = max(
                    1,
                    Int(ceil(Double(peakCount) * span / Double(lineCount)))
                )
                let firstDrawnPeak = max(0, firstPeak / peakStride * peakStride - peakStride)
                let lastDrawnPeak = min(
                    peaks.count - 1,
                    (lastPeak + peakStride - 1) / peakStride * peakStride
                )
                let colorBandCount = 18
                var dimmedPaths = Array(repeating: Path(), count: colorBandCount)
                var brightPaths = Array(repeating: Path(), count: colorBandCount)

                var centerLine = Path()
                centerLine.move(to: CGPoint(x: 0, y: center))
                centerLine.addLine(to: CGPoint(x: width, y: center))
                context.stroke(centerLine, with: .color(.white.opacity(0.12)), lineWidth: 1)

                for index in stride(from: firstDrawnPeak, through: lastDrawnPeak, by: peakStride) {
                    let position = Double(index) / Double(peakCount)
                    let peak = peaks[index]
                    let x = CGFloat((position - visibleRange.lowerBound) / span) * width
                    let level = CGFloat(min(max(peak.rms / amplitudeScale, 0), 1))
                    let top = center - level * amplitude
                    let bottom = center + level * amplitude

                    let band = min(
                        colorBandCount - 1,
                        Int(min(max(Double(peak.rms), 0), 1) * Double(colorBandCount))
                    )
                    let isDimmed = (position <= progress) == dimPlayed
                    if isDimmed {
                        dimmedPaths[band].move(to: CGPoint(x: x, y: top))
                        dimmedPaths[band].addLine(to: CGPoint(x: x, y: bottom))
                    } else {
                        brightPaths[band].move(to: CGPoint(x: x, y: top))
                        brightPaths[band].addLine(to: CGPoint(x: x, y: bottom))
                    }
                }

                let lineWidth = min(
                    max(width * CGFloat(peakStride) / (CGFloat(peakCount) * CGFloat(span)) * 0.72, 0.55),
                    1.25
                )
                for band in 0..<colorBandCount {
                    context.stroke(
                        dimmedPaths[band],
                        with: .color(peakColor(band: band, count: colorBandCount, dimmed: true)),
                        lineWidth: lineWidth
                    )
                    context.stroke(
                        brightPaths[band],
                        with: .color(peakColor(band: band, count: colorBandCount, dimmed: false)),
                        lineWidth: lineWidth
                    )
                }

                for beatPosition in beatPositions {
                    guard beatPosition >= visibleRange.lowerBound,
                          beatPosition <= visibleRange.upperBound else { continue }
                    let beatX = CGFloat((beatPosition - visibleRange.lowerBound) / span) * width
                    var beatLine = Path()
                    beatLine.move(to: CGPoint(x: beatX, y: 0))
                    beatLine.addLine(to: CGPoint(x: beatX, y: height))
                    context.stroke(beatLine, with: .color(.white.opacity(0.72)), lineWidth: 2)
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

    private func peakColor(band: Int, count: Int, dimmed: Bool) -> Color {
        let loudness = (Double(band) + 0.5) / Double(count)
        var hue = (0.72 - loudness * 0.95).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return Color(
            hue: hue,
            saturation: dimmed ? 0.76 : 0.9,
            brightness: dimmed ? 0.72 : 0.98
        )
    }
}
