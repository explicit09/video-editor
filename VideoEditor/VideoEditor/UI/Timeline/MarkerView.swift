import SwiftUI
import EditorCore

struct MarkersOverlay: View {
    let markers: [Marker]
    let viewState: TimelineViewState

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(markers) { marker in
                let x = viewState.durationToWidth(marker.time)

                // Marker line (thin, full height)
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    .stroke(CinematicTheme.primary.opacity(0.4), lineWidth: 0.5)
                }

                // Marker flag pinned to top edge only
                HStack(spacing: 2) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(CinematicTheme.primary)

                    if !marker.label.isEmpty {
                        Text(marker.label)
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(CinematicTheme.onPrimaryContainer)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(CinematicTheme.primaryContainer.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .offset(x: x - 3, y: 0) // Pin to very top
            }
        }
        .allowsHitTesting(false)
    }
}
