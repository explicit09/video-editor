import Foundation
import EditorCore

/// Searches transcript data across all assets for matching text.
/// Pure local, zero cost. Keyword matching with context windows.
public struct TranscriptSearchEngine: Sendable {

    public init() {}

    /// Search all assets' transcripts for a query string.
    public func search(
        query: String,
        assets: [MediaAsset],
        maxResults: Int = 20,
        contextWords: Int = 8
    ) -> [SearchResult] {
        let queryLower = query.lowercased()
        let queryTerms = queryLower.split(separator: " ").map(String.init)
        guard !queryTerms.isEmpty else { return [] }

        var results: [SearchResult] = []

        for asset in assets {
            guard let words = asset.analysis?.transcript, !words.isEmpty else { continue }

            let matches = searchWords(
                queryTerms: queryTerms,
                words: words,
                assetID: asset.id,
                assetName: asset.name,
                contextWords: contextWords
            )
            results.append(contentsOf: matches)

            if results.count >= maxResults { break }
        }

        // Sort by relevance (exact matches first, then partial)
        results.sort { $0.relevance > $1.relevance }
        return Array(results.prefix(maxResults))
    }

    /// Search within a single asset's transcript.
    public func searchAsset(
        query: String,
        asset: MediaAsset,
        contextWords: Int = 8
    ) -> [SearchResult] {
        let queryTerms = query.lowercased().split(separator: " ").map(String.init)
        guard !queryTerms.isEmpty,
              let words = asset.analysis?.transcript, !words.isEmpty else { return [] }

        return searchWords(
            queryTerms: queryTerms,
            words: words,
            assetID: asset.id,
            assetName: asset.name,
            contextWords: contextWords
        )
    }

    // MARK: - Core search

    private func searchWords(
        queryTerms: [String],
        words: [TranscriptWord],
        assetID: UUID,
        assetName: String,
        contextWords: Int
    ) -> [SearchResult] {
        var results: [SearchResult] = []

        for (i, word) in words.enumerated() {
            let wordLower = word.word.lowercased()
                .trimmingCharacters(in: .punctuationCharacters)

            // Check if this word matches any query term
            var matchScore: Double = 0
            for term in queryTerms {
                if wordLower == term {
                    matchScore += 1.0  // Exact match
                } else if wordLower.range(of: term) != nil {
                    matchScore += 0.5  // Partial/substring match
                }
            }

            guard matchScore > 0 else { continue }

            // Build context window
            let contextStart = max(0, i - contextWords)
            let contextEnd = min(words.count, i + contextWords + 1)
            let contextSlice = words[contextStart..<contextEnd]
            let contextText = contextSlice.map(\.word).joined(separator: " ")

            // Time range of the context window
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
                relevance: matchScore / Double(queryTerms.count)
            ))
        }

        return results
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
