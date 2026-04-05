import SwiftUI
import EditorCore

struct TimelineRuler: View {
    let viewState: TimelineViewState
    let totalWidth: Double
    var horizontalOffset: Double = 0

    var body: some View {
        Canvas { context, size in
            let step = rulerStep(for: viewState.zoom)
            let totalSeconds = totalWidth / viewState.zoom
            var time: TimeInterval = 0

            while time <= totalSeconds {
                let x = viewState.durationToWidth(time) - horizontalOffset
                let isMajor = isMajorTick(time, step: step)
                let isZero = time == 0

                let tickHeight: Double = isMajor ? 16 : 8
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x, y: size.height - tickHeight))
                }
                context.stroke(
                    path,
                    with: .color(isZero ? CinematicTheme.primary.opacity(0.7) : CinematicTheme.onSurfaceVariant.opacity(isMajor ? 0.44 : 0.22)),
                    lineWidth: isMajor ? 1 : 0.5
                )

                if isMajor {
                    let label = TimeFormatter.rulerTimecode(time)
                    context.draw(
                        Text(label).font(.cinLabel).foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72)),
                        at: CGPoint(x: x + 4, y: 8),
                        anchor: .leading
                    )
                }

                time += step
            }
        }
        .background(
            LinearGradient(
                colors: [
                    CinematicTheme.surfaceContainerHighest,
                    CinematicTheme.surfaceContainerHigh,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CinematicTheme.outlineVariant.opacity(0.3))
                .frame(height: 1)
        }
    }

    /// Choose ruler tick spacing based on zoom level.
    private func rulerStep(for zoom: Double) -> TimeInterval {
        let targetPixelSpacing: Double = 60
        let rawStep = targetPixelSpacing / zoom

        let steps: [TimeInterval] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60]
        return steps.first { $0 >= rawStep } ?? 60
    }

    private func isMajorTick(_ time: TimeInterval, step: TimeInterval) -> Bool {
        if step < 1 {
            return time.truncatingRemainder(dividingBy: 1.0) < 0.001
        }
        return time.truncatingRemainder(dividingBy: step * 5) < 0.001
    }

}
