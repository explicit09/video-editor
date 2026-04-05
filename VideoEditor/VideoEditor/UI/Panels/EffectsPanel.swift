import SwiftUI

struct EffectsPanel: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedTool: EditorTool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            UtilityPanelHeader(
                eyebrow: "TOOLS",
                title: "Effects & Modes",
                subtitle: "Selection posture, timeline modifiers, and fast-access finishing controls."
            )

            ScrollView {
                VStack(alignment: .leading, spacing: UtilitySpacing.md) {
                    section(title: "Edit Tools") {
                        HStack(spacing: UtilitySpacing.xs) {
                            ForEach(EditorTool.allCases, id: \.self) { tool in
                                toolButton(for: tool)
                            }
                        }
                    }

                    section(title: "Timeline Modifiers") {
                        VStack(spacing: UtilitySpacing.xs) {
                            toggleRow(
                                title: "Linked Selection",
                                subtitle: "Keep paired clips available for explicit extend-select moves.",
                                isOn: binding(
                                    get: { appState.timelineViewState.linkedSelectionEnabled },
                                    set: { appState.timelineViewState.linkedSelectionEnabled = $0 }
                                )
                            )
                            toggleRow(
                                title: "Snapping",
                                subtitle: "Lock trims and moves to nearby edit points.",
                                isOn: binding(
                                    get: { appState.timelineViewState.snapEnabled },
                                    set: { appState.timelineViewState.snapEnabled = $0 }
                                )
                            )
                            toggleRow(
                                title: "Ripple",
                                subtitle: "Close gaps automatically when removing material.",
                                isOn: binding(
                                    get: { appState.timelineViewState.rippleEnabled },
                                    set: { appState.timelineViewState.rippleEnabled = $0 }
                                )
                            )
                        }
                    }

                    section(title: "Quick Effects") {
                        VStack(spacing: UtilitySpacing.xs) {
                            effectPill(title: "Transform Presets", subtitle: "Position, scale, and crop adjustments")
                            effectPill(title: "Color Cleanup", subtitle: "Balance exposure and contrast")
                            effectPill(title: "Audio Polish", subtitle: "Voice focus and loudness shaping")
                        }
                    }
                }
                .padding(UtilitySpacing.md)
            }
        }
        .background(CinematicTheme.surfaceContainerLow)
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

    private func toolButton(for tool: EditorTool) -> some View {
        Button {
            selectedTool = tool
        } label: {
            VStack(alignment: .leading, spacing: UtilitySpacing.xxxs) {
                Image(systemName: tool.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(tool.rawValue)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selectedTool == tool ? UtilityTheme.accentText : UtilityTheme.text)
            .padding(UtilitySpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedTool == tool ? UtilityTheme.accent : UtilityTheme.chrome)
            .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.sm))
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: UtilitySpacing.xxxs) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UtilityTheme.text)
                Text(subtitle)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(UtilityTheme.textMuted)
            }
        }
        .toggleStyle(.switch)
        .padding(UtilitySpacing.sm)
        .background(UtilityTheme.chrome)
        .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.sm))
    }

    private func effectPill(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: UtilitySpacing.xxxs) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(UtilityTheme.text)
            Text(subtitle)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(UtilityTheme.textMuted)
        }
        .padding(UtilitySpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UtilityTheme.chrome)
        .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.sm))
    }

    private func binding(
        get: @escaping @Sendable () -> Bool,
        set: @escaping @Sendable (Bool) -> Void
    ) -> Binding<Bool> {
        Binding(get: get, set: set)
    }
}
