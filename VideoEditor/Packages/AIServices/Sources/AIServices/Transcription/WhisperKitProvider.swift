import Foundation
import EditorCore
@preconcurrency import WhisperKit

// MARK: - WhisperKitProvider

/// Local transcription provider using WhisperKit (Core ML optimized for Apple Silicon).
/// Downloads models from HuggingFace on first use. Zero cost, works offline after initial download.
public final class WhisperKitProvider: TranscriptionProvider, @unchecked Sendable {
    public let name = "WhisperKit"

    private let modelName: String
    private var pipeline: WhisperKit?
    private let lock = NSLock()

    /// Status callback for model download / loading progress.
    public var onStatus: (@Sendable (String) -> Void)?

    /// Available model sizes. Larger = more accurate but slower and bigger download.
    public enum ModelSize: String, Sendable {
        case base = "base"          // 74MB  -- fast, good for most content
        case small = "small"        // 244MB -- better accuracy
        case largeV3 = "large-v3"   // 1.5GB -- best accuracy, slower
    }

    public init(model: ModelSize = .base) {
        self.modelName = model.rawValue
    }

    public init(modelName: String) {
        self.modelName = modelName
    }

    public func transcribe(
        audioURL: URL,
        language: String?,
        enableDiarization: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        let pipe = try await loadPipeline(progress: progress)

        progress(0.3)
        onStatus?("Transcribing locally with WhisperKit (\(modelName))...")

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0.0,
            skipSpecialTokens: true,
            wordTimestamps: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6
        )

        let wkResults = try await pipe.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )

        progress(0.9)

        // WhisperKit returns [WhisperKit.TranscriptionResult] — a class with segments.
        // Each segment has optional word-level timings.
        let allWords: [TranscriptWord] = wkResults.flatMap { result in
            result.segments.flatMap { segment -> [TranscriptWord] in
                guard let words = segment.words else { return [] }
                return words.map { timing in
                    TranscriptWord(
                        word: timing.word.trimmingCharacters(in: CharacterSet.whitespaces),
                        start: TimeInterval(timing.start),
                        end: TimeInterval(timing.end),
                        confidence: Double(timing.probability)
                    )
                }
            }
        }

        let fullText = wkResults.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let detectedLanguage = wkResults.first?.language ?? language
        let duration = allWords.last?.end ?? 0

        progress(1.0)

        return TranscriptionResult(
            text: fullText,
            words: allWords,
            speakers: nil, // WhisperKit does not support speaker diarization
            language: detectedLanguage,
            duration: duration
        )
    }

    // MARK: - Private

    private func loadPipeline(
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> WhisperKit {
        if let existing = getPipeline() {
            return existing
        }

        onStatus?("Loading WhisperKit model '\(modelName)' (downloads on first use)...")
        progress(0.05)

        let config = WhisperKitConfig(model: modelName)
        let pipe = try await WhisperKit(config)

        setPipeline(pipe)
        progress(0.2)
        onStatus?("WhisperKit model loaded.")

        return pipe
    }

    private func getPipeline() -> WhisperKit? {
        lock.lock()
        defer { lock.unlock() }
        return pipeline
    }

    private func setPipeline(_ pipe: WhisperKit) {
        lock.lock()
        defer { lock.unlock() }
        pipeline = pipe
    }
}

// MARK: - WhisperKitError

public enum WhisperKitError: Error, LocalizedError {
    case modelLoadFailed(String)
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let detail): "WhisperKit model load failed: \(detail)"
        case .transcriptionFailed(let detail): "WhisperKit transcription failed: \(detail)"
        }
    }
}
