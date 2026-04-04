import Testing
import Foundation
@testable import EditorCore

@Suite("AutoCutEngine Tests")
struct AutoCutEngineTests {

    let engine = AutoCutEngine()

    // MARK: - Preset Config

    @Test("Gentle preset only removes long silences")
    func gentlePreset() {
        let silences = [
            SilenceRange(start: 5.0, end: 5.5),   // 0.5s — below threshold
            SilenceRange(start: 10.0, end: 10.8),  // 0.8s — below threshold
            SilenceRange(start: 20.0, end: 22.5),  // 2.5s — above threshold
            SilenceRange(start: 30.0, end: 33.0),  // 3.0s — above threshold
        ]

        let plan = engine.generatePlan(
            preset: .gentle,
            assetDuration: 60.0,
            silenceRanges: silences,
            transcript: [],
            energyReadings: []
        )

        // Only 2 silences >= 2.0s
        #expect(plan.segments.count == 2)
        #expect(plan.segments.allSatisfy { $0.action == .remove })
        #expect(plan.stats.segmentsRemoved == 2)
    }

    @Test("Standard preset removes silences + fillers")
    func standardPreset() {
        let silences = [
            SilenceRange(start: 10.0, end: 11.0),  // 1.0s — above 0.8s
            SilenceRange(start: 20.0, end: 20.5),  // 0.5s — below threshold
        ]

        let transcript = [
            TranscriptWord(word: "So", start: 1.0, end: 1.2),
            TranscriptWord(word: "um", start: 1.3, end: 1.5),
            TranscriptWord(word: "the", start: 1.6, end: 1.8),
            TranscriptWord(word: "thing", start: 1.9, end: 2.2),
        ]

        let plan = engine.generatePlan(
            preset: .standard,
            assetDuration: 30.0,
            silenceRanges: silences,
            transcript: transcript,
            energyReadings: []
        )

        let removals = plan.segments.filter { $0.action == .remove }
        let fillers = plan.segments.filter { $0.action == .removeFiller }

        #expect(removals.count == 1) // Only the 1.0s silence
        #expect(fillers.count == 1) // "um"
        #expect(plan.stats.fillerWordsRemoved == 1)
    }

    @Test("Aggressive preset catches hedge words and multi-word fillers")
    func aggressivePreset() {
        let transcript = [
            TranscriptWord(word: "So", start: 1.0, end: 1.2),
            TranscriptWord(word: "basically", start: 1.3, end: 1.7),
            TranscriptWord(word: "you", start: 2.0, end: 2.1),
            TranscriptWord(word: "know", start: 2.15, end: 2.3),
            TranscriptWord(word: "it", start: 2.5, end: 2.6),
            TranscriptWord(word: "works", start: 2.7, end: 3.0),
        ]

        let plan = engine.generatePlan(
            preset: .aggressive,
            assetDuration: 10.0,
            silenceRanges: [],
            transcript: transcript,
            energyReadings: []
        )

        let fillers = plan.segments.filter { $0.action == .removeFiller }
        // "basically" + "you know"
        #expect(fillers.count == 2)
    }

    // MARK: - Filler Detection

    @Test("Standard fillers detected")
    func standardFillers() {
        let transcript = [
            TranscriptWord(word: "hello", start: 0, end: 0.3),
            TranscriptWord(word: "um", start: 0.5, end: 0.7),
            TranscriptWord(word: "world", start: 0.8, end: 1.0),
            TranscriptWord(word: "uh", start: 1.2, end: 1.4),
            TranscriptWord(word: "er", start: 1.5, end: 1.6),
            TranscriptWord(word: "hmm", start: 1.8, end: 2.0),
        ]

        let fillers = engine.detectFillerWords(in: transcript, aggressive: false)
        #expect(fillers.count == 4)
        let words = Set(fillers.map(\.word))
        #expect(words.contains("um"))
        #expect(words.contains("uh"))
        #expect(words.contains("er"))
        #expect(words.contains("hmm"))
    }

    @Test("Non-filler words not detected")
    func noFalsePositives() {
        let transcript = [
            TranscriptWord(word: "the", start: 0, end: 0.2),
            TranscriptWord(word: "algorithm", start: 0.3, end: 0.8),
            TranscriptWord(word: "works", start: 0.9, end: 1.2),
            TranscriptWord(word: "perfectly", start: 1.3, end: 1.7),
        ]

        let fillers = engine.detectFillerWords(in: transcript, aggressive: true)
        #expect(fillers.isEmpty)
    }

    // MARK: - Re-take Detection

    @Test("Detects re-take with high lemma overlap")
    func detectsRetake() {
        let transcript = [
            // First take: "the system processes data quickly"
            TranscriptWord(word: "the", lemma: "the", start: 1.0, end: 1.1, confidence: 0.8),
            TranscriptWord(word: "system", lemma: "system", start: 1.2, end: 1.5, confidence: 0.7),
            TranscriptWord(word: "processes", lemma: "process", start: 1.6, end: 2.0, confidence: 0.6),
            TranscriptWord(word: "data.", lemma: "data", start: 2.1, end: 2.3, confidence: 0.7),
            // Second take (1 second gap): "the system processes data quickly and efficiently"
            TranscriptWord(word: "the", lemma: "the", start: 3.3, end: 3.4, confidence: 0.9),
            TranscriptWord(word: "system", lemma: "system", start: 3.5, end: 3.8, confidence: 0.9),
            TranscriptWord(word: "processes", lemma: "process", start: 3.9, end: 4.3, confidence: 0.9),
            TranscriptWord(word: "data", lemma: "data", start: 4.4, end: 4.6, confidence: 0.9),
            TranscriptWord(word: "quickly", lemma: "quick", start: 4.7, end: 5.0, confidence: 0.9),
            TranscriptWord(word: "and", lemma: "and", start: 5.1, end: 5.2, confidence: 0.9),
            TranscriptWord(word: "efficiently.", lemma: "efficient", start: 5.3, end: 5.8, confidence: 0.9),
        ]

        let retakes = engine.detectRetakes(in: transcript)
        #expect(retakes.count == 1)

        if let retake = retakes.first {
            // First take should be inferior (shorter, lower confidence)
            #expect(retake.inferiorRange.start < 3.0)
            #expect(retake.superiorRange.start >= 3.0)
            #expect(retake.similarity >= 0.6)
        }
    }

    @Test("No re-take for unrelated sentences")
    func noRetakeForDifferent() {
        let transcript = [
            TranscriptWord(word: "hello", lemma: "hello", start: 0.0, end: 0.3),
            TranscriptWord(word: "world.", lemma: "world", start: 0.4, end: 0.7),
            TranscriptWord(word: "goodbye", lemma: "goodbye", start: 1.5, end: 1.8),
            TranscriptWord(word: "moon.", lemma: "moon", start: 1.9, end: 2.2),
        ]

        let retakes = engine.detectRetakes(in: transcript)
        #expect(retakes.isEmpty)
    }

    @Test("No re-take when gap is too large")
    func noRetakeForLargeGap() {
        let transcript = [
            TranscriptWord(word: "system", lemma: "system", start: 0.0, end: 0.3),
            TranscriptWord(word: "works.", lemma: "work", start: 0.4, end: 0.7),
            // 5 second gap — too far apart
            TranscriptWord(word: "system", lemma: "system", start: 5.7, end: 6.0),
            TranscriptWord(word: "works.", lemma: "work", start: 6.1, end: 6.4),
        ]

        let retakes = engine.detectRetakes(in: transcript)
        #expect(retakes.isEmpty)
    }

    // MARK: - Cut Plan Stats

    @Test("Stats reflect removals correctly")
    func statsAccuracy() {
        let silences = [
            SilenceRange(start: 5.0, end: 8.0),   // 3.0s
            SilenceRange(start: 15.0, end: 18.0),  // 3.0s
        ]

        let plan = engine.generatePlan(
            preset: .gentle,
            assetDuration: 30.0,
            silenceRanges: silences,
            transcript: [],
            energyReadings: []
        )

        #expect(plan.stats.originalDuration == 30.0)
        #expect(plan.stats.resultDuration == 24.0) // 30 - 3 - 3
        #expect(plan.stats.segmentsRemoved == 2)
    }

    // MARK: - Plan to Intents

    @Test("Plan generates batch intent")
    func planToIntentsBatch() {
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 30),
            sourceRange: TimeRange(start: 0, end: 30)
        )

        let plan = CutPlan(
            preset: .gentle,
            segments: [
                CutSegment(
                    sourceRange: TimeRange(start: 5, end: 8),
                    action: .remove,
                    reason: "Silence",
                    confidence: 0.95
                )
            ],
            stats: CutStats(
                originalDuration: 30, resultDuration: 27,
                segmentsRemoved: 1, fillerWordsRemoved: 0, retakesRemoved: 0,
                speechRatioBefore: 0.5, speechRatioAfter: 0.6,
                engagementBefore: 40, engagementAfter: 50
            )
        )

        let intents = engine.planToIntents(plan: plan, clipID: clip.id, clip: clip)
        #expect(intents.count == 1) // One batch

        if case .batch(let inner) = intents.first {
            #expect(!inner.isEmpty)
        } else {
            Issue.record("Expected batch intent")
        }
    }

    // MARK: - Overlap Merging

    @Test("Overlapping segments are merged")
    func mergeOverlapping() {
        let silences = [
            SilenceRange(start: 5.0, end: 8.0),
            SilenceRange(start: 7.5, end: 10.0), // overlaps
        ]

        let plan = engine.generatePlan(
            preset: .gentle,
            assetDuration: 30.0,
            silenceRanges: silences,
            transcript: [],
            energyReadings: []
        )

        // Should merge into one segment 5.0-10.0
        #expect(plan.segments.count == 1)
        #expect(plan.segments[0].sourceRange.start == 5.0)
        #expect(plan.segments[0].sourceRange.end == 10.0)
    }

    // MARK: - Empty Input

    @Test("Empty input returns empty plan")
    func emptyInput() {
        let plan = engine.generatePlan(
            preset: .standard,
            assetDuration: 60.0,
            silenceRanges: [],
            transcript: [],
            energyReadings: []
        )

        #expect(plan.segments.isEmpty)
        #expect(plan.stats.originalDuration == 60.0)
        #expect(plan.stats.resultDuration == 60.0)
    }
}
