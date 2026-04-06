import SwiftUI
import EditorCore

struct PlayheadView: View {
    let viewState: TimelineViewState
    var onSeek: (() -> Void)?
    var horizontalOffset: Double = 0
    var scrubHeight: Double = 32

    private var playheadX: Double {
        viewState.durationToWidth(viewState.playheadPosition) - horizontalOffset
    }

    var body: some View {
        GeometryReader { geo in
            let x = playheadX
            let playheadColor = CinematicTheme.error
            let scrubRect = PlayheadInteractionLayout.scrubRect(
                containerWidth: geo.size.width,
                containerHeight: geo.size.height,
                scrubHeight: scrubHeight
            )

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    // Glow band
                    context.fill(
                        Path(CGRect(x: x - 4.5, y: 0, width: 9, height: size.height)),
                        with: .color(playheadColor.opacity(0.12))
                    )

                    // Outer stroke (surface halo)
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(CinematicTheme.surface.opacity(0.88)), lineWidth: 3.6)

                    // Inner stroke (playhead color)
                    context.stroke(line, with: .color(playheadColor), lineWidth: 1.3)
                }
                .allowsHitTesting(false)

                // Head indicator — kept as SwiftUI view for gradient + border fidelity
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [playheadColor, playheadColor.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 16, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(CinematicTheme.surface.opacity(0.94), lineWidth: 1)
                    )
                    .shadow(color: playheadColor.opacity(0.24), radius: 3, x: 0, y: 1)
                    .position(x: x, y: 7)
                    .allowsHitTesting(false)

                Color.clear
                    .frame(width: scrubRect.width, height: scrubRect.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                viewState.playheadPosition = max(0, viewState.xToTime(value.location.x + horizontalOffset))
                                onSeek?()
                            }
                    )
            }
            .drawingGroup()
        }
    }
}
