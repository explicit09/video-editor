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
    static let success = Color(hex: 0x53E16F)
    static let warning = Color(hex: 0xF5CC64)
    static let danger = Color(hex: 0xFFB4AB)
    static let info = Color(hex: 0x7DE7FF)
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

struct UtilityStatusBadgeMetrics: Equatable, Sendable {
    let height: CGFloat
    let horizontalPadding: CGFloat

    static func make(text: String, showsIcon: Bool) -> Self {
        Self(
            height: UtilityMetrics.controlHeight - 4,
            horizontalPadding: showsIcon || text.count > 2 ? UtilitySpacing.sm : UtilitySpacing.xs
        )
    }
}

enum UtilityStatusBadgeStyle: Equatable, Sendable {
    case neutral
    case accent
    case success
    case warning
    case danger
    case info

    var foregroundColor: Color {
        switch self {
        case .neutral:
            UtilityTheme.textMuted
        case .accent:
            UtilityTheme.accentText
        case .success:
            UtilityTheme.success
        case .warning:
            UtilityTheme.warning
        case .danger:
            UtilityTheme.danger
        case .info:
            UtilityTheme.info
        }
    }

    var backgroundColor: Color {
        switch self {
        case .neutral:
            UtilityTheme.chrome
        case .accent:
            UtilityTheme.accent
        case .success:
            UtilityTheme.success.opacity(0.16)
        case .warning:
            UtilityTheme.warning.opacity(0.16)
        case .danger:
            UtilityTheme.danger.opacity(0.16)
        case .info:
            UtilityTheme.info.opacity(0.16)
        }
    }

    var isSolidFill: Bool {
        self == .accent
    }
}

struct UtilitySegmentedControlMetrics: Equatable, Sendable {
    let showsLabels: Bool
    let controlHeight: CGFloat

    static func make(availableWidth: CGFloat, itemCount: Int) -> Self {
        let widthPerItem = availableWidth / max(CGFloat(itemCount), 1)

        return Self(
            showsLabels: widthPerItem >= 76,
            controlHeight: UtilityMetrics.controlHeight
        )
    }
}

struct UtilityStatusBadge: View {
    let text: String
    var icon: String? = nil
    var style: UtilityStatusBadgeStyle = .neutral

    init(text: String, icon: String? = nil, style: UtilityStatusBadgeStyle = .neutral) {
        self.text = text
        self.icon = icon
        self.style = style
    }

    init(text: String, icon: String? = nil, isAccent: Bool) {
        self.init(text: text, icon: icon, style: isAccent ? .accent : .neutral)
    }

    var body: some View {
        let metrics = UtilityStatusBadgeMetrics.make(text: text, showsIcon: icon != nil)

        HStack(spacing: UtilitySpacing.xxs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(style.foregroundColor)
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(height: metrics.height)
        .background(style.backgroundColor)
        .clipShape(Capsule())
    }
}

struct UtilitySegmentedControl<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let availableWidth: CGFloat
    let label: (Item) -> String
    var icon: ((Item) -> String?)? = nil

    var body: some View {
        let metrics = UtilitySegmentedControlMetrics.make(
            availableWidth: availableWidth,
            itemCount: items.count
        )

        HStack(spacing: UtilitySpacing.xs) {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    HStack(spacing: UtilitySpacing.xxs) {
                        if let iconName = icon?(item) {
                            Image(systemName: iconName)
                                .font(.system(size: 11, weight: .semibold))
                        }

                        if metrics.showsLabels {
                            Text(label(item))
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .foregroundStyle(selection == item ? UtilityTheme.accentText : UtilityTheme.text)
                    .padding(.horizontal, UtilitySpacing.sm)
                    .frame(height: metrics.controlHeight)
                    .frame(maxWidth: .infinity)
                    .background(selection == item ? UtilityTheme.accent : UtilityTheme.chrome)
                    .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(UtilitySpacing.xxs)
        .background(UtilityTheme.recessed)
        .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.md))
    }
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

struct UtilityPanelHeaderMetrics: Equatable, Sendable {
    let compactLayout: CompactPanelHeaderLayout
    let minimumHeight: CGFloat

    static func make(
        availableWidth: Double,
        subtitle: String?,
        badgeCount: Int,
        showsPrimaryAction: Bool
    ) -> Self {
        let compactLayout = CompactPanelHeaderLayout.make(
            availableWidth: availableWidth,
            badgeCount: badgeCount,
            showsPrimaryAction: showsPrimaryAction
        )

        guard let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self(
                compactLayout: compactLayout,
                minimumHeight: UtilityMetrics.panelHeaderMinHeight
            )
        }

        var minimumHeight: CGFloat = 52

        if showsPrimaryAction {
            minimumHeight += 8
        }

        if availableWidth < 360 || subtitle.count > 72 {
            minimumHeight += 12
        }

        if availableWidth < 280 || subtitle.count > 120 {
            minimumHeight += 12
        }

        return Self(
            compactLayout: compactLayout,
            minimumHeight: minimumHeight
        )
    }
}

struct UtilityHeaderBadge: View {
    let text: String
    var systemImage: String? = nil
    var style: UtilityStatusBadgeStyle = .neutral

    var body: some View {
        UtilityStatusBadge(text: text, icon: systemImage, style: style)
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
    @State private var availableWidth: CGFloat = 0

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
        let metrics = UtilityPanelHeaderMetrics.make(
            availableWidth: availableWidth > 0 ? availableWidth : 480,
            subtitle: subtitle,
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
            trailingAccessory(metrics.compactLayout)
        }
        .padding(.horizontal, UtilitySpacing.md)
        .padding(.vertical, UtilitySpacing.sm)
        .frame(maxWidth: .infinity, minHeight: metrics.minimumHeight, alignment: .topLeading)
        .background(UtilityTheme.chromeElevated)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: UtilityPanelHeaderWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        }
        .onPreferenceChange(UtilityPanelHeaderWidthPreferenceKey.self) { availableWidth = $0 }
    }
}

private struct UtilityPanelHeaderWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
