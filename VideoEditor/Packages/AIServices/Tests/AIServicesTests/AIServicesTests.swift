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

@Suite("Transcript Search Tests")
struct TranscriptSearchTests {

    @Test("Finds exact word match")
    func exactMatch() {
        let asset = makeAsset(words: [
            TranscriptWord(word: "we", start: 0, end: 0.2),
            TranscriptWord(word: "launched", start: 0.3, end: 0.6),
            TranscriptWord(word: "in", start: 0.7, end: 0.8),
            TranscriptWord(word: "Seattle", start: 0.9, end: 1.3),
            TranscriptWord(word: "last", start: 1.4, end: 1.6),
            TranscriptWord(word: "month", start: 1.7, end: 2.0),
        ])

        let engine = TranscriptSearchEngine()
        let results = engine.search(query: "Seattle", assets: [asset])

        #expect(results.count == 1)
        #expect(results[0].matchWord == "Seattle")
        #expect(results[0].matchTime == 0.9)
        #expect(results[0].contextText.contains("launched"))
    }

    @Test("Finds partial match")
    func partialMatch() {
        let asset = makeAsset(words: [
            TranscriptWord(word: "pricing", start: 5.0, end: 5.5),
            TranscriptWord(word: "model", start: 5.6, end: 6.0),
        ])

        let engine = TranscriptSearchEngine()
        let results = engine.search(query: "price", assets: [asset])

        #expect(results.count == 1)
        #expect(results[0].matchWord == "pricing")
    }

    @Test("Returns empty for no matches")
    func noMatch() {
        let asset = makeAsset(words: [
            TranscriptWord(word: "hello", start: 0, end: 0.5),
            TranscriptWord(word: "world", start: 0.6, end: 1.0),
        ])

        let engine = TranscriptSearchEngine()
        let results = engine.search(query: "goodbye", assets: [asset])

        #expect(results.isEmpty)
    }

    @Test("Skips assets without transcripts")
    func skipsUntranscribed() {
        var asset = MediaAsset(
            name: "test", sourceURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            type: .video, duration: 10
        )
        asset.analysis = nil

        let engine = TranscriptSearchEngine()
        let results = engine.search(query: "hello", assets: [asset])

        #expect(results.isEmpty)
    }

    @Test("Searches specific asset")
    func searchSingleAsset() {
        let asset = makeAsset(words: [
            TranscriptWord(word: "testing", start: 2.0, end: 2.5),
        ])

        let engine = TranscriptSearchEngine()
        let results = engine.searchAsset(query: "testing", asset: asset)

        #expect(results.count == 1)
        #expect(results[0].assetID == asset.id)
    }

    // MARK: - Helper

    private func makeAsset(words: [TranscriptWord]) -> MediaAsset {
        var asset = MediaAsset(
            name: "test-video",
            sourceURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            type: .video,
            duration: 60
        )
        asset.analysis = MediaAnalysis(transcript: words)
        return asset
    }
}
