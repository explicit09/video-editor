import Foundation
import EditorCore

/// Manages transcription lifecycle: trigger, cache, store results.
/// Transcripts are tied to asset IDs and never regenerated without explicit permission.
public actor TranscriptionService {
    private var provider: (any TranscriptionProvider)?
    private var inProgress: Set<UUID> = []

    public init() {}

    public func configure(provider: any TranscriptionProvider) {
        self.provider = provider
    }

    /// Get transcript for an asset. Checks: in-memory → disk → returns nil.
    /// Does NOT trigger transcription. Use `transcribe` for that.
    public func getTranscript(
        for asset: MediaAsset,
        bundleURL: URL
    ) -> TranscriptionResult? {
        // Check in-memory (on the asset)
        if let words = asset.analysis?.transcript, !words.isEmpty {
            return TranscriptionResult(
                text: words.map(\.word).joined(separator: " "),
                words: words,
                speakers: asset.analysis?.speakerSegments,
                duration: asset.duration
            )
        }

        // Check persisted on disk
        return loadTranscript(for: asset.id, bundleURL: bundleURL)
    }

    /// Transcribe an asset. Only runs if no transcript exists (or force = true).
    /// Returns the result, or nil if provider not configured.
    public func transcribe(
        asset: MediaAsset,
        mediaManager: MediaManager,
        bundleURL: URL,
        force: Bool = false,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> TranscriptionResult? {
        if !force {
            if let existing = getTranscript(for: asset, bundleURL: bundleURL) {
                return existing
            }
        }

        guard !inProgress.contains(asset.id) else { return nil }
        guard let provider else { return nil }

        inProgress.insert(asset.id)
        defer { inProgress.remove(asset.id) }

        // Step 1: Extract audio from video
        let audioExtractor = AudioExtractor()
        let audioURL: URL
        if asset.type == .video {
            onStatus?("Extracting audio from video...")
            audioURL = try await audioExtractor.extractAudio(from: asset.sourceURL)
            onStatus?("Audio extracted. Uploading to Deepgram...")
        } else {
            onStatus?("Uploading audio to Deepgram...")
            audioURL = asset.sourceURL
        }
        defer {
            if asset.type == .video { audioExtractor.cleanup(tempURL: audioURL) }
        }

        // Step 2: Transcribe
        onStatus?("Transcribing with Deepgram Nova-3...")
        let rawResult = try await provider.transcribe(
            audioURL: audioURL,
            language: nil,
            enableDiarization: true,
            progress: { _ in }
        )

        // Step 3: Lemmatize for search
        onStatus?("Processing \(rawResult.words.count) words...")
        let lemmatizer = Lemmatizer()
        let lemmatizedWords = lemmatizer.lemmatizeTranscript(rawResult.words)
        let result = TranscriptionResult(
            text: rawResult.text,
            words: lemmatizedWords,
            speakers: rawResult.speakers,
            language: rawResult.language,
            duration: rawResult.duration
        )

        // Store on asset in memory
        await mediaManager.updateAsset(id: asset.id) { asset in
            var analysis = asset.analysis ?? MediaAnalysis()
            analysis.transcript = result.words
            analysis.speakerSegments = result.speakers
            asset.analysis = analysis
        }

        // Persist to disk — tied to asset ID
        persistTranscript(result, assetID: asset.id, bundleURL: bundleURL)

        return result
    }

    /// Check if a transcript exists for this asset (memory or disk).
    public func hasTranscript(for asset: MediaAsset, bundleURL: URL) -> Bool {
        if let transcript = asset.analysis?.transcript, !transcript.isEmpty { return true }
        return FileManager.default.fileExists(atPath: transcriptPath(for: asset.id, bundleURL: bundleURL))
    }

    /// Load a persisted transcript from disk.
    public func loadTranscript(for assetID: UUID, bundleURL: URL) -> TranscriptionResult? {
        let path = transcriptPath(for: assetID, bundleURL: bundleURL)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(TranscriptionResult.self, from: data)
    }

    /// Check if transcription is currently running for an asset.
    public func isTranscribing(assetID: UUID) -> Bool {
        inProgress.contains(assetID)
    }

    // MARK: - Private

    private func transcriptPath(for assetID: UUID, bundleURL: URL) -> String {
        bundleURL.appendingPathComponent("analysis/transcripts/\(assetID.uuidString).json").path
    }

    private func persistTranscript(_ result: TranscriptionResult, assetID: UUID, bundleURL: URL) {
        let dir = bundleURL.appendingPathComponent("analysis/transcripts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(assetID.uuidString).json")
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: url)
        }
    }
}
