import SwiftUI
import EditorCore
import AVFoundation

/// Export dialog — Stitch Screen 6: AI-recommended presets.
struct ExportDialog: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    @State private var selectedPreset: ExportPreset = .youtube4k

    enum ExportPreset: String, CaseIterable, Identifiable {
        case youtube4k = "YouTube 4K"
        case youtube1080 = "YouTube 1080p"
        case tiktok = "TikTok/Reels (Vertical)"
        case prores = "ProRes 4444"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .youtube4k, .youtube1080: "play.rectangle.fill"
            case .tiktok: "iphone"
            case .prores: "film"
            }
        }

        var details: String {
            switch self {
            case .youtube4k: "3840 × 2160 • H.264 • 60fps"
            case .youtube1080: "1920 × 1080 • H.264 • 30fps"
            case .tiktok: "1080 × 1920 • H.264 • 30fps"
            case .prores: "Uncompressed • Mastering Quality"
            }
        }

        var avPreset: String {
            switch self {
            case .youtube4k: AVAssetExportPreset3840x2160
            case .youtube1080: AVAssetExportPreset1920x1080
            case .tiktok: AVAssetExportPreset1920x1080
            case .prores: AVAssetExportPresetAppleProRes4444LPCM
            }
        }

        var fileType: AVFileType {
            switch self {
            case .youtube4k, .youtube1080, .tiktok: .mp4
            case .prores: .mov
            }
        }

        var fileExtension: String {
            switch self {
            case .youtube4k, .youtube1080, .tiktok: "mp4"
            case .prores: "mov"
            }
        }
    }

    var body: some View {
        let isExporting: Bool = {
            if case .exporting = appState.exportEngine.state { return true }
            return false
        }()
        let canExport = appState.canExportCurrentTimeline && !isExporting

        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Project")
                    .font(.cinHeadline)
                    .foregroundStyle(CinematicTheme.onSurface)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(CinematicTheme.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            // AI recommendation
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(CinematicTheme.primary)
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI RECOMMENDATION")
                        .font(.cinLabel)
                        .tracking(1)
                        .foregroundStyle(CinematicTheme.primary)
                    Text("YouTube 4K is suggested based on your source footage resolution.")
                        .font(.cinLabelRegular)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.7))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CinematicTheme.primaryContainer.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
            .padding(.horizontal, 20)

            if !appState.canExportCurrentTimeline {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(CinematicTheme.warning)
                    Text("Add at least one clip to the timeline before exporting.")
                        .font(.cinLabelRegular)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            Spacer().frame(height: 16)

            // Project info
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DURATION")
                        .font(.cinLabel)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                    Text(TimeFormatter.durationHMS(appState.timeline.duration))
                        .font(.cinTimecode)
                        .foregroundStyle(CinematicTheme.onSurface)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRACKS")
                        .font(.cinLabel)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                    Text("\(appState.timeline.tracks.count)")
                        .font(.cinTimecode)
                        .foregroundStyle(CinematicTheme.onSurface)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("CLIPS")
                        .font(.cinLabel)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                    Text("\(appState.clipCount)")
                        .font(.cinTimecode)
                        .foregroundStyle(CinematicTheme.onSurface)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            Spacer().frame(height: 20)

            // Preset list
            Text("EXPORT PRESETS")
                .font(.cinLabel)
                .tracking(1)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            Spacer().frame(height: 8)

            VStack(spacing: 6) {
                ForEach(ExportPreset.allCases) { preset in
                    presetRow(preset)
                }
            }
            .padding(.horizontal, 20)

            Spacer().frame(height: 20)

            // Actions
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                    .font(.cinBody)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant)
                    .padding(.trailing, 16)

                Button(action: startExport) {
                    HStack(spacing: 6) {
                        Text("Export")
                            .font(.cinTitleSmall)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(CinematicTheme.onPrimaryContainer)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(CinematicTheme.primaryContainer)
                    .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
                }
                .buttonStyle(.plain)
                .disabled(!canExport)
                .opacity(canExport ? 1 : 0.45)
            }
            .padding(20)
        }
        .frame(width: 420, height: 520)
        .background(CinematicTheme.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.xl)
                .strokeBorder(CinematicTheme.outlineVariant.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30)
    }

    private func presetRow(_ preset: ExportPreset) -> some View {
        let isSelected = selectedPreset == preset
        return Button(action: { selectedPreset = preset }) {
            HStack(spacing: 12) {
                Image(systemName: preset.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? CinematicTheme.primary : CinematicTheme.onSurfaceVariant.opacity(0.5))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.rawValue)
                        .font(.cinTitleSmall)
                        .foregroundStyle(CinematicTheme.onSurface)
                    Text(preset.details)
                        .font(.cinLabelRegular)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(CinematicTheme.primaryContainer)
                }
            }
            .padding(10)
            .background(isSelected ? CinematicTheme.primaryContainer.opacity(0.08) : CinematicTheme.surfaceContainerHigh)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .strokeBorder(isSelected ? CinematicTheme.primaryContainer.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func startExport() {
        guard appState.canExportCurrentTimeline else { return }
        isPresented = false
        let preset = selectedPreset
        let panel = NSSavePanel()
        panel.allowedContentTypes = preset.fileType == .mov ? [.quickTimeMovie] : [.mpeg4Movie]
        panel.nameFieldStringValue = "export.\(preset.fileExtension)"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await appState.exportEngine.export(
                timeline: appState.timeline,
                assets: appState.assets,
                to: url,
                preset: preset.avPreset,
                fileType: preset.fileType
            )
        }
    }

}
