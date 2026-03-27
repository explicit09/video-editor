import Foundation

// MARK: - Project

public struct Project: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var settings: ProjectSettings
    public var timeline: Timeline
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        settings: ProjectSettings = .default,
        timeline: Timeline = Timeline(),
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.settings = settings
        self.timeline = timeline
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

// MARK: - ProjectSettings

public struct ProjectSettings: Codable, Sendable {
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var sampleRate: Int
    public var backgroundColorHex: String

    public init(
        width: Int = 1920,
        height: Int = 1080,
        frameRate: Double = 30.0,
        sampleRate: Int = 48000,
        backgroundColorHex: String = "#000000"
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.sampleRate = sampleRate
        self.backgroundColorHex = backgroundColorHex
    }

    public static let `default` = ProjectSettings()
}
