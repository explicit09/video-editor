import Foundation

/// Detects episode boundaries in long recordings by combining energy analysis,
/// transcript continuity, and context layer detection.
///
/// Strategy:
/// 1. Find candidate starts (intro phrases, energy spikes after silence)
/// 2. Validate each candidate by looking backward (is there a break before?) and
///    forward (does sustained on-air content follow?)
/// 3. Find candidate ends by detecting context breaks — transitions from content
///    to meta-talk (production discussion, "off camera", planning next episode)
/// 4. Build confidence incrementally — more evidence = higher confidence
public struct EpisodeBoundaryDetector: Sendable {

    public init() {}

    // MARK: - Detect Episodes

    /// Detect all episodes in a recording.
    /// Requires pre-computed transcript words and energy readings.
    public func detect(
        transcript: [TranscriptWord],
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading],
        totalDuration: TimeInterval
    ) -> [DetectedEpisode] {
        guard !transcript.isEmpty else { return [] }

        // Step 1: Find candidate starts
        let startCandidates = findStartCandidates(transcript: transcript, energyReadings: energyReadings)

        // Step 2: For each start, find the end
        var episodes: [DetectedEpisode] = []

        for (i, start) in startCandidates.enumerated() {
            // End boundary: either the next episode's start area, or the recording end
            let searchEnd: TimeInterval
            if i + 1 < startCandidates.count {
                searchEnd = startCandidates[i + 1].time
            } else {
                searchEnd = totalDuration
            }

            let end = findEndBoundary(
                afterStart: start.time,
                searchEnd: searchEnd,
                transcript: transcript,
                energyReadings: energyReadings
            )

            let duration = end.time - start.time
            guard duration > 60 else { continue } // Skip anything under 1 minute

            episodes.append(DetectedEpisode(
                startTime: start.time,
                endTime: end.time,
                startConfidence: start.confidence,
                endConfidence: end.confidence,
                title: start.matchedPhrase,
                startEvidence: start.evidence,
                endEvidence: end.evidence
            ))
        }

        return episodes
    }
}

// MARK: - Models

public struct DetectedEpisode: Codable, Sendable {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let startConfidence: Double    // 0-1
    public let endConfidence: Double      // 0-1
    public let title: String?             // Extracted from intro if found
    public let startEvidence: [String]
    public let endEvidence: [String]

    public var duration: TimeInterval { endTime - startTime }

    public var formattedStart: String { formatTime(startTime) }
    public var formattedEnd: String { formatTime(endTime) }
    public var formattedDuration: String { formatTime(duration) }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}

struct BoundaryCandidate2 {
    let time: TimeInterval
    var confidence: Double
    var evidence: [String]
    var matchedPhrase: String?
}

// MARK: - Start Detection

extension EpisodeBoundaryDetector {

    /// Find candidate episode starts by looking for intro patterns and energy transitions.
    func findStartCandidates(
        transcript: [TranscriptWord],
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading]
    ) -> [BoundaryCandidate2] {
        var candidates: [BoundaryCandidate2] = []

        // Strategy 1: Intro phrase detection
        let introPatterns: [(phrase: [String], weight: Double)] = [
            (["welcome", "to"], 0.4),
            (["today", "we", "are"], 0.3),
            (["this", "is"], 0.15),
            (["hey", "guys"], 0.2),
            (["hello", "everyone"], 0.25),
            (["what's", "up"], 0.15),
            (["good", "morning"], 0.2),
            (["good", "evening"], 0.2),
            (["episode"], 0.2),
        ]

        for (idx, word) in transcript.enumerated() {
            for pattern in introPatterns {
                if matchesSequence(at: idx, pattern: pattern.phrase, in: transcript) {
                    var candidate = BoundaryCandidate2(
                        time: word.start,
                        confidence: pattern.weight,
                        evidence: ["Intro phrase: \"\(pattern.phrase.joined(separator: " "))\" at \(formatTime(word.start))"],
                        matchedPhrase: extractTitle(at: idx, in: transcript)
                    )

                    // Validate: look backward — was there a break/silence before?
                    let backwardScore = checkBackward(before: word.start, transcript: transcript, energyReadings: energyReadings)
                    candidate.confidence += backwardScore.score
                    candidate.evidence.append(contentsOf: backwardScore.evidence)

                    // Validate: look forward — does sustained content follow?
                    let forwardScore = checkForward(after: word.start, transcript: transcript, energyReadings: energyReadings)
                    candidate.confidence += forwardScore.score
                    candidate.evidence.append(contentsOf: forwardScore.evidence)

                    // Only keep if confidence is meaningful
                    if candidate.confidence >= 0.5 {
                        candidates.append(candidate)
                    }
                }
            }
        }

        // Strategy 2: Energy transition — long silence/low-energy followed by sustained speech
        let energyStarts = findEnergyTransitions(energyReadings: energyReadings)
        for transition in energyStarts {
            // Check if we already have a phrase-based candidate near this time
            let nearExisting = candidates.contains { abs($0.time - transition.time) < 30 }
            if !nearExisting {
                var candidate = BoundaryCandidate2(
                    time: transition.time,
                    confidence: 0.3,
                    evidence: transition.evidence,
                    matchedPhrase: nil
                )

                let forwardScore = checkForward(after: transition.time, transcript: transcript, energyReadings: energyReadings)
                candidate.confidence += forwardScore.score
                candidate.evidence.append(contentsOf: forwardScore.evidence)

                if candidate.confidence >= 0.5 {
                    candidates.append(candidate)
                }
            }
        }

        // Deduplicate: if multiple candidates within 60s, keep highest confidence
        candidates.sort { $0.time < $1.time }
        var deduped: [BoundaryCandidate2] = []
        for candidate in candidates {
            if let last = deduped.last, candidate.time - last.time < 60 {
                if candidate.confidence > last.confidence {
                    deduped[deduped.count - 1] = candidate
                }
            } else {
                deduped.append(candidate)
            }
        }

        return deduped
    }

    /// Check what's happening before a candidate start.
    /// High score if there's silence, topic break, or meta-talk before.
    private func checkBackward(
        before time: TimeInterval,
        transcript: [TranscriptWord],
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading]
    ) -> (score: Double, evidence: [String]) {
        var score = 0.0
        var evidence: [String] = []
        let windowStart = max(time - 60, 0)

        // Check for silence/low energy in the 30s before
        let preReadings = energyReadings.filter { $0.time >= windowStart && $0.time < time }
        let silenceCount = preReadings.filter { $0.isSilence }.count
        let silenceRatio = preReadings.isEmpty ? 0 : Float(silenceCount) / Float(preReadings.count)

        if silenceRatio > 0.5 {
            score += 0.2
            evidence.append("High silence before (\(Int(silenceRatio * 100))%)")
        }

        // Check for meta-talk before (production language)
        let preWords = transcript.filter { $0.start >= windowStart && $0.end < time }
        let metaScore = detectMetaTalk(in: preWords)
        if metaScore > 0 {
            score += min(Double(metaScore) * 0.15, 0.2)
            evidence.append("Meta-talk detected before start")
        }

        return (score, evidence)
    }

    /// Check what's happening after a candidate start.
    /// High score if sustained on-air content follows.
    private func checkForward(
        after time: TimeInterval,
        transcript: [TranscriptWord],
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading]
    ) -> (score: Double, evidence: [String]) {
        var score = 0.0
        var evidence: [String] = []

        // Check energy in the 5 minutes after
        let postReadings = energyReadings.filter { $0.time >= time && $0.time < time + 300 }
        let speechCount = postReadings.filter { $0.isSpeech }.count
        let speechRatio = postReadings.isEmpty ? 0 : Float(speechCount) / Float(postReadings.count)

        if speechRatio > 0.5 {
            score += 0.2
            evidence.append("Sustained speech after (\(Int(speechRatio * 100))% in next 5 min)")
        }

        // Check for topic consistency — do the same topics continue for several minutes?
        let postWords = transcript.filter { $0.start >= time && $0.end < time + 300 }
        let metaScore = detectMetaTalk(in: postWords)
        if metaScore == 0 {
            score += 0.1
            evidence.append("No meta-talk in next 5 min (on-air content)")
        }

        return (score, evidence)
    }
}

// MARK: - End Detection

extension EpisodeBoundaryDetector {

    /// Find where an episode ends after a given start time.
    func findEndBoundary(
        afterStart startTime: TimeInterval,
        searchEnd: TimeInterval,
        transcript: [TranscriptWord],
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading]
    ) -> BoundaryCandidate2 {
        let wordsInRange = transcript.filter { $0.start >= startTime && $0.end <= searchEnd }

        // Strategy 1: Look for context breaks — meta-talk transitions
        // Scan in 30-second windows, looking for the first sustained meta-talk
        let windowSize: TimeInterval = 30
        var cursor = startTime + 120 // Don't check first 2 min (episode is still starting)

        var bestEnd: BoundaryCandidate2?

        while cursor < searchEnd - windowSize {
            let windowWords = wordsInRange.filter {
                $0.start >= cursor && $0.end < cursor + windowSize
            }

            let metaScore = detectMetaTalk(in: windowWords)

            if metaScore >= 2 {
                // Strong meta-talk detected — this is likely the end
                // But verify: check if content resumes after (could be a brief aside)
                let afterWords = wordsInRange.filter {
                    $0.start >= cursor + windowSize && $0.end < cursor + windowSize + 60
                }
                let afterMeta = detectMetaTalk(in: afterWords)
                let contentResumes = afterMeta == 0

                if !contentResumes || afterMeta >= 1 {
                    // Meta-talk continues — this is the real end
                    var candidate = BoundaryCandidate2(
                        time: cursor,
                        confidence: min(Double(metaScore) * 0.25, 0.9),
                        evidence: ["Context break: meta-talk at \(formatTime(cursor))"],
                        matchedPhrase: nil
                    )

                    // Check for specific end markers
                    let endMarkers = findEndMarkers(in: windowWords)
                    candidate.evidence.append(contentsOf: endMarkers.evidence)
                    candidate.confidence += endMarkers.score

                    if bestEnd == nil || candidate.confidence > bestEnd!.confidence {
                        bestEnd = candidate
                    }

                    break // First strong meta-talk transition is the end
                }
            }

            cursor += windowSize / 2 // 50% overlap
        }

        // Strategy 2: If no meta-talk found, use energy drop
        if bestEnd == nil {
            let endByEnergy = findEndByEnergy(
                afterStart: startTime,
                searchEnd: searchEnd,
                energyReadings: energyReadings
            )
            if let e = endByEnergy {
                bestEnd = e
            }
        }

        // Fallback: use searchEnd
        return bestEnd ?? BoundaryCandidate2(
            time: searchEnd,
            confidence: 0.3,
            evidence: ["Fallback: no clear end detected, using next boundary"],
            matchedPhrase: nil
        )
    }

    /// Look for specific closing/transition markers in transcript.
    private func findEndMarkers(in words: [TranscriptWord]) -> (score: Double, evidence: [String]) {
        var score = 0.0
        var evidence: [String] = []

        let text = words.map { $0.word.lowercased() }.joined(separator: " ")

        let endPhrases: [(phrase: String, weight: Double, label: String)] = [
            ("off camera", 0.3, "\"off camera\" marker"),
            ("which topics", 0.2, "planning next episode"),
            ("next format", 0.15, "format discussion"),
            ("choosing today", 0.2, "topic selection"),
            ("that's a wrap", 0.3, "wrap marker"),
            ("thank you for", 0.2, "thank you closing"),
            ("see you next", 0.25, "see you next"),
            ("until next time", 0.25, "until next time"),
            ("bye bye", 0.2, "farewell"),
            ("peace out", 0.2, "farewell"),
            ("signing off", 0.3, "sign-off"),
            ("let's stop", 0.2, "stop marker"),
            ("we should stop", 0.2, "stop marker"),
            ("let's do", 0.1, "transition to next task"),
        ]

        for ep in endPhrases {
            if text.contains(ep.phrase) {
                score += ep.weight
                evidence.append(ep.label)
            }
        }

        return (score, evidence)
    }

    /// Find end by sustained energy drop.
    private func findEndByEnergy(
        afterStart: TimeInterval,
        searchEnd: TimeInterval,
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading]
    ) -> BoundaryCandidate2? {
        // Look for sustained silence (>30s) after at least 3 min of content
        let minContentDuration: TimeInterval = 180
        let readings = energyReadings.filter { $0.time >= afterStart + minContentDuration && $0.time < searchEnd }

        var silenceStart: TimeInterval?
        for reading in readings {
            if reading.isSilence {
                if silenceStart == nil { silenceStart = reading.time }
            } else {
                if let start = silenceStart, reading.time - start >= 30 {
                    return BoundaryCandidate2(
                        time: start,
                        confidence: 0.5,
                        evidence: ["Sustained silence (\(Int(reading.time - start))s) at \(formatTime(start))"],
                        matchedPhrase: nil
                    )
                }
                silenceStart = nil
            }
        }

        return nil
    }
}

// MARK: - Meta-Talk Detection

extension EpisodeBoundaryDetector {

    /// Detect "meta-talk" — production discussion, not content.
    /// Returns a score: 0 = content, 1+ = meta-talk (higher = more confident).
    ///
    /// Meta-talk indicators:
    /// - References to the recording process ("off camera", "recording", "take")
    /// - Production planning ("which topics", "next episode", "format")
    /// - Self-referential ("our intro", "our podcast", "we should")
    /// - Technical production ("edit", "caption", "thumbnail", "upload")
    func detectMetaTalk(in words: [TranscriptWord]) -> Int {
        guard !words.isEmpty else { return 0 }

        let text = words.map { $0.word.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .joined(separator: " ")

        var hits = 0

        // Strong meta indicators (2 points each)
        let strongMeta = [
            "off camera", "which topics", "choosing today", "next format",
            "our intro", "let's do the", "new format", "signing off",
            "should we talk about", "what are we", "let's plan",
        ]
        for phrase in strongMeta {
            if text.contains(phrase) { hits += 2 }
        }

        // Medium meta indicators (1 point each)
        let mediumMeta = [
            "our podcast", "our episode", "the edit", "the caption",
            "the thumbnail", "the algorithm", "push content",
            "reaction video", "twenty minute max", "upload",
            "our people", "our viewers", "retention",
        ]
        for phrase in mediumMeta {
            if text.contains(phrase) { hits += 1 }
        }

        // Weak meta indicators — only count if multiple appear
        let weakMeta = ["logo", "content", "clip", "format", "views", "tags", "description"]
        let weakCount = weakMeta.filter { text.contains($0) }.count
        if weakCount >= 3 { hits += 1 }

        return hits
    }
}

// MARK: - Helpers

extension EpisodeBoundaryDetector {

    /// Check if transcript at index matches a word sequence.
    private func matchesSequence(at index: Int, pattern: [String], in transcript: [TranscriptWord]) -> Bool {
        guard index + pattern.count <= transcript.count else { return false }

        for (offset, expected) in pattern.enumerated() {
            let actual = transcript[index + offset].word
                .lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            if actual != expected { return false }
        }

        // Words should be close together (<1s gaps)
        for offset in 0..<(pattern.count - 1) {
            let gap = transcript[index + offset + 1].start - transcript[index + offset].end
            if gap > 1.0 { return false }
        }

        return true
    }

    /// Extract a potential title from the transcript after an intro phrase.
    /// e.g., "Welcome to Technologer" → "Technologer"
    private func extractTitle(at index: Int, in transcript: [TranscriptWord]) -> String? {
        // Look for "welcome to X" pattern
        guard index + 2 < transcript.count else { return nil }
        let w0 = transcript[index].word.lowercased()
        let w1 = transcript[index + 1].word.lowercased()

        if w0 == "welcome" && w1 == "to" {
            // Next word(s) are the title — take up to 3 words until punctuation
            var titleWords: [String] = []
            for j in (index + 2)..<min(index + 6, transcript.count) {
                let word = transcript[j].word
                let clean = word.trimmingCharacters(in: .punctuationCharacters)
                if word.hasSuffix(",") || word.hasSuffix(".") {
                    if !clean.isEmpty { titleWords.append(clean) }
                    break
                }
                titleWords.append(clean)
            }
            return titleWords.isEmpty ? nil : titleWords.joined(separator: " ")
        }

        return nil
    }

    /// Find energy transitions: long low-energy followed by sustained high-energy.
    private func findEnergyTransitions(
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading]
    ) -> [BoundaryCandidate2] {
        var candidates: [BoundaryCandidate2] = []

        // Look for: >=20s of silence/low followed by >=60s of speech
        var lowStart: TimeInterval?
        var lowCount = 0

        for (i, reading) in energyReadings.enumerated() {
            if reading.isSilence || !reading.isSpeech {
                if lowStart == nil { lowStart = reading.time }
                lowCount += 1
            } else {
                if let start = lowStart, lowCount >= 20 {
                    // Check if speech sustains for 60s after
                    let afterReadings = energyReadings.suffix(from: i).prefix(60)
                    let speechCount = afterReadings.filter { $0.isSpeech }.count
                    if speechCount > 40 {
                        candidates.append(BoundaryCandidate2(
                            time: reading.time,
                            confidence: 0.3,
                            evidence: ["Energy transition: \(lowCount)s low → sustained speech at \(formatTime(reading.time))"],
                            matchedPhrase: nil
                        ))
                    }
                }
                lowStart = nil
                lowCount = 0
            }
        }

        return candidates
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}
