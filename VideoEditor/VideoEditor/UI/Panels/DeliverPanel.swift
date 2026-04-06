import SwiftUI
import AppKit

struct DeliverPanel: View {
    @Environment(AppState.self) private var appState
    @State private var isExportDialogPresented = false

    var body: some View {
        VStack(spacing: 0) {
            UtilityPanelHeader(
                eyebrow: "DELIVER",
                title: "Export & Output",
                subtitle: headerSubtitle
            ) {
                readinessBadge
            }

            ScrollView {
                VStack(alignment: .leading, spacing: UtilitySpacing.md) {
                    readinessSection
                    presetsSection
                    summarySection
                    exportStatusSection
                }
                .padding(UtilitySpacing.md)
            }
        }
        .background(CinematicTheme.surfaceContainerLow)
        .sheet(isPresented: $isExportDialogPresented) {
            ExportDialog(isPresented: $isExportDialogPresented)
        }
    }

    private var headerSubtitle: String {
        if appState.canExportCurrentTimeline {
            return "Export presets, readiness checks, and output status for the active sequence."
        }

        return "Add clips to the timeline before opening the export flow."
    }

    private var readinessBadge: some View {
        Text(appState.canExportCurrentTimeline ? "READY" : "NEEDS CLIPS")
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(appState.canExportCurrentTimeline ? UtilityTheme.accentText : UtilityTheme.text)
            .padding(.horizontal, UtilitySpacing.sm)
            .padding(.vertical, UtilitySpacing.xxxs)
            .background(appState.canExportCurrentTimeline ? UtilityTheme.accent : UtilityTheme.chrome)
            .clipShape(Capsule())
    }

    private var readinessSection: some View {
        section(title: "Readiness") {
            VStack(spacing: UtilitySpacing.xs) {
                statusRow(
                    title: "Timeline content",
                    detail: appState.clipCount > 0
                        ? "\(appState.clipCount) clips available for output"
                        : "No clips are placed on the sequence yet",
                    isReady: appState.clipCount > 0
                )
                statusRow(
                    title: "Program duration",
                    detail: appState.timeline.duration > 0
                        ? TimeFormatter.duration(appState.timeline.duration)
                        : "Timeline duration is still zero",
                    isReady: appState.timeline.duration > 0
                )
                statusRow(
                    title: "Output target",
                    detail: "Use the export dialog to choose destination, codec, and preset.",
                    isReady: true
                )
            }
        }
    }

    private var presetsSection: some View {
        section(title: "Presets") {
            VStack(alignment: .leading, spacing: UtilitySpacing.sm) {
                HStack(spacing: UtilitySpacing.xs) {
                    presetPill(title: "YouTube 4K", systemImage: "play.rectangle.fill")
                    presetPill(title: "YouTube 1080p", systemImage: "play.rectangle")
                    presetPill(title: "ProRes Master", systemImage: "film")
                }

                Button {
                    isExportDialogPresented = true
                } label: {
                    Label("Open Export Dialog", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appState.canExportCurrentTimeline ? UtilityTheme.accentText : UtilityTheme.textMuted)
                        .padding(.horizontal, UtilitySpacing.md)
                        .frame(height: 34)
                        .frame(maxWidth: .infinity)
                        .background(appState.canExportCurrentTimeline ? UtilityTheme.accent : UtilityTheme.chrome)
                        .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.sm))
                }
                .buttonStyle(.plain)
                .disabled(!appState.canExportCurrentTimeline)
            }
        }
    }

    private var summarySection: some View {
        section(title: "Sequence Summary") {
            HStack(spacing: UtilitySpacing.sm) {
                summaryMetric(value: "\(appState.timeline.tracks.count)", label: "Tracks")
                summaryMetric(value: "\(appState.clipCount)", label: "Clips")
                summaryMetric(value: TimeFormatter.duration(appState.timeline.duration), label: "Runtime")
            }
        }
    }

    @ViewBuilder
    private var exportStatusSection: some View {
        switch appState.exportEngine.state {
        case .idle:
            section(title: "Export Status") {
                Text("No export is running. Open the export dialog when the sequence is ready.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(UtilityTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .exporting(let progress):
            section(title: "Export Status") {
                VStack(alignment: .leading, spacing: UtilitySpacing.sm) {
                    HStack {
                        Text("Exporting timeline")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(UtilityTheme.text)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(UtilityTheme.accent)
                    }

                    ProgressView(value: Double(progress))
                        .tint(UtilityTheme.accent)

                    Button("Cancel Export") {
                        appState.exportEngine.cancel()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CinematicTheme.error)
                }
            }
        case .completed(let url):
            section(title: "Export Status") {
                VStack(alignment: .leading, spacing: UtilitySpacing.sm) {
                    statusRow(
                        title: "Export complete",
                        detail: url.lastPathComponent,
                        isReady: true
                    )

                    HStack(spacing: UtilitySpacing.sm) {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(
                                url.path,
                                inFileViewerRootedAtPath: url.deletingLastPathComponent().path
                            )
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(UtilityTheme.accent)

                        Button("Clear Status") {
                            appState.exportEngine.reset()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(UtilityTheme.textMuted)
                    }
                }
            }
        case .failed(let message):
            section(title: "Export Status") {
                VStack(alignment: .leading, spacing: UtilitySpacing.sm) {
                    statusRow(
                        title: "Export failed",
                        detail: message,
                        isReady: false
                    )

                    Button("Clear Error") {
                        appState.exportEngine.reset()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UtilityTheme.textMuted)
                }
            }
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: UtilitySpacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(UtilityTheme.textMuted)

            content()
        }
    }

    private func statusRow(
        title: String,
        detail: String,
        isReady: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: UtilitySpacing.sm) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isReady ? CinematicTheme.success : CinematicTheme.warning)

            VStack(alignment: .leading, spacing: UtilitySpacing.xxxs) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UtilityTheme.text)
                Text(detail)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(UtilityTheme.textMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(UtilitySpacing.sm)
        .background(UtilityTheme.chrome)
        .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.sm))
    }

    private func presetPill(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(UtilityTheme.text)
            .padding(.horizontal, UtilitySpacing.sm)
            .padding(.vertical, UtilitySpacing.xxxs)
            .background(UtilityTheme.chrome)
            .clipShape(Capsule())
    }

    private func summaryMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: UtilitySpacing.xxxs) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(UtilityTheme.text)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(UtilityTheme.textMuted)
        }
        .padding(UtilitySpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UtilityTheme.chrome)
        .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.sm))
    }
}
