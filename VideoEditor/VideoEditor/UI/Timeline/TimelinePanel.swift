import Foundation
import SwiftUI
import AppKit
import Observation
import EditorCore

struct TimelinePanel: View {
    let tool: EditorTool
    @Environment(AppState.self) private var appState
    @State private var thumbnails: [UUID: CGImage] = [:]
    @State private var pinchBaseZoom: Double?

    /// Re-run media loading when the timeline changes, when assets become available,
    /// or when background analysis writes a waveform profile onto an existing asset.
    private var mediaLoadKey: [String] {
        let assetsByID = Dictionary(uniqueKeysWithValues: appState.assets.map { ($0.id, $0) })

        return appState.timeline.tracks
            .flatMap(\.clips)
            .map { clip in
                guard let asset = assetsByID[clip.assetID] else {
                    return "\(clip.assetID.uuidString):missing"
                }

                let waveformCount = asset.analysis?.loudnessProfile?.count ?? 0
                return "\(clip.assetID.uuidString):present:\(waveformCount)"
            }
    }

    var body: some View {
        TimelineShellView(
            tool: tool,
            timeline: appState.timeline,
            viewState: appState.timelineViewState,
            thumbnails: thumbnails,
            waveformStates: appState.media.waveformStates
        )
        .background(CinematicTheme.surfaceContainer)
        .task(id: mediaLoadKey) {
            await loadVisibleMedia()
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    if pinchBaseZoom == nil {
                        pinchBaseZoom = appState.timelineViewState.zoom
                    }
                    appState.timelineViewState.setZoom((pinchBaseZoom ?? appState.timelineViewState.zoom) * value.magnification)
                }
                .onEnded { _ in
                    pinchBaseZoom = nil
                }
        )
        .focusable()
        .onKeyPress(.space) {
            guard EditorShortcutGuard.shouldHandleGlobalShortcut(isTextInputFocused: textInputIsFocused) else {
                return .ignored
            }
            appState.playbackEngine.togglePlayPause()
            return .handled
        }
        .onKeyPress(.delete) {
            guard EditorShortcutGuard.shouldHandleGlobalShortcut(isTextInputFocused: textInputIsFocused) else {
                return .ignored
            }
            deleteSelectedClips()
            return .handled
        }
        .onKeyPress(KeyEquivalent("\u{7F}")) {
            guard EditorShortcutGuard.shouldHandleGlobalShortcut(isTextInputFocused: textInputIsFocused) else {
                return .ignored
            }
            guard !appState.timelineViewState.selectedClipIDs.isEmpty else { return .ignored }
            deleteSelectedClips()
            return .handled
        }
    }

    private var textInputIsFocused: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func loadVisibleMedia() async {
        for track in appState.timeline.tracks {
            for clip in track.clips {
                let assetID = clip.assetID
                guard let asset = appState.assets.first(where: { $0.id == assetID }) else { continue }

                if thumbnails[assetID] == nil {
                    let thumb = await appState.media.thumbnail(for: assetID)
                    if let thumb { thumbnails[assetID] = thumb }
                }

                await appState.media.refreshWaveformState(for: asset.id)
            }
        }
    }

    private func deleteSelectedClips() {
        let selected = Array(appState.timelineViewState.selectedClipIDs)
        guard !selected.isEmpty else { return }
        try? appState.perform(.deleteClips(clipIDs: selected))
        appState.timelineViewState.clearSelection()
    }
}

@MainActor @Observable
final class TimelineScrollCoordinator {
    var horizontalOffset: Double = 0
    var verticalOffset: Double = 0
    var pendingRequest: TimelineScrollRequest?

    func update(horizontal: Double, vertical: Double) {
        horizontalOffset = horizontal
        verticalOffset = vertical
    }

    func requestScroll(_ request: TimelineScrollRequest?) {
        pendingRequest = request
    }
}

struct TimelineShellView: View {
    let tool: EditorTool
    let timeline: Timeline
    let viewState: TimelineViewState
    let thumbnails: [UUID: CGImage]
    let waveformStates: [UUID: WaveformLoadState]

    @State private var scrollCoordinator = TimelineScrollCoordinator()

    private let expandedTrackHeight = 84.0
    private let collapsedTrackHeight = 28.0
    private let rowSpacing = Double(CinematicSpacing.clipGap)
    private let toolbarHeight = Double(CinematicMetrics.controlHeight) + 20

    var body: some View {
        GeometryReader { geo in
            let metrics = TimelineShellMetrics.make(
                viewportWidth: geo.size.width,
                viewportHeight: geo.size.height,
                trackCount: timeline.tracks.count,
                expandedTrackHeight: expandedTrackHeight,
                collapsedTrackHeight: collapsedTrackHeight
            )
            let rightColumnWidth = max(geo.size.width - metrics.headerWidth, 0)
            let rightColumnHeight = max(geo.size.height - toolbarHeight, 0)

            VStack(spacing: 0) {
                TimelineToolbarView(tool: tool, viewState: viewState, timeline: timeline)

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        TimelineCornerView()
                            .frame(width: metrics.headerWidth, height: metrics.rulerHeight)

                        TrackHeaderColumnView(
                            tracks: timeline.tracks,
                            viewState: viewState,
                            coordinator: scrollCoordinator,
                            rowHeight: expandedTrackHeight
                        )
                        .frame(width: metrics.headerWidth)
                    }

                    VStack(spacing: 0) {
                        TimelineRuler(
                            viewState: viewState,
                            totalWidth: viewState.durationToWidth(timeline.duration + 10),
                            horizontalOffset: scrollCoordinator.horizontalOffset
                        )
                        .frame(height: metrics.rulerHeight)

                        TimelineCanvasView(
                            timeline: timeline,
                            viewState: viewState,
                            thumbnails: thumbnails,
                            waveformStates: waveformStates,
                            coordinator: scrollCoordinator,
                            rowHeight: expandedTrackHeight,
                            rowSpacing: rowSpacing
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: rightColumnWidth, height: rightColumnHeight, alignment: .topLeading)
                    .overlay(alignment: .topLeading) {
                        PlayheadView(
                            viewState: viewState,
                            onSeek: nil,
                            horizontalOffset: scrollCoordinator.horizontalOffset,
                            scrubHeight: metrics.rulerHeight
                        )
                        .frame(width: rightColumnWidth, height: rightColumnHeight, alignment: .topLeading)
                        .allowsHitTesting(true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shellBackground)
            .onAppear {
                updateScrollRequest(containerSize: geo.size, metrics: metrics)
            }
            .onChange(of: viewState.selectedClipIDs) { _, _ in
                updateScrollRequest(containerSize: geo.size, metrics: metrics)
            }
            .onChange(of: viewState.playheadPosition) { _, _ in
                updateScrollRequest(containerSize: geo.size, metrics: metrics)
            }
            .onChange(of: viewState.autoFollowPlayhead) { _, _ in
                updateScrollRequest(containerSize: geo.size, metrics: metrics)
            }
            .onChange(of: scrollCoordinator.horizontalOffset) { _, _ in
                updateScrollRequest(containerSize: geo.size, metrics: metrics)
            }
            .onChange(of: scrollCoordinator.verticalOffset) { _, _ in
                updateScrollRequest(containerSize: geo.size, metrics: metrics)
            }
        }
    }

    private var shellBackground: some View {
        LinearGradient(
            colors: [
                CinematicTheme.surface,
                CinematicTheme.surfaceDim,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(CinematicTheme.primaryContainer.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 90, y: -50)
        }
    }

    private func updateScrollRequest(containerSize: CGSize, metrics: TimelineShellMetrics) {
        let visibleWidth = max(containerSize.width - metrics.headerWidth, 0)
        let visibleHeight = max(containerSize.height - toolbarHeight - metrics.rulerHeight, 0)
        let viewport = TimelineViewport(
            visibleXRange: scrollCoordinator.horizontalOffset ... (scrollCoordinator.horizontalOffset + visibleWidth),
            visibleYRange: scrollCoordinator.verticalOffset ... (scrollCoordinator.verticalOffset + visibleHeight)
        )

        let selectionRequest = selectionRevealRequest(in: viewport)
        let playheadRequest = TimelineScrollTargetResolver.requestToKeepPlayheadVisible(
            playheadX: viewState.durationToWidth(viewState.playheadPosition),
            in: viewport,
            autoFollow: viewState.autoFollowPlayhead,
            padding: 72
        )

        scrollCoordinator.requestScroll(selectionRequest ?? playheadRequest)
    }

    private func selectionRevealRequest(in viewport: TimelineViewport) -> TimelineScrollRequest? {
        guard let frame = selectedClipFrame() else { return nil }

        return TimelineScrollTargetResolver.requestToReveal(
            frame,
            in: viewport,
            padding: 40
        )
    }

    private func selectedClipFrame() -> TimelineVisibleFrame? {
        var minX: Double?
        var maxX: Double?
        var minY: Double?
        var maxY: Double?

        for (index, track) in timeline.tracks.enumerated() {
            let rowY = 8 + Double(index) * (expandedTrackHeight + rowSpacing)

            for clip in track.clips where viewState.selectedClipIDs.contains(clip.id) {
                let clipMinX = viewState.durationToWidth(clip.timelineRange.start)
                let clipMaxX = viewState.durationToWidth(clip.timelineRange.end)

                minX = min(minX ?? clipMinX, clipMinX)
                maxX = max(maxX ?? clipMaxX, clipMaxX)
                minY = min(minY ?? rowY, rowY)
                maxY = max(maxY ?? (rowY + expandedTrackHeight), rowY + expandedTrackHeight)
            }
        }

        guard let minX, let maxX, let minY, let maxY else { return nil }
        return TimelineVisibleFrame(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }
}

struct TimelineToolbarView: View {
    @Environment(AppState.self) private var appState

    let tool: EditorTool
    let viewState: TimelineViewState
    let timeline: Timeline

    var body: some View {
        HStack(spacing: CinematicSpacing.sm) {
            Menu {
                Button("Video Track") { appState.addTrack(of: .video, positionedAfter: viewState.selectedTrackID) }
                Button("Audio Track") { appState.addTrack(of: .audio, positionedAfter: viewState.selectedTrackID) }
                Button("Text Track") { appState.addTrack(of: .text, positionedAfter: viewState.selectedTrackID) }
                Button("Effect Track") { appState.addTrack(of: .effect, positionedAfter: viewState.selectedTrackID) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Track")
                        .font(.cinLabel)
                }
                .foregroundStyle(CinematicTheme.onSurface)
                .padding(.horizontal, 12)
                .frame(height: CinematicMetrics.controlHeight)
                .background(CinematicTheme.surfaceContainerHighest)
                .clipShape(Capsule())
            }
            .menuStyle(.button)

            CinematicStatusPill(
                text: tool.rawValue.uppercased(),
                icon: tool.icon,
                tone: CinematicTheme.primary
            )

            HStack(spacing: 6) {
                CinematicToolbarButton(icon: "arrow.uturn.backward", action: { try? appState.undo() })
                    .disabled(!appState.commandHistory.canUndo)
                CinematicToolbarButton(icon: "arrow.uturn.forward", action: { try? appState.redo() })
                    .disabled(!appState.commandHistory.canRedo)
            }

            Button {
                viewState.snapEnabled.toggle()
            } label: {
                CinematicStatusPill(
                    text: viewState.snapEnabled ? "SNAP ON" : "SNAP OFF",
                    icon: "scope",
                    tone: viewState.snapEnabled ? CinematicTheme.primary : CinematicTheme.onSurfaceVariant
                )
            }
            .buttonStyle(.plain)

            Button {
                viewState.rippleEnabled.toggle()
            } label: {
                CinematicStatusPill(
                    text: viewState.rippleEnabled ? "RIPPLE ON" : "RIPPLE OFF",
                    icon: "arrow.left.arrow.right.circle",
                    tone: viewState.rippleEnabled ? CinematicTheme.warning : CinematicTheme.onSurfaceVariant
                )
            }
            .buttonStyle(.plain)

            Button {
                viewState.linkedSelectionEnabled.toggle()
            } label: {
                CinematicStatusPill(
                    text: viewState.linkedSelectionEnabled ? "LINKED ON" : "LINKED OFF",
                    icon: "link",
                    tone: viewState.linkedSelectionEnabled ? CinematicTheme.success : CinematicTheme.onSurfaceVariant
                )
            }
            .buttonStyle(.plain)

            Button {
                viewState.autoFollowPlayhead.toggle()
            } label: {
                CinematicStatusPill(
                    text: viewState.autoFollowPlayhead ? "FOLLOW ON" : "FOLLOW OFF",
                    icon: "dot.radiowaves.left.and.right",
                    tone: viewState.autoFollowPlayhead ? CinematicTheme.aqua : CinematicTheme.onSurfaceVariant
                )
            }
            .buttonStyle(.plain)

            CinematicStatusPill(
                text: "\(timeline.tracks.count) lanes",
                icon: "square.stack.3d.down.right",
                tone: CinematicTheme.aqua
            )

            CinematicStatusPill(
                text: zoomLabel(for: viewState.zoom),
                icon: "timeline.selection",
                tone: CinematicTheme.tertiary
            )

            Menu {
                Button("Zoom In") { viewState.zoomIn() }
                Button("Zoom Out") { viewState.zoomOut() }
                Divider()
                Button("Full Extent") { viewState.zoomToFit(duration: timeline.duration) }
                    .disabled(timeline.duration == 0)
                Button("Detail Zoom") { viewState.zoomToDetail() }
            } label: {
                HStack(spacing: 6) {
                    CinematicToolbarButton(icon: "minus", action: { viewState.zoomOut() })
                    CinematicToolbarButton(icon: "arrow.left.and.right", action: { viewState.zoomToFit(duration: timeline.duration) })
                        .disabled(timeline.duration == 0)
                    CinematicToolbarButton(icon: "plus", action: { viewState.zoomIn() })
                }
            }
            .menuStyle(.button)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    CinematicTheme.surfaceContainerHigh,
                    CinematicTheme.surfaceContainerHighest.opacity(0.86),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CinematicTheme.outlineVariant.opacity(0.2))
                .frame(height: 1)
        }
    }

    private func zoomLabel(for zoom: Double) -> String {
        if zoom < 10 {
            return String(format: "%.1f px/s", zoom)
        }
        return "\(Int(zoom.rounded())) px/s"
    }
}

struct TimelineCanvasView: View {
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
            let contentHeight = max(timelineContentHeight, geo.size.height)

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

private struct TrackHeaderColumnView: View {
    let tracks: [Track]
    let viewState: TimelineViewState
    let coordinator: TimelineScrollCoordinator
    let rowHeight: Double

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: CinematicSpacing.clipGap) {
                ForEach(tracks) { track in
                    TrackHeaderRowView(track: track, viewState: viewState, rowHeight: rowHeight)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .offset(y: -coordinator.verticalOffset)
        }
        .clipped()
        .background(CinematicTheme.surfaceContainer)
    }
}

private struct TrackHeaderRowView: View {
    let track: Track
    let viewState: TimelineViewState
    let rowHeight: Double

    private var accent: Color {
        switch track.type {
        case .video: CinematicTheme.primary
        case .audio: CinematicTheme.success
        case .text: CinematicTheme.tertiary
        case .effect: CinematicTheme.aqua
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(accent.opacity(0.88))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(CinematicTheme.onSurface.opacity(0.18), lineWidth: 0.5))

                Text(track.type.rawValue.uppercased())
                    .font(.cinLabel)
                    .tracking(1)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72))

                Spacer(minLength: 0)

                Text("\(track.clips.count)")
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.74))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(CinematicTheme.surfaceContainerHighest)
                    .clipShape(Capsule())
            }

            Text(track.name)
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurface)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if track.isMuted {
                    headerBadge(icon: "speaker.slash", label: "Muted", tone: CinematicTheme.warning)
                }
                if track.isLocked {
                    headerBadge(icon: "lock.fill", label: "Locked", tone: CinematicTheme.onSurfaceVariant)
                }
                if viewState.selectedTrackID == track.id {
                    headerBadge(icon: "checkmark.circle.fill", label: "Selected", tone: CinematicTheme.primary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: rowHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: CinematicRadius.md)
                .fill(CinematicTheme.surfaceContainerHighest.opacity(0.72))
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(CinematicTheme.outlineVariant.opacity(0.24))
                .frame(width: 1)
        }
    }

    private func headerBadge(icon: String, label: String, tone: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .foregroundStyle(tone)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(tone.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct TimelineCornerView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CinematicTheme.primary.opacity(0.92))

            VStack(alignment: .leading, spacing: 1) {
                Text("TRACKS")
                    .font(.cinLabel)
                    .tracking(1.2)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.7))

                Text("TIMELINE")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.48))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .background(
            LinearGradient(
                colors: [
                    CinematicTheme.surfaceContainerHighest,
                    CinematicTheme.surfaceContainerHigh,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(CinematicTheme.outlineVariant.opacity(0.26))
                .frame(height: 1)
        }
    }
}

private struct TimelineScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero

    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}
