import SwiftUI

/// Renders an audio waveform from amplitude data.
/// Draws a mirrored bar visualization — peaks up and down from center.
struct WaveformView: View {
    let amplitudes: [Float]
    var color: Color = Color(hex: 0x53E16F)

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let sampled = sampledAmplitudes(maxBars: max(Int(size.width / 2), 24))
                let count = sampled.count
                guard count > 0 else { return }

                let barWidth = size.width / CGFloat(count)
                let midY = size.height / 2

                for (i, amp) in sampled.enumerated() {
                    let normalizedAmp = max(CGFloat(amp), 0.06)
                    let barHeight = normalizedAmp * midY * 0.92
                    let x = CGFloat(i) * barWidth

                    let rect = CGRect(
                        x: x,
                        y: midY - barHeight,
                        width: max(barWidth - 0.6, 0.6),
                        height: barHeight * 2
                    )

                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth > 2 ? 1 : 0),
                        with: .linearGradient(
                            Gradient(colors: [
                                color.opacity(Double(0.35 + amp * 0.4)),
                                color.opacity(Double(0.8 + amp * 0.15)),
                                color.opacity(Double(0.35 + amp * 0.4)),
                            ]),
                            startPoint: CGPoint(x: rect.midX, y: rect.minY),
                            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                        )
                    )
                }
            }
        }
    }

    private func sampledAmplitudes(maxBars: Int) -> [Float] {
        guard amplitudes.count > maxBars, maxBars > 0 else { return amplitudes }

        let bucketSize = Double(amplitudes.count) / Double(maxBars)
        return (0..<maxBars).map { bucket in
            let start = Int(Double(bucket) * bucketSize)
            let end = min(Int(Double(bucket + 1) * bucketSize), amplitudes.count)
            let slice = amplitudes[start..<max(start + 1, end)]
            return slice.max() ?? 0
        }
    }
}
