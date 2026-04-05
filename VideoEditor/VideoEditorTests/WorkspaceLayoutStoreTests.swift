import Foundation
import Testing
@testable import VideoEditor

@Suite("Workspace Layout Store Tests")
struct WorkspaceLayoutStoreTests {
    @Test("workspace layout store falls back to defaults when persisted layout references unknown panels")
    func workspaceLayoutFallback() throws {
        let defaults = WorkspaceDefaultLayouts.make()
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WorkspaceLayoutStore(
            defaults: defaults,
            fileManager: .default,
            baseURL: baseURL,
            allowedPanelIDs: WorkspaceDefaultLayouts.knownPanelIDs
        )

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(
            DockWorkspaceLayout(
                workspaceID: "edit",
                root: .tabs(activePanelID: PanelID(rawValue: "missing"), panelIDs: [PanelID(rawValue: "missing")])
            )
        )
        .write(to: baseURL.appendingPathComponent("edit.json"))

        let resolved = try store.loadLayout(for: "edit")

        #expect(resolved == defaults["edit"])
    }

    @Test("malformed json falls back to defaults")
    func malformedJSONFallsBackToDefaults() throws {
        let defaults = WorkspaceDefaultLayouts.make()
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WorkspaceLayoutStore(
            defaults: defaults,
            fileManager: .default,
            baseURL: baseURL,
            allowedPanelIDs: WorkspaceDefaultLayouts.knownPanelIDs
        )

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: baseURL.appendingPathComponent("edit.json"))

        let resolved = try store.loadLayout(for: "edit")

        #expect(resolved == defaults["edit"])
    }

    @Test("invalid split ratio falls back to defaults")
    func invalidSplitRatioFallsBackToDefaults() throws {
        let defaults = WorkspaceDefaultLayouts.make()
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WorkspaceLayoutStore(
            defaults: defaults,
            fileManager: .default,
            baseURL: baseURL,
            allowedPanelIDs: WorkspaceDefaultLayouts.knownPanelIDs
        )

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(
            DockWorkspaceLayout(
                workspaceID: "edit",
                root: .split(
                    axis: .vertical,
                    ratio: 1.2,
                    leading: .panel(.timeline),
                    trailing: .panel(.inspector)
                )
            )
        )
        .write(to: baseURL.appendingPathComponent("edit.json"))

        let resolved = try store.loadLayout(for: "edit")

        #expect(resolved == defaults["edit"])
    }

    @Test("save rejects invalid layouts before writing")
    func saveRejectsInvalidLayouts() throws {
        let defaults = WorkspaceDefaultLayouts.make()
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WorkspaceLayoutStore(
            defaults: defaults,
            fileManager: .default,
            baseURL: baseURL,
            allowedPanelIDs: WorkspaceDefaultLayouts.knownPanelIDs
        )

        let invalidLayout = DockWorkspaceLayout(
            workspaceID: "edit",
            root: .split(
                axis: .horizontal,
                ratio: 0,
                leading: .panel(.timeline),
                trailing: .panel(.inspector)
            )
        )

        do {
            try store.save(invalidLayout)
            Issue.record("Expected invalid layout save to throw")
        } catch let error as WorkspaceLayoutStoreError {
            #expect(error == .invalidLayout(workspaceID: "edit"))
        } catch {
            Issue.record("Expected WorkspaceLayoutStoreError.invalidLayout, got \(error)")
        }

        #expect(!FileManager.default.fileExists(atPath: baseURL.appendingPathComponent("edit.json").path))
    }
}
