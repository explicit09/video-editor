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
    let onDrag: (TimeInterval, Double) -> Void
    var onTrimStart: ((TimeInterval) -> Void)?
    var onTrimEnd: ((TimeInterval) -> Void)?

    @State private var dragOffset: Double = 0
    @State private var isDragging = false
    @State private var isHovered = false
    @State private var trimStartOffset: Double = 0
    @State private var trimEndOffset: Double = 0
    @State private var isTrimming = false
    private var clipX: Double {
        viewState.durationToWidth(clip.timelineRange.start) + dragOffset + trimStartOffset
    }

    private var clipWidth: Double {
        max(viewState.durationToWidth(clip.timelineRange.duration) - trimStartOffset + trimEndOffset, 8)
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
            Rectangle()
                .fill(clipAccentColor)
                .frame(height: 3)

            ZStack {
                RoundedRectangle(cornerRadius: CinematicRadius.lg)
                    .fill(clipBackground)

                if let waveform, trackType == .audio, !waveform.isEmpty {
                    WaveformView(amplitudes: waveform, color: clipAccentColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                } else if let cgImage = thumbnail, trackType == .video {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.05),
                                    Color.black.opacity(0.38),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .opacity(0.72)
                } else {
                    Rectangle()
                        .fill(clipBackground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(clipLabel, alignment: .topLeading)
            .overlay(alignment: .bottomLeading) {
                clipFooter
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.lg)
                .strokeBorder(
                    outlineColor,
                    lineWidth: outlineWidth
                )
        )
        .shadow(color: shadowColor, radius: isDragging ? 12 : 8, y: isDragging ? 6 : 2)
        .overlay(alignment: .leading) {
            trimHandle(isStart: true)
        }
        .overlay(alignment: .trailing) {
            trimHandle(isStart: false)
        }
        .onHover { isHovered = $0 }
    }

    private func trimHandle(isStart: Bool) -> some View {
        RoundedRectangle(cornerRadius: CinematicRadius.full)
            .fill(isSelected || isTrimming || isHovered ? CinematicTheme.onSurface.opacity(0.85) : Color.clear)
            .frame(width: 5)
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
            .foregroundStyle(CinematicTheme.onSurface)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(trackType == .video ? 0.42 : 0.18))
            .clipShape(Capsule())
            .padding(.horizontal, 6)
            .padding(.top, 6)
    }

    private var clipFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: footerIcon)
                .font(.system(size: 9, weight: .bold))
            Text(TimeFormatter.duration(max(clip.timelineRange.duration, 0.1)))
                .font(.cinLabelRegular)
                .monospacedDigit()
        }
        .foregroundStyle(CinematicTheme.onSurface.opacity(0.82))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private var footerIcon: String {
        switch trackType {
        case .video: "film"
        case .audio: "waveform"
        case .text: "textformat"
        case .effect: "sparkles"
        }
    }

    private var clipBackground: LinearGradient {
        let leading = clipAccentColor.opacity(trackType == .audio ? 0.22 : 0.18)
        let trailing = CinematicTheme.surfaceContainerLowest

        return LinearGradient(
            colors: [
                leading,
                trailing,
                clipAccentColor.opacity(isSelected ? 0.12 : 0.06),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var clipAccentColor: Color {
        switch trackType {
        case .video: CinematicTheme.tertiary
        case .audio: Color(hex: 0x53E16F)
        case .text: CinematicTheme.primary
        case .effect: CinematicTheme.primaryFixedDim
        }
    }

    private var outlineColor: Color {
        if isSelected {
            return CinematicTheme.primary
        }
        if isHovered || isDragging {
            return clipAccentColor.opacity(0.85)
        }
        return CinematicTheme.outlineVariant.opacity(0.24)
    }

    private var outlineWidth: Double {
        isSelected ? 1.6 : (isHovered ? 1.0 : 0.6)
    }

    private var shadowColor: Color {
        if isSelected || isDragging {
            return clipAccentColor.opacity(0.24)
        }
        return .clear
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
                onDrag(newStart, value.translation.height)
            }
    }
}
