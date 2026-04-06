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

    @Test("Clip decodes legacy JSON without overlay presentation")
    func clipDecodesLegacyJSON() throws {
        let clipID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let assetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let legacyJSON = """
        {
          "id": "\(clipID.uuidString)",
          "assetID": "\(assetID.uuidString)",
          "timelineRange": { "start": 0, "end": 5 },
          "sourceRange": { "start": 1, "end": 6 },
          "transform": {
            "positionX": 12,
            "positionY": -8,
            "scaleX": 0.8,
            "scaleY": 0.8,
            "rotation": 5,
            "anchorX": 0.5,
            "anchorY": 0.5
          },
          "cropRect": { "x": 0.1, "y": 0.2, "width": 0.7, "height": 0.6 },
          "opacity": 0.75,
          "volume": 0.9,
          "effects": [],
          "keyframes": { "tracks": {} },
          "metadata": {
            "label": "Legacy Clip",
            "tags": [],
            "transcriptSegment": null,
            "sceneType": null
          },
          "speed": 1,
          "transitionIn": { "type": "none", "duration": 0 },
          "linkGroupID": null,
          "blendMode": "multiply"
        }
        """

        let decoded = try JSONDecoder().decode(Clip.self, from: Data(legacyJSON.utf8))
        #expect(decoded.id == clipID)
        #expect(decoded.assetID == assetID)
        #expect(decoded.blendMode == .multiply)
        #expect(decoded.overlayPresentation == .default)
    }
}
