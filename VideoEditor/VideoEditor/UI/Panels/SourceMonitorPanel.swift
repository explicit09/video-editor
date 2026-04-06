import SwiftUI
import AVFoundation
import EditorCore

struct SourceMonitorPanel: View {
    @Environment(AppState.self) private var appState
    @State private var sourcePlayer = AVPlayer()
    @State private var sourceCurrentTime: TimeInterval = 0
    @State private var markedInTime: TimeInterval?
    @State private var markedOutTime: TimeInterval?

    private let timer = Timer.publish(every: 1.0 / 15.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            UtilityPanelHeader(
                eyebrow: "SOURCE",
                title: sourceContext?.asset.name ?? "Source Monitor",
                subtitle: sourceSubtitle
            ) {
                HStack(spacing: UtilitySpacing.xs) {
                    MonitorMetricView(label: "IN", value: timecode(for: resolvedMarkedIn))
                    MonitorMetricView(label: "OUT", value: timecode(for: resolvedMarkedOut))
                }
            }

            MonitorViewport(
                player: shouldShowSourcePlayer ? sourcePlayer : nil,
                emptyState: sourceContext == nil
                    ? MonitorEmptyState(
                        icon: "film.stack",
                        title: "No source clip selected",
                        detail: "Select a clip on the timeline to inspect its source, set marks, and prepare insert or overwrite edits."
                    )
                    : nil
            )

            controlStrip
        }
        .background(CinematicTheme.surfaceContainerLow)
        .onAppear(perform: configureSourceMonitor)
        .onChange(of: sourceContext?.identity) { _, _ in
            configureSourceMonitor()
        }
        .onChange(of: appState.timelineViewState.playheadPosition) { _, _ in
            syncSourceMonitorToSelection()
        }
        .onReceive(timer) { _ in
            syncSourceMonitorTime()
        }
        .onDisappear {
            sourcePlayer.pause()
            sourcePlayer.replaceCurrentItem(with: nil)
        }
    }

    private var sourceContext: SourceMonitorContext? {
        let selectedIDs = appState.timelineViewState.selectedClipIDs

        if let selectedID = selectedIDs.first,
           selectedIDs.count == 1,
           let resolved = resolveContext(for: selectedID) {
            return resolved
        }

        let playhead = appState.timelineViewState.playheadPosition
        for track in appState.timeline.tracks {
            if let clip = track.clips.first(where: { $0.timelineRange.contains(playhead) }),
               let resolved = resolveContext(for: clip.id) {
                return resolved
            }
        }

        return nil
    }

    private var shouldShowSourcePlayer: Bool {
        guard let sourceContext else { return false }
        return sourceContext.asset.type != .image
    }

    private var sourceSubtitle: String {
        guard let sourceContext else {
            return "Prep a clip independently from the current program output."
        }

        return "\(sourceContext.track.name) • \(timecode(for: sourceContext.clip.sourceRange.start)) to \(timecode(for: sourceContext.clip.sourceRange.end))"
    }

    private var resolvedMarkedIn: TimeInterval {
        guard let sourceContext else { return 0 }
        return min(max(markedInTime ?? sourceCurrentTime, 0), max(sourceContext.asset.duration, 0))
    }

    private var resolvedMarkedOut: TimeInterval {
        guard let sourceContext else { return 0 }
        let duration = max(sourceContext.asset.duration, 0)
        return min(max(markedOutTime ?? duration, resolvedMarkedIn), duration)
    }

    private var selectedSourceRange: TimeRange? {
        guard let sourceContext else { return nil }

        let lowerBound = min(resolvedMarkedIn, resolvedMarkedOut)
        let upperBound = max(resolvedMarkedOut, lowerBound + 0.1)
        let duration = sourceContext.asset.duration

        if duration <= 0 {
            return TimeRange(start: 0, end: max(sourceContext.clip.sourceRange.duration, 0.1))
        }

        return TimeRange(start: lowerBound, end: min(upperBound, duration))
    }

    private var controlStrip: some View {
        HStack(spacing: UtilitySpacing.sm) {
            MonitorControlButton(
                icon: sourcePlayer.rate == 0 ? "play.fill" : "pause.fill",
                label: sourcePlayer.rate == 0 ? "Play" : "Pause",
                isActive: sourcePlayer.rate != 0,
                action: toggleSourcePlayback
            )
            .disabled(sourceContext == nil || !shouldShowSourcePlayer)

            MonitorControlButton(icon: "flag.fill", label: "Mark In", action: {
                markedInTime = sourceCurrentTime
                if let markedOutTime, markedOutTime < sourceCurrentTime {
                    self.markedOutTime = sourceCurrentTime
                }
            })
            .disabled(sourceContext == nil)

            MonitorControlButton(icon: "flag.checkered", label: "Mark Out", action: {
                markedOutTime = sourceCurrentTime
                if let markedInTime, markedInTime > sourceCurrentTime {
                    self.markedInTime = sourceCurrentTime
                }
            })
            .disabled(sourceContext == nil)

            Spacer(minLength: 0)

            MonitorControlButton(icon: "arrow.down.left.and.arrow.up.right", label: "Insert", isProminent: true, action: insertSelectedRange)
                .disabled(sourceContext == nil || selectedSourceRange == nil)

            MonitorControlButton(icon: "square.on.square", label: "Overwrite", isProminent: true, action: overwriteSelectedRange)
                .disabled(sourceContext == nil || selectedSourceRange == nil)
        }
        .padding(.horizontal, UtilitySpacing.md)
        .padding(.vertical, UtilitySpacing.sm)
        .background(UtilityTheme.chromeElevated)
    }

    private func resolveContext(for clipID: UUID) -> SourceMonitorContext? {
        for track in appState.timeline.tracks {
            guard let clip = track.clips.first(where: { $0.id == clipID }),
                  let asset = appState.assets.first(where: { $0.id == clip.assetID }) else {
                continue
            }

            return SourceMonitorContext(track: track, clip: clip, asset: asset)
        }

        return nil
    }

    private func configureSourceMonitor() {
        guard let sourceContext else {
            sourcePlayer.pause()
            sourcePlayer.replaceCurrentItem(with: nil)
            sourceCurrentTime = 0
            markedInTime = nil
            markedOutTime = nil
            return
        }

        sourcePlayer.pause()
        markedInTime = nil
        markedOutTime = nil

        if sourceContext.asset.type == .image {
            sourcePlayer.replaceCurrentItem(with: nil)
            sourceCurrentTime = sourceContext.clip.sourceRange.start
            return
        }

        sourcePlayer.replaceCurrentItem(with: AVPlayerItem(url: sourceContext.asset.sourceURL))
        sourcePlayer.actionAtItemEnd = .pause
        seekSourceMonitor(to: preferredSourceTime(for: sourceContext))
    }

    private func syncSourceMonitorToSelection() {
        guard let sourceContext, sourcePlayer.rate == 0 else { return }

        let targetTime = preferredSourceTime(for: sourceContext)
        guard abs(targetTime - sourceCurrentTime) > 0.1 else { return }
        seekSourceMonitor(to: targetTime)
    }

    private func syncSourceMonitorTime() {
        guard let currentItem = sourcePlayer.currentItem else { return }

        guard let resolved = MonitorPlaybackTimeResolver.resolve(
            currentTime: sourcePlayer.currentTime().seconds,
            duration: currentItem.duration.seconds
        ) else {
            return
        }

        if abs(sourceCurrentTime - resolved) > 0.02 {
            sourceCurrentTime = resolved
        }
    }

    private func seekSourceMonitor(to time: TimeInterval) {
        let duration = max(sourceContext?.asset.duration ?? time, 0)
        let clamped = min(max(time, 0), duration)
        sourceCurrentTime = clamped
        sourcePlayer.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func toggleSourcePlayback() {
        if sourcePlayer.rate == 0 {
            sourcePlayer.play()
        } else {
            sourcePlayer.pause()
        }
    }

    private func insertSelectedRange() {
        guard let sourceContext, let selectedSourceRange else { return }
        appState.insertAssetSegmentAtPlayhead(
            sourceContext.asset,
            sourceRange: selectedSourceRange,
            label: sourceContext.asset.name
        )
    }

    private func overwriteSelectedRange() {
        guard let sourceContext, let selectedSourceRange else { return }
        appState.overwriteAssetSegmentAtPlayhead(
            sourceContext.asset,
            sourceRange: selectedSourceRange,
            label: sourceContext.asset.name
        )
    }

    private func preferredSourceTime(for sourceContext: SourceMonitorContext) -> TimeInterval {
        let playhead = appState.timelineViewState.playheadPosition
        let clampedTimelineTime = min(
            max(playhead, sourceContext.clip.timelineRange.start),
            sourceContext.clip.timelineRange.end
        )
        let mappedSourceTime = sourceContext.clip.sourceRange.start + (clampedTimelineTime - sourceContext.clip.timelineRange.start)
        return min(max(mappedSourceTime, sourceContext.clip.sourceRange.start), sourceContext.clip.sourceRange.end)
    }

    private func timecode(for time: TimeInterval) -> String {
        TimeFormatter.timecode(max(time, 0))
    }
}

private struct SourceMonitorContext {
    let track: Track
    let clip: Clip
    let asset: MediaAsset

    var identity: String {
        "\(clip.id.uuidString):\(asset.id.uuidString)"
    }
}

struct MonitorMetricView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: UtilitySpacing.xxxs) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(UtilityTheme.textMuted)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(UtilityTheme.text)
        }
        .padding(.horizontal, UtilitySpacing.sm)
        .padding(.vertical, UtilitySpacing.xs)
        .background(UtilityTheme.chrome)
        .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.sm))
    }
}

struct MonitorControlButton: View {
    let icon: String
    let label: String
    var isActive = false
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: UtilitySpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isProminent || isActive ? UtilityTheme.accentText : UtilityTheme.text)
            .padding(.horizontal, UtilitySpacing.sm)
            .frame(height: UtilityMetrics.controlHeight)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.sm))
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        if isProminent || isActive {
            return UtilityTheme.accent
        }
        return UtilityTheme.chrome
    }
}
