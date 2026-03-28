import Foundation

// MARK: - Timeline

public struct Timeline: Codable, Sendable {
    public var tracks: [Track]
    public var markers: [Marker]

    public var duration: TimeInterval {
        tracks.flatMap(\.clips).map(\.timelineRange.end).max() ?? 0
    }

    public init(tracks: [Track] = [], markers: [Marker] = []) {
        self.tracks = tracks
        self.markers = markers
    }
}

// MARK: - Track

public struct Track: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var type: TrackType
    public var clips: [Clip]
    public var isMuted: Bool
    public var isLocked: Bool
    public var isSoloed: Bool
    public var volume: Double
    public var opacity: Double

    public init(
        id: UUID = UUID(),
        name: String = "",
        type: TrackType,
        clips: [Clip] = [],
        isMuted: Bool = false,
        isLocked: Bool = false,
        isSoloed: Bool = false,
        volume: Double = 1.0,
        opacity: Double = 1.0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.clips = clips
        self.isMuted = isMuted
        self.isLocked = isLocked
        self.isSoloed = isSoloed
        self.volume = volume
        self.opacity = opacity
    }
}

// MARK: - TrackType

public enum TrackType: String, Codable, Sendable {
    case video
    case audio
    case text
    case effect
}

// MARK: - Marker

public struct Marker: Codable, Identifiable, Sendable {
    public let id: UUID
    public var time: TimeInterval
    public var label: String
    public var color: String

    public init(
        id: UUID = UUID(),
        time: TimeInterval,
        label: String = "",
        color: String = "#FF0000"
    ) {
        self.id = id
        self.time = time
        self.label = label
        self.color = color
    }
}
