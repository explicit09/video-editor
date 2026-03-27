import Foundation

// MARK: - Clip (Reference + Instructions)

public struct Clip: Codable, Identifiable, Sendable {
    public let id: UUID
    public var assetID: UUID
    public var timelineRange: TimeRange
    public var sourceRange: TimeRange
    public var transform: Transform2D
    public var opacity: Double
    public var volume: Double
    public var effects: [EffectInstance]
    public var keyframes: KeyframeStore
    public var metadata: ClipMetadata

    public init(
        id: UUID = UUID(),
        assetID: UUID,
        timelineRange: TimeRange,
        sourceRange: TimeRange,
        transform: Transform2D = .identity,
        opacity: Double = 1.0,
        volume: Double = 1.0,
        effects: [EffectInstance] = [],
        keyframes: KeyframeStore = KeyframeStore(),
        metadata: ClipMetadata = ClipMetadata()
    ) {
        self.id = id
        self.assetID = assetID
        self.timelineRange = timelineRange
        self.sourceRange = sourceRange
        self.transform = transform
        self.opacity = opacity
        self.volume = volume
        self.effects = effects
        self.keyframes = keyframes
        self.metadata = metadata
    }
}

// MARK: - TimeRange

public struct TimeRange: Codable, Sendable, Equatable {
    public var start: TimeInterval
    public var end: TimeInterval

    public var duration: TimeInterval { end - start }

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    public init(start: TimeInterval, duration: TimeInterval) {
        self.start = start
        self.end = start + duration
    }

    public func contains(_ time: TimeInterval) -> Bool {
        time >= start && time < end
    }

    public func overlaps(_ other: TimeRange) -> Bool {
        start < other.end && end > other.start
    }
}

// MARK: - Transform2D

public struct Transform2D: Codable, Sendable, Equatable {
    public var positionX: Double
    public var positionY: Double
    public var scaleX: Double
    public var scaleY: Double
    public var rotation: Double
    public var anchorX: Double
    public var anchorY: Double

    public init(
        positionX: Double = 0,
        positionY: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        rotation: Double = 0,
        anchorX: Double = 0.5,
        anchorY: Double = 0.5
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotation = rotation
        self.anchorX = anchorX
        self.anchorY = anchorY
    }

    public static let identity = Transform2D()
}

// MARK: - ClipMetadata (AI-enrichable)

public struct ClipMetadata: Codable, Sendable {
    public var label: String?
    public var tags: [String]
    public var transcriptSegment: TranscriptSegment?
    public var sceneType: String?

    public init(
        label: String? = nil,
        tags: [String] = [],
        transcriptSegment: TranscriptSegment? = nil,
        sceneType: String? = nil
    ) {
        self.label = label
        self.tags = tags
        self.transcriptSegment = transcriptSegment
        self.sceneType = sceneType
    }
}

// MARK: - TranscriptSegment

public struct TranscriptSegment: Codable, Sendable {
    public var text: String
    public var words: [TranscriptWord]

    public init(text: String, words: [TranscriptWord] = []) {
        self.text = text
        self.words = words
    }
}

public struct TranscriptWord: Codable, Sendable {
    public var word: String
    public var lemma: String?
    public var start: TimeInterval
    public var end: TimeInterval
    public var confidence: Double

    public init(word: String, lemma: String? = nil, start: TimeInterval, end: TimeInterval, confidence: Double = 1.0) {
        self.word = word
        self.lemma = lemma
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

// MARK: - Effect & Keyframe stubs

public struct EffectInstance: Codable, Sendable {
    public let id: UUID
    public var type: String
    public var parameters: [String: Double]
    public var isEnabled: Bool

    public init(id: UUID = UUID(), type: String, parameters: [String: Double] = [:], isEnabled: Bool = true) {
        self.id = id
        self.type = type
        self.parameters = parameters
        self.isEnabled = isEnabled
    }
}

public struct KeyframeStore: Codable, Sendable {
    public var tracks: [String: [Keyframe]]

    public init(tracks: [String: [Keyframe]] = [:]) {
        self.tracks = tracks
    }
}

public struct Keyframe: Codable, Sendable {
    public var time: TimeInterval
    public var value: Double
    public var interpolation: KeyframeInterpolation

    public init(time: TimeInterval, value: Double, interpolation: KeyframeInterpolation = .linear) {
        self.time = time
        self.value = value
        self.interpolation = interpolation
    }
}

public enum KeyframeInterpolation: String, Codable, Sendable {
    case linear
    case hold
    case easeIn
    case easeOut
    case easeInOut
}
