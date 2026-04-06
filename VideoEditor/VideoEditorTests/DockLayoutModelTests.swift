import Foundation
import Testing
@testable import VideoEditor

@Suite("Dock Layout Model Tests")
struct DockLayoutModelTests {
    @Test("dock layout encodes and decodes split and tab nodes")
    func dockLayoutRoundTrip() throws {
        let layout = DockWorkspaceLayout(
            workspaceID: "edit",
            root: .split(
                axis: .vertical,
                ratio: 0.62,
                leading: .tabs(activePanelID: .programMonitor, panelIDs: [.sourceMonitor, .programMonitor]),
                trailing: .panel(.timeline)
            )
        )

        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(DockWorkspaceLayout.self, from: data)

        #expect(decoded == layout)
    }

    @Test("edit default layout expands program monitor without source monitor")
    @MainActor
    func editDefaultLayoutUsesSingleProgramMonitor() {
        let layout = PanelRegistry.editDefaultLayout

        #expect(layout.root.containsPanel(.programMonitor))
        #expect(!layout.root.containsPanel(.sourceMonitor))
    }
}
