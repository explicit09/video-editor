import SwiftUI
import EditorCore

struct TimelineClipView: View {
    let clip: Clip
    let viewState: TimelineViewState
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
        RoundedRectangle(cornerRadius: CinematicRadius.lg)
            .fill(clipColor)
            .overlay(alignment: .top) {
                // Top accent bar (2px) — per design system
                Rectangle()
                    .fill(clipAccentColor)
                    .frame(height: 2)
            }
            .overlay(
                RoundedRectangle(cornerRadius: CinematicRadius.lg)
                    .strokeBorder(
                        isSelected ? CinematicTheme.primary : CinematicTheme.outlineVariant.opacity(0.15),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .overlay(clipLabel, alignment: .leading)
            .shadow(color: isDragging ? CinematicTheme.primaryContainer.opacity(0.2) : .clear, radius: 6)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
    }

    // MARK: - Label

    private var clipLabel: some View {
        Text(clip.metadata.label ?? "Clip")
            .font(.cinLabelRegular)
            .foregroundStyle(CinematicTheme.onSurface.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.top, 6)
    }

    // MARK: - Colors (muted pro-colorist aesthetic)

    private var clipColor: Color {
        let base = clipAccentColor
        return base.opacity(isDragging ? 0.25 : 0.15)
    }

    private var clipAccentColor: Color {
        switch trackType {
        case .video: CinematicTheme.tertiary
        case .audio: Color(hex: 0x53E16F)
        case .text: CinematicTheme.primary
        case .effect: CinematicTheme.primaryFixedDim
        }
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
