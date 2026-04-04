import Foundation
import EditorCore

/// Searches transcript data across all assets using lemma-based matching.
/// Supports single-word and phrase search.
public struct TranscriptSearchEngine: Sendable {

    private let lemmatizer = Lemmatizer()

    public init() {}

    /// Search all assets' transcripts. Searches ALL assets before ranking.
    public func search(
        query: String,
        assets: [MediaAsset],
        maxResults: Int = 20,
        contextWords: Int = 8
    ) -> [SearchResult] {
        let queryLemmas = lemmatizeQuery(query)
        guard !queryLemmas.isEmpty else { return [] }

        var allResults: [SearchResult] = []

        for asset in assets {
            guard let words = asset.analysis?.transcript, !words.isEmpty else { continue }

            let matches = queryLemmas.count > 1
                ? searchPhrase(queryLemmas: queryLemmas, words: words, assetID: asset.id, assetName: asset.name, contextWords: contextWords)
                : searchSingleWord(queryLemma: queryLemmas[0], words: words, assetID: asset.id, assetName: asset.name, contextWords: contextWords)

            allResults.append(contentsOf: matches)
        }

        // Global ranking AFTER searching all assets
        allResults.sort { $0.relevance > $1.relevance }
        return Array(allResults.prefix(maxResults))
    }

    /// Search within a single asset's transcript.
    public func searchAsset(
        query: String,
        asset: MediaAsset,
        contextWords: Int = 8
    ) -> [SearchResult] {
        let queryLemmas = lemmatizeQuery(query)
        guard !queryLemmas.isEmpty,
              let words = asset.analysis?.transcript, !words.isEmpty else { return [] }

        return queryLemmas.count > 1
            ? searchPhrase(queryLemmas: queryLemmas, words: words, assetID: asset.id, assetName: asset.name, contextWords: contextWords)
            : searchSingleWord(queryLemma: queryLemmas[0], words: words, assetID: asset.id, assetName: asset.name, contextWords: contextWords)
    }

    // MARK: - Single word search

    private func searchSingleWord(
        queryLemma: String,
        words: [TranscriptWord],
        assetID: UUID,
        assetName: String,
        contextWords: Int
    ) -> [SearchResult] {
        var results: [SearchResult] = []

        for (i, word) in words.enumerated() {
            let wordLemma = (word.lemma ?? word.word).lowercased()
            guard wordLemma == queryLemma else { continue }

            let context = buildContext(words: words, centerIndex: i, contextWords: contextWords)
            results.append(SearchResult(
                assetID: assetID,
                assetName: assetName,
                matchTime: word.start,
                matchWord: word.word,
                contextText: context.text,
                contextStartTime: context.startTime,
                contextEndTime: context.endTime,
                relevance: 1.0
            ))
        }
        return results
    }

    // MARK: - Phrase search

    /// Matches consecutive transcript words against the full query phrase.
    /// "pricing model" matches only when "pricing" and "model" appear consecutively.
    private func searchPhrase(
        queryLemmas: [String],
        words: [TranscriptWord],
        assetID: UUID,
        assetName: String,
        contextWords: Int
    ) -> [SearchResult] {
        var results: [SearchResult] = []
        let phraseLen = queryLemmas.count

        guard words.count >= phraseLen else { return results }

        for i in 0...(words.count - phraseLen) {
            var matched = true
            for j in 0..<phraseLen {
                let wordLemma = (words[i + j].lemma ?? words[i + j].word).lowercased()
                if wordLemma != queryLemmas[j] {
                    matched = false
                    break
                }
            }

            guard matched else { continue }

            let phraseStart = words[i].start
            let phraseEnd = words[i + phraseLen - 1].end
            let matchedWords = words[i..<(i + phraseLen)].map(\.word).joined(separator: " ")

            let context = buildContext(words: words, centerIndex: i, contextWords: contextWords)
            results.append(SearchResult(
                assetID: assetID,
                assetName: assetName,
                matchTime: phraseStart,
                matchWord: matchedWords,
                contextText: context.text,
                contextStartTime: context.startTime,
                contextEndTime: context.endTime,
                relevance: 1.0
            ))
        }
        return results
    }

    // MARK: - Context window

    private struct ContextWindow {
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    private func buildContext(words: [TranscriptWord], centerIndex: Int, contextWords: Int) -> ContextWindow {
        let start = max(0, centerIndex - contextWords)
        let end = min(words.count, centerIndex + contextWords + 1)
        let slice = words[start..<end]
        return ContextWindow(
            text: slice.map(\.word).joined(separator: " "),
            startTime: slice.first?.start ?? 0,
            endTime: slice.last?.end ?? 0
        )
    }

    // MARK: - Query lemmatization

    private func lemmatizeQuery(_ query: String) -> [String] {
        query.lowercased()
            .split(separator: " ")
            .map { lemmatizer.lemmatize(word: String($0)) }
    }
}

// MARK: - SearchResult

public struct SearchResult: Codable, Sendable, Identifiable {
    public var id: String { "\(assetID.uuidString)_\(matchTime)" }
    public let assetID: UUID
    public let assetName: String
    public let matchTime: TimeInterval
    public let matchWord: String
    public let contextText: String
    public let contextStartTime: TimeInterval
    public let contextEndTime: TimeInterval
    public let relevance: Double

    public var formattedTime: String {
        let mins = Int(matchTime) / 60
        let secs = Int(matchTime) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
