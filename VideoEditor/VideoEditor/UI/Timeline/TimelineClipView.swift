import SwiftUI
import EditorCore

struct TimelineClipView: View {
    let clip: Clip
    @ObservedObject var viewState: TimelineViewState
    let isSelected: Bool
    let trackType: TrackType
    let onTap: (Bool) -> Void
    let onDrag: (TimeInterval) -> Void

    @State private var dragOffset: Double = 0
    @State private var isDragging = false

    var body: some View {
        let x = viewState.durationToWidth(clip.timelineRange.start) + dragOffset
        let width = max(viewState.durationToWidth(clip.timelineRange.duration), 4)

        RoundedRectangle(cornerRadius: 4)
            .fill(clipColor)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
            )
            .overlay(clipLabel, alignment: .leading)
            .frame(width: width, height: 52)
            .offset(x: x, y: 4)
            .shadow(color: isDragging ? .black.opacity(0.3) : .clear, radius: 4)
            .onTapGesture {
                onTap(NSEvent.modifierFlags.contains(.shift))
            }
            .gesture(dragGesture)
    }

    // MARK: - Clip color

    private var clipColor: Color {
        let base: Color = switch trackType {
        case .video: .blue
        case .audio: .green
        case .text: .orange
        case .effect: .purple
        }
        return base.opacity(isDragging ? 0.8 : 0.6)
    }

    // MARK: - Label

    private var clipLabel: some View {
        Text(clip.metadata.label ?? "Clip")
            .font(.caption2)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }

    // MARK: - Drag

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation.width
            }
            .onEnded { value in
                isDragging = false
                let timeDelta = value.translation.width / viewState.zoom
                let newStart = max(0, clip.timelineRange.start + timeDelta)

                // Snap
                if viewState.snapEnabled {
                    // Snap will be applied by the caller if needed
                }

                dragOffset = 0
                onDrag(newStart)
            }
    }
}
