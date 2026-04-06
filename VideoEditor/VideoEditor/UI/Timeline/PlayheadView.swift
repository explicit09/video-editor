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
            let playheadColor = CinematicTheme.error
            let linePath = Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: geo.size.height))
            }

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(playheadColor.opacity(0.12))
                    .frame(width: 9, height: geo.size.height)
                    .position(x: x, y: geo.size.height / 2)

                linePath
                    .stroke(CinematicTheme.surface.opacity(0.88), lineWidth: 3.6)
                    .shadow(color: .black.opacity(0.14), radius: 1, x: 0, y: 0)

                linePath
                    .stroke(playheadColor, lineWidth: 1.3)
                    .shadow(color: playheadColor.opacity(0.28), radius: 2, x: 0, y: 0)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                playheadColor,
                                playheadColor.opacity(0.72),
                            ],
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
            }

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
