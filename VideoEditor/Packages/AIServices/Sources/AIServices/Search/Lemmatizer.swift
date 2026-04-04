import Foundation
import NaturalLanguage
import EditorCore

/// Lemmatizes transcript words using Apple's NLTagger.
/// Reduces words to root form: "pricing" → "price", "talking" → "talk".
/// Uses full sentence context for accuracy.
public struct Lemmatizer: Sendable {

    public init() {}

    /// Lemmatize a single word (less accurate without context).
    public func lemmatize(word: String) -> String {
        let tagger = NLTagger(tagSchemes: [.lemma])
        let input = word.lowercased()
        tagger.string = input
        var result = input
        tagger.enumerateTags(in: input.startIndex..<input.endIndex, unit: .word, scheme: .lemma) { tag, _ in
            if let lemma = tag?.rawValue {
                result = lemma.lowercased()
            }
            return true
        }
        return result
    }

    /// Lemmatize transcript words using full sentence context.
    /// This is the preferred method — sentence context gives NLTagger
    /// the information it needs for accurate lemmatization.
    public func lemmatizeTranscript(_ words: [TranscriptWord]) -> [TranscriptWord] {
        guard !words.isEmpty else { return words }

        // Build the full sentence for context
        let fullText = words.map(\.word).joined(separator: " ")
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = fullText

        // Map word positions in the full text to their indices in the words array
        var lemmaMap: [Int: String] = [:]
        var wordIndex = 0
        var searchFrom = fullText.startIndex

        for (i, transcriptWord) in words.enumerated() {
            // Find this word in the full text
            guard let range = fullText.range(of: transcriptWord.word, range: searchFrom..<fullText.endIndex) else {
                continue
            }

            // Get the lemma at this position
            let (tag, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
            if let lemma = tag?.rawValue, !lemma.isEmpty {
                lemmaMap[i] = lemma.lowercased()
            }

            searchFrom = range.upperBound
        }

        // Apply lemmas to transcript words
        return words.enumerated().map { (i, word) in
            var updated = word
            updated.lemma = lemmaMap[i] ?? word.word.lowercased()
            return updated
        }
    }
}
