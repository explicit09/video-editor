import SwiftUI
import EditorCore

struct TimelineToolbarView: View {
    @Environment(AppState.self) private var appState

    let tool: EditorTool
    let viewState: TimelineViewState
    let timeline: Timeline

    var body: some View {
        let selectionRange = viewState.selectedTimeRange(in: timeline)
        let canZoomToExtent = timeline.duration > 0

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

            UtilityStatusBadge(
                text: tool.rawValue.uppercased(),
                icon: tool.icon,
                isAccent: true
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
                UtilityStatusBadge(
                    text: viewState.snapEnabled ? "SNAP ON" : "SNAP OFF",
                    icon: "scope",
                    isAccent: viewState.snapEnabled
                )
            }
            .buttonStyle(.plain)

            Button {
                viewState.rippleEnabled.toggle()
            } label: {
                UtilityStatusBadge(
                    text: viewState.rippleEnabled ? "RIPPLE ON" : "RIPPLE OFF",
                    icon: "arrow.left.arrow.right.circle",
                    isAccent: viewState.rippleEnabled
                )
            }
            .buttonStyle(.plain)

            Button {
                viewState.linkedSelectionEnabled.toggle()
            } label: {
                UtilityStatusBadge(
                    text: viewState.linkedSelectionEnabled ? "LINKED ON" : "LINKED OFF",
                    icon: "link",
                    isAccent: viewState.linkedSelectionEnabled
                )
            }
            .buttonStyle(.plain)

            Button {
                viewState.autoFollowPlayhead.toggle()
            } label: {
                UtilityStatusBadge(
                    text: viewState.autoFollowPlayhead ? "FOLLOW ON" : "FOLLOW OFF",
                    icon: "dot.radiowaves.left.and.right",
                    isAccent: viewState.autoFollowPlayhead
                )
            }
            .buttonStyle(.plain)

            UtilityStatusBadge(
                text: "\(timeline.tracks.count) lanes",
                icon: "square.stack.3d.down.right",
            )

            UtilityStatusBadge(
                text: zoomLabel(for: viewState.zoom),
                icon: "timeline.selection",
            )

            Menu {
                Button("Zoom In") { viewState.zoomIn() }
                Button("Zoom Out") { viewState.zoomOut() }
                Divider()
                Button("Fit Selection") {
                    if let selectionRange {
                        viewState.zoomToRange(selectionRange)
                    }
                }
                .disabled(selectionRange == nil)
                Button("Full Extent") { viewState.zoomToFit(duration: timeline.duration) }
                    .disabled(!canZoomToExtent)
                Button("Detail Zoom") { viewState.zoomToDetail() }
                Divider()
                ForEach(TimelineViewState.zoomPresets, id: \.self) { preset in
                    Button(zoomPresetLabel(for: preset)) {
                        viewState.setZoom(preset)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    CinematicToolbarButton(icon: "minus", action: { viewState.zoomOut() })
                    CinematicToolbarButton(
                        icon: selectionRange == nil ? "arrow.left.and.right" : "viewfinder",
                        action: { performPrimaryZoom(selectionRange: selectionRange, canZoomToExtent: canZoomToExtent) }
                    )
                    .disabled(selectionRange == nil && !canZoomToExtent)
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

    private func performPrimaryZoom(selectionRange: TimeRange?, canZoomToExtent: Bool) {
        if let selectionRange {
            viewState.zoomToRange(selectionRange)
        } else if canZoomToExtent {
            viewState.zoomToFit(duration: timeline.duration)
        }
    }

    private func zoomPresetLabel(for preset: Double) -> String {
        if preset < 10 {
            return String(format: "%.1f px/s", preset)
        }
        return "\(Int(preset.rounded())) px/s"
    }
}
