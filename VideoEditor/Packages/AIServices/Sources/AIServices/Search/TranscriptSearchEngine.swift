import Foundation
import EditorCore

/// Searches transcript data across all assets using lemma-based matching.
/// Lemmas are computed at transcription time via NLTagger.
/// "price" matches "pricing" because both lemmatize to "price".
public struct TranscriptSearchEngine: Sendable {

    private let lemmatizer = Lemmatizer()

    public init() {}

    /// Search all assets' transcripts for a query string.
    public func search(
        query: String,
        assets: [MediaAsset],
        maxResults: Int = 20,
        contextWords: Int = 8
    ) -> [SearchResult] {
        let queryLemmas = lemmatizeQuery(query)
        guard !queryLemmas.isEmpty else { return [] }

        var results: [SearchResult] = []

        for asset in assets {
            guard let words = asset.analysis?.transcript, !words.isEmpty else { continue }

            let matches = searchWords(
                queryLemmas: queryLemmas,
                words: words,
                assetID: asset.id,
                assetName: asset.name,
                contextWords: contextWords
            )
            results.append(contentsOf: matches)

            if results.count >= maxResults { break }
        }

        results.sort { $0.relevance > $1.relevance }
        return Array(results.prefix(maxResults))
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

        return searchWords(
            queryLemmas: queryLemmas,
            words: words,
            assetID: asset.id,
            assetName: asset.name,
            contextWords: contextWords
        )
    }

    // MARK: - Core search

    private func searchWords(
        queryLemmas: [String],
        words: [TranscriptWord],
        assetID: UUID,
        assetName: String,
        contextWords: Int
    ) -> [SearchResult] {
        var results: [SearchResult] = []

        for (i, word) in words.enumerated() {
            let wordLemma = (word.lemma ?? word.word).lowercased()

            // Match against query lemmas (all lowercased)
            var matchScore: Double = 0
            for queryLemma in queryLemmas {
                if wordLemma == queryLemma {
                    matchScore += 1.0
                }
            }

            guard matchScore > 0 else { continue }

            // Build context window
            let contextStart = max(0, i - contextWords)
            let contextEnd = min(words.count, i + contextWords + 1)
            let contextSlice = words[contextStart..<contextEnd]
            let contextText = contextSlice.map(\.word).joined(separator: " ")

            let startTime = contextSlice.first?.start ?? word.start
            let endTime = contextSlice.last?.end ?? word.end

            results.append(SearchResult(
                assetID: assetID,
                assetName: assetName,
                matchTime: word.start,
                matchWord: word.word,
                contextText: contextText,
                contextStartTime: startTime,
                contextEndTime: endTime,
                relevance: matchScore / Double(queryLemmas.count)
            ))
        }

        return results
    }

    // MARK: - Query lemmatization

    /// Lemmatize the search query terms.
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
