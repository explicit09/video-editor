import Foundation

// MARK: - ContentScorer

/// Scores content segments on 5 independent dimensions.
/// Uses gate-based quality filtering: all dimensions must pass.
public struct ContentScorer: Sendable {

    public init() {}

    // MARK: - Score a Segment

    /// Score a segment on all 5 dimensions using pre-computed analysis data.
    public func score(
        segment: TimeRange,
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading],
        transcript: [TranscriptWord]
    ) -> ScoreCard {
        let segReadings = energyReadings.filter {
            $0.time >= segment.start && $0.time < segment.end
        }
        let segWords = transcript.filter {
            $0.start >= segment.start && $0.end <= segment.end
        }

        return ScoreCard(
            hookStrength: scoreHook(readings: segReadings, words: segWords),
            retentionCurve: scoreRetention(readings: segReadings),
            emotionalArc: scoreEmotionalArc(readings: segReadings),
            completeness: scoreCompleteness(words: segWords, segment: segment),
            audioQuality: scoreAudioQuality(readings: segReadings)
        )
    }

    /// Score multiple segments and return ranked results.
    public func rankSegments(
        segments: [TimeRange],
        energyReadings: [SpeechEnergyAnalyzer.EnergyReading],
        transcript: [TranscriptWord]
    ) -> [(segment: TimeRange, score: ScoreCard)] {
        segments
            .map { seg in
                (segment: seg, score: score(
                    segment: seg,
                    energyReadings: energyReadings,
                    transcript: transcript
                ))
            }
            .sorted { $0.score.overall > $1.score.overall }
    }
}

// MARK: - ScoreCard

public struct ScoreCard: Codable, Sendable {
    public let hookStrength: Double
    public let retentionCurve: Double
    public let emotionalArc: Double
    public let completeness: Double
    public let audioQuality: Double

    /// Overall = minimum of all dimensions (gate-based, not average).
    public var overall: Double {
        [hookStrength, retentionCurve, emotionalArc, completeness, audioQuality].min() ?? 0
    }

    /// Average across all dimensions.
    public var average: Double {
        (hookStrength + retentionCurve + emotionalArc + completeness + audioQuality) / 5.0
    }

    /// Passes quality gate: all dimensions >= threshold.
    public func passesGate(threshold: Double = 7.0) -> Bool { overall >= threshold }

    /// Auto-reject: any dimension below floor.
    public func autoReject(floor: Double = 5.0) -> Bool { overall < floor }

    public init(
        hookStrength: Double,
        retentionCurve: Double,
        emotionalArc: Double,
        completeness: Double,
        audioQuality: Double
    ) {
        self.hookStrength = hookStrength
        self.retentionCurve = retentionCurve
        self.emotionalArc = emotionalArc
        self.completeness = completeness
        self.audioQuality = audioQuality
    }
}

// MARK: - Dimension Scorers

extension ContentScorer {

    /// Hook strength: Do the first 3 seconds grab attention?
    func scoreHook(
        readings: [SpeechEnergyAnalyzer.EnergyReading],
        words: [TranscriptWord]
    ) -> Double {
        guard !readings.isEmpty else { return 5.0 }

        var score = 0.0
        let avgRMS = readings.map(\.rms).reduce(0, +) / Float(readings.count)

        // First 3 seconds energy spike
        let hookReadings = readings.prefix(3)
        if !hookReadings.isEmpty {
            let hookAvg = hookReadings.map(\.rms).reduce(0, +) / Float(hookReadings.count)
            if hookAvg > avgRMS * 1.5 { score += 3.0 }
            else if hookAvg > avgRMS * 1.2 { score += 1.5 }
        }

        // Transcript patterns in first 3 seconds
        let hookWords = words.filter { $0.start < (readings.first?.time ?? 0) + 3.0 }
        let hookText = hookWords.map(\.word).joined(separator: " ").lowercased()

        if hookText.contains("?") { score += 2.0 } // Question hook
        let boldClaims: [String] = ["never", "always", "actually", "truth", "secret", "mistake", "wrong", "nobody"]
        if boldClaims.contains(where: { hookText.contains($0) }) { score += 2.0 }

        // Contains a specific number/statistic
        let hasNumber = hookWords.contains { $0.word.rangeOfCharacter(from: .decimalDigits) != nil }
        if hasNumber { score += 1.5 }

        // No filler in first 3 seconds
        let fillerWords: Set<String> = ["um", "uh", "er", "ah", "hmm"]
        let startsWithFiller = hookWords.contains {
            fillerWords.contains($0.word.lowercased().trimmingCharacters(in: .punctuationCharacters))
        }
        if startsWithFiller { score -= 2.0 } else { score += 1.0 }

        return min(max(score, 0), 10)
    }

    /// Retention curve: Does energy stay high throughout?
    func scoreRetention(readings: [SpeechEnergyAnalyzer.EnergyReading]) -> Double {
        guard readings.count >= 4 else { return 5.0 }

        let quarter = readings.count / 4
        let q0 = Array(readings[0..<quarter])
        let q1 = Array(readings[quarter..<quarter*2])
        let q2 = Array(readings[quarter*2..<quarter*3])
        let q3 = Array(readings[quarter*3..<readings.count])
        let quartiles: [[SpeechEnergyAnalyzer.EnergyReading]] = [q0, q1, q2, q3]

        let quartileEngagement: [Float] = quartiles.map { q in
            let speechCount = Float(q.filter { $0.isSpeech }.count)
            let rmsAvg = q.map { $0.rms }.reduce(Float(0), +) / Float(max(q.count, 1))
            return speechCount / Float(max(q.count, 1)) * 50 + min(rmsAvg * 500, 50)
        }

        let allHigh = quartileEngagement.allSatisfy { $0 > 50 }
        let rising = zip(quartileEngagement, quartileEngagement.dropFirst()).allSatisfy { $0 <= $1 }
        let trailingOff = quartileEngagement.last ?? 0 < (quartileEngagement.first ?? 0) * 0.6
        let allLow = quartileEngagement.allSatisfy { $0 < 25 }

        if allHigh { return 9.0 }
        if rising { return 8.0 }
        if allLow { return 2.0 }
        if trailingOff { return 3.0 }

        // Middle ground: check how many quartiles are above average
        let avg = quartileEngagement.reduce(0, +) / Float(quartileEngagement.count)
        let aboveAvg = quartileEngagement.filter { $0 >= avg }.count
        return Double(aboveAvg) * 2.0 + 1.0
    }

    /// Emotional arc: Is there a build-up and payoff?
    func scoreEmotionalArc(readings: [SpeechEnergyAnalyzer.EnergyReading]) -> Double {
        guard readings.count >= 4 else { return 5.0 }

        let rmsValues = readings.map(\.rms)
        let avgRMS = rmsValues.reduce(0, +) / Float(rmsValues.count)

        // Find peak position
        guard let peakIdx = rmsValues.enumerated().max(by: { $0.element < $1.element })?.offset else {
            return 5.0
        }

        let peakPosition = Double(peakIdx) / Double(rmsValues.count) // 0-1
        let peakValue = rmsValues[peakIdx]

        // Classic arc: build-up (0-0.6), peak (0.3-0.8), resolution (0.7-1.0)
        let hasBuildUp = peakPosition > 0.2
        let hasPeak = peakValue > avgRMS * 1.5
        let hasResolution = peakPosition < 0.9

        if hasBuildUp && hasPeak && hasResolution { return 9.0 }
        if hasPeak && (hasBuildUp || hasResolution) { return 7.0 }
        if hasPeak { return 6.0 }

        // Flat energy
        let variance = rmsValues.map { ($0 - avgRMS) * ($0 - avgRMS) }.reduce(0, +) / Float(rmsValues.count)
        if variance < 0.0001 { return 3.0 } // Monotone

        return 5.0
    }

    /// Completeness: Does the segment start/end at natural boundaries?
    func scoreCompleteness(words: [TranscriptWord], segment: TimeRange) -> Double {
        guard !words.isEmpty else { return 3.0 }

        var score = 0.0

        // Starts at sentence boundary
        if let first = words.first {
            let firstChar = first.word.prefix(1)
            let isCapitalized = firstChar == firstChar.uppercased() && firstChar != firstChar.lowercased()
            if isCapitalized { score += 3.0 }
            // Gap between segment start and first word is small
            if first.start - segment.start < 0.5 { score += 0.5 }
        }

        // Ends at sentence boundary
        if let last = words.last {
            let endsPunctuation = last.word.hasSuffix(".") || last.word.hasSuffix("?") || last.word.hasSuffix("!")
            if endsPunctuation { score += 3.0 }
            // Tight ending
            if segment.end - last.end < 0.5 { score += 1.5 }
        }

        // Contains at least one complete sentence
        let sentenceEnders = words.filter {
            $0.word.hasSuffix(".") || $0.word.hasSuffix("?") || $0.word.hasSuffix("!")
        }
        if !sentenceEnders.isEmpty { score += 2.0 }

        return min(max(score, 0), 10)
    }

    /// Audio quality: Clean, consistent, no artifacts?
    func scoreAudioQuality(readings: [SpeechEnergyAnalyzer.EnergyReading]) -> Double {
        guard !readings.isEmpty else { return 5.0 }

        var score = 0.0

        let rmsValues = readings.map(\.rms)
        let avgRMS = rmsValues.reduce(0, +) / Float(rmsValues.count)

        // Consistent RMS (low variance)
        let variance = rmsValues.map { ($0 - avgRMS) * ($0 - avgRMS) }.reduce(0, +) / Float(rmsValues.count)
        if variance < 0.005 { score += 3.0 }
        else if variance < 0.01 { score += 2.0 }
        else if variance < 0.02 { score += 1.0 }

        // Speech ratio > 70%
        let speechRatio = Float(readings.filter(\.isSpeech).count) / Float(readings.count)
        if speechRatio > 0.7 { score += 3.0 }
        else if speechRatio > 0.5 { score += 2.0 }
        else if speechRatio > 0.3 { score += 1.0 }

        // No silence gaps > 1 second within segment
        var consecutiveSilence = 0
        var maxSilence = 0
        for reading in readings {
            if reading.isSilence { consecutiveSilence += 1 }
            else {
                maxSilence = max(maxSilence, consecutiveSilence)
                consecutiveSilence = 0
            }
        }
        maxSilence = max(maxSilence, consecutiveSilence)
        if maxSilence <= 1 { score += 2.0 }
        else if maxSilence <= 2 { score += 1.0 }

        // Peak-to-average ratio (no clipping)
        let peak = rmsValues.max() ?? 0
        let ratio = avgRMS > 0 ? peak / avgRMS : 1
        if ratio < 3.0 { score += 2.0 }
        else if ratio < 5.0 { score += 1.0 }

        return min(max(score, 0), 10)
    }
}
