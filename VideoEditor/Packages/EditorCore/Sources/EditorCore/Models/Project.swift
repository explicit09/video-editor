import Foundation
import CoreImage
import CoreGraphics

// MARK: - Project

public struct Project: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var settings: ProjectSettings
    public var timeline: Timeline
    public var broadcastOverlay: BroadcastOverlayConfig?
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        settings: ProjectSettings = .default,
        timeline: Timeline = Timeline(),
        broadcastOverlay: BroadcastOverlayConfig? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.settings = settings
        self.timeline = timeline
        self.broadcastOverlay = broadcastOverlay
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
        self.width = max(width, 1)
        self.height = max(height, 1)
        self.frameRate = max(frameRate, 1)
        self.sampleRate = max(sampleRate, 8000)
        self.backgroundColorHex = backgroundColorHex
    }

    public static let `default` = ProjectSettings()

    /// Parse backgroundColorHex into a CIColor. Falls back to black.
    public var backgroundCIColor: CIColor {
        let hex = backgroundColorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return .black }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return CIColor(red: r, green: g, blue: b)
    }

    /// Parse backgroundColorHex into a CGColor. Falls back to black.
    public var backgroundCGColor: CGColor {
        let hex = backgroundColorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else {
            return CGColor(gray: 0, alpha: 1)
        }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
