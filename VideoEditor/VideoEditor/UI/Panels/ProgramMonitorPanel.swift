import SwiftUI

struct ProgramMonitorPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            UtilityPanelHeader(
                eyebrow: "PROGRAM",
                title: "Program Monitor",
                subtitle: appState.clipCount == 0
                    ? "Timeline output appears here once clips are on the sequence."
                    : "\(appState.clipCount) clips across \(appState.timeline.tracks.count) tracks"
            ) {
                HStack(spacing: UtilitySpacing.xs) {
                    MonitorMetricView(label: "TC", value: TimeFormatter.timecode(appState.playbackEngine.currentTime))
                    MonitorMetricView(label: "DUR", value: TimeFormatter.timecode(appState.playbackEngine.duration))
                }
            }

            MonitorViewport(
                player: appState.playbackEngine.duration == 0 ? nil : appState.playbackEngine.player,
                emptyState: appState.playbackEngine.duration == 0
                    ? MonitorEmptyState(
                        icon: "rectangle.on.rectangle.angled",
                        title: "No active composition",
                        detail: "Import media or add clips to the timeline to populate the program monitor."
                    )
                    : nil
            ) {
                if let overlayClip = appState.selectedVideoOverlayClip {
                    OverlayMonitorControls(
                        clip: overlayClip,
                        onTransformUpdate: { transform in
                            try? appState.perform(.setClipTransform(clipID: overlayClip.id, transform: transform))
                        }
                    )
                }

                if appState.aiChat.isProcessing {
                    VStack(spacing: UtilitySpacing.sm) {
                        ProgressView()
                            .tint(CinematicTheme.primary)
                        Text(appState.aiChat.processingStatus ?? "AI is analyzing the current edit…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(UtilityTheme.text)
                    }
                    .padding(.horizontal, UtilitySpacing.lg)
                    .padding(.vertical, UtilitySpacing.md)
                    .background(UtilityTheme.chrome.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.md))
                    .padding(.bottom, 28)
                }
            }

            controlStrip
        }
        .background(CinematicTheme.surfaceContainerLow)
    }

    private var controlStrip: some View {
        HStack(spacing: UtilitySpacing.sm) {
            MonitorControlButton(icon: "backward.end.fill", label: "Start", action: {
                appState.playbackEngine.seek(to: 0)
                appState.timelineViewState.playheadPosition = 0
            })

            MonitorControlButton(
                icon: appState.playbackEngine.isPlaying ? "pause.fill" : "play.fill",
                label: appState.playbackEngine.isPlaying ? "Pause" : "Play",
                isActive: appState.playbackEngine.isPlaying,
                isProminent: true,
                action: {
                    appState.playbackEngine.togglePlayPause()
                }
            )

            MonitorControlButton(icon: "forward.end.fill", label: "End", action: {
                let duration = appState.playbackEngine.duration
                appState.playbackEngine.seek(to: duration)
                appState.timelineViewState.playheadPosition = duration
            })

            Spacer(minLength: 0)

            MonitorControlButton(icon: "repeat", label: "Loop", isActive: appState.playbackEngine.loopEnabled, action: {
                appState.playbackEngine.loopEnabled.toggle()
            })

            MonitorControlButton(icon: "minus.magnifyingglass", label: "Zoom Out", action: {
                appState.timelineViewState.zoomOut()
            })

            MonitorControlButton(icon: "plus.magnifyingglass", label: "Zoom In", action: {
                appState.timelineViewState.zoomIn()
            })
        }
        .padding(.horizontal, UtilitySpacing.md)
        .padding(.vertical, UtilitySpacing.sm)
        .background(UtilityTheme.chromeElevated)
    }
}
