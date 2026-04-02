import Testing
import Foundation
@testable import EditorCore

@Suite("Version Control Tests")
struct VersionControlTests {

    @Test("Snapshots persist across fresh VersionControl instances")
    func snapshotsPersistAcrossInstances() async throws {
        let projectURL = temporaryProjectURL()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let timeline = Timeline(
            tracks: [Track(name: "Video 1", type: .video, clips: [])],
            markers: []
        )

        let first = VersionControl(projectBundleURL: projectURL)
        try await first.saveSnapshot(name: "Snap A", timeline: timeline)

        let second = VersionControl(projectBundleURL: projectURL)
        try await second.saveSnapshot(name: "Snap B", timeline: timeline)

        let third = VersionControl(projectBundleURL: projectURL)
        let snapshots = await third.listSnapshots()

        #expect(snapshots.count == 2)
        #expect(Set(snapshots.map(\.name)) == ["Snap A", "Snap B"])
    }

    @Test("Snapshot listing survives a stale index when snapshot files exist")
    func snapshotFilesBackstopStaleIndex() async throws {
        let projectURL = temporaryProjectURL()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let timeline = Timeline(
            tracks: [Track(name: "Video 1", type: .video, clips: [])],
            markers: []
        )

        let versionControl = VersionControl(projectBundleURL: projectURL)
        try await versionControl.saveSnapshot(name: "Resilient Snap", timeline: timeline)

        let versionsURL = projectURL.appendingPathComponent("versions", isDirectory: true)
        let indexURL = versionsURL.appendingPathComponent("index.json")
        try Data("[]".utf8).write(to: indexURL)

        let reloaded = VersionControl(projectBundleURL: projectURL)
        let snapshots = await reloaded.listSnapshots()

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.name == "Resilient Snap")
    }

    private func temporaryProjectURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("version-control-\(UUID().uuidString).veditor", isDirectory: true)
    }
}
