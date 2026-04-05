import AppKit
import SwiftUI

struct DockTabStripView: View {
    let panelIDs: [PanelID]
    let activePanelID: PanelID
    var onSelectPanel: (PanelID) -> Void = { _ in }
    var onBeginDrag: (PanelID) -> Void = { _ in }

    var body: some View {
        HStack(spacing: CinematicSpacing.xs) {
            ForEach(panelIDs, id: \.self) { panelID in
                tabButton(for: panelID)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, CinematicSpacing.sm)
        .padding(.vertical, 6)
        .frame(height: CinematicMetrics.panelHeaderHeight)
        .background(CinematicTheme.surfaceContainerHigh)
    }

    private func tabButton(for panelID: PanelID) -> some View {
        let isActive = panelID == activePanelID

        return Button {
            onSelectPanel(panelID)
        } label: {
            Text(label(for: panelID))
                .font(.cinLabel)
                .foregroundStyle(isActive ? CinematicTheme.onPrimaryContainer : CinematicTheme.onSurfaceVariant)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: CinematicMetrics.controlHeight)
                .background(isActive ? CinematicTheme.primaryContainer : CinematicTheme.surfaceContainerLowest)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onDrag {
            onBeginDrag(panelID)
            return NSItemProvider(object: panelID.rawValue as NSString)
        }
    }

    private func label(for panelID: PanelID) -> String {
        panelID.rawValue
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
