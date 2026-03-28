import Testing
import Foundation
@testable import EditorCore

@Suite("Project Persistence Tests")
struct ProjectPersistenceTests {

    @Test("ProjectStore saves bundle structure and round-trips metadata with the timeline")
    func saveAndLoadRoundTrip() async throws {
        let projectURL = temporaryProjectURL()
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 1, end: 5),
            sourceRange: TimeRange(start: 10, end: 14),
            metadata: ClipMetadata(label: "Interview")
        )
        let timeline = Timeline(
            tracks: [Track(name: "Primary", type: .video, clips: [clip])],
            markers: [Marker(time: 3, label: "Beat")]
        )

        let store = ProjectStore(name: "Round Trip")
        await store.updateMetadata { metadata in
            metadata.settings = ProjectSettings(
                width: 3840,
                height: 2160,
                frameRate: 60,
                sampleRate: 44100,
                backgroundColorHex: "#FFFFFF"
            )
        }

        try await store.save(to: projectURL, timeline: timeline)

        for subdirectory in ["media", "proxies", "cache", "analysis"] {
            let subdirectoryURL = projectURL.appendingPathComponent(subdirectory)
            #expect(FileManager.default.fileExists(atPath: subdirectoryURL.path))
        }
        #expect(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("timeline.json").path))

        let loadedStore = ProjectStore()
        let loadedTimeline = try await loadedStore.load(from: projectURL)
        let metadata = await loadedStore.projectMetadata()

        #expect(metadata.name == "Round Trip")
        #expect(metadata.settings.width == 3840)
        #expect(metadata.settings.height == 2160)
        #expect(metadata.settings.frameRate == 60)
        #expect(metadata.settings.sampleRate == 44100)
        #expect(metadata.settings.backgroundColorHex == "#FFFFFF")

        #expect(loadedTimeline.tracks.count == 1)
        #expect(loadedTimeline.tracks[0].name == "Primary")
        #expect(loadedTimeline.tracks[0].clips.count == 1)
        #expect(loadedTimeline.tracks[0].clips[0].metadata.label == "Interview")
        #expect(loadedTimeline.markers.count == 1)
        #expect(loadedTimeline.markers[0].label == "Beat")
    }

    @Test("ProjectStore updateMetadata refreshes modifiedAt")
    func updateMetadataRefreshesModifiedDate() async throws {
        let store = ProjectStore(name: "Original")
        let initialMetadata = await store.projectMetadata()

        try await Task.sleep(nanoseconds: 20_000_000)
        await store.updateMetadata { metadata in
            metadata.name = "Updated"
        }

        let updatedMetadata = await store.projectMetadata()
        #expect(updatedMetadata.name == "Updated")
        #expect(updatedMetadata.modifiedAt > initialMetadata.modifiedAt)
    }

    private func temporaryProjectURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("project-\(UUID().uuidString).veditor", isDirectory: true)
    }
}
