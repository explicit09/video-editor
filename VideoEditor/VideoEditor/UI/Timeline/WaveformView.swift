import SwiftUI

/// Renders an audio waveform from amplitude data.
/// Draws a mirrored bar visualization — peaks up and down from center.
struct WaveformView: View {
    let amplitudes: [Float]
    var color: Color = Color(hex: 0x53E16F)

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let count = amplitudes.count
                guard count > 0 else { return }

                let barWidth = size.width / CGFloat(count)
                let midY = size.height / 2

                for (i, amp) in amplitudes.enumerated() {
                    let barHeight = CGFloat(amp) * midY * 0.9 // 90% of half-height max
                    let x = CGFloat(i) * barWidth

                    let rect = CGRect(
                        x: x,
                        y: midY - barHeight,
                        width: max(barWidth - 0.5, 0.5), // tiny gap between bars
                        height: barHeight * 2
                    )

                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth > 2 ? 1 : 0),
                        with: .color(color.opacity(Double(0.3 + amp * 0.5)))
                    )
                }
            }
        }
    }
}
