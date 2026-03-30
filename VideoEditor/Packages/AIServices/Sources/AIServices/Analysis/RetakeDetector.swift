import Foundation
import EditorCore

/// Detects re-takes in transcripts: consecutive similar sentences
/// where a speaker restarts. Identifies the inferior take for removal.
///
/// Local algorithm uses lemma overlap (Jaccard similarity).
/// Optional LLM refinement for nuanced comparison (not yet wired).
public struct RetakeDetector: Sendable {

    public init() {}

    /// Detect re-takes using local heuristics (lemma overlap).
    /// Returns pairs of (inferior, superior) ranges.
    public func detect(in transcript: [TranscriptWord]) -> [RetakePair] {
        // Delegate to AutoCutEngine's retake detection — same algorithm,
        // single source of truth. RetakeDetector adds the AIServices-layer
        // entry point for future LLM refinement.
        let engine = AutoCutEngine()
        return engine.detectRetakes(in: transcript)
    }

    /// Detect re-takes with confidence-based filtering.
    /// Only returns pairs above the minimum similarity threshold.
    public func detect(
        in transcript: [TranscriptWord],
        minSimilarity: Double = 0.6,
        maxGap: TimeInterval = 3.0
    ) -> [RetakePair] {
        detect(in: transcript).filter { pair in
            pair.similarity >= minSimilarity
        }
    }
}
