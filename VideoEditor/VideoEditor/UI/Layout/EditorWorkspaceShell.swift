import SwiftUI

struct EditorWorkspaceShellLayout: Equatable, Sendable {
    let leftRailWidth: Double
    let rightRailWidth: Double
    let centerColumnMaxWidth: Double?
    let topSectionMinHeight: Double
    let timelineSectionMinHeight: Double

    static let topSectionChromeHeight =
        Double(CinematicMetrics.panelHeaderHeight) +
        transportBarHeight +
        commandDockHeight +
        Double(CinematicSpacing.md * 2)

    static let verticalSectionSpacing = Double(CinematicSpacing.md)

    var previewContentMinHeight: Double {
        max(0, topSectionMinHeight - Self.topSectionChromeHeight)
    }

    static func make(
        containerWidth: Double,
        containerHeight: Double,
        leftRailVisible: Bool,
        rightRailVisible: Bool
    ) -> EditorWorkspaceShellLayout {
        let railExpansion = interpolationProgress(
            value: containerWidth,
            lowerBound: 1280,
            upperBound: 1880
        )
        let heightExpansion = interpolationProgress(
            value: containerHeight,
            lowerBound: 680,
            upperBound: 980
        )
        let availableVerticalBudget = max(
            Self.topSectionChromeHeight + 2,
            containerHeight - verticalSectionSpacing
        )
        let preferredTopSectionHeight = Self.topSectionChromeHeight + interpolatedValue(
            minimum: 72,
            maximum: 180,
            progress: heightExpansion
        )
        let topSectionBudgetCap = max(
            Self.topSectionChromeHeight + 24,
            availableVerticalBudget * 0.39
        )
        let topSectionMinHeight = min(preferredTopSectionHeight, topSectionBudgetCap)
        let timelineSectionMinHeight = max(
            topSectionMinHeight + 1,
            availableVerticalBudget - topSectionMinHeight
        )
        let centerColumnMaxWidth =
            containerWidth >= 1760
            ? interpolatedValue(
                minimum: 1100,
                maximum: 1280,
                progress: interpolationProgress(
                    value: containerWidth,
                    lowerBound: 1760,
                    upperBound: 2200
                )
            )
            : nil

        return EditorWorkspaceShellLayout(
            leftRailWidth: leftRailVisible ? interpolatedValue(minimum: 220, maximum: 280, progress: railExpansion) : 0,
            rightRailWidth: rightRailVisible ? interpolatedValue(minimum: 244, maximum: 312, progress: railExpansion) : 0,
            centerColumnMaxWidth: centerColumnMaxWidth,
            topSectionMinHeight: topSectionMinHeight,
            timelineSectionMinHeight: timelineSectionMinHeight
        )
    }

    private static let transportBarHeight = 54.0
    private static let commandDockHeight = 54.0

    private static func interpolationProgress(
        value: Double,
        lowerBound: Double,
        upperBound: Double
    ) -> Double {
        guard upperBound > lowerBound else { return 1 }

        let progress = (value - lowerBound) / (upperBound - lowerBound)
        return min(max(progress, 0), 1)
    }

    private static func interpolatedValue(
        minimum: Double,
        maximum: Double,
        progress: Double
    ) -> Double {
        minimum + ((maximum - minimum) * progress)
    }
}

struct EditorWorkspaceShell<LeftRail: View, CenterTop: View, CenterBottom: View, RightRail: View>: View {
    let isLeftPanelVisible: Bool
    let isRightRailVisible: Bool
    let leftRail: () -> LeftRail
    let centerTop: (EditorWorkspaceShellLayout) -> CenterTop
    let centerBottom: (EditorWorkspaceShellLayout) -> CenterBottom
    let rightRail: () -> RightRail

    var body: some View {
        GeometryReader { geometry in
            let layout = EditorWorkspaceShellLayout.make(
                containerWidth: geometry.size.width,
                containerHeight: geometry.size.height,
                leftRailVisible: isLeftPanelVisible,
                rightRailVisible: isRightRailVisible
            )

            HStack(alignment: .top, spacing: CinematicSpacing.md) {
                if isLeftPanelVisible {
                    leftRail()
                        .frame(width: layout.leftRailWidth)
                }

                VStack(spacing: CinematicSpacing.md) {
                    centerTop(layout)
                        .frame(
                            minHeight: layout.topSectionMinHeight,
                            idealHeight: layout.topSectionMinHeight,
                            alignment: .top
                        )

                    centerBottom(layout)
                        .frame(minHeight: layout.timelineSectionMinHeight, maxHeight: .infinity, alignment: .top)
                        .layoutPriority(1)
                }
                .frame(maxWidth: layout.centerColumnMaxWidth ?? .infinity, maxHeight: .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isRightRailVisible {
                    rightRail()
                        .frame(width: layout.rightRailWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
