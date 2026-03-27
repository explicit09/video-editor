import SwiftUI
import EditorCore

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()

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
        }
        .frame(minWidth: 1200, minHeight: 700)
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        HStack {
            Text("Video Editor")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            ExportButton()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
