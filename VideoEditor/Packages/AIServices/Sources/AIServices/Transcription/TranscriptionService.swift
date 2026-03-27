import Foundation
import EditorCore

/// Manages transcription lifecycle: trigger, cache, store results.
/// Auto-transcribes assets before AI needs them.
public actor TranscriptionService {
    private var provider: (any TranscriptionProvider)?
    private var inProgress: Set<UUID> = []

    public init() {}

    public func configure(provider: any TranscriptionProvider) {
        self.provider = provider
    }

    /// Transcribe an asset if not already transcribed. Returns the transcript.
    public func ensureTranscript(
        for asset: MediaAsset,
        mediaManager: MediaManager,
        bundleURL: URL
    ) async throws -> TranscriptionResult? {
        // Already has transcript
        if asset.analysis?.transcript != nil {
            let words = asset.analysis!.transcript!
            return TranscriptionResult(
                text: words.map(\.word).joined(separator: " "),
                words: words,
                speakers: asset.analysis?.speakerSegments,
                duration: asset.duration
            )
        }

        // Already in progress
        guard !inProgress.contains(asset.id) else { return nil }

        guard let provider else { return nil }

        inProgress.insert(asset.id)
        defer { inProgress.remove(asset.id) }

        // Extract audio from video if needed
        let audioURL = asset.type == .audio ? asset.sourceURL : asset.sourceURL

        let result = try await provider.transcribe(
            audioURL: audioURL,
            language: nil,
            enableDiarization: true,
            progress: { _ in }
        )

        // Store results on the asset
        await mediaManager.updateAsset(id: asset.id) { asset in
            var analysis = asset.analysis ?? MediaAnalysis()
            analysis.transcript = result.words
            analysis.speakerSegments = result.speakers
            asset.analysis = analysis
        }

        // Persist transcript to project bundle
        let transcriptDir = bundleURL.appendingPathComponent("analysis/transcripts")
        try? FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
        let transcriptURL = transcriptDir.appendingPathComponent("\(asset.id.uuidString).json")
        let data = try JSONEncoder().encode(result)
        try data.write(to: transcriptURL)

        return result
    }

    /// Check if an asset has a transcript (either in memory or on disk).
    public func hasTranscript(for asset: MediaAsset, bundleURL: URL) -> Bool {
        if asset.analysis?.transcript != nil { return true }
        let path = bundleURL.appendingPathComponent("analysis/transcripts/\(asset.id.uuidString).json")
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Load a persisted transcript from disk.
    public func loadTranscript(for assetID: UUID, bundleURL: URL) -> TranscriptionResult? {
        let path = bundleURL.appendingPathComponent("analysis/transcripts/\(assetID.uuidString).json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(TranscriptionResult.self, from: data)
    }
}
