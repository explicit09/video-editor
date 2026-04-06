import SwiftUI
import EditorCore

struct TimelineRuler: View {
    let viewState: TimelineViewState
    let totalWidth: Double
    var horizontalOffset: Double = 0

    var body: some View {
        let step = rulerStep(for: viewState.zoom)
        let totalSeconds = max(totalWidth / max(viewState.zoom, 0.001), 0)

        return Canvas { context, size in
            var time: TimeInterval = 0

            while time <= totalSeconds {
                let x = viewState.durationToWidth(time) - horizontalOffset
                let isMajor = isMajorTick(time, step: step)
                let isZero = time == 0
                let tickHeight: Double = isMajor ? 18 : 7

                let path = Path { path in
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x, y: size.height - tickHeight))
                }

                context.stroke(
                    path,
                    with: .color(
                        isZero
                        ? CinematicTheme.primary.opacity(0.9)
                        : CinematicTheme.onSurfaceVariant.opacity(isMajor ? 0.58 : 0.18)
                    ),
                    lineWidth: isMajor ? 1.1 : 0.6
                )

                // Draw label for major ticks
                if isMajor {
                    let label = Text(TimeFormatter.rulerTimecode(time))
                        .font(.cinLabelRegular)
                        .foregroundStyle(isZero ? CinematicTheme.primary : CinematicTheme.onSurface)

                    let resolved = context.resolve(label)
                    let labelSize = resolved.measure(in: CGSize(width: 200, height: 30))

                    // Background pill
                    let pillW = Double(labelSize.width) + 10
                    let pillH = Double(labelSize.height) + 4
                    let pillRect = CGRect(
                        x: x + 28 - pillW / 2,
                        y: 10 - pillH / 2,
                        width: pillW,
                        height: pillH
                    )
                    let pillPath = RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .path(in: pillRect)
                    context.fill(
                        pillPath,
                        with: .color(isZero ? CinematicTheme.primary.opacity(0.14) : CinematicTheme.surfaceContainerHighest.opacity(0.92))
                    )
                    context.stroke(
                        pillPath,
                        with: .color(isZero ? CinematicTheme.primary.opacity(0.28) : CinematicTheme.outlineVariant.opacity(0.18)),
                        lineWidth: 0.8
                    )

                    context.draw(resolved, at: CGPoint(x: x + 28, y: 10))
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
                .fill(CinematicTheme.outlineVariant.opacity(0.34))
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
