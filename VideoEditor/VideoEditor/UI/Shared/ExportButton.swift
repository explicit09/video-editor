import SwiftUI
import EditorCore

struct ExportButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.exportEngine.state {
        case .idle:
            Button(action: startExport) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(appState.timeline.tracks.isEmpty)

        case .exporting(let progress):
            HStack(spacing: 8) {
                ProgressView(value: Double(progress))
                    .frame(width: 80)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                Button("Cancel") {
                    appState.exportEngine.cancel()
                }
                .buttonStyle(.borderless)
            }

        case .completed:
            Label("Exported", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .onAppear {
                    // Reset after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        appState.exportEngine.reset()
                    }
                }

        case .failed(let message):
            HStack {
                Label("Failed", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .lineLimit(1)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    appState.exportEngine.reset()
                }
            }
        }
    }

    private func startExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "export.mp4"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await appState.exportEngine.export(
                timeline: appState.timeline,
                assets: appState.assets,
                to: url
            )
        }
    }
}
