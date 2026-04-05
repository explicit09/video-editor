import SwiftUI
import EditorCore

struct TimelineRuler: View {
    let viewState: TimelineViewState
    let totalWidth: Double
    var horizontalOffset: Double = 0

    var body: some View {
        let step = rulerStep(for: viewState.zoom)
        let totalSeconds = max(totalWidth / max(viewState.zoom, 0.001), 0)

        return ZStack(alignment: .topLeading) {
            Canvas { context, size in
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

                    time += step
                }
            }

            GeometryReader { _ in
                ForEach(majorTickTimes(step: step, totalSeconds: totalSeconds), id: \.self) { time in
                    let x = viewState.durationToWidth(time) - horizontalOffset
                    Text(TimeFormatter.rulerTimecode(time))
                        .font(.cinLabelRegular)
                        .monospacedDigit()
                        .foregroundStyle(time == 0 ? CinematicTheme.primary : CinematicTheme.onSurface)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    time == 0
                                    ? CinematicTheme.primary.opacity(0.14)
                                    : CinematicTheme.surfaceContainerHighest.opacity(0.92)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(
                                    time == 0
                                    ? CinematicTheme.primary.opacity(0.28)
                                    : CinematicTheme.outlineVariant.opacity(0.18),
                                    lineWidth: 0.8
                                )
                        )
                        .position(x: x + 28, y: 10)
                }
            }
            .allowsHitTesting(false)
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

    private func majorTickTimes(step: TimeInterval, totalSeconds: TimeInterval) -> [TimeInterval] {
        var times: [TimeInterval] = []
        var time: TimeInterval = 0

        while time <= totalSeconds {
            if isMajorTick(time, step: step) {
                times.append(time)
            }
            time += step
        }

        return times
    }

    private func isMajorTick(_ time: TimeInterval, step: TimeInterval) -> Bool {
        if step < 1 {
            return time.truncatingRemainder(dividingBy: 1.0) < 0.001
        }
        return time.truncatingRemainder(dividingBy: step * 5) < 0.001
    }
}
