import SwiftUI
import EditorCore

struct PlayheadView: View {
    let viewState: TimelineViewState
    var onSeek: (() -> Void)?

    var body: some View {
        GeometryReader { geo in
            let x = viewState.durationToWidth(viewState.playheadPosition)

            // Playhead line
            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: geo.size.height))
            }
            .stroke(CinematicTheme.error, lineWidth: 1)

            // Playhead handle (top triangle)
            Path { path in
                path.move(to: CGPoint(x: x - 6, y: 0))
                path.addLine(to: CGPoint(x: x + 6, y: 0))
                path.addLine(to: CGPoint(x: x, y: 10))
                path.closeSubpath()
            }
            .fill(CinematicTheme.error)

            // Scrub area (ruler height)
            Color.clear
                .frame(height: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            viewState.playheadPosition = max(0, viewState.xToTime(value.location.x))
                            onSeek?()
                        }
                )
        }
        .allowsHitTesting(true)
    }
}
