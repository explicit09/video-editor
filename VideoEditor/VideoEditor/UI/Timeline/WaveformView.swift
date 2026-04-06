import SwiftUI

/// Renders an audio waveform from amplitude data.
/// Draws a mirrored continuous waveform instead of a bar graph.
struct WaveformView: View {
    let amplitudes: [Float]
    var color: Color = Color(hex: 0x53E16F)
    var isSelected: Bool = false

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let sampled = sampledAmplitudes(maxSamples: max(Int(size.width / 3), 40))
                let count = sampled.count
                guard count > 1 else { return }

                let stepX = size.width / CGFloat(max(count - 1, 1))
                let midY = size.height / 2
                let verticalScale = midY * (isSelected ? 0.9 : 0.82)
                let topStrokeColor = color.opacity(isSelected ? 0.92 : 0.58)
                let bottomStrokeColor = color.opacity(isSelected ? 0.64 : 0.28)
                let fillLowOpacity = isSelected ? 0.18 : 0.08
                let fillMidOpacity = isSelected ? 0.56 : 0.3

                let points: [CGPoint] = sampled.enumerated().map { index, amplitude in
                    let normalized = max(CGFloat(amplitude), 0.02)
                    return CGPoint(x: CGFloat(index) * stepX, y: normalized * verticalScale)
                }

                var fillPath = Path()
                fillPath.move(to: CGPoint(x: 0, y: midY))

                for point in points {
                    fillPath.addLine(to: CGPoint(x: point.x, y: midY - point.y))
                }

                for point in points.reversed() {
                    fillPath.addLine(to: CGPoint(x: point.x, y: midY + point.y))
                }

                fillPath.closeSubpath()

                context.fill(
                    fillPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            color.opacity(fillLowOpacity),
                            color.opacity(fillMidOpacity),
                            color.opacity(fillLowOpacity),
                        ]),
                        startPoint: CGPoint(x: size.width / 2, y: 0),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)
                    )
                )

                var topStroke = Path()
                topStroke.move(to: CGPoint(x: 0, y: midY - points[0].y))
                for point in points.dropFirst() {
                    topStroke.addLine(to: CGPoint(x: point.x, y: midY - point.y))
                }

                var bottomStroke = Path()
                bottomStroke.move(to: CGPoint(x: 0, y: midY + points[0].y))
                for point in points.dropFirst() {
                    bottomStroke.addLine(to: CGPoint(x: point.x, y: midY + point.y))
                }

                context.stroke(topStroke, with: .color(topStrokeColor), lineWidth: isSelected ? 1.3 : 1.0)
                context.stroke(bottomStroke, with: .color(bottomStrokeColor), lineWidth: isSelected ? 1.0 : 0.8)

                let centerLine = Path(CGRect(x: 0, y: midY, width: size.width, height: 0.5))
                context.stroke(centerLine, with: .color(color.opacity(isSelected ? 0.24 : 0.12)), lineWidth: 0.5)
            }
        }
    }

    private func sampledAmplitudes(maxSamples: Int) -> [Float] {
        guard maxSamples > 0 else { return amplitudes }

        let reduced: [Float]
        if amplitudes.count > maxSamples {
            let bucketSize = Double(amplitudes.count) / Double(maxSamples)
            reduced = (0..<maxSamples).map { bucket in
                let start = Int(Double(bucket) * bucketSize)
                let end = min(Int(Double(bucket + 1) * bucketSize), amplitudes.count)
                let slice = amplitudes[start..<max(start + 1, end)]
                return slice.max() ?? 0
            }
        } else {
            reduced = amplitudes
        }

        guard reduced.count > 2 else { return reduced }

        return reduced.enumerated().map { index, amplitude in
            let previous = reduced[max(index - 1, 0)]
            let next = reduced[min(index + 1, reduced.count - 1)]
            return (previous + amplitude + next) / 3
        }
    }
}
