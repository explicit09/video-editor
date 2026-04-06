import SwiftUI
import EditorCore

struct OverlayPresentationSection: View {
    let clip: Clip
    let applyPreset: (OverlayPiPPreset) -> Void
    let updatePresentation: (OverlayPresentation) -> Void

    private var presentation: OverlayPresentation { clip.overlayPresentation }
    private var isPiP: Bool { presentation.mode == .pip }

    var body: some View {
        CinematicCard {
            VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                Text("Picture in Picture")
                    .font(.cinTitleSmall)
                    .foregroundStyle(CinematicTheme.onSurface)

                presetGrid

                if isPiP {
                    styleControls
                    resetButton
                }
            }
        }
    }

    // MARK: - Preset Grid

    private var presetGrid: some View {
        VStack(spacing: CinematicSpacing.sm) {
            Text("Position")
                .font(.cinLabelRegular)
                .foregroundStyle(CinematicTheme.onSurfaceVariant)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: CinematicSpacing.sm) {
                presetButton(.topLeft, label: "Top Left", icon: "arrow.up.left")
                presetButton(.topRight, label: "Top Right", icon: "arrow.up.right")
                presetButton(.bottomLeft, label: "Bottom Left", icon: "arrow.down.left")
                presetButton(.bottomRight, label: "Bottom Right", icon: "arrow.down.right")
            }
        }
    }

    private func presetButton(_ preset: OverlayPiPPreset, label: String, icon: String) -> some View {
        Button {
            applyPreset(preset)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.cinLabelRegular)
            }
            .frame(maxWidth: .infinity)
            .frame(height: CinematicMetrics.fieldHeight)
            .background(CinematicTheme.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
        }
        .buttonStyle(.plain)
        .foregroundStyle(CinematicTheme.onSurface)
    }

    // MARK: - Style Controls

    private var styleControls: some View {
        VStack(alignment: .leading, spacing: CinematicSpacing.sm) {
            CinematicInspectorFieldRow(label: "Border") {
                Toggle("", isOn: Binding(
                    get: { presentation.border.isVisible },
                    set: { newValue in
                        var p = presentation
                        p.border.isVisible = newValue
                        if newValue && p.border.width == 0 { p.border.width = 2 }
                        updatePresentation(p)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            CinematicInspectorFieldRow(label: "Shadow") {
                Picker("", selection: Binding(
                    get: { presentation.shadow },
                    set: { newValue in
                        var p = presentation
                        p.shadow = newValue
                        updatePresentation(p)
                    }
                )) {
                    ForEach([OverlayShadowStyle.none, .light, .medium, .heavy], id: \.self) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                }
                .labelsHidden()
            }

            CinematicInspectorFieldRow(label: "Radius") {
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { presentation.cornerRadius },
                        set: { newValue in
                            var p = presentation
                            p.cornerRadius = newValue
                            updatePresentation(p)
                        }
                    ), in: 0...50)
                    .tint(CinematicTheme.primary)
                    Text("\(Int(presentation.cornerRadius))")
                        .font(.cinLabelRegular)
                        .monospacedDigit()
                        .foregroundStyle(CinematicTheme.onSurfaceVariant)
                        .frame(width: 28, alignment: .trailing)
                }
            }

            CinematicInspectorFieldRow(label: "Shape") {
                Picker("", selection: Binding(
                    get: { presentation.maskShape },
                    set: { newValue in
                        var p = presentation
                        p.maskShape = newValue
                        updatePresentation(p)
                    }
                )) {
                    ForEach([OverlayMaskShape.rectangle, .roundedRect, .circle], id: \.self) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .labelsHidden()
            }
        }
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button("Reset to Inline") {
            updatePresentation(.default)
        }
        .font(.cinLabelRegular)
        .foregroundStyle(CinematicTheme.primary)
        .buttonStyle(.plain)
    }
}
