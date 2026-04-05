import SwiftUI

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
    static let panelHeaderMinHeight: CGFloat = 34
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

struct CompactPanelHeaderLayout: Equatable, Sendable {
    let showsPrimaryAction: Bool
    let showsSecondaryBadges: Bool

    static func make(
        availableWidth: Double,
        badgeCount: Int,
        showsPrimaryAction: Bool
    ) -> Self {
        let resolvedBadgeCount = max(badgeCount, 0)
        let supportsSecondaryBadges = resolvedBadgeCount > 0 && availableWidth >= 236

        return Self(
            showsPrimaryAction: showsPrimaryAction,
            showsSecondaryBadges: supportsSecondaryBadges
        )
    }
}

struct UtilityHeaderBadge: View {
    let text: String
    var systemImage: String? = nil
    var isAccent = false

    var body: some View {
        HStack(spacing: UtilitySpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isAccent ? UtilityTheme.accentText : UtilityTheme.textMuted)
        .padding(.horizontal, UtilitySpacing.sm)
        .frame(height: UtilityMetrics.controlHeight - 4)
        .background(isAccent ? UtilityTheme.accent : UtilityTheme.chrome)
        .clipShape(Capsule())
    }
}

struct UtilityHeaderButton: View {
    let icon: String
    var title: String? = nil
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: UtilitySpacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))

                if let title {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isProminent ? UtilityTheme.accentText : UtilityTheme.text)
            .padding(.horizontal, UtilitySpacing.sm)
            .frame(height: UtilityMetrics.controlHeight)
            .background(isProminent ? UtilityTheme.accent : UtilityTheme.chrome)
            .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.sm))
        }
        .buttonStyle(.plain)
    }
}

struct UtilityPanelHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    let badgeCount: Int
    let showsPrimaryAction: Bool
    private let leadingAccessory: AnyView
    private let trailingAccessory: (CompactPanelHeaderLayout) -> AnyView

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leadingAccessory: () -> some View = { EmptyView() },
        @ViewBuilder trailingAccessory: @escaping () -> some View = { EmptyView() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.badgeCount = 0
        self.showsPrimaryAction = false
        self.leadingAccessory = AnyView(leadingAccessory())
        self.trailingAccessory = { _ in AnyView(trailingAccessory()) }
    }

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        badgeCount: Int,
        showsPrimaryAction: Bool,
        @ViewBuilder leadingAccessory: () -> some View = { EmptyView() },
        @ViewBuilder trailingAccessory: @escaping (CompactPanelHeaderLayout) -> some View
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.badgeCount = badgeCount
        self.showsPrimaryAction = showsPrimaryAction
        self.leadingAccessory = AnyView(leadingAccessory())
        self.trailingAccessory = { layout in AnyView(trailingAccessory(layout)) }
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = CompactPanelHeaderLayout.make(
                availableWidth: geometry.size.width,
                badgeCount: badgeCount,
                showsPrimaryAction: showsPrimaryAction
            )

            HStack(
                alignment: subtitle == nil ? .center : .top,
                spacing: UtilitySpacing.sm
            ) {
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
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
                trailingAccessory(layout)
            }
            .padding(.horizontal, UtilitySpacing.md)
            .padding(.vertical, UtilitySpacing.sm)
            .frame(
                width: geometry.size.width,
                height: headerHeight,
                alignment: .topLeading
            )
            .background(UtilityTheme.chromeElevated)
        }
        .frame(height: headerHeight, alignment: .top)
    }

    private var headerHeight: CGFloat {
        subtitle == nil ? UtilityMetrics.panelHeaderMinHeight : 48
    }
}
