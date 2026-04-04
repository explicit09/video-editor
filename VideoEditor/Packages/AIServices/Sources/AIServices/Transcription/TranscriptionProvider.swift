import Foundation
import EditorCore

// MARK: - TranscriptionProvider protocol

/// Abstraction for transcription services. Supports swapping between
/// Deepgram (cloud), whisper.cpp (local), or any future provider.
public protocol TranscriptionProvider: Sendable {
    var name: String { get }
    func transcribe(
        audioURL: URL,
        language: String?,
        enableDiarization: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult
}

// MARK: - TranscriptionResult

public struct TranscriptionResult: Codable, Sendable {
    public let text: String
    public let words: [TranscriptWord]
    public let speakers: [SpeakerSegment]?
    public let language: String?
    public let duration: TimeInterval

    public init(text: String, words: [TranscriptWord], speakers: [SpeakerSegment]? = nil, language: String? = nil, duration: TimeInterval = 0) {
        self.text = text
        self.words = words
        self.speakers = speakers
        self.language = language
        self.duration = duration
    }
}
