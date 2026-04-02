import Testing
@testable import AIServices
@testable import EditorCore

@Suite("Topic Segmenter Tests")
struct TopicSegmenterTests {

    @Test("Segmenter handles empty energy readings without crashing")
    func segmenterHandlesEmptyEnergyReadings() {
        let segmenter = TopicSegmenter()
        let transcript = [
            TranscriptWord(word: "LearnX", lemma: "learnx", start: 0, end: 0.5),
            TranscriptWord(word: "helps", lemma: "help", start: 0.5, end: 1.0),
            TranscriptWord(word: "students", lemma: "student", start: 1.0, end: 1.5),
            TranscriptWord(word: "learn", lemma: "learn", start: 11.0, end: 11.5),
            TranscriptWord(word: "faster", lemma: "fast", start: 11.5, end: 12.0),
        ]

        let segments = segmenter.segment(
            transcript: transcript,
            silenceRanges: [SilenceRange(start: 5, end: 7)],
            speakerSegments: [SpeakerSegment(speakerID: "host", range: TimeRange(start: 0, end: 12))],
            energyReadings: [],
            minSegmentDuration: 5
        )

        #expect(!segments.isEmpty)
        #expect(segments[0].range.start == 0)
        #expect(segments[0].range.end >= 5)
    }
}
