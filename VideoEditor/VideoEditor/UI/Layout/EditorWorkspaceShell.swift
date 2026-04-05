import SwiftUI

struct EditorWorkspaceShellLayout: Equatable, Sendable {
    let leftRailWidth: Double
    let rightRailWidth: Double
    let centerColumnMaxWidth: Double?
    let centerColumnWidth: Double
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
        rightRailVisible: Bool,
        previewAspectRatio: Double? = nil
    ) -> EditorWorkspaceShellLayout {
        let railExpansion = interpolationProgress(
            value: containerWidth,
            lowerBound: 1280,
            upperBound: 1880
        )
        let resolvedPreviewAspectRatio = previewAspectRatio ?? (16.0 / 9.0)
        let portraitPreviewBoost = resolvedPreviewAspectRatio < 1 ? 1.0 : 0.0
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
        let visibleRailCount = (leftRailVisible ? 1.0 : 0.0) + (rightRailVisible ? 1.0 : 0.0)
        let horizontalSpacing = Double(CinematicSpacing.md) * visibleRailCount
        let centerColumnWidthBudget = max(
            320.0,
            containerWidth - horizontalSpacing - (leftRailVisible ? interpolatedValue(minimum: 220, maximum: 280, progress: railExpansion) : 0) - (rightRailVisible ? interpolatedValue(minimum: 244, maximum: 312, progress: railExpansion) : 0)
        )
        let centerColumnWidth = min(centerColumnWidthBudget, centerColumnMaxWidth ?? centerColumnWidthBudget)
        let availableVerticalBudget = max(
            Self.topSectionChromeHeight + 2,
            containerHeight - verticalSectionSpacing
        )
        let previewMinimumHeight = portraitPreviewBoost > 0 ? 280.0 : 220.0
        let previewMaximumHeight = portraitPreviewBoost > 0 ? 540.0 : 420.0
        let aspectFitPreviewHeight = max(0, centerColumnWidth / resolvedPreviewAspectRatio)
        let previewPreferredHeight = min(
            max(previewMinimumHeight, aspectFitPreviewHeight),
            previewMaximumHeight
        )
        let centerColumnComfort = interpolationProgress(
            value: centerColumnWidth,
            lowerBound: 480,
            upperBound: 1100
        )
        let minimumTimelineShare = interpolatedValue(
            minimum: portraitPreviewBoost > 0 ? 0.30 : 0.34,
            maximum: portraitPreviewBoost > 0 ? 0.38 : 0.42,
            progress: centerColumnComfort
        )
        let minimumTimelineHeight = max(240.0, availableVerticalBudget * minimumTimelineShare)
        let topSectionBudgetCap = max(
            Self.topSectionChromeHeight + previewMinimumHeight,
            availableVerticalBudget - minimumTimelineHeight
        )
        let topSectionMinHeight = min(
            Self.topSectionChromeHeight + previewPreferredHeight,
            topSectionBudgetCap
        )
        let timelineSectionMinHeight = max(0, availableVerticalBudget - topSectionMinHeight)

        return EditorWorkspaceShellLayout(
            leftRailWidth: leftRailVisible ? interpolatedValue(minimum: 220, maximum: 280, progress: railExpansion) : 0,
            rightRailWidth: rightRailVisible ? interpolatedValue(minimum: 244, maximum: 312, progress: railExpansion) : 0,
            centerColumnMaxWidth: centerColumnMaxWidth,
            centerColumnWidth: centerColumnWidth,
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
    let previewAspectRatio: Double?
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
                rightRailVisible: isRightRailVisible,
                previewAspectRatio: previewAspectRatio
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
