import SwiftUI
import EditorCore

struct TimelinePanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let viewState = appState.timelineViewState
        let timeline = appState.timeline

        VStack(spacing: 0) {
            timelineToolbar(viewState: viewState, trackCount: timeline.tracks.count)
            Divider()
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        let totalWidth = max(viewState.durationToWidth(timeline.duration + 10), geo.size.width)

                        VStack(spacing: 0) {
                            TimelineRuler(viewState: viewState, totalWidth: totalWidth)
                                .frame(height: 28)

                            Divider()

                            if timeline.tracks.isEmpty {
                                emptyTimeline(width: totalWidth, height: geo.size.height - 30)
                            } else {
                                trackStack(timeline: timeline, viewState: viewState, width: totalWidth)
                            }
                        }
                        .frame(width: totalWidth)

                        PlayheadView(viewState: viewState) {
                            appState.seekFromPlayhead()
                        }
                        .frame(width: totalWidth, height: geo.size.height)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Toolbar

    private func timelineToolbar(viewState: TimelineViewState, trackCount: Int) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                let track = Track(name: "Video \(trackCount + 1)", type: .video)
                try? appState.perform(.addTrack(track: track))
            }) {
                Label("Add Track", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Spacer()

            // Undo/Redo
            Button(action: { try? appState.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(!appState.commandHistory.canUndo)

            Button(action: { try? appState.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.borderless)
            .disabled(!appState.commandHistory.canRedo)

            Spacer()

            Button(action: { viewState.zoomOut() }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Text("\(Int(viewState.zoom))px/s")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 55)

            Button(action: { viewState.zoomIn() }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private func emptyTimeline(width: Double, height: Double) -> some View {
        VStack {
            Spacer()
            Text("Add a track to begin editing")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
        }
        .frame(width: width, height: height)
    }

    // MARK: - Track Stack

    private func trackStack(timeline: Timeline, viewState: TimelineViewState, width: Double) -> some View {
        VStack(spacing: 1) {
            ForEach(timeline.tracks) { track in
                TimelineTrackView(
                    track: track,
                    viewState: viewState,
                    selectedClipIDs: viewState.selectedClipIDs,
                    isSelectedTrack: viewState.selectedTrackID == track.id,
                    totalWidth: width,
                    onTrackTap: { viewState.selectedTrackID = track.id },
                    onClipTap: { clipID, extend in
                        viewState.selectedTrackID = track.id
                        viewState.toggleSelection(clipID, extend: extend)
                    },
                    onClipDrag: { clipID, newStart in
                        try? appState.perform(.moveClip(clipID: clipID, newStart: newStart, trackID: track.id))
                    }
                )
            }
            Spacer()
        }
    }
}
