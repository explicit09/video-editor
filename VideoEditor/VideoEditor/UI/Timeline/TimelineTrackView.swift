import SwiftUI
import EditorCore

struct TimelineTrackView: View {
    let track: Track
    @ObservedObject var viewState: TimelineViewState
    let selectedClipIDs: Set<UUID>
    let isSelectedTrack: Bool
    let totalWidth: Double
    let onTrackTap: () -> Void
    let onClipTap: (UUID, Bool) -> Void
    let onClipDrag: (UUID, TimeInterval) -> Void

    private let trackHeight: Double = 60

    var body: some View {
        ZStack(alignment: .leading) {
            // Track background
            Rectangle()
                .fill(isSelectedTrack ? trackBackgroundColor.opacity(3) : trackBackgroundColor)
                .frame(width: totalWidth, height: trackHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewState.clearSelection()
                    onTrackTap()
                }

            // Track label
            Text(track.name.isEmpty ? track.type.rawValue.capitalized : track.name)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
                .padding(.top, 2)
                .frame(width: totalWidth, height: trackHeight, alignment: .topLeading)
                .allowsHitTesting(false)

            // Clips — each positioned absolutely via .position() in TimelineClipView
            ForEach(track.clips) { clip in
                TimelineClipView(
                    clip: clip,
                    viewState: viewState,
                    isSelected: selectedClipIDs.contains(clip.id),
                    trackType: track.type,
                    trackHeight: trackHeight,
                    onTap: { extend in onClipTap(clip.id, extend) },
                    onDrag: { newStart in onClipDrag(clip.id, newStart) }
                )
            }
        }
        .frame(width: totalWidth, height: trackHeight)
        .clipped()
    }

    private var trackBackgroundColor: Color {
        switch track.type {
        case .video: Color.blue.opacity(0.05)
        case .audio: Color.green.opacity(0.05)
        case .text: Color.orange.opacity(0.05)
        case .effect: Color.purple.opacity(0.05)
        }
    }
}
