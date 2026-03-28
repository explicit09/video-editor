import Testing
import Foundation
@testable import AIServices
@testable import EditorCore

@Suite("Transcription Service Tests")
struct TranscriptionServiceTests {

    @Test("hasTranscript ignores empty in-memory transcript arrays")
    func hasTranscriptIgnoresEmptyTranscriptArrays() async {
        let service = TranscriptionService()
        let asset = MediaAsset(
            name: "Audio",
            sourceURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
            type: .audio,
            duration: 5,
            analysis: MediaAnalysis(transcript: [])
        )

        let hasTranscript = await service.hasTranscript(
            for: asset,
            bundleURL: temporaryBundleURL()
        )

        #expect(hasTranscript == false)
    }

    @Test("transcribe updates media, persists transcript, and lemmatizes words for audio assets")
    func transcribePersistsAndLemmatizesAudioAssets() async throws {
        let service = TranscriptionService()
        let provider = MockTranscriptionProvider(result: TranscriptionResult(
            text: "Running fast",
            words: [TranscriptWord(word: "Running", start: 0, end: 0.5)],
            speakers: [SpeakerSegment(speakerID: "Speaker 1", range: TimeRange(start: 0, end: 0.5))],
            language: "en",
            duration: 1
        ))
        await service.configure(provider: provider)

        let asset = MediaAsset(
            name: "Audio",
            sourceURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
            type: .audio,
            duration: 5
        )
        let mediaManager = MediaManager(assets: [asset])
        let bundleURL = temporaryBundleURL()
        let statusCollector = StatusCollector()
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let result = try await service.transcribe(
            asset: asset,
            mediaManager: mediaManager,
            bundleURL: bundleURL,
            onStatus: { statusCollector.append($0) }
        )

        #expect(result?.words.first?.lemma == "run")
        #expect(result?.language == "en")
        #expect(await provider.callCount == 1)
        #expect(statusCollector.snapshot() == [
            "Uploading audio to Deepgram...",
            "Transcribing with Deepgram Nova-3...",
            "Processing 1 words...",
        ])

        let updatedAsset = await mediaManager.asset(id: asset.id)
        #expect(updatedAsset?.analysis?.transcript?.first?.lemma == "run")
        #expect(updatedAsset?.analysis?.speakerSegments?.count == 1)

        let persisted = await service.loadTranscript(for: asset.id, bundleURL: bundleURL)
        #expect(persisted?.words.first?.lemma == "run")
        #expect(persisted?.text == "Running fast")
    }

    @Test("transcribe returns cached in-memory transcripts without invoking the provider")
    func transcribeUsesCachedTranscripts() async throws {
        let service = TranscriptionService()
        let provider = MockTranscriptionProvider(result: TranscriptionResult(
            text: "Fresh transcript",
            words: [TranscriptWord(word: "Fresh", start: 0, end: 0.5)]
        ))
        await service.configure(provider: provider)

        let cachedWords = [TranscriptWord(word: "Cached", start: 0, end: 0.5)]
        let asset = MediaAsset(
            name: "Audio",
            sourceURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
            type: .audio,
            duration: 5,
            analysis: MediaAnalysis(transcript: cachedWords)
        )
        let mediaManager = MediaManager(assets: [asset])

        let result = try await service.transcribe(
            asset: asset,
            mediaManager: mediaManager,
            bundleURL: temporaryBundleURL()
        )

        #expect(result?.text == "Cached")
        #expect(result?.words.count == 1)
        #expect(await provider.callCount == 0)
    }

    @Test("transcribe rejects concurrent requests for the same asset while work is in progress")
    func transcribeRejectsConcurrentRequests() async throws {
        let service = TranscriptionService()
        let provider = MockTranscriptionProvider(
            result: TranscriptionResult(
                text: "Queued",
                words: [TranscriptWord(word: "Queued", start: 0, end: 0.5)]
            ),
            delayNanoseconds: 80_000_000
        )
        await service.configure(provider: provider)

        let asset = MediaAsset(
            name: "Audio",
            sourceURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
            type: .audio,
            duration: 5
        )
        let mediaManager = MediaManager(assets: [asset])
        let bundleURL = temporaryBundleURL()
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let firstTask = Task {
            try await service.transcribe(asset: asset, mediaManager: mediaManager, bundleURL: bundleURL)
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(await service.isTranscribing(assetID: asset.id))

        let secondResult = try await service.transcribe(
            asset: asset,
            mediaManager: mediaManager,
            bundleURL: bundleURL
        )

        #expect(secondResult == nil)
        #expect(try await firstTask.value != nil)
        #expect(await service.isTranscribing(assetID: asset.id) == false)
        #expect(await provider.callCount == 1)
    }

    private func temporaryBundleURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-bundle-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor MockTranscriptionProvider: TranscriptionProvider {
    nonisolated let name = "Mock"

    private(set) var callCount = 0
    private let result: TranscriptionResult
    private let delayNanoseconds: UInt64

    init(result: TranscriptionResult, delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func transcribe(
        audioURL: URL,
        language: String?,
        enableDiarization: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        callCount += 1
        progress(0.5)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        progress(1.0)
        return result
    }
}

private final class StatusCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [String] = []

    func append(_ status: String) {
        lock.lock()
        statuses.append(status)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return statuses
    }
}
