import SwiftUI
import EditorCore

struct TimelineTrackView: View {
    let track: Track
    let viewState: TimelineViewState
    let selectedClipIDs: Set<UUID>
    let isSelectedTrack: Bool
    let totalWidth: Double
    let thumbnails: [UUID: CGImage]
    let onTrackTap: () -> Void
    let onClipTap: (UUID, Bool) -> Void
    let onClipDrag: (UUID, TimeInterval) -> Void
    var onClipTrim: ((UUID, TimeInterval, TimeInterval) -> Void)?

    private let trackHeight: Double = 60

    var body: some View {
        HStack(spacing: 0) {
            // Track label sidebar
            trackLabel

            // Clip area
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(isSelectedTrack ? trackBackgroundColor.opacity(1.5) : trackBackgroundColor)
                    .frame(width: totalWidth, height: trackHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewState.clearSelection()
                        onTrackTap()
                    }

                ForEach(track.clips) { clip in
                    TimelineClipView(
                        clip: clip,
                        viewState: viewState,
                        isSelected: selectedClipIDs.contains(clip.id),
                        trackType: track.type,
                        trackHeight: trackHeight,
                        thumbnail: thumbnails[clip.assetID],
                        onTap: { extend in onClipTap(clip.id, extend) },
                        onDrag: { newStart in onClipDrag(clip.id, newStart) },
                        onTrimStart: { newSourceStart in
                            onClipTrim?(clip.id, newSourceStart, clip.sourceRange.end)
                        },
                        onTrimEnd: { newSourceEnd in
                            onClipTrim?(clip.id, clip.sourceRange.start, newSourceEnd)
                        }
                    )
                }
            }
        }
        .frame(height: trackHeight)
        .clipped()
    }

    // MARK: - Track Label

    private var trackLabel: some View {
        HStack(spacing: 6) {
            // Track type icon
            Image(systemName: trackIcon)
                .font(.system(size: 10))
                .foregroundStyle(trackAccentColor.opacity(0.7))

            Text(track.name.isEmpty ? track.type.rawValue.capitalized : track.name)
                .font(.cinLabel)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
                .lineLimit(1)
        }
        .frame(width: 120, height: trackHeight)
        .background(CinematicTheme.surfaceContainerLow)
    }

    private var trackIcon: String {
        switch track.type {
        case .video: "film"
        case .audio: "waveform"
        case .text: "textformat"
        case .effect: "sparkles"
        }
    }

    private var trackAccentColor: Color {
        switch track.type {
        case .video: CinematicTheme.tertiary
        case .audio: Color(hex: 0x53E16F)
        case .text: CinematicTheme.primary
        case .effect: CinematicTheme.primaryFixedDim
        }
    }

    private var trackBackgroundColor: Color {
        switch track.type {
        case .video: CinematicTheme.tertiary.opacity(0.03)
        case .audio: Color(hex: 0x53E16F).opacity(0.03)
        case .text: CinematicTheme.primary.opacity(0.03)
        case .effect: CinematicTheme.primaryFixedDim.opacity(0.03)
        }
    }
}
