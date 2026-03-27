import SwiftUI
import EditorCore

struct PlayheadView: View {
    @ObservedObject var viewState: TimelineViewState

    var body: some View {
        GeometryReader { geo in
            let x = viewState.durationToWidth(viewState.playheadPosition)

            // Playhead line
            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: geo.size.height))
            }
            .stroke(Color.red, lineWidth: 1)

            // Playhead handle (top triangle)
            Path { path in
                path.move(to: CGPoint(x: x - 6, y: 0))
                path.addLine(to: CGPoint(x: x + 6, y: 0))
                path.addLine(to: CGPoint(x: x, y: 10))
                path.closeSubpath()
            }
            .fill(Color.red)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        viewState.playheadPosition = max(0, viewState.xToTime(value.location.x))
                    }
            )

            // Click anywhere on ruler area to seek
            Color.clear
                .frame(height: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            viewState.playheadPosition = max(0, viewState.xToTime(value.location.x))
                        }
                )
        }
        .allowsHitTesting(true)
    }
}
