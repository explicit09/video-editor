import Testing
import Foundation
@testable import AIServices
@testable import EditorCore

@Suite("AI Services Tests")
struct AIServicesTests {

    @Test("AIMessage encodes correctly")
    func messageEncoding() throws {
        let message = AIMessage(role: "user", content: "Hello")
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(AIMessage.self, from: data)
        #expect(decoded.role == "user")
        #expect(decoded.content == "Hello")
    }

    @Test("CostTier values are correct")
    func costTiers() {
        #expect(CostTier.local.rawValue == "local")
        #expect(CostTier.frequent.rawValue == "frequent")
        #expect(CostTier.expensive.rawValue == "expensive")
    }
}

@Suite("Lemmatizer Tests")
struct LemmatizerTests {

    @Test("Lemmatizes common word forms")
    func basicLemmatization() {
        let lemmatizer = Lemmatizer()
        // These are single-word lemmatizations — less context, but core verbs work
        #expect(lemmatizer.lemmatize(word: "running") == "run")
        #expect(lemmatizer.lemmatize(word: "talked") == "talk")
        #expect(lemmatizer.lemmatize(word: "edited") == "edit")
    }

    @Test("Lemmatizes transcript with sentence context")
    func transcriptLemmatization() {
        let lemmatizer = Lemmatizer()
        let words = [
            TranscriptWord(word: "We", start: 0, end: 0.2),
            TranscriptWord(word: "were", start: 0.3, end: 0.5),
            TranscriptWord(word: "discussing", start: 0.6, end: 1.0),
            TranscriptWord(word: "pricing", start: 1.1, end: 1.5),
            TranscriptWord(word: "models", start: 1.6, end: 2.0),
        ]

        let result = lemmatizer.lemmatizeTranscript(words)

        // Every word should have a lemma
        for word in result {
            #expect(word.lemma != nil)
        }

        // "discussing" should lemmatize to "discuss"
        #expect(result[2].lemma == "discuss")
        // "pricing" should lemmatize to "price"
        #expect(result[3].lemma == "price")
    }
}

@Suite("Transcript Search Tests")
struct TranscriptSearchTests {

    @Test("Finds exact word match")
    func exactMatch() {
        let asset = makeAsset(words: [
            TranscriptWord(word: "we", lemma: "we", start: 0, end: 0.2),
            TranscriptWord(word: "launched", lemma: "launch", start: 0.3, end: 0.6),
            TranscriptWord(word: "in", lemma: "in", start: 0.7, end: 0.8),
            TranscriptWord(word: "Seattle", lemma: "seattle", start: 0.9, end: 1.3),
            TranscriptWord(word: "last", lemma: "last", start: 1.4, end: 1.6),
            TranscriptWord(word: "month", lemma: "month", start: 1.7, end: 2.0),
        ])

        let engine = TranscriptSearchEngine()
        let results = engine.search(query: "Seattle", assets: [asset])

        #expect(results.count == 1)
        #expect(results[0].matchWord == "Seattle")
        #expect(results[0].matchTime == 0.9)
    }

    @Test("Finds morphological match via lemma — price matches pricing")
    func lemmaMatch() {
        let asset = makeAsset(words: [
            TranscriptWord(word: "the", lemma: "the", start: 4.5, end: 4.7),
            TranscriptWord(word: "pricing", lemma: "price", start: 5.0, end: 5.5),
            TranscriptWord(word: "model", lemma: "model", start: 5.6, end: 6.0),
        ])

        let engine = TranscriptSearchEngine()
        let results = engine.searchAsset(query: "price", asset: asset)

        #expect(results.count == 1)
        if let first = results.first {
            #expect(first.matchWord == "pricing")
        }
    }

    @Test("Returns empty for no matches")
    func noMatch() {
        let asset = makeAsset(words: [
            TranscriptWord(word: "hello", lemma: "hello", start: 0, end: 0.5),
            TranscriptWord(word: "world", lemma: "world", start: 0.6, end: 1.0),
        ])

        let engine = TranscriptSearchEngine()
        let results = engine.search(query: "goodbye", assets: [asset])

        #expect(results.isEmpty)
    }

    @Test("Skips assets without transcripts")
    func skipsUntranscribed() {
        let asset = MediaAsset(
            name: "test", sourceURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            type: .video, duration: 10
        )

        let engine = TranscriptSearchEngine()
        let results = engine.search(query: "hello", assets: [asset])

        #expect(results.isEmpty)
    }

    @Test("Searches specific asset")
    func searchSingleAsset() {
        let asset = makeAsset(words: [
            TranscriptWord(word: "testing", lemma: "test", start: 2.0, end: 2.5),
        ])

        let engine = TranscriptSearchEngine()
        // "test" query lemmatizes to "test", matches lemma "test"
        let results = engine.searchAsset(query: "test", asset: asset)

        #expect(results.count == 1)
        #expect(results[0].assetID == asset.id)
    }

    // MARK: - Helper

    private func makeAsset(words: [TranscriptWord]) -> MediaAsset {
        MediaAsset(
            name: "test-video",
            sourceURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            type: .video,
            duration: 60,
            analysis: MediaAnalysis(transcript: words)
        )
    }
}
