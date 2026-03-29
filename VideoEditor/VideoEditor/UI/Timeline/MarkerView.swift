import SwiftUI
import EditorCore

struct MarkersOverlay: View {
    let markers: [Marker]
    let viewState: TimelineViewState

    var body: some View {
        GeometryReader { geo in
            ForEach(markers) { marker in
                let x = viewState.durationToWidth(marker.time)

                // Marker line (thin, subtle)
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
                .stroke(CinematicTheme.primary.opacity(0.5), lineWidth: 0.5)

                // Marker flag at top
                VStack(spacing: 0) {
                    // Diamond
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: 4, y: 4))
                        path.addLine(to: CGPoint(x: 0, y: 8))
                        path.addLine(to: CGPoint(x: -4, y: 4))
                        path.closeSubpath()
                    }
                    .fill(CinematicTheme.primary)
                    .frame(width: 8, height: 8)

                    // Label (compact pill, only if non-empty)
                    if !marker.label.isEmpty {
                        Text(marker.label)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(CinematicTheme.onPrimaryContainer)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(CinematicTheme.primaryContainer.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .position(x: x, y: 12)
            }
        }
        .allowsHitTesting(false)
    }
}
