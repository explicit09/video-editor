import Foundation
import EditorCore

/// Breaks long content into coherent topic segments using local heuristics.
/// Analyzes pauses, speaker changes, energy resets, and vocabulary shifts
/// to find natural topic boundaries.
public struct TopicSegmenter: Sendable {

    public init() {}

    // MARK: - Segment

    /// Find topic boundaries using local heuristics (no LLM).
    public func segment(
        transcript: [TranscriptWord],
        silenceRanges: [SilenceRange],
        speakerSegments: [SpeakerSegment]? = nil,
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading] = [],
        minSegmentDuration: TimeInterval = 15.0
    ) -> [TopicSegment] {
        guard !transcript.isEmpty else { return [] }

        let totalStart = transcript.first!.start
        let totalEnd = transcript.last!.end

        // 1. Collect boundary candidates
        var candidates: [BoundaryCandidate] = []

        // Long pauses (>1.5s)
        for silence in silenceRanges where silence.duration >= 1.5 {
            let midpoint = (silence.start + silence.end) / 2
            candidates.append(BoundaryCandidate(time: midpoint, type: .longPause, score: 0))
        }

        // Speaker changes
        if let speakers = speakerSegments, speakers.count > 1 {
            for i in 1..<speakers.count {
                if speakers[i].speakerID != speakers[i - 1].speakerID {
                    candidates.append(BoundaryCandidate(
                        time: speakers[i].range.start,
                        type: .speakerChange,
                        score: 0
                    ))
                }
            }
        }

        // Energy resets: drop below silence then rise above speech
        for i in 1..<energyReadings.count {
            let prev = energyReadings[i - 1]
            let curr = energyReadings[i]
            if prev.isSilence && curr.isSpeech {
                candidates.append(BoundaryCandidate(time: curr.time, type: .energyReset, score: 0))
            }
        }

        // 2. Score each candidate
        for i in 0..<candidates.count {
            var score = 0.0

            // Sentence ending nearby
            let nearSentenceEnd = transcript.contains { word in
                let endsWithPunct = word.word.hasSuffix(".") || word.word.hasSuffix("?") || word.word.hasSuffix("!")
                return endsWithPunct && abs(word.end - candidates[i].time) < 1.0
            }
            if nearSentenceEnd { score += 0.3 }

            // Type bonuses
            switch candidates[i].type {
            case .speakerChange: score += 0.2
            case .energyReset: score += 0.2
            case .longPause: score += 0.15
            case .topicShift: score += 0.3
            }

            // Vocabulary shift: compare lemmas before and after
            let vocabShift = measureVocabShift(at: candidates[i].time, in: transcript)
            score += vocabShift * 0.3

            candidates[i].score = score
        }

        // 3. Filter and merge
        var accepted = candidates
            .filter { $0.score >= 0.35 }
            .sorted { $0.time < $1.time }

        // Merge boundaries that are too close
        accepted = mergeCandidates(accepted, minGap: max(minSegmentDuration * 0.5, 5.0))

        // 4. Build segments from boundaries
        var segments: [TopicSegment] = []
        var prevTime = totalStart

        for boundary in accepted {
            if boundary.time - prevTime >= minSegmentDuration {
                let segWords = transcript.filter { $0.start >= prevTime && $0.end <= boundary.time }
                let keywords = extractKeywords(from: segWords)

                segments.append(TopicSegment(
                    range: TimeRange(start: prevTime, end: boundary.time),
                    label: keywords.prefix(3).joined(separator: ", "),
                    keywords: keywords,
                    confidence: boundary.score,
                    boundaryType: boundary.type
                ))
                prevTime = boundary.time
            }
        }

        // Final segment
        if totalEnd - prevTime >= minSegmentDuration / 2 {
            let segWords = transcript.filter { $0.start >= prevTime && $0.end <= totalEnd }
            let keywords = extractKeywords(from: segWords)
            segments.append(TopicSegment(
                range: TimeRange(start: prevTime, end: totalEnd),
                label: keywords.prefix(3).joined(separator: ", "),
                keywords: keywords,
                confidence: 0.5,
                boundaryType: .longPause
            ))
        }

        return segments
    }
}

// MARK: - Models

public struct TopicSegment: Codable, Sendable {
    public let range: TimeRange
    public let label: String
    public let keywords: [String]
    public let confidence: Double
    public let boundaryType: BoundaryType

    public init(range: TimeRange, label: String, keywords: [String], confidence: Double, boundaryType: BoundaryType) {
        self.range = range
        self.label = label
        self.keywords = keywords
        self.confidence = confidence
        self.boundaryType = boundaryType
    }
}

public enum BoundaryType: String, Codable, Sendable {
    case speakerChange
    case longPause
    case topicShift
    case energyReset
}

// SpeakerSegment is defined in EditorCore/Models/MediaAsset.swift

// MARK: - Private

private struct BoundaryCandidate {
    var time: TimeInterval
    var type: BoundaryType
    var score: Double
}

extension TopicSegmenter {

    /// Measure vocabulary shift at a given time point.
    /// Compares lemma sets in a window before vs after.
    private func measureVocabShift(at time: TimeInterval, in transcript: [TranscriptWord]) -> Double {
        let windowSize: TimeInterval = 10.0

        let before = Set(
            transcript
                .filter { $0.end >= time - windowSize && $0.end < time }
                .map { ($0.lemma ?? $0.word).lowercased() }
        )
        let after = Set(
            transcript
                .filter { $0.start >= time && $0.start < time + windowSize }
                .map { ($0.lemma ?? $0.word).lowercased() }
        )

        let stopwords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been",
            "have", "has", "had", "do", "does", "did", "will", "would",
            "i", "you", "he", "she", "it", "we", "they", "and", "or",
            "but", "not", "in", "on", "at", "to", "for", "of", "with",
        ]

        let beforeFiltered = before.subtracting(stopwords)
        let afterFiltered = after.subtracting(stopwords)

        guard !beforeFiltered.isEmpty, !afterFiltered.isEmpty else { return 0 }

        let overlap = beforeFiltered.intersection(afterFiltered).count
        let total = beforeFiltered.union(afterFiltered).count
        guard total > 0 else { return 0 }

        // Higher shift = lower overlap = higher score
        let similarity = Double(overlap) / Double(total)
        return 1.0 - similarity
    }

    /// Merge candidates that are too close together, keeping the higher-scored one.
    private func mergeCandidates(_ candidates: [BoundaryCandidate], minGap: TimeInterval) -> [BoundaryCandidate] {
        guard !candidates.isEmpty else { return [] }

        var merged: [BoundaryCandidate] = [candidates[0]]

        for candidate in candidates.dropFirst() {
            if let last = merged.last, candidate.time - last.time < minGap {
                // Keep the higher-scored one
                if candidate.score > last.score {
                    merged[merged.count - 1] = candidate
                }
            } else {
                merged.append(candidate)
            }
        }

        return merged
    }

    /// Extract top keywords from transcript words (non-stopword, by frequency).
    private func extractKeywords(from words: [TranscriptWord], count: Int = 5) -> [String] {
        let stopwords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been",
            "have", "has", "had", "do", "does", "did", "will", "would",
            "could", "should", "may", "might", "can", "shall",
            "i", "you", "he", "she", "it", "we", "they", "me", "him",
            "her", "us", "them", "my", "your", "his", "its", "our", "their",
            "this", "that", "these", "those", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "and", "or", "but", "not", "so",
            "if", "then", "than", "just", "also", "very", "really",
        ]

        var freq: [String: Int] = [:]
        for word in words {
            let lemma = (word.lemma ?? word.word).lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            guard lemma.count > 2, !stopwords.contains(lemma) else { continue }
            freq[lemma, default: 0] += 1
        }

        return freq
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map(\.key)
    }
}
