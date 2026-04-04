import Testing
import Foundation
@testable import EditorCore

@Suite("Core Model Tests")
struct ModelTests {

    @Test("Project round-trips through JSON")
    func projectCodable() throws {
        let project = Project(name: "Test Project")
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        #expect(decoded.id == project.id)
        #expect(decoded.name == project.name)
    }

    @Test("TimeRange duration is correct")
    func timeRangeDuration() {
        let range = TimeRange(start: 1.0, end: 4.5)
        #expect(range.duration == 3.5)
    }

    @Test("TimeRange overlap detection")
    func timeRangeOverlap() {
        let a = TimeRange(start: 0, end: 5)
        let b = TimeRange(start: 3, end: 8)
        let c = TimeRange(start: 6, end: 10)
        #expect(a.overlaps(b))
        #expect(!a.overlaps(c))
    }

    @Test("TimeRange contains time")
    func timeRangeContains() {
        let range = TimeRange(start: 2.0, end: 5.0)
        #expect(range.contains(3.0))
        #expect(!range.contains(5.0))
        #expect(!range.contains(1.0))
    }

    @Test("Timeline duration computed from clips")
    func timelineDuration() {
        let clip1 = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5)
        )
        let clip2 = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 3, end: 10),
            sourceRange: TimeRange(start: 0, end: 7)
        )
        let track = Track(type: .video, clips: [clip1, clip2])
        let timeline = Timeline(tracks: [track])
        #expect(timeline.duration == 10.0)
    }

    @Test("Empty timeline has zero duration")
    func emptyTimelineDuration() {
        let timeline = Timeline()
        #expect(timeline.duration == 0)
    }

    @Test("Clip defaults are sensible")
    func clipDefaults() {
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5)
        )
        #expect(clip.opacity == 1.0)
        #expect(clip.volume == 1.0)
        #expect(clip.transform == .identity)
        #expect(clip.effects.isEmpty)
    }
}
