import SwiftUI

struct WorkspacePageBarMetrics: Equatable, Sendable {
    let barHeight: CGFloat
    let showsLabels: Bool
    let usesVerticalRail: Bool

    static func make(containerWidth: CGFloat) -> Self {
        switch containerWidth {
        case ..<720:
            Self(barHeight: 32, showsLabels: false, usesVerticalRail: true)
        case ..<1120:
            Self(barHeight: 34, showsLabels: false, usesVerticalRail: false)
        default:
            Self(barHeight: 36, showsLabels: true, usesVerticalRail: false)
        }
    }
}

struct WorkspacePageBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let metrics: WorkspacePageBarMetrics
    let title: (Item) -> String
    let icon: (Item) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UtilitySpacing.xs) {
                ForEach(items, id: \.self) { item in
                    workspaceButton(for: item)
                }
            }
            .padding(.horizontal, UtilitySpacing.sm)
        }
        .frame(height: metrics.barHeight)
        .utilitySurface(.chrome)
    }

    private func workspaceButton(for item: Item) -> some View {
        let isSelected = item == selection

        return Button {
            selection = item
        } label: {
            HStack(spacing: UtilitySpacing.xs) {
                Image(systemName: icon(item))
                    .font(.system(size: 11, weight: .semibold))

                if metrics.showsLabels {
                    Text(title(item))
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(isSelected ? UtilityTheme.accentText : UtilityTheme.textMuted)
            .padding(.horizontal, metrics.showsLabels ? UtilitySpacing.md : UtilitySpacing.sm)
            .frame(height: max(metrics.barHeight - 8, 24))
            .background(isSelected ? UtilityTheme.accent : UtilityTheme.chromeElevated)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
