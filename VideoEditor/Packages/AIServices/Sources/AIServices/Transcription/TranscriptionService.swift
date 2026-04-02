import Foundation
import EditorCore

/// Manages transcription lifecycle: trigger, cache, store results.
/// Transcripts are tied to asset IDs and never regenerated without explicit permission.
public actor TranscriptionService {
    private var provider: (any TranscriptionProvider)?
    private var localProvider: (any TranscriptionProvider)?
    private var inProgress: Set<UUID> = []

    public init() {}

    public func configure(provider: any TranscriptionProvider) {
        self.provider = provider
    }

    public func configureLocal(provider: any TranscriptionProvider) {
        self.localProvider = provider
    }

    /// Resolve which provider to use based on preference and availability.
    /// - When `useLocal` is true, always use local provider.
    /// - When diarization is needed and cloud provider exists, prefer cloud (it supports diarization).
    /// - Otherwise fall back to local if cloud is unavailable.
    public func resolveProvider(preferLocal: Bool, needsDiarization: Bool) -> (any TranscriptionProvider)? {
        if preferLocal {
            return localProvider ?? provider
        }
        if needsDiarization, provider != nil {
            return provider
        }
        return provider ?? localProvider
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

        // Check persisted on disk (by asset ID or source URL)
        return loadTranscript(for: asset.id, bundleURL: bundleURL, sourceURL: asset.sourceURL)
    }

    /// Transcribe an asset. Only runs if no transcript exists (or force = true).
    /// Returns the result, or nil if no provider is configured.
    /// Set `useLocal` to force local (WhisperKit) transcription.
    public func transcribe(
        asset: MediaAsset,
        mediaManager: MediaManager,
        bundleURL: URL,
        force: Bool = false,
        useLocal: Bool = false,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> TranscriptionResult? {
        if !force {
            if let existing = getTranscript(for: asset, bundleURL: bundleURL) {
                return existing
            }
        }

        guard !inProgress.contains(asset.id) else { return nil }

        let enableDiarization = !useLocal // Only cloud providers support diarization
        guard let activeProvider = resolveProvider(
            preferLocal: useLocal,
            needsDiarization: enableDiarization
        ) else { return nil }

        inProgress.insert(asset.id)
        defer { inProgress.remove(asset.id) }

        let isLocal = activeProvider.name == "WhisperKit"

        // Step 1: Extract audio from video
        let audioExtractor = AudioExtractor()
        let audioURL: URL
        if asset.type == .video {
            onStatus?("Extracting audio from video...")
            audioURL = try await audioExtractor.extractAudio(from: asset.sourceURL)
            let next = isLocal ? "Transcribing locally..." : "Uploading to \(activeProvider.name)..."
            onStatus?("Audio extracted. \(next)")
        } else {
            let action = isLocal ? "Preparing local transcription..." : "Uploading audio to \(activeProvider.name)..."
            onStatus?(action)
            audioURL = asset.sourceURL
        }
        defer {
            if asset.type == .video { audioExtractor.cleanup(tempURL: audioURL) }
        }

        // Step 2: Transcribe
        onStatus?("Transcribing with \(activeProvider.name)...")
        let rawResult = try await activeProvider.transcribe(
            audioURL: audioURL,
            language: nil,
            enableDiarization: enableDiarization,
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

        // Persist to disk — by asset ID and also by source file hash for cross-ID lookup
        persistTranscript(result, assetID: asset.id, bundleURL: bundleURL)
        persistTranscriptBySource(result, sourceURL: asset.sourceURL, bundleURL: bundleURL)

        return result
    }

    /// Check if a transcript exists for this asset (memory, disk by ID, or disk by source).
    public func hasTranscript(for asset: MediaAsset, bundleURL: URL) -> Bool {
        if let transcript = asset.analysis?.transcript, !transcript.isEmpty { return true }
        if FileManager.default.fileExists(atPath: transcriptPath(for: asset.id, bundleURL: bundleURL)) { return true }
        if FileManager.default.fileExists(atPath: transcriptPathBySource(asset.sourceURL, bundleURL: bundleURL)) { return true }
        return false
    }

    /// Load a persisted transcript from disk — checks by asset ID first, then by source URL.
    public func loadTranscript(for assetID: UUID, bundleURL: URL, sourceURL: URL? = nil) -> TranscriptionResult? {
        // Try by asset ID first
        let path = transcriptPath(for: assetID, bundleURL: bundleURL)
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return try? JSONDecoder().decode(TranscriptionResult.self, from: data)
        }
        // Try by source URL
        if let sourceURL {
            let sourcePath = transcriptPathBySource(sourceURL, bundleURL: bundleURL)
            if let data = try? Data(contentsOf: URL(fileURLWithPath: sourcePath)) {
                return try? JSONDecoder().decode(TranscriptionResult.self, from: data)
            }
        }
        return nil
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

    /// Persist transcript keyed by source file name — survives re-imports with new asset IDs.
    private func persistTranscriptBySource(_ result: TranscriptionResult, sourceURL: URL, bundleURL: URL) {
        let dir = bundleURL.appendingPathComponent("analysis/transcripts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = sourceHashKey(sourceURL)
        let url = dir.appendingPathComponent("src_\(key).json")
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: url)
        }
    }

    private func transcriptPathBySource(_ sourceURL: URL, bundleURL: URL) -> String {
        let key = sourceHashKey(sourceURL)
        return bundleURL.appendingPathComponent("analysis/transcripts/src_\(key).json").path
    }

    /// Stable key from source file name + size (avoids full path dependency).
    private func sourceHashKey(_ sourceURL: URL) -> String {
        let name = sourceURL.lastPathComponent
        let size = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0
        return "\(name)_\(size)".replacingOccurrences(of: " ", with: "_")
    }
}
