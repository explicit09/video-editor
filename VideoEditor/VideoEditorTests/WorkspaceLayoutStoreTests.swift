import Foundation
import Testing
@testable import VideoEditor

@Suite("Workspace Layout Store Tests")
struct WorkspaceLayoutStoreTests {
    @Test("workspace layout store falls back to defaults when persisted layout references unknown panels")
    func workspaceLayoutFallback() throws {
        let defaults = WorkspaceDefaultLayouts.make()
        let store = WorkspaceLayoutStore(
            defaults: defaults,
            fileManager: .default,
            baseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )

        try store.save(
            DockWorkspaceLayout(
                workspaceID: "edit",
                root: .tabs(activePanelID: PanelID(rawValue: "missing"), panelIDs: [PanelID(rawValue: "missing")])
            )
        )

        let resolved = try store.loadLayout(for: "edit")

        #expect(resolved == defaults["edit"])
    }
}
