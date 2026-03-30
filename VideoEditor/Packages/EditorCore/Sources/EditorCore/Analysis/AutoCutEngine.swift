import Foundation

// MARK: - AutoCutEngine

/// Analyzes audio + transcript to generate intelligent cut plans.
/// Pure analysis — returns a CutPlan, never executes edits directly.
public struct AutoCutEngine: Sendable {

    public init() {}

    // MARK: - Generate Plan

    /// Generate a cut plan from pre-analyzed data.
    public func generatePlan(
        preset: AutoCutPreset,
        assetDuration: TimeInterval,
        silenceRanges: [SilenceRange],
        transcript: [TranscriptWord],
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading]
    ) -> CutPlan {
        var segments: [CutSegment] = []

        let config = preset.config

        // 1. Mark silence ranges for removal
        let filteredSilences = silenceRanges.filter { $0.duration >= config.silenceThreshold }
        for silence in filteredSilences {
            segments.append(CutSegment(
                sourceRange: TimeRange(start: silence.start, end: silence.end),
                action: .remove,
                reason: "Silence (\(String(format: "%.1f", silence.duration))s)",
                confidence: 0.95
            ))
        }

        // 2. Detect and mark filler words (standard + aggressive)
        if config.removeFillers {
            let fillers = detectFillerWords(in: transcript, aggressive: config.removeHedgeWords)
            for filler in fillers {
                // Skip if already inside a silence removal range
                let alreadyCovered = segments.contains { seg in
                    seg.action == .remove &&
                    seg.sourceRange.contains(filler.start) &&
                    seg.sourceRange.contains(filler.end)
                }
                guard !alreadyCovered else { continue }

                segments.append(CutSegment(
                    sourceRange: TimeRange(start: filler.start, end: filler.end),
                    action: .removeFiller,
                    reason: "Filler: \"\(filler.word)\"",
                    confidence: filler.confidence > 0.8 ? 0.9 : 0.7
                ))
            }
        }

        // 3. Detect re-takes (standard + aggressive)
        if config.detectRetakes {
            let retakes = detectRetakes(in: transcript)
            for retake in retakes {
                let alreadyCovered = segments.contains { seg in
                    seg.action == .remove &&
                    seg.sourceRange.overlaps(retake.inferiorRange)
                }
                guard !alreadyCovered else { continue }

                segments.append(CutSegment(
                    sourceRange: retake.inferiorRange,
                    action: .removeRetake,
                    reason: "Re-take (similarity: \(String(format: "%.0f", retake.similarity * 100))%)",
                    confidence: retake.similarity > 0.8 ? 0.85 : 0.65
                ))
            }
        }

        // 4. Speed up weak sections (aggressive only)
        if config.speedUpWeak {
            let weakSections = findWeakSections(
                energyReadings: energyReadings,
                threshold: 30
            )
            for section in weakSections {
                let alreadyCovered = segments.contains { seg in
                    seg.sourceRange.overlaps(section)
                }
                guard !alreadyCovered else { continue }

                segments.append(CutSegment(
                    sourceRange: section,
                    action: .speedUp,
                    reason: "Low engagement — speed to 1.12x",
                    confidence: 0.7
                ))
            }
        }

        // Sort by start time
        segments.sort { $0.sourceRange.start < $1.sourceRange.start }

        // Merge overlapping removals
        segments = mergeOverlapping(segments)

        // Compute stats
        let stats = computeStats(
            originalDuration: assetDuration,
            segments: segments,
            energyReadings: energyReadings
        )

        return CutPlan(
            preset: preset,
            segments: segments,
            stats: stats
        )
    }

    // MARK: - Filler Detection

    /// Detect filler words in a transcript using word matching.
    public func detectFillerWords(
        in transcript: [TranscriptWord],
        aggressive: Bool = false
    ) -> [TranscriptWord] {
        let standardFillers: Set<String> = ["um", "uh", "er", "ah", "hmm", "umm", "uhh", "erm"]
        let hedgeWords: Set<String> = ["basically", "actually", "literally"]

        // Multi-word fillers detected as sequences
        let multiWordFillers = ["you know", "i mean", "sort of", "kind of"]

        var fillers: [TranscriptWord] = []

        for (i, word) in transcript.enumerated() {
            let lowered = word.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let lemma = (word.lemma ?? lowered).lowercased()

            // Standard single-word fillers
            if standardFillers.contains(lowered) || standardFillers.contains(lemma) {
                fillers.append(word)
                continue
            }

            // "like" as filler (not comparative/verb): check context
            if aggressive && (lowered == "like" || lemma == "like") {
                if isFillerLike(at: i, in: transcript) {
                    fillers.append(word)
                    continue
                }
            }

            // Hedge words (aggressive only)
            if aggressive && (hedgeWords.contains(lowered) || hedgeWords.contains(lemma)) {
                fillers.append(word)
                continue
            }

            // Multi-word fillers: check if this word starts a known phrase
            if aggressive || standardFillers.isEmpty == false { // always check "you know" etc in aggressive
                if aggressive {
                    for phrase in multiWordFillers {
                        let phraseWords = phrase.split(separator: " ").map(String.init)
                        if matchesPhrase(at: i, phraseWords: phraseWords, in: transcript) {
                            // Create a combined word spanning the phrase
                            let lastIdx = min(i + phraseWords.count - 1, transcript.count - 1)
                            fillers.append(TranscriptWord(
                                word: phrase,
                                lemma: phrase,
                                start: word.start,
                                end: transcript[lastIdx].end,
                                confidence: word.confidence
                            ))
                        }
                    }
                }
            }
        }

        return fillers
    }

    // MARK: - Re-take Detection

    /// Detect re-takes: consecutive similar sentences where speaker restarts.
    public func detectRetakes(in transcript: [TranscriptWord]) -> [RetakePair] {
        let sentences = splitIntoSentences(transcript)
        guard sentences.count >= 2 else { return [] }

        var retakes: [RetakePair] = []

        for i in 0..<(sentences.count - 1) {
            let a = sentences[i]
            let b = sentences[i + 1]

            // Must be close together (gap < 3s)
            guard a.range.end > 0, b.range.start > 0 else { continue }
            let gap = b.range.start - a.range.end
            guard gap < 3.0, gap >= 0 else { continue }

            // Compute lemma overlap
            let similarity = lemmaSimilarity(a.lemmas, b.lemmas)
            guard similarity >= 0.6 else { continue }

            // Determine which is inferior
            // Prefer: longer sentence, higher confidence, later (usually improved)
            let aScore = sentenceQuality(a)
            let bScore = sentenceQuality(b)

            let (inferior, superior) = aScore < bScore
                ? (a.range, b.range)
                : (b.range, a.range)

            retakes.append(RetakePair(
                inferiorRange: inferior,
                superiorRange: superior,
                similarity: similarity,
                reason: aScore < bScore
                    ? "First attempt replaced by improved re-take"
                    : "Second attempt is weaker re-take"
            ))
        }

        return retakes
    }

    // MARK: - Rehearsal Detection

    /// Detect repeated intros/phrases — multiple takes of the same opening.
    /// Returns the time range to cut (everything from the first take to just before the last take).
    /// Works regardless of gap between takes (could be seconds or minutes apart).
    public func detectRehearsals(in transcript: [TranscriptWord]) -> TimeRange? {
        // Build n-grams (4-word sequences) and find repeats
        let minNgramSize = 4
        guard transcript.count >= minNgramSize else { return nil }

        // Extract all 4-word sequences with their start times
        struct NGram {
            let text: String
            let startTime: TimeInterval
            let endTime: TimeInterval
        }

        var ngrams: [NGram] = []
        for i in 0..<(transcript.count - minNgramSize + 1) {
            let words = transcript[i..<(i + minNgramSize)]
            let text = words.map {
                $0.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            }.joined(separator: " ")
            ngrams.append(NGram(
                text: text,
                startTime: transcript[i].start,
                endTime: transcript[i + minNgramSize - 1].end
            ))
        }

        // Find n-grams that appear more than once
        var ngramOccurrences: [String: [NGram]] = [:]
        for ng in ngrams {
            ngramOccurrences[ng.text, default: []].append(ng)
        }

        // Filter to repeated phrases (2+ occurrences) that appear near the start of the clip
        // "Near the start" = within the first 25% of the transcript duration
        let totalDuration = (transcript.last?.end ?? 0) - (transcript.first?.start ?? 0)
        let earlyThreshold = (transcript.first?.start ?? 0) + totalDuration * 0.25

        var bestRehearsal: TimeRange?
        var bestRehearsalLength = 0 // Prefer longer repeated phrases

        for (text, occurrences) in ngramOccurrences {
            guard occurrences.count >= 2 else { continue }

            // At least one occurrence should be in the early part
            let earlyOccurrences = occurrences.filter { $0.startTime < earlyThreshold }
            guard !earlyOccurrences.isEmpty else { continue }

            // Skip very common phrases (filler-like)
            let commonPhrases: Set<String> = [
                "you know what i", "i don't know if", "i think it's like",
                "and then we can", "i was just like", "like you know like",
            ]
            if commonPhrases.contains(text) { continue }

            // The last occurrence is the "good take" — everything before it is rehearsal
            let sorted = occurrences.sorted { $0.startTime < $1.startTime }
            let firstOccurrence = sorted.first!
            let lastOccurrence = sorted.last!

            // Must have meaningful time gap between first and last (>10s)
            guard lastOccurrence.startTime - firstOccurrence.startTime > 10 else { continue }

            // The rehearsal range: from the start of the clip to just before the last take
            // Cut everything before the final good take
            let clipStart = transcript.first?.start ?? firstOccurrence.startTime
            let rehearsalStart = clipStart
            let rehearsalEnd = lastOccurrence.startTime - 0.05

            // Prefer the longest repeated phrase (more confident it's a real rehearsal)
            if text.split(separator: " ").count > bestRehearsalLength {
                bestRehearsalLength = text.split(separator: " ").count
                bestRehearsal = TimeRange(start: rehearsalStart, end: rehearsalEnd)
            }
        }

        // Only return if the rehearsal range starts near the beginning of the clip
        // (rehearsals happen at the start, not mid-episode)
        if let range = bestRehearsal {
            let clipStart = transcript.first?.start ?? 0
            if range.start - clipStart < totalDuration * 0.25 {
                return range
            }
        }

        return nil
    }

    // MARK: - Plan to Intents

    /// Convert a CutPlan into EditorIntents for a specific clip.
    /// Processes end-to-start to avoid position shifts.
    public func planToIntents(
        plan: CutPlan,
        clipID: UUID,
        clip: Clip
    ) -> [EditorIntent] {
        // Filter to actionable segments, sorted end-to-start
        let actionable = plan.segments
            .filter { $0.action != .keep }
            .sorted { $0.sourceRange.start > $1.sourceRange.start }

        guard !actionable.isEmpty else { return [] }

        var intents: [EditorIntent] = []

        for segment in actionable {
            // Convert source time to timeline time
            let tlStart = clip.timelineRange.start +
                (segment.sourceRange.start - clip.sourceRange.start) / clip.speed
            let tlEnd = clip.timelineRange.start +
                (segment.sourceRange.end - clip.sourceRange.start) / clip.speed

            // Clamp to clip boundaries
            let clampedStart = max(tlStart, clip.timelineRange.start + 0.01)
            let clampedEnd = min(tlEnd, clip.timelineRange.end - 0.01)
            guard clampedStart < clampedEnd else { continue }

            switch segment.action {
            case .remove, .removeFiller, .removeRetake:
                // Split at start, split at end, delete the middle
                // The split creates a new clip — we use batch to make it atomic
                intents.append(.splitClip(clipID: clipID, at: clampedStart))
                intents.append(.splitClip(clipID: clipID, at: clampedEnd))
                // Note: actual clip IDs for delete will be resolved at execution time
                // by the compound handler. We encode the time range for the handler.

            case .speedUp:
                intents.append(.splitClip(clipID: clipID, at: clampedStart))
                intents.append(.splitClip(clipID: clipID, at: clampedEnd))
                intents.append(.setClipSpeed(clipID: clipID, speed: 1.12))

            case .keep:
                break
            }
        }

        return [.batch(intents)]
    }
}

// MARK: - Preset Configuration

public enum AutoCutPreset: String, Codable, Sendable, CaseIterable {
    case gentle
    case standard
    case aggressive

    var config: AutoCutConfig {
        switch self {
        case .gentle:
            return AutoCutConfig(
                silenceThreshold: 2.0,
                removeFillers: false,
                removeHedgeWords: false,
                detectRetakes: false,
                speedUpWeak: false
            )
        case .standard:
            return AutoCutConfig(
                silenceThreshold: 0.8,
                removeFillers: true,
                removeHedgeWords: false,
                detectRetakes: true,
                speedUpWeak: false
            )
        case .aggressive:
            return AutoCutConfig(
                silenceThreshold: 0.3,
                removeFillers: true,
                removeHedgeWords: true,
                detectRetakes: true,
                speedUpWeak: true
            )
        }
    }
}

struct AutoCutConfig {
    let silenceThreshold: TimeInterval
    let removeFillers: Bool
    let removeHedgeWords: Bool
    let detectRetakes: Bool
    let speedUpWeak: Bool
}

// MARK: - CutPlan

public struct CutPlan: Codable, Sendable {
    public let preset: AutoCutPreset
    public let segments: [CutSegment]
    public let stats: CutStats

    public init(preset: AutoCutPreset, segments: [CutSegment], stats: CutStats) {
        self.preset = preset
        self.segments = segments
        self.stats = stats
    }
}

public struct CutSegment: Codable, Sendable {
    public let sourceRange: TimeRange
    public let action: SegmentAction
    public let reason: String
    public let confidence: Double

    public init(sourceRange: TimeRange, action: SegmentAction, reason: String, confidence: Double) {
        self.sourceRange = sourceRange
        self.action = action
        self.reason = reason
        self.confidence = confidence
    }
}

public enum SegmentAction: String, Codable, Sendable {
    case keep
    case remove
    case speedUp
    case removeFiller
    case removeRetake
}

public struct CutStats: Codable, Sendable {
    public let originalDuration: TimeInterval
    public let resultDuration: TimeInterval
    public let segmentsRemoved: Int
    public let fillerWordsRemoved: Int
    public let retakesRemoved: Int
    public let speechRatioBefore: Float
    public let speechRatioAfter: Float
    public let engagementBefore: Int
    public let engagementAfter: Int

    public init(
        originalDuration: TimeInterval,
        resultDuration: TimeInterval,
        segmentsRemoved: Int,
        fillerWordsRemoved: Int,
        retakesRemoved: Int,
        speechRatioBefore: Float,
        speechRatioAfter: Float,
        engagementBefore: Int,
        engagementAfter: Int
    ) {
        self.originalDuration = originalDuration
        self.resultDuration = resultDuration
        self.segmentsRemoved = segmentsRemoved
        self.fillerWordsRemoved = fillerWordsRemoved
        self.retakesRemoved = retakesRemoved
        self.speechRatioBefore = speechRatioBefore
        self.speechRatioAfter = speechRatioAfter
        self.engagementBefore = engagementBefore
        self.engagementAfter = engagementAfter
    }
}

public struct RetakePair: Codable, Sendable {
    public let inferiorRange: TimeRange
    public let superiorRange: TimeRange
    public let similarity: Double
    public let reason: String

    public init(inferiorRange: TimeRange, superiorRange: TimeRange, similarity: Double, reason: String) {
        self.inferiorRange = inferiorRange
        self.superiorRange = superiorRange
        self.similarity = similarity
        self.reason = reason
    }
}

// MARK: - Private Helpers

extension AutoCutEngine {

    /// Check if "like" at a given index is a filler (not verb/comparative).
    private func isFillerLike(at index: Int, in transcript: [TranscriptWord]) -> Bool {
        // "like" after a pause or at sentence start → likely filler
        if index == 0 { return true }

        let prev = transcript[index - 1]
        let gap = transcript[index].start - prev.end

        // Big gap before → filler
        if gap > 0.3 { return true }

        // After common filler-preceding words → filler
        let prevWord = prev.word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let fillerPrecursors: Set<String> = ["was", "is", "it's", "i'm", "just", "so", "and", "but", "or"]
        if fillerPrecursors.contains(prevWord) { return true }

        return false
    }

    /// Check if transcript starting at `index` matches a multi-word phrase.
    private func matchesPhrase(at index: Int, phraseWords: [String], in transcript: [TranscriptWord]) -> Bool {
        guard index + phraseWords.count <= transcript.count else { return false }

        for (offset, expected) in phraseWords.enumerated() {
            let actual = transcript[index + offset].word
                .lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            if actual != expected { return false }
        }

        // Check words are close together (< 0.5s between each)
        for offset in 0..<(phraseWords.count - 1) {
            let gap = transcript[index + offset + 1].start - transcript[index + offset].end
            if gap > 0.5 { return false }
        }

        return true
    }

    /// Split transcript into sentences based on punctuation and pauses.
    struct Sentence {
        let words: [TranscriptWord]
        let range: TimeRange
        let lemmas: Set<String>
    }

    func splitIntoSentences(_ transcript: [TranscriptWord]) -> [Sentence] {
        var sentences: [Sentence] = []
        var current: [TranscriptWord] = []

        for (i, word) in transcript.enumerated() {
            current.append(word)

            let isEnd = word.word.hasSuffix(".") ||
                        word.word.hasSuffix("?") ||
                        word.word.hasSuffix("!")

            // Also split on long pauses
            let hasLongPause = i < transcript.count - 1 &&
                (transcript[i + 1].start - word.end) > 0.8

            if isEnd || hasLongPause || i == transcript.count - 1 {
                guard !current.isEmpty,
                      let first = current.first,
                      let last = current.last else { continue }

                let lemmas = Set(current.compactMap { ($0.lemma ?? $0.word).lowercased() })
                sentences.append(Sentence(
                    words: current,
                    range: TimeRange(start: first.start, end: last.end),
                    lemmas: lemmas
                ))
                current = []
            }
        }

        return sentences
    }

    /// Jaccard similarity between two lemma sets.
    func lemmaSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let stopwords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been",
            "have", "has", "had", "do", "does", "did", "will", "would",
            "could", "should", "may", "might", "can", "shall",
            "i", "you", "he", "she", "it", "we", "they", "me", "him",
            "her", "us", "them", "my", "your", "his", "its", "our", "their",
            "this", "that", "these", "those", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "and", "or", "but", "not", "so",
        ]

        let aFiltered = a.subtracting(stopwords)
        let bFiltered = b.subtracting(stopwords)

        guard !aFiltered.isEmpty || !bFiltered.isEmpty else { return 0 }

        let intersection = aFiltered.intersection(bFiltered).count
        let union = aFiltered.union(bFiltered).count
        guard union > 0 else { return 0 }

        return Double(intersection) / Double(union)
    }

    /// Quality score for a sentence (used to pick the better re-take).
    func sentenceQuality(_ sentence: Sentence) -> Double {
        var score = 0.0
        // Longer is usually better
        score += Double(sentence.words.count) * 2
        // Higher confidence
        let avgConfidence = sentence.words.map(\.confidence).reduce(0, +) / Double(max(sentence.words.count, 1))
        score += avgConfidence * 10
        // Later position (speaker usually improves)
        score += sentence.range.start * 0.01
        return score
    }

    /// Find sections where engagement is below threshold for >= 3 seconds.
    func findWeakSections(
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading],
        threshold: Int
    ) -> [TimeRange] {
        var sections: [TimeRange] = []
        var weakStart: TimeInterval?

        for reading in energyReadings {
            // Approximate engagement from individual reading
            let isWeak = reading.isSilence || (!reading.isSpeech && reading.rms < 0.02)

            if isWeak {
                if weakStart == nil { weakStart = reading.time }
            } else {
                if let start = weakStart {
                    let duration = reading.time - start
                    if duration >= 3.0 {
                        sections.append(TimeRange(start: start, end: reading.time))
                    }
                    weakStart = nil
                }
            }
        }

        // Close trailing
        if let start = weakStart, let last = energyReadings.last {
            let duration = last.time - start
            if duration >= 3.0 {
                sections.append(TimeRange(start: start, end: last.time + 1.0))
            }
        }

        return sections
    }

    /// Merge overlapping segments, preferring the stronger action.
    func mergeOverlapping(_ segments: [CutSegment]) -> [CutSegment] {
        guard !segments.isEmpty else { return [] }

        var merged: [CutSegment] = [segments[0]]

        for segment in segments.dropFirst() {
            if let last = merged.last, last.sourceRange.overlaps(segment.sourceRange) {
                // Extend the existing segment
                let combined = CutSegment(
                    sourceRange: TimeRange(
                        start: min(last.sourceRange.start, segment.sourceRange.start),
                        end: max(last.sourceRange.end, segment.sourceRange.end)
                    ),
                    action: priorityAction(last.action, segment.action),
                    reason: "\(last.reason); \(segment.reason)",
                    confidence: min(last.confidence, segment.confidence)
                )
                merged[merged.count - 1] = combined
            } else {
                merged.append(segment)
            }
        }

        return merged
    }

    /// Higher priority action wins when merging.
    private func priorityAction(_ a: SegmentAction, _ b: SegmentAction) -> SegmentAction {
        let priority: [SegmentAction: Int] = [
            .remove: 3, .removeRetake: 2, .removeFiller: 2, .speedUp: 1, .keep: 0
        ]
        return (priority[a] ?? 0) >= (priority[b] ?? 0) ? a : b
    }

    /// Compute before/after statistics from a cut plan.
    func computeStats(
        originalDuration: TimeInterval,
        segments: [CutSegment],
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading]
    ) -> CutStats {
        var removedDuration: TimeInterval = 0
        var fillerCount = 0
        var retakeCount = 0
        var speedUpDuration: TimeInterval = 0

        for seg in segments {
            switch seg.action {
            case .remove:
                removedDuration += seg.sourceRange.duration
            case .removeFiller:
                removedDuration += seg.sourceRange.duration
                fillerCount += 1
            case .removeRetake:
                removedDuration += seg.sourceRange.duration
                retakeCount += 1
            case .speedUp:
                // At 1.12x, saves ~10.7% of the segment's duration
                speedUpDuration += seg.sourceRange.duration * (1.0 - 1.0 / 1.12)
            case .keep:
                break
            }
        }

        let resultDuration = originalDuration - removedDuration - speedUpDuration
        let totalReadings = Float(max(energyReadings.count, 1))
        let speechCount = Float(energyReadings.filter(\.isSpeech).count)
        let silenceCount = Float(energyReadings.filter(\.isSilence).count)
        let speechRatioBefore = speechCount / totalReadings

        // Estimate after: removed sections are mostly silence/filler
        let remainingTotal = totalReadings - Float(removedDuration) // approximate
        let speechRatioAfter = remainingTotal > 0
            ? speechCount / max(remainingTotal, 1)
            : speechRatioBefore

        // Engagement: average of all readings (crude but directional)
        let avgRMS = energyReadings.map(\.rms).reduce(0, +) / Float(max(energyReadings.count, 1))
        let engagementBefore = min(100, Int(speechRatioBefore * 30 + min(avgRMS * 500, 25) + (1 - silenceCount / totalReadings) * 15))
        let engagementAfter = min(100, Int(min(speechRatioAfter, 1.0) * 30 + min(avgRMS * 500, 25) + 15))

        return CutStats(
            originalDuration: originalDuration,
            resultDuration: max(resultDuration, 0),
            segmentsRemoved: segments.filter { $0.action != .keep && $0.action != .speedUp }.count,
            fillerWordsRemoved: fillerCount,
            retakesRemoved: retakeCount,
            speechRatioBefore: speechRatioBefore,
            speechRatioAfter: min(speechRatioAfter, 1.0),
            engagementBefore: engagementBefore,
            engagementAfter: engagementAfter
        )
    }
}
