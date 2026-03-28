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
    /// Inputs, small elements (0.125rem → 2pt)
    static let sm: CGFloat = 2
    /// Buttons (0.375rem → 6pt)
    static let md: CGFloat = 6
    /// Cards, clips (0.25rem → 4pt)
    static let lg: CGFloat = 4
    /// Panels, large containers (0.5rem → 8pt)
    static let xl: CGFloat = 8
    /// Pills, command bar (0.75rem → 12pt)
    static let full: CGFloat = 12
}

// MARK: - Spacing

enum CinematicSpacing {
    /// Micro gap between clips (0.1rem → 1.6pt)
    static let clipGap: CGFloat = 1.6
    /// Tight density padding (0.5rem → 8pt)
    static let standard: CGFloat = 8
    /// Section spacing (0.3rem → 4.8pt)
    static let sectionGap: CGFloat = 4.8
    /// Panel padding
    static let panelPadding: CGFloat = 16
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
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.full))
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
