import SwiftUI

struct DockDropOverlayView: View {
    let target: DockDropTarget?

    var body: some View {
        GeometryReader { geometry in
            if let target {
                overlay(for: target, size: geometry.size)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.12), value: target)
    }

    @ViewBuilder
    private func overlay(for target: DockDropTarget, size: CGSize) -> some View {
        let highlight = CinematicTheme.primaryContainer.opacity(0.22)
        let border = CinematicTheme.primary.opacity(0.9)
        let tabHeight = min(size.height, DockDropGeometry.tabStripHeight)
        let edgeWidth = max(44, size.width * DockDropGeometry.edgeInsetRatio)
        let edgeHeight = max(44, size.height * DockDropGeometry.edgeInsetRatio)

        switch target {
        case .tabStack:
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .fill(highlight)
                    .frame(height: tabHeight)
                Spacer(minLength: 0)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .stroke(border, lineWidth: 2)
                    .frame(height: tabHeight)
            }
        case .splitLeading:
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .fill(highlight)
                    .frame(width: edgeWidth)
                Spacer(minLength: 0)
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .stroke(border, lineWidth: 2)
                    .frame(width: edgeWidth)
            }
        case .splitTrailing:
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .fill(highlight)
                    .frame(width: edgeWidth)
            }
            .overlay(alignment: .trailing) {
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .stroke(border, lineWidth: 2)
                    .frame(width: edgeWidth)
            }
        case .splitTop:
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .fill(highlight)
                    .frame(height: edgeHeight)
                Spacer(minLength: 0)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .stroke(border, lineWidth: 2)
                    .frame(height: edgeHeight)
            }
        case .splitBottom:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .fill(highlight)
                    .frame(height: edgeHeight)
            }
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .stroke(border, lineWidth: 2)
                    .frame(height: edgeHeight)
            }
        }
    }
}
