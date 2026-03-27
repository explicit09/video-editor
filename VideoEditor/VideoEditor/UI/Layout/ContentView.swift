import SwiftUI
import EditorCore

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HSplitView {
            MediaBrowserPanel()
                .frame(minWidth: 200, idealWidth: 250)

            VSplitView {
                PreviewPanel()
                    .frame(minHeight: 200)

                TimelinePanel()
                    .frame(minHeight: 150)
            }

            InspectorPanel()
                .frame(minWidth: 200, idealWidth: 250)
        }
        .frame(minWidth: 1200, minHeight: 700)
        .focusable()
        .onKeyPress(.space) {
            appState.playbackEngine.togglePlayPause()
            return .handled
        }
        .onKeyPress(.delete) {
            deleteSelectedClips()
            return .handled
        }
        .onKeyPress(KeyEquivalent("\u{7F}")) {
            deleteSelectedClips()
            return .handled
        }
    }

    private func deleteSelectedClips() {
        let selected = Array(appState.timelineViewState.selectedClipIDs)
        guard !selected.isEmpty else { return }
        try? appState.perform(.deleteClips(clipIDs: selected))
        appState.timelineViewState.clearSelection()
    }
}
