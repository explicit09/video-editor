import Foundation
import EditorCore

/// Matches B-roll clips to transcript content based on semantic keywords.
/// Analyzes transcript for topics and finds matching assets from the library.
public struct BRollMatcher: Sendable {

    public struct BRollSuggestion: Sendable {
        /// Asset to use as B-roll
        public let assetID: UUID
        public let assetName: String
        /// Where in the timeline to place the B-roll
        public let startTime: TimeInterval
        /// How long the B-roll should cover
        public let duration: TimeInterval
        /// Why this was matched
        public let reason: String
        /// Match confidence (0-1)
        public let confidence: Double
    }

    public init() {}

    /// Analyze transcript and suggest B-roll placements from available assets.
    /// Uses keyword matching between transcript words and asset names/tags/scene labels.
    public func suggest(
        transcript: [TranscriptWord],
        assets: [MediaAsset],
        timeline: Timeline,
        maxSuggestions: Int = 5
    ) -> [BRollSuggestion] {
        guard !transcript.isEmpty, !assets.isEmpty else { return [] }

        // Build keyword index from assets (name, tags, scene descriptions)
        let assetKeywords = buildAssetKeywordIndex(assets)

        // Find transcript segments that mention topics matching available B-roll
        let segments = groupTranscriptIntoTopicSegments(transcript)
        var suggestions: [BRollSuggestion] = []

        for segment in segments {
            let segmentWords = Set(segment.keywords)

            // Score each asset against this segment
            var bestMatch: (assetID: UUID, name: String, score: Double, matchedKeyword: String)?

            for (assetID, keywords) in assetKeywords {
                let asset = assets.first(where: { $0.id == assetID })
                let assetName = asset?.name ?? ""

                for keyword in keywords {
                    if segmentWords.contains(keyword) {
                        let score = 1.0
                        if bestMatch == nil || score > bestMatch!.score {
                            bestMatch = (assetID, assetName, score, keyword)
                        }
                    }
                }
            }

            if let match = bestMatch {
                // Don't suggest B-roll for assets already on the timeline
                let usedAssetIDs = Set(timeline.tracks.flatMap(\.clips).map(\.assetID))
                guard !usedAssetIDs.contains(match.assetID) || assets.filter({ $0.type == .video }).count > 1 else { continue }

                suggestions.append(BRollSuggestion(
                    assetID: match.assetID,
                    assetName: match.name,
                    startTime: segment.startTime,
                    duration: min(segment.duration, 5.0), // Max 5s per B-roll
                    reason: "Matches '\(match.matchedKeyword)' mentioned at \(String(format: "%.0f", segment.startTime))s",
                    confidence: match.score
                ))
            }

            if suggestions.count >= maxSuggestions { break }
        }

        return suggestions
    }

    // MARK: - Keyword Extraction

    private func buildAssetKeywordIndex(_ assets: [MediaAsset]) -> [UUID: Set<String>] {
        var index: [UUID: Set<String>] = [:]

        for asset in assets where asset.type == .video || asset.type == .image {
            var keywords = Set<String>()

            // Extract keywords from asset name
            let nameWords = asset.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
            keywords.formUnion(nameWords)

            // Extract from scene descriptions if available
            if let scenes = asset.analysis?.sceneDescriptions {
                for scene in scenes {
                    let sceneWords = scene.description.lowercased()
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { $0.count > 2 }
                    keywords.formUnion(sceneWords)
                    if let label = scene.label {
                        keywords.insert(label.lowercased())
                    }
                }
            }

            if !keywords.isEmpty {
                index[asset.id] = keywords
            }
        }

        return index
    }

    private struct TopicSegment {
        let startTime: TimeInterval
        let duration: TimeInterval
        let keywords: [String]
    }

    private func groupTranscriptIntoTopicSegments(_ words: [TranscriptWord]) -> [TopicSegment] {
        let chunkSize = 15
        var segments: [TopicSegment] = []

        for start in stride(from: 0, to: words.count, by: chunkSize) {
            let end = min(start + chunkSize, words.count)
            let chunk = Array(words[start..<end])

            let startTime = chunk.first?.start ?? 0
            let endTime = chunk.last?.end ?? 0

            // Extract meaningful keywords (nouns, topics — simplified as words > 3 chars)
            let keywords = chunk.map { ($0.lemma ?? $0.word).lowercased() }
                .filter { $0.count > 3 }

            segments.append(TopicSegment(
                startTime: startTime,
                duration: endTime - startTime,
                keywords: keywords
            ))
        }

        return segments
    }
}
