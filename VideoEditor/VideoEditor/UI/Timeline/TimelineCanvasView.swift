import SwiftUI
import AppKit
import EditorCore

struct TimelineCanvasView: View {
    @Environment(AppState.self) private var appState

    let timeline: Timeline
    let viewState: TimelineViewState
    let thumbnails: [UUID: CGImage]
    let waveformStates: [UUID: WaveformLoadState]
    let coordinator: TimelineScrollCoordinator
    let rowHeight: Double
    let rowSpacing: Double

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(viewState.durationToWidth(timeline.duration + 10), geo.size.width)
            let contentHeight = max(
                timelineContentHeight,
                geo.size.height
            )

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    timelineBackdrop(width: contentWidth, height: contentHeight)

                    if timeline.tracks.isEmpty {
                        emptyTimeline(width: contentWidth, height: contentHeight)
                    } else {
                        ForEach(Array(timeline.tracks.enumerated()), id: \.element.id) { index, track in
                            TrackCanvasRowView(
                                track: track,
                                rowHeight: rowHeight,
                                contentWidth: contentWidth,
                                viewState: viewState,
                                thumbnails: thumbnails,
                                waveformStates: waveformStates
                            )
                            .offset(y: 8 + Double(index) * (rowHeight + rowSpacing))
                        }
                    }

                    MarkersOverlay(markers: timeline.markers, viewState: viewState)
                        .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TimelineScrollOffsetPreferenceKey.self,
                            value: CGPoint(
                                x: -proxy.frame(in: .named(Self.scrollSpaceName)).minX,
                                y: -proxy.frame(in: .named(Self.scrollSpaceName)).minY
                            )
                        )
                    }
                )
            }
            .coordinateSpace(name: Self.scrollSpaceName)
            .onPreferenceChange(TimelineScrollOffsetPreferenceKey.self) { offset in
                coordinator.update(horizontal: offset.x, vertical: offset.y)
            }
            .background(CinematicTheme.surfaceContainer)
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(CinematicTheme.outlineVariant.opacity(0.18))
                    .frame(height: 1)
            }
            .clipShape(Rectangle())
        }
    }

    private var timelineContentHeight: Double {
        guard !timeline.tracks.isEmpty else { return 0 }
        let rowCount = Double(timeline.tracks.count)
        let gaps = Double(max(timeline.tracks.count - 1, 0)) * rowSpacing
        return (rowCount * rowHeight) + gaps + 16
    }

    private func timelineBackdrop(width: Double, height: Double) -> some View {
        Rectangle()
            .fill(CinematicTheme.surfaceContainer)
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                Path { path in
                    var y = 8.0
                    for _ in timeline.tracks {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                        y += rowHeight + rowSpacing
                    }
                }
                .stroke(CinematicTheme.outlineVariant.opacity(0.14), lineWidth: 0.6)
            }
    }

    private func emptyTimeline(width: Double, height: Double) -> some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "film.stack")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.28))

            Text("Add a track to begin editing")
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))

            Spacer()
        }
        .frame(width: width, height: height)
    }

    private static let scrollSpaceName = "TimelineCanvasScrollSpace"
}

private struct TrackCanvasRowView: View {
    let track: Track
    let rowHeight: Double
    let contentWidth: Double
    let viewState: TimelineViewState
    let thumbnails: [UUID: CGImage]
    let waveformStates: [UUID: WaveformLoadState]

    private var trackAccent: Color {
        switch track.type {
        case .video: CinematicTheme.primary
        case .audio: CinematicTheme.success
        case .text: CinematicTheme.tertiary
        case .effect: CinematicTheme.aqua
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: CinematicRadius.md)
                .fill(rowFill)
                .frame(width: contentWidth - 16, height: rowHeight)
                .offset(x: 8, y: 0)

            ForEach(track.clips) { clip in
                ClipBarView(
                    clip: clip,
                    rowHeight: rowHeight,
                    viewState: viewState,
                    trackAccent: trackAccent,
                    thumbnail: thumbnails[clip.assetID],
                    waveformState: waveformStates[clip.assetID]
                )
                .offset(x: 8 + viewState.durationToWidth(clip.timelineRange.start), y: 7)
                .onTapGesture {
                    viewState.selectClip(clip.id, in: track.id)
                }
            }
        }
        .frame(width: contentWidth, height: rowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            viewState.selectTrack(track.id)
        }
    }

    private var rowFill: some ShapeStyle {
        let base = track.isMuted ? CinematicTheme.surfaceContainerHighest.opacity(0.54) : CinematicTheme.surfaceContainerHighest.opacity(0.82)
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    base,
                    CinematicTheme.surfaceContainer.opacity(0.95),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

}

private struct ClipBarView: View {
    let clip: Clip
    let rowHeight: Double
    let viewState: TimelineViewState
    let trackAccent: Color
    let thumbnail: CGImage?
    let waveformState: WaveformLoadState?

    private var clipWidth: Double {
        max(viewState.durationToWidth(clip.timelineRange.duration), 44)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            trackAccent.opacity(0.84),
                            trackAccent.opacity(0.56),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let thumbnail {
                Image(decorative: thumbnail, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.42)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let waveformState {
                waveformIndicator(for: waveformState)
                    .frame(height: 4)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }

            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(clip.metadata.label ?? "Clip")
                    .font(.cinLabel)
                    .foregroundStyle(CinematicTheme.onPrimaryContainer)
                    .lineLimit(1)

                Text(TimeFormatter.rulerTimecode(clip.timelineRange.duration))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(CinematicTheme.onPrimaryContainer.opacity(0.72))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(width: clipWidth, height: rowHeight - 14)
        .shadow(color: trackAccent.opacity(0.18), radius: 4, x: 0, y: 2)
        .opacity(clip.metadata.label == nil ? 0.96 : 1)
    }

    private var borderColor: Color {
        viewState.selectedClipIDs.contains(clip.id)
            ? CinematicTheme.onSurface.opacity(0.55)
            : CinematicTheme.onPrimaryContainer.opacity(0.28)
    }

    @ViewBuilder
    private func waveformIndicator(for state: WaveformLoadState) -> some View {
        switch state {
        case .ready:
            Capsule()
                .fill(CinematicTheme.success.opacity(0.7))
        case .loading:
            Capsule()
                .fill(CinematicTheme.aqua.opacity(0.56))
        case .noAudio:
            Capsule()
                .fill(CinematicTheme.onPrimaryContainer.opacity(0.18))
        case .failed:
            Capsule()
                .fill(CinematicTheme.warning.opacity(0.56))
        }
    }
}

private struct TimelineScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero

    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}
