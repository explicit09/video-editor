import SwiftUI
import EditorCore

struct TimelineClipView: View {
    let clip: Clip
    @ObservedObject var viewState: TimelineViewState
    let isSelected: Bool
    let trackType: TrackType
    let trackHeight: Double
    let onTap: (Bool) -> Void
    let onDrag: (TimeInterval) -> Void

    @State private var dragOffset: Double = 0
    @State private var isDragging = false

    private var clipX: Double {
        viewState.durationToWidth(clip.timelineRange.start) + dragOffset
    }

    private var clipWidth: Double {
        max(viewState.durationToWidth(clip.timelineRange.duration), 8)
    }

    var body: some View {
        clipBody
            .frame(width: clipWidth, height: trackHeight - 8)
            .position(x: clipX + clipWidth / 2, y: trackHeight / 2)
            .gesture(dragGesture)
            .simultaneousGesture(tapGesture)
    }

    private var clipBody: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(clipColor)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
            )
            .overlay(clipLabel, alignment: .leading)
            .shadow(color: isDragging ? .black.opacity(0.3) : .clear, radius: 4)
    }

    // MARK: - Label

    private var clipLabel: some View {
        Text(clip.metadata.label ?? "Clip")
            .font(.caption2)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
    }

    // MARK: - Color

    private var clipColor: Color {
        let base: Color = switch trackType {
        case .video: .blue
        case .audio: .green
        case .text: .orange
        case .effect: .purple
        }
        return base.opacity(isDragging ? 0.8 : 0.6)
    }

    // MARK: - Gestures

    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded {
                onTap(NSEvent.modifierFlags.contains(.shift))
            }
    }

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
                dragOffset = 0
                onDrag(newStart)
            }
    }
}
