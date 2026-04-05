import SwiftUI

// MARK: - The Cinematic Canvas Design System
// Extracted from Stitch project "VideoEditor" (project ID: 17752847932777922491)

/// Color tokens from "The Cinematic Canvas" design system.
/// No-Line Rule: structure defined through background color shifts, not borders.
enum CinematicTheme {

    // MARK: - Surface Hierarchy (Level 0–3)

    /// Level 0 — Base canvas
    static let surface = Color(hex: 0x131313)
    /// Level 0 — Dim variant (same as surface for OLED safety)
    static let surfaceDim = Color(hex: 0x131313)
    /// Level 1 — Sub-panels (media pools, secondary tools)
    static let surfaceContainerLow = Color(hex: 0x1C1B1B)
    /// Between Level 1 and 2
    static let surfaceContainer = Color(hex: 0x201F1F)
    /// Level 2 — Active focus (timeline tracks, inspector fields)
    static let surfaceContainerHigh = Color(hex: 0x2A2A2A)
    /// Level 3 — Floating elements (command bar, menus)
    static let surfaceContainerHighest = Color(hex: 0x353534)
    /// Recessed elements (input fields, deepest blacks)
    static let surfaceContainerLowest = Color(hex: 0x0E0E0E)
    /// Hover states
    static let surfaceBright = Color(hex: 0x393939)
    static let surfaceGlass = Color(hex: 0x171A22)

    // MARK: - Primary (AI Accent — Electric Indigo)

    /// AI accent light — text, icons on dark backgrounds
    static let primary = Color(hex: 0xC2C1FF)
    /// AI accent dark — buttons, active indicators
    static let primaryContainer = Color(hex: 0x5E5CE6)
    /// Text on primary container
    static let onPrimaryContainer = Color(hex: 0xF4F1FF)
    /// Fixed primary (for non-theme-aware contexts)
    static let primaryFixed = Color(hex: 0xE2DFFF)
    static let primaryFixedDim = Color(hex: 0xC2C1FF)

    // MARK: - Secondary (Neutral)

    static let secondary = Color(hex: 0xC8C6C8)
    static let secondaryContainer = Color(hex: 0x49494B)

    // MARK: - Tertiary (Timeline / Functional Blue)

    static let tertiary = Color(hex: 0xAAC7FF)
    static let tertiaryContainer = Color(hex: 0x006DD6)
    static let tertiaryFixedDim = Color(hex: 0xAAC7FF)
    static let aqua = Color(hex: 0x7DE7FF)

    // MARK: - Error / Alert

    static let error = Color(hex: 0xFFB4AB)
    static let errorContainer = Color(hex: 0x93000A)

    // MARK: - Text

    /// Primary text — headlines, active values
    static let onSurface = Color(hex: 0xE5E2E1)
    /// Secondary text — labels, inactive content
    static let onSurfaceVariant = Color(hex: 0xC7C4D7)
    /// Text on background
    static let onBackground = Color(hex: 0xE5E2E1)

    // MARK: - Outlines

    /// Visible outlines (rare)
    static let outline = Color(hex: 0x918FA0)
    /// Ghost borders — 15% opacity max
    static let outlineVariant = Color(hex: 0x464554)

    // MARK: - Inverse (for contrast elements)

    static let inverseSurface = Color(hex: 0xE5E2E1)
    static let inverseOnSurface = Color(hex: 0x313030)
    static let inversePrimary = Color(hex: 0x4D4AD5)

    // MARK: - Semantic Colors

    /// Clip type colors (muted pro-colorist aesthetic)
    static let clipVideo = tertiaryFixedDim
    static let clipAudio = Color(hex: 0x53E16F).opacity(0.6)
    static let clipSubtitle = primaryFixedDim

    /// AI glow shadow
    static let aiGlow = primaryContainer.opacity(0.3)
    static let panelStroke = outlineVariant.opacity(0.28)
    static let panelShadow = Color.black.opacity(0.28)
    static let success = Color(hex: 0x53E16F)
    static let warning = Color(hex: 0xF5CC64)
}

// MARK: - Typography

extension Font {
    /// Display — Hero AI stats, mode transitions (3.5rem / Bold)
    static let cinDisplayLarge = Font.system(size: 56, weight: .bold, design: .default)
    /// Headline — Major panel headers (1.5rem / SemiBold)
    static let cinHeadline = Font.system(size: 24, weight: .semibold, design: .default)
    /// Headline Small — Section headers (1.125rem / SemiBold)
    static let cinHeadlineSmall = Font.system(size: 18, weight: .semibold, design: .default)
    /// Title — Clip names, effect titles (1rem / Medium)
    static let cinTitle = Font.system(size: 16, weight: .medium, design: .default)
    /// Title Small — Compact titles (0.875rem / Medium)
    static let cinTitleSmall = Font.system(size: 14, weight: .medium, design: .default)
    /// Body — Metadata, AI chat text (0.875rem / Regular)
    static let cinBody = Font.system(size: 14, weight: .regular, design: .default)
    /// Label — Timestamps, keyboard shortcuts (0.6875rem / Bold)
    static let cinLabel = Font.system(size: 11, weight: .bold, design: .default)
    /// Label Regular — Less prominent labels
    static let cinLabelRegular = Font.system(size: 11, weight: .regular, design: .default)
    /// Timecode — Monospaced for stable layout (1rem / SemiBold)
    static let cinTimecode = Font.system(size: 16, weight: .semibold, design: .monospaced)
    /// Timecode Large — Hero timecode display (2.25rem / Bold)
    static let cinTimecodeLarge = Font.system(size: 36, weight: .bold, design: .monospaced)
}

// MARK: - Corner Radius

enum CinematicRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 18
    static let full: CGFloat = 999
}

// MARK: - Spacing

enum CinematicSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 36
    static let clipGap: CGFloat = 2
    static let standard: CGFloat = 8
    static let sectionGap: CGFloat = 12
    static let panelPadding: CGFloat = 16
}

enum CinematicMetrics {
    static let topBarHeight: CGFloat = 52
    static let panelHeaderHeight: CGFloat = 50
    static let controlHeight: CGFloat = 30
    static let fieldHeight: CGFloat = 34
    static let compactSidebarWidth: CGFloat = 280
    static let expandedSidebarWidth: CGFloat = 336
    static let compactRightRailWidth: CGFloat = 300
    static let expandedRightRailWidth: CGFloat = 360
}

enum DesignSystem {
    static let utilityTopBarHeight = UtilityMetrics.topBarHeight
    static let utilityPageBarHeight = UtilityMetrics.pageBarHeight
    static let utilityPanelHeaderHeight = UtilityMetrics.panelHeaderHeight
    static let utilityControlHeight = UtilityMetrics.controlHeight
}

enum UtilityTheme {
    static let canvas = Color(hex: 0x171819)
    static let chrome = Color(hex: 0x1D1F21)
    static let chromeElevated = Color(hex: 0x25282B)
    static let panel = Color(hex: 0x202326)
    static let recessed = Color(hex: 0x141618)
    static let stroke = Color.white.opacity(0.08)
    static let text = Color(hex: 0xE7EAEE)
    static let textMuted = Color(hex: 0xA2A9B0)
    static let accent = Color(hex: 0x5E87FF)
    static let accentText = Color.white
    static let shadow = Color.black.opacity(0.18)
}

enum UtilitySpacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
}

enum UtilityRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
    static let capsule: CGFloat = 999
}

enum UtilityMetrics {
    static let topBarHeight: CGFloat = 42
    static let pageBarHeight: CGFloat = 36
    static let controlHeight: CGFloat = 28
    static let panelHeaderHeight: CGFloat = 34
}

enum UtilitySurfaceTone {
    case chrome
    case chromeElevated
    case panel
    case recessed

    var fill: Color {
        switch self {
        case .chrome:
            UtilityTheme.chrome
        case .chromeElevated:
            UtilityTheme.chromeElevated
        case .panel:
            UtilityTheme.panel
        case .recessed:
            UtilityTheme.recessed
        }
    }
}

struct UtilitySurfaceModifier: ViewModifier {
    let tone: UtilitySurfaceTone
    var radius: CGFloat = UtilityRadius.md
    var shadow: Bool = false

    func body(content: Content) -> some View {
        content
            .background(tone.fill)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(UtilityTheme.stroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .shadow(color: shadow ? UtilityTheme.shadow : .clear, radius: 10, y: 4)
    }
}

extension View {
    func utilitySurface(
        _ tone: UtilitySurfaceTone = .panel,
        radius: CGFloat = UtilityRadius.md,
        shadow: Bool = false
    ) -> some View {
        modifier(UtilitySurfaceModifier(tone: tone, radius: radius, shadow: shadow))
    }
}

struct UtilityPanelHeader<LeadingAccessory: View, TrailingAccessory: View>: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    @ViewBuilder var leadingAccessory: LeadingAccessory
    @ViewBuilder var trailingAccessory: TrailingAccessory

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leadingAccessory: () -> LeadingAccessory = { EmptyView() },
        @ViewBuilder trailingAccessory: () -> TrailingAccessory = { EmptyView() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.leadingAccessory = leadingAccessory()
        self.trailingAccessory = trailingAccessory()
    }

    var body: some View {
        HStack(spacing: UtilitySpacing.sm) {
            leadingAccessory

            VStack(alignment: .leading, spacing: UtilitySpacing.xxxs) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(UtilityTheme.textMuted)
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(UtilityTheme.text)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(UtilityTheme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
            trailingAccessory
        }
        .padding(.horizontal, UtilitySpacing.md)
        .frame(height: UtilityMetrics.panelHeaderHeight)
        .background(UtilityTheme.chromeElevated)
    }
}

enum CinematicPanelTone {
    case base
    case elevated
    case recessed
    case floating

    var fill: Color {
        switch self {
        case .base: CinematicTheme.surfaceContainerLow
        case .elevated: CinematicTheme.surfaceContainer
        case .recessed: CinematicTheme.surfaceContainerLowest
        case .floating: CinematicTheme.surfaceGlass
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Glass Panel Modifier

struct GlassPanel: ViewModifier {
    var blur: CGFloat = 20
    var tint: Color = CinematicTheme.surfaceContainerHighest

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(tint.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
    }
}

extension View {
    func glassPanel(blur: CGFloat = 20, tint: Color = CinematicTheme.surfaceContainerHighest) -> some View {
        modifier(GlassPanel(blur: blur, tint: tint))
    }
}

// MARK: - AI Glow Shadow Modifier

struct AIGlow: ViewModifier {
    var radius: CGFloat = 15
    var color: Color = CinematicTheme.primaryContainer

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.3), radius: radius)
    }
}

extension View {
    func aiGlow(radius: CGFloat = 15) -> some View {
        modifier(AIGlow(radius: radius))
    }
}

struct CinematicPanelSurface: ViewModifier {
    let tone: CinematicPanelTone
    var strokeOpacity: Double = 1
    var shadow: Bool = false

    func body(content: Content) -> some View {
        content
            .background(tone.fill)
            .overlay(
                RoundedRectangle(cornerRadius: CinematicRadius.lg)
                    .strokeBorder(CinematicTheme.panelStroke.opacity(strokeOpacity), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
            .shadow(color: shadow ? CinematicTheme.panelShadow : .clear, radius: 16, y: 10)
    }
}

extension View {
    func panelSurface(_ tone: CinematicPanelTone = .base, strokeOpacity: Double = 1, shadow: Bool = false) -> some View {
        modifier(CinematicPanelSurface(tone: tone, strokeOpacity: strokeOpacity, shadow: shadow))
    }
}

struct CinematicPanelHeader<LeadingAccessory: View, TrailingAccessory: View>: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    @ViewBuilder var leadingAccessory: LeadingAccessory
    @ViewBuilder var trailingAccessory: TrailingAccessory

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leadingAccessory: () -> LeadingAccessory = { EmptyView() },
        @ViewBuilder trailingAccessory: () -> TrailingAccessory = { EmptyView() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.leadingAccessory = leadingAccessory()
        self.trailingAccessory = trailingAccessory()
    }

    var body: some View {
        HStack(spacing: CinematicSpacing.sm) {
            leadingAccessory

            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.cinLabel)
                        .tracking(1.4)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72))
                }

                Text(title)
                    .font(.cinTitle)
                    .foregroundStyle(CinematicTheme.onSurface)

                if let subtitle {
                    Text(subtitle)
                        .font(.cinLabelRegular)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.68))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
            trailingAccessory
        }
        .frame(height: CinematicMetrics.panelHeaderHeight)
        .padding(.horizontal, CinematicSpacing.md)
    }
}

struct CinematicToolbarButton: View {
    let icon: String
    var label: String? = nil
    var isActive = false
    var isDestructive = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                if let label {
                    Text(label)
                        .font(.cinLabelRegular)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, label == nil ? 8 : 10)
            .frame(height: CinematicMetrics.controlHeight)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        if isDestructive {
            return CinematicTheme.error
        }
        return isActive ? CinematicTheme.onPrimaryContainer : CinematicTheme.onSurfaceVariant
    }

    private var background: some ShapeStyle {
        if isDestructive {
            return AnyShapeStyle(CinematicTheme.errorContainer.opacity(0.2))
        }
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [CinematicTheme.primaryContainer, CinematicTheme.tertiaryContainer.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(CinematicTheme.surfaceContainerHighest.opacity(0.72))
    }
}

struct CinematicStatusPill: View {
    let text: String
    var icon: String? = nil
    var tone: Color = CinematicTheme.primary

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.cinLabel)
                .tracking(1)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(tone.opacity(0.12))
        .clipShape(Capsule())
    }
}

struct CinematicCard<Content: View>: View {
    let tone: CinematicPanelTone
    @ViewBuilder var content: Content

    init(tone: CinematicPanelTone = .elevated, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        content
            .padding(CinematicSpacing.md)
            .panelSurface(tone, strokeOpacity: 0.8)
    }
}

struct CinematicEmptyStateBlock<Accessory: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder var accessory: Accessory

    init(icon: String, title: String, detail: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: CinematicSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(CinematicTheme.aqua.opacity(0.72))
                .frame(width: 52, height: 52)
                .background(CinematicTheme.surfaceContainerHighest.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))

            VStack(spacing: 6) {
                Text(title)
                    .font(.cinHeadlineSmall)
                    .foregroundStyle(CinematicTheme.onSurface)
                Text(detail)
                    .font(.cinBody)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72))
                    .multilineTextAlignment(.center)
            }

            accessory
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CinematicSpacing.xl)
    }
}

struct CinematicInspectorFieldRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    init(label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.cinLabel)
                .tracking(1.2)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.64))
            value
        }
    }
}

struct CinematicSegmentedTabBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    var label: (Item) -> String
    var icon: ((Item) -> String?)? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item
                Button {
                    selection = item
                } label: {
                    HStack(spacing: 6) {
                        if let iconName = icon?(item) {
                            Image(systemName: iconName)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(label(item))
                            .font(.cinLabelRegular)
                    }
                    .foregroundStyle(isSelected ? CinematicTheme.onPrimaryContainer : CinematicTheme.onSurfaceVariant)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [CinematicTheme.primaryContainer, CinematicTheme.tertiaryContainer.opacity(0.72)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            : AnyShapeStyle(CinematicTheme.surfaceContainerHighest.opacity(0.68))
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(CinematicTheme.surfaceContainerLowest.opacity(0.9))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(CinematicTheme.panelStroke.opacity(0.8), lineWidth: 1)
        )
    }
}
