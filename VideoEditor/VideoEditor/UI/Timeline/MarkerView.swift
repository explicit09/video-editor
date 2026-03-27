import SwiftUI
import EditorCore

struct MarkersOverlay: View {
    let markers: [Marker]
    @ObservedObject var viewState: TimelineViewState

    var body: some View {
        GeometryReader { geo in
            ForEach(markers) { marker in
                let x = viewState.durationToWidth(marker.time)

                // Marker line
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
                .stroke(Color.orange, lineWidth: 1)

                // Marker diamond
                Path { path in
                    path.move(to: CGPoint(x: x, y: 2))
                    path.addLine(to: CGPoint(x: x + 5, y: 7))
                    path.addLine(to: CGPoint(x: x, y: 12))
                    path.addLine(to: CGPoint(x: x - 5, y: 7))
                    path.closeSubpath()
                }
                .fill(Color.orange)

                // Label
                if !marker.label.isEmpty {
                    Text(marker.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .offset(x: x + 7, y: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
