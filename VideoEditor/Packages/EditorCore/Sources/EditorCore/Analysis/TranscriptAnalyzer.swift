import Foundation

/// Analyzes a full transcript to understand content structure before any editing.
///
/// This is the foundation layer — read the entire transcript first, understand
/// what's happening, THEN use audio tools to refine boundaries.
///
/// Produces a ContentMap: a sequence of labeled sections with time ranges,
/// content summaries, and structural roles (pre-show, episode, planning, etc.)
public struct TranscriptAnalyzer: Sendable {

    public init() {}

    // MARK: - Analyze

    /// Analyze a full transcript and produce a content map.
    /// This is the transcript-first approach: understand structure from text,
    /// then refine with audio analysis.
    public func analyze(
        words: [TranscriptWord],
        totalDuration: TimeInterval
    ) -> ContentMap {
        guard !words.isEmpty else {
            return ContentMap(sections: [], totalDuration: totalDuration)
        }

        // Step 1: Chunk into ~2-minute windows with text
        let chunks = chunkTranscript(words: words, chunkDuration: 120)

        // Step 2: Classify each chunk by content type
        var classifiedChunks = chunks.map { chunk -> ClassifiedChunk in
            let contentType = classifyChunk(chunk)
            return ClassifiedChunk(chunk: chunk, contentType: contentType)
        }

        // Step 3: Find episode boundaries using structural markers
        let episodeMarkers = findEpisodeMarkers(in: words)

        // Step 4: Merge consecutive chunks of the same type into sections
        var sections = mergeSections(classifiedChunks, episodeMarkers: episodeMarkers)

        // Step 5: Label sections with summaries
        sections = labelSections(sections, words: words)

        return ContentMap(sections: sections, totalDuration: totalDuration)
    }
}

// MARK: - Content Map

public struct ContentMap: Codable, Sendable {
    public let sections: [ContentSection]
    public let totalDuration: TimeInterval

    public var episodeCount: Int {
        sections.filter { $0.role == .episode }.count
    }

    public var episodes: [ContentSection] {
        sections.filter { $0.role == .episode }
    }

    public var summary: String {
        var lines: [String] = []
        lines.append("Content Map (\(formatTime(totalDuration)) total, \(sections.count) sections, \(episodeCount) episodes)")
        lines.append("")
        for (i, section) in sections.enumerated() {
            let dur = formatTime(section.duration)
            lines.append("  \(i+1). [\(formatTime(section.startTime))-\(formatTime(section.endTime))] \(dur) — \(section.role.rawValue)")
            if let title = section.title {
                lines.append("     Title: \(title)")
            }
            lines.append("     \(section.summary)")
            if !section.keyPhrases.isEmpty {
                lines.append("     Key: \(section.keyPhrases.prefix(5).joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}

public struct ContentSection: Codable, Sendable {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let role: ContentRole
    public let title: String?
    public let summary: String
    public let keyPhrases: [String]
    public let wordCount: Int
    public let confidence: Double

    public var duration: TimeInterval { endTime - startTime }
}

public enum ContentRole: String, Codable, Sendable {
    case preShow        // Casual conversation before recording
    case episode        // Actual podcast/video content
    case planning       // Discussing what to record next
    case rehearsal      // Practicing intros, re-takes
    case offCamera      // Explicitly marked off-camera content
    case transition     // Brief gap between sections
    case silence        // Dead air
    case unknown
}

// MARK: - Internal Types

struct TranscriptChunk {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let words: [TranscriptWord]
    let text: String
}

struct ClassifiedChunk {
    let chunk: TranscriptChunk
    var contentType: ContentRole
}

struct EpisodeMarker {
    let time: TimeInterval
    let type: MarkerType
    let phrase: String
    let title: String?

    enum MarkerType {
        case introPhrase    // "Welcome to X"
        case outroPhrase    // "Thank you for watching"
        case offCamera      // "Off camera"
        case metaTalk       // Production discussion
        case topicPlanning  // "Which topics are we choosing"
    }
}

// MARK: - Chunking

extension TranscriptAnalyzer {

    /// Split transcript into time-based chunks with full text.
    func chunkTranscript(words: [TranscriptWord], chunkDuration: TimeInterval) -> [TranscriptChunk] {
        guard let firstWord = words.first, let lastWord = words.last else { return [] }

        var chunks: [TranscriptChunk] = []
        let totalStart = firstWord.start
        let totalEnd = lastWord.end
        var cursor = totalStart

        while cursor < totalEnd {
            let chunkEnd = min(cursor + chunkDuration, totalEnd)
            let chunkWords = words.filter { $0.start >= cursor && $0.start < chunkEnd }

            if !chunkWords.isEmpty {
                chunks.append(TranscriptChunk(
                    startTime: cursor,
                    endTime: chunkEnd,
                    words: chunkWords,
                    text: chunkWords.map(\.word).joined(separator: " ")
                ))
            }

            cursor = chunkEnd
        }

        return chunks
    }
}

// MARK: - Chunk Classification

extension TranscriptAnalyzer {

    /// Classify a chunk by analyzing its text content.
    func classifyChunk(_ chunk: TranscriptChunk) -> ContentRole {
        let text = chunk.text.lowercased()
        let wordCount = chunk.words.count

        // Very few words = silence/transition
        if wordCount < 5 {
            return .silence
        }

        // Check for explicit markers first
        if text.contains("off camera") || text.contains("off-camera") {
            return .offCamera
        }

        // Check for meta/production talk
        let metaScore = scoreMetaTalk(text)
        let contentScore = scoreContentTalk(text)

        // Check for intro phrases
        let hasIntro = text.contains("welcome to") ||
                       (text.contains("today") && text.contains("episode")) ||
                       text.contains("tuning in") ||
                       text.contains("hello everyone")

        // Check for planning language
        let planningScore = scorePlanningTalk(text)

        // Check for rehearsal — multiple intro attempts in one chunk
        let introCount = countOccurrences(of: "welcome to", in: text)
        if introCount >= 2 {
            return .rehearsal
        }

        // Decision logic
        if hasIntro && contentScore > metaScore {
            return .episode
        }

        if planningScore > 3 && planningScore > contentScore {
            return .planning
        }

        if metaScore > contentScore && metaScore > 3 {
            if planningScore > 2 { return .planning }
            return .preShow
        }

        if contentScore > 2 {
            return .episode
        }

        // Default: if there's substantial speech, call it preShow
        // (will be refined by merging with neighbors)
        return .preShow
    }

    /// Score how much the text sounds like production/meta discussion.
    private func scoreMetaTalk(_ text: String) -> Int {
        var score = 0

        let strongMeta = [
            "off camera", "which topics", "our intro", "our podcast",
            "the edit", "the thumbnail", "our viewers", "push content",
            "the algorithm", "our people", "caption it", "retention",
            "new format", "let's plan", "should we talk about",
            "choosing today", "reaction video", "our episode",
        ]

        let weakMeta = [
            "upload", "views", "content", "clip", "format",
            "tags", "description", "subscribe", "platform",
        ]

        for phrase in strongMeta {
            if text.contains(phrase) { score += 2 }
        }
        for word in weakMeta {
            if text.contains(word) { score += 1 }
        }

        return score
    }

    /// Score how much the text sounds like actual on-air content.
    private func scoreContentTalk(_ text: String) -> Int {
        var score = 0

        // Substantive topic words (not about the podcast itself)
        let contentIndicators = [
            "technology", "finance", "ai ", "artificial intelligence",
            "startup", "business", "company", "industry",
            "economic", "market", "strategy", "innovation",
            "software", "hardware", "data", "model",
            "research", "development", "investment", "product",
            "customer", "feedback", "user", "problem",
            "solution", "build", "launch", "scale",
        ]

        for word in contentIndicators {
            score += countOccurrences(of: word, in: text)
        }

        // Explanatory language = on-air
        let explanatory = [
            "what i think", "the reason", "for example",
            "what happens is", "the way i see it", "if you think about",
            "the thing is", "let me explain", "so basically",
        ]

        for phrase in explanatory {
            if text.contains(phrase) { score += 2 }
        }

        return score
    }

    /// Score planning/production-planning language.
    private func scorePlanningTalk(_ text: String) -> Int {
        var score = 0

        let planningPhrases = [
            "which topics", "what should we", "let's do",
            "next episode", "new format", "twenty minute",
            "what could we talk about", "how would we do",
            "let's try", "choosing today", "shall we",
            "we need to plan", "for today",
        ]

        for phrase in planningPhrases {
            if text.contains(phrase) { score += 2 }
        }

        return score
    }

    private func countOccurrences(of substring: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: substring, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }
}

// MARK: - Episode Markers

extension TranscriptAnalyzer {

    /// Find specific structural markers in the transcript.
    func findEpisodeMarkers(in words: [TranscriptWord]) -> [EpisodeMarker] {
        var markers: [EpisodeMarker] = []

        for (i, word) in words.enumerated() {
            let lowered = word.word.lowercased().trimmingCharacters(in: .punctuationCharacters)

            // "Welcome to X"
            if lowered == "welcome" && i + 2 < words.count {
                let next = words[i + 1].word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                if next == "to" {
                    let titleWords = words[(i+2)..<min(i+6, words.count)]
                        .prefix(while: { !$0.word.hasSuffix(",") && !$0.word.hasSuffix(".") })
                        .map { $0.word.trimmingCharacters(in: .punctuationCharacters) }
                    let title = titleWords.joined(separator: " ")

                    markers.append(EpisodeMarker(
                        time: word.start,
                        type: .introPhrase,
                        phrase: "Welcome to \(title)",
                        title: title.isEmpty ? nil : title
                    ))
                }
            }

            // "off camera"
            if lowered == "off" && i + 1 < words.count {
                let next = words[i + 1].word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                if next == "camera" {
                    markers.append(EpisodeMarker(
                        time: word.start,
                        type: .offCamera,
                        phrase: "off camera",
                        title: nil
                    ))
                }
            }

            // "which topics"
            if lowered == "which" && i + 1 < words.count {
                let next = words[i + 1].word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                if next == "topics" {
                    markers.append(EpisodeMarker(
                        time: word.start,
                        type: .topicPlanning,
                        phrase: "which topics",
                        title: nil
                    ))
                }
            }
        }

        return markers
    }
}

// MARK: - Section Merging

extension TranscriptAnalyzer {

    /// Build sections using intros as anchors.
    /// Nothing is an episode until an intro phrase appears.
    /// Episodes end at off-camera markers, planning markers, or the next intro.
    func mergeSections(_ chunks: [ClassifiedChunk], episodeMarkers: [EpisodeMarker]) -> [ContentSection] {
        guard !chunks.isEmpty else { return [] }

        let totalStart = chunks.first!.chunk.startTime
        let totalEnd = chunks.last!.chunk.endTime

        // Find real intro markers (deduplicate re-takes: if multiple intros within 5 min, keep the last)
        let introMarkers = episodeMarkers.filter { $0.type == .introPhrase }
        let dedupedIntros = deduplicateIntros(introMarkers)

        // Find end markers
        let endMarkers = episodeMarkers.filter { $0.type == .offCamera || $0.type == .topicPlanning }

        // Build sections from anchors
        var sections: [ContentSection] = []

        // Sort all markers by time
        struct Anchor: Comparable {
            let time: TimeInterval
            let role: ContentRole
            let title: String?
            static func < (lhs: Anchor, rhs: Anchor) -> Bool { lhs.time < rhs.time }
        }

        var anchors: [Anchor] = []

        // Everything before first intro is preShow
        if let firstIntro = dedupedIntros.first, firstIntro.time > totalStart + 30 {
            anchors.append(Anchor(time: totalStart, role: .preShow, title: nil))
        }

        // Each intro starts an episode
        for intro in dedupedIntros {
            anchors.append(Anchor(time: intro.time, role: .episode, title: intro.title))
        }

        // Each end marker starts off-camera or planning
        for end in endMarkers {
            // Only add if it's not inside an episode that started after it
            let isAfterAnIntro = dedupedIntros.contains { $0.time < end.time }
            if isAfterAnIntro {
                let role: ContentRole = end.type == .offCamera ? .offCamera : .planning
                anchors.append(Anchor(time: end.time, role: role, title: nil))
            }
        }

        anchors.sort()

        // Remove anchors that would create tiny sections or conflict
        var filtered: [Anchor] = []
        for anchor in anchors {
            if let last = filtered.last {
                // Skip if too close to previous and same role
                if anchor.time - last.time < 30 && anchor.role == last.role {
                    continue
                }
                // If an end marker comes right before an intro (<60s), skip the end marker
                if (last.role == .offCamera || last.role == .planning) && anchor.role == .episode && anchor.time - last.time < 60 {
                    filtered[filtered.count - 1] = anchor
                    continue
                }
            }
            filtered.append(anchor)
        }

        // Build sections from filtered anchors
        for (i, anchor) in filtered.enumerated() {
            let sectionEnd: TimeInterval
            if i + 1 < filtered.count {
                sectionEnd = filtered[i + 1].time
            } else {
                sectionEnd = totalEnd
            }

            // Count words in this section
            let sectionWords = chunks.flatMap(\.chunk.words).filter {
                $0.start >= anchor.time && $0.end <= sectionEnd
            }

            // For non-episode sections between episodes, classify as planning
            var role = anchor.role
            if role == .preShow {
                // Check if there's an episode before this — if so, it's planning, not preShow
                let hasEpisodeBefore = filtered[0..<i].contains { $0.role == .episode }
                if hasEpisodeBefore { role = .planning }
            }

            sections.append(ContentSection(
                startTime: anchor.time,
                endTime: sectionEnd,
                role: role,
                title: anchor.title,
                summary: "",
                keyPhrases: [],
                wordCount: sectionWords.count,
                confidence: role == .episode ? 0.85 : 0.7
            ))
        }

        // If no intros found at all, return one big preShow section
        if sections.isEmpty {
            let allWords = chunks.flatMap(\.chunk.words)
            sections.append(ContentSection(
                startTime: totalStart,
                endTime: totalEnd,
                role: .preShow,
                title: nil,
                summary: "",
                keyPhrases: [],
                wordCount: allWords.count,
                confidence: 0.5
            ))
        }

        return sections
    }

    /// Deduplicate intro markers: if multiple "welcome to X" within 5 minutes,
    /// they're re-takes — keep the last one (usually the best take).
    private func deduplicateIntros(_ intros: [EpisodeMarker]) -> [EpisodeMarker] {
        guard !intros.isEmpty else { return [] }

        var groups: [[EpisodeMarker]] = [[intros[0]]]

        for i in 1..<intros.count {
            if intros[i].time - (groups.last?.last?.time ?? 0) < 300 { // Within 5 min
                groups[groups.count - 1].append(intros[i])
            } else {
                groups.append([intros[i]])
            }
        }

        // From each group, keep the last one (best take)
        return groups.compactMap(\.last)
    }
}

// MARK: - Section Labeling

extension TranscriptAnalyzer {

    /// Add summaries and key phrases to sections.
    func labelSections(_ sections: [ContentSection], words: [TranscriptWord]) -> [ContentSection] {
        sections.map { section in
            let sectionWords = words.filter { $0.start >= section.startTime && $0.end <= section.endTime }
            let keyPhrases = extractKeyPhrases(from: sectionWords)
            let summary = generateSummary(role: section.role, words: sectionWords, keyPhrases: keyPhrases)

            return ContentSection(
                startTime: section.startTime,
                endTime: section.endTime,
                role: section.role,
                title: section.title,
                summary: summary,
                keyPhrases: keyPhrases,
                wordCount: section.wordCount,
                confidence: section.confidence
            )
        }
    }

    /// Extract key phrases (most frequent non-stopword terms).
    private func extractKeyPhrases(from words: [TranscriptWord], count: Int = 8) -> [String] {
        let stopwords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been",
            "have", "has", "had", "do", "does", "did", "will", "would",
            "could", "should", "may", "might", "can", "shall",
            "i", "you", "he", "she", "it", "we", "they", "me", "him",
            "her", "us", "them", "my", "your", "his", "its", "our", "their",
            "this", "that", "these", "those", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "and", "or", "but", "not", "so",
            "if", "then", "than", "just", "also", "very", "really",
            "like", "yeah", "mhmm", "oh", "okay", "right", "um", "uh",
            "know", "think", "going", "thing", "stuff", "get", "got",
        ]

        var freq: [String: Int] = [:]
        for word in words {
            let clean = (word.lemma ?? word.word).lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            guard clean.count > 2, !stopwords.contains(clean) else { continue }
            freq[clean, default: 0] += 1
        }

        return freq.sorted { $0.value > $1.value }.prefix(count).map(\.key)
    }

    /// Generate a brief summary based on role and key phrases.
    private func generateSummary(role: ContentRole, words: [TranscriptWord], keyPhrases: [String]) -> String {
        let wordCount = words.count
        let durationSec = (words.last?.end ?? 0) - (words.first?.start ?? 0)
        let durationMin = Int(durationSec) / 60

        switch role {
        case .episode:
            let topics = keyPhrases.prefix(4).joined(separator: ", ")
            return "Episode content (\(wordCount) words, ~\(durationMin) min). Topics: \(topics)"

        case .preShow:
            let topics = keyPhrases.prefix(3).joined(separator: ", ")
            return "Pre-show conversation (\(wordCount) words). Discussing: \(topics)"

        case .planning:
            return "Production planning (\(wordCount) words). Discussing format, topics, next steps."

        case .rehearsal:
            return "Rehearsal/re-takes (\(wordCount) words). Multiple intro attempts."

        case .offCamera:
            let topics = keyPhrases.prefix(3).joined(separator: ", ")
            return "Off-camera discussion (\(wordCount) words). Talking about: \(topics)"

        case .transition:
            return "Brief transition (\(wordCount) words)."

        case .silence:
            return "Silence/minimal speech."

        case .unknown:
            return "Unclassified content (\(wordCount) words)."
        }
    }
}
