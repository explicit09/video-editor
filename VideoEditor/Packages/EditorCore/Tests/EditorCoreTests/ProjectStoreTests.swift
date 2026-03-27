import Testing
import Foundation
@testable import EditorCore

@Suite("ProjectStore Tests")
struct ProjectStoreTests {

    @Test("Save and load project bundle")
    func saveAndLoad() async throws {
        let store = ProjectStore(project: Project(name: "Test"))
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5)
        )
        let track = Track(type: .video, clips: [clip])
        await store.setTimeline(Timeline(tracks: [track]))

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).veditor")

        try await store.save(to: tempDir)

        // Verify files exist
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("timeline.json").path))

        // Load into a fresh store
        let loadedStore = ProjectStore()
        try await loadedStore.load(from: tempDir)
        let loaded = await loadedStore.currentProject()

        #expect(loaded.name == "Test")
        #expect(loaded.timeline.tracks.count == 1)
        #expect(loaded.timeline.tracks[0].clips.count == 1)

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Project bundle creates subdirectories")
    func bundleStructure() async throws {
        let store = ProjectStore(project: Project(name: "Structure Test"))
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).veditor")

        try await store.save(to: tempDir)

        for subdir in ["media", "proxies", "cache", "analysis"] {
            let path = tempDir.appendingPathComponent(subdir).path
            #expect(FileManager.default.fileExists(atPath: path), "Missing: \(subdir)")
        }

        try? FileManager.default.removeItem(at: tempDir)
    }
}

@Suite("TimelineManager Tests")
struct TimelineManagerTests {

    @Test("Add and remove tracks")
    func trackOperations() async {
        let mgr = TimelineManager()
        let track = Track(type: .video)
        await mgr.addTrack(track)

        let timeline = await mgr.snapshot()
        #expect(timeline.tracks.count == 1)

        await mgr.removeTrack(id: track.id)
        let after = await mgr.snapshot()
        #expect(after.tracks.isEmpty)
    }

    @Test("Add clip to track")
    func addClip() async {
        let mgr = TimelineManager()
        let track = Track(type: .video)
        await mgr.addTrack(track)

        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 3),
            sourceRange: TimeRange(start: 0, end: 3)
        )
        await mgr.addClip(clip, toTrack: track.id)

        let found = await mgr.clip(id: clip.id)
        #expect(found != nil)
        #expect(found?.id == clip.id)
    }

    @Test("Update clip in place")
    func updateClip() async {
        let mgr = TimelineManager()
        let track = Track(type: .video)
        await mgr.addTrack(track)

        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5)
        )
        await mgr.addClip(clip, toTrack: track.id)
        await mgr.updateClip(id: clip.id) { $0.opacity = 0.5 }

        let updated = await mgr.clip(id: clip.id)
        #expect(updated?.opacity == 0.5)
    }

    @Test("Snapshot and restore")
    func snapshotRestore() async {
        let mgr = TimelineManager()
        await mgr.addTrack(Track(type: .audio))
        let snapshot = await mgr.snapshot()
        #expect(snapshot.tracks.count == 1)

        await mgr.addTrack(Track(type: .video))
        let after = await mgr.snapshot()
        #expect(after.tracks.count == 2)

        await mgr.restore(snapshot)
        let restored = await mgr.snapshot()
        #expect(restored.tracks.count == 1)
    }
}
