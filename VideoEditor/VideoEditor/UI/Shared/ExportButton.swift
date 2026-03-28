import SwiftUI
import EditorCore

struct ExportButton: View {
    @Environment(AppState.self) private var appState
    @State private var showExportDialog = false

    var body: some View {
        Group {
            switch appState.exportEngine.state {
            case .idle:
                Button(action: { showExportDialog = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                        Text("Export")
                            .font(.cinTitleSmall)
                    }
                    .foregroundStyle(CinematicTheme.onPrimaryContainer)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(CinematicTheme.primaryContainer)
                    .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
                }
                .buttonStyle(.plain)
                .disabled(!appState.canExportCurrentTimeline)

            case .exporting(let progress):
                HStack(spacing: 8) {
                    ProgressView(value: Double(progress))
                        .frame(width: 80)
                        .tint(CinematicTheme.primary)
                    Text("\(Int(progress * 100))%")
                        .font(.cinLabel)
                        .monospacedDigit()
                        .foregroundStyle(CinematicTheme.onSurfaceVariant)
                    Button("Cancel") {
                        appState.exportEngine.cancel()
                    }
                    .buttonStyle(.plain)
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.error)
                }

            case .completed:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: 0x53E16F))
                    Text("Exported")
                        .font(.cinTitleSmall)
                        .foregroundStyle(Color(hex: 0x53E16F))
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        appState.exportEngine.reset()
                    }
                }

            case .failed(let message):
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(CinematicTheme.error)
                    Text(message)
                        .font(.cinLabelRegular)
                        .foregroundStyle(CinematicTheme.error)
                        .lineLimit(1)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        appState.exportEngine.reset()
                    }
                }
            }
        }
        .sheet(isPresented: $showExportDialog) {
            ExportDialog(isPresented: $showExportDialog)
        }
    }
}
