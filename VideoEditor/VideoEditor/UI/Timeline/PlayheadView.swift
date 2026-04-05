import SwiftUI
import EditorCore

struct PlayheadView: View {
    let viewState: TimelineViewState
    var onSeek: (() -> Void)?
    var horizontalOffset: Double = 0
    var scrubHeight: Double = 32

    var body: some View {
        GeometryReader { geo in
            let x = viewState.durationToWidth(viewState.playheadPosition) - horizontalOffset

            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: geo.size.height))
            }
            .stroke(CinematicTheme.error.opacity(0.92), lineWidth: 1.4)
            .shadow(color: CinematicTheme.error.opacity(0.24), radius: 2, x: 0, y: 0)

            Path { path in
                path.move(to: CGPoint(x: x - 7, y: 0))
                path.addLine(to: CGPoint(x: x + 7, y: 0))
                path.addLine(to: CGPoint(x: x, y: 12))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [CinematicTheme.error, CinematicTheme.error.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: CinematicTheme.error.opacity(0.18), radius: 1, x: 0, y: 1)

            Color.clear
                .frame(height: scrubHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            viewState.playheadPosition = max(0, viewState.xToTime(value.location.x + horizontalOffset))
                            onSeek?()
                        }
                )
        }
        .allowsHitTesting(true)
    }
}
