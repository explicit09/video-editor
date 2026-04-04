import Foundation

// MARK: - MediaAsset (Immutable source reference)

public struct MediaAsset: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var sourceURL: URL
    public var proxyURL: URL?
    public var thumbnailURL: URL?
    public var type: MediaType
    public var duration: TimeInterval
    public var width: Int?
    public var height: Int?
    public var codec: String?
    public var fileSize: Int64
    public var importedAt: Date
    public var analysis: MediaAnalysis?
    /// Whether the source file has an audio track. Probed once at import time.
    public var hasAudioTrack: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        sourceURL: URL,
        proxyURL: URL? = nil,
        thumbnailURL: URL? = nil,
        type: MediaType,
        duration: TimeInterval = 0,
        width: Int? = nil,
        height: Int? = nil,
        codec: String? = nil,
        fileSize: Int64 = 0,
        importedAt: Date = Date(),
        analysis: MediaAnalysis? = nil,
        hasAudioTrack: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.proxyURL = proxyURL
        self.thumbnailURL = thumbnailURL
        self.type = type
        self.duration = duration
        self.width = width
        self.height = height
        self.codec = codec
        self.fileSize = fileSize
        self.importedAt = importedAt
        self.analysis = analysis
        self.hasAudioTrack = hasAudioTrack
    }
}

// MARK: - MediaType

public enum MediaType: String, Codable, Sendable {
    case video
    case audio
    case image
}

// MARK: - MediaAnalysis (AI-enriched, populated by background analysis)

public struct MediaAnalysis: Codable, Sendable {
    public var transcript: [TranscriptWord]?
    public var shotBoundaries: [TimeInterval]?
    public var silenceRanges: [TimeRange]?
    public var speakerSegments: [SpeakerSegment]?
    public var sceneDescriptions: [SceneSegment]?
    public var loudnessProfile: [Float]?

    public init(
        transcript: [TranscriptWord]? = nil,
        shotBoundaries: [TimeInterval]? = nil,
        silenceRanges: [TimeRange]? = nil,
        speakerSegments: [SpeakerSegment]? = nil,
        sceneDescriptions: [SceneSegment]? = nil,
        loudnessProfile: [Float]? = nil
    ) {
        self.transcript = transcript
        self.shotBoundaries = shotBoundaries
        self.silenceRanges = silenceRanges
        self.speakerSegments = speakerSegments
        self.sceneDescriptions = sceneDescriptions
        self.loudnessProfile = loudnessProfile
    }
}

public struct SpeakerSegment: Codable, Sendable {
    public var speakerID: String
    public var range: TimeRange

    public init(speakerID: String, range: TimeRange) {
        self.speakerID = speakerID
        self.range = range
    }
}

public struct SceneSegment: Codable, Sendable {
    public var range: TimeRange
    public var description: String
    public var label: String?

    public init(range: TimeRange, description: String, label: String? = nil) {
        self.range = range
        self.description = description
        self.label = label
    }
}
