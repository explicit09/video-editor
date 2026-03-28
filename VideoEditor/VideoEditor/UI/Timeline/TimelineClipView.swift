import SwiftUI
import AppKit
import EditorCore

struct TimelineClipView: View {
    let clip: Clip
    let viewState: TimelineViewState
    let isSelected: Bool
    let trackType: TrackType
    let trackHeight: Double
    let thumbnail: CGImage?
    let waveform: [Float]?
    let onTap: (Bool) -> Void
    let onDrag: (TimeInterval) -> Void
    var onTrimStart: ((TimeInterval) -> Void)?
    var onTrimEnd: ((TimeInterval) -> Void)?

    @State private var dragOffset: Double = 0
    @State private var isDragging = false
    @State private var trimStartOffset: Double = 0
    @State private var trimEndOffset: Double = 0
    @State private var isTrimming = false
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
        VStack(spacing: 0) {
            // Top accent bar (2px)
            Rectangle()
                .fill(clipAccentColor)
                .frame(height: 2)

            // Clip content
            ZStack {
                if let waveform, trackType == .audio, !waveform.isEmpty {
                    // Audio: show waveform
                    Rectangle().fill(clipColor)
                    WaveformView(amplitudes: waveform, color: clipAccentColor)
                        .padding(.vertical, 4)
                } else if let cgImage = thumbnail, trackType == .video {
                    // Video: show thumbnail
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.4)
                } else {
                    Rectangle().fill(clipColor)
                }
            }
            .overlay(clipLabel, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.lg)
                .strokeBorder(
                    isSelected ? CinematicTheme.primary : CinematicTheme.outlineVariant.opacity(0.15),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .shadow(color: isDragging ? CinematicTheme.primaryContainer.opacity(0.2) : .clear, radius: 6)
        // Trim handles
        .overlay(alignment: .leading) {
            trimHandle(isStart: true)
        }
        .overlay(alignment: .trailing) {
            trimHandle(isStart: false)
        }
    }

    private func trimHandle(isStart: Bool) -> some View {
        Rectangle()
            .fill(isSelected || isTrimming ? CinematicTheme.primary.opacity(0.6) : Color.clear)
            .frame(width: 4)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isTrimming = true
                        if isStart { trimStartOffset = value.translation.width }
                        else { trimEndOffset = value.translation.width }
                    }
                    .onEnded { value in
                        isTrimming = false
                        let timeDelta = value.translation.width / viewState.zoom
                        if isStart {
                            trimStartOffset = 0
                            let newStart = max(0, clip.sourceRange.start + timeDelta)
                            onTrimStart?(newStart)
                        } else {
                            trimEndOffset = 0
                            let newEnd = max(clip.sourceRange.start + 0.1, clip.sourceRange.end + timeDelta)
                            onTrimEnd?(newEnd)
                        }
                    }
            )
    }

    // MARK: - Label

    private var clipLabel: some View {
        Text(clip.metadata.label ?? "Clip")
            .font(.cinLabelRegular)
            .foregroundStyle(CinematicTheme.onSurface.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.top, 4)
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
