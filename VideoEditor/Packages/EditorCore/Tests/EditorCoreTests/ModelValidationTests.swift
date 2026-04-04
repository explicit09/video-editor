import Testing
import Foundation
@testable import EditorCore

@Suite("Model Validation Tests")
struct ModelValidationTests {

    // MARK: - TimeRange

    @Test("TimeRange clamps end >= start")
    func timeRangeEndClamped() {
        let range = TimeRange(start: 10, end: 5) // end < start
        #expect(range.start == 10)
        #expect(range.end == 10) // clamped to start
        #expect(range.duration == 0)
    }

    @Test("TimeRange clamps negative start to zero")
    func timeRangeNegativeStart() {
        let range = TimeRange(start: -5, end: 10)
        #expect(range.start == 0)
        #expect(range.end == 10)
    }

    @Test("TimeRange duration init clamps negative duration")
    func timeRangeDurationClamped() {
        let range = TimeRange(start: 5, duration: -3)
        #expect(range.duration == 0) // negative clamped to 0
    }

    @Test("TimeRange valid values pass through")
    func timeRangeValid() {
        let range = TimeRange(start: 2, end: 8)
        #expect(range.start == 2)
        #expect(range.end == 8)
        #expect(range.duration == 6)
    }

    @Test("TimeRange.empty is zero")
    func timeRangeEmpty() {
        let range = TimeRange.empty
        #expect(range.start == 0)
        #expect(range.end == 0)
        #expect(range.duration == 0)
    }

    // MARK: - Clip

    @Test("Clip clamps opacity to 0...1")
    func clipOpacityClamped() {
        let over = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), opacity: 2.5)
        #expect(over.opacity == 1.0)

        let under = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), opacity: -0.5)
        #expect(under.opacity == 0.0)
    }

    @Test("Clip clamps volume to >= 0")
    func clipVolumeClamped() {
        let negative = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), volume: -1.0)
        #expect(negative.volume == 0.0)

        let loud = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), volume: 3.0)
        #expect(loud.volume == 3.0) // boost allowed
    }

    @Test("Clip valid values pass through")
    func clipValidValues() {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 10), sourceRange: TimeRange(start: 0, end: 10), opacity: 0.7, volume: 0.5)
        #expect(clip.opacity == 0.7)
        #expect(clip.volume == 0.5)
    }

    // MARK: - ProjectSettings

    @Test("ProjectSettings clamps invalid dimensions")
    func settingsClamped() {
        let settings = ProjectSettings(width: 0, height: -100, frameRate: 0, sampleRate: 0)
        #expect(settings.width == 1)
        #expect(settings.height == 1)
        #expect(settings.frameRate == 1)
        #expect(settings.sampleRate == 8000)
    }

    @Test("ProjectSettings valid values pass through")
    func settingsValid() {
        let settings = ProjectSettings(width: 3840, height: 2160, frameRate: 60, sampleRate: 48000)
        #expect(settings.width == 3840)
        #expect(settings.height == 2160)
        #expect(settings.frameRate == 60)
        #expect(settings.sampleRate == 48000)
    }
}
