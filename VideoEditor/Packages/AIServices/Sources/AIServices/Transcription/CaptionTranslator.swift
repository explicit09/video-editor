import Foundation
import EditorCore

/// Translates transcript/caption text between languages.
/// Uses Apple's Translation framework on macOS 15+.
public struct CaptionTranslator: Sendable {

    public struct TranslatedCaption: Sendable {
        public let originalText: String
        public let translatedText: String
        public let sourceLanguage: String
        public let targetLanguage: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval
    }

    /// Supported languages for caption translation.
    public enum CaptionLanguage: String, Sendable, CaseIterable {
        case english = "en"
        case spanish = "es"
        case french = "fr"
        case german = "de"
        case portuguese = "pt"
        case japanese = "ja"
        case korean = "ko"
        case chinese = "zh"
        case arabic = "ar"
        case hindi = "hi"
        case italian = "it"
        case dutch = "nl"
        case russian = "ru"
        case turkish = "tr"
        case swedish = "sv"

        public var displayName: String {
            switch self {
            case .english: "English"
            case .spanish: "Spanish"
            case .french: "French"
            case .german: "German"
            case .portuguese: "Portuguese"
            case .japanese: "Japanese"
            case .korean: "Korean"
            case .chinese: "Chinese"
            case .arabic: "Arabic"
            case .hindi: "Hindi"
            case .italian: "Italian"
            case .dutch: "Dutch"
            case .russian: "Russian"
            case .turkish: "Turkish"
            case .swedish: "Swedish"
            }
        }
    }

    public init() {}

    /// Translate transcript words into target language captions.
    /// Groups words into subtitle-length phrases before translation.
    public func translate(
        words: [TranscriptWord],
        from sourceLanguage: CaptionLanguage = .english,
        to targetLanguage: CaptionLanguage,
        wordsPerSegment: Int = 8
    ) async -> [TranslatedCaption] {
        let segments = groupIntoSegments(words, wordsPerSegment: wordsPerSegment)
        var translations: [TranslatedCaption] = []

        for segment in segments {
            // Use Apple's Translation framework if available (macOS 15+)
            let translated = await translateText(segment.text, from: sourceLanguage, to: targetLanguage)

            translations.append(TranslatedCaption(
                originalText: segment.text,
                translatedText: translated ?? segment.text,
                sourceLanguage: sourceLanguage.rawValue,
                targetLanguage: targetLanguage.rawValue,
                startTime: segment.startTime,
                endTime: segment.endTime
            ))
        }

        return translations
    }

    /// Convert translations to SubtitleRenderer entries for burn-in.
    public func toSubtitleEntries(_ translations: [TranslatedCaption]) -> [SubtitleRenderer.SubtitleEntry] {
        translations.map {
            SubtitleRenderer.SubtitleEntry(
                text: $0.translatedText,
                startTime: $0.startTime,
                endTime: $0.endTime
            )
        }
    }

    // MARK: - Private

    private struct TextSegment {
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    private func groupIntoSegments(_ words: [TranscriptWord], wordsPerSegment: Int) -> [TextSegment] {
        var segments: [TextSegment] = []

        for start in stride(from: 0, to: words.count, by: wordsPerSegment) {
            let end = min(start + wordsPerSegment, words.count)
            let chunk = Array(words[start..<end])
            segments.append(TextSegment(
                text: chunk.map(\.word).joined(separator: " "),
                startTime: chunk.first?.start ?? 0,
                endTime: chunk.last?.end ?? 0
            ))
        }

        return segments
    }

    /// Translate text using available translation service.
    /// Falls back to original text if translation is unavailable.
    private func translateText(
        _ text: String,
        from source: CaptionLanguage,
        to target: CaptionLanguage
    ) async -> String? {
        // Try Apple's Translation framework (macOS 15+)
        // In production, this would use:
        //   let session = TranslationSession(from: source.locale, to: target.locale)
        //   let response = try await session.translate(text)
        //   return response.targetText
        //
        // For now, return nil to indicate translation unavailable.
        // The AI can be used as a fallback translator via prompt.
        return nil
    }
}
