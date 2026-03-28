import Foundation

/// Pre-built project configurations for common video formats.
public struct ProjectTemplate: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let description: String
    public let settings: ProjectSettings
    public let tracks: [TemplateTrack]

    public struct TemplateTrack: Codable, Sendable {
        public let name: String
        public let type: TrackType
    }

    public init(id: UUID = UUID(), name: String, description: String, settings: ProjectSettings, tracks: [TemplateTrack]) {
        self.id = id
        self.name = name
        self.description = description
        self.settings = settings
        self.tracks = tracks
    }

    // MARK: - Built-in Templates

    public static let youtubeVideo = ProjectTemplate(
        name: "YouTube Video",
        description: "16:9 HD video with A/V tracks",
        settings: ProjectSettings(width: 1920, height: 1080, frameRate: 30),
        tracks: [
            TemplateTrack(name: "Video", type: .video),
            TemplateTrack(name: "B-Roll", type: .video),
            TemplateTrack(name: "Audio", type: .audio),
            TemplateTrack(name: "Music", type: .audio),
        ]
    )

    public static let youtubeShort = ProjectTemplate(
        name: "YouTube Short / TikTok",
        description: "9:16 vertical short-form",
        settings: ProjectSettings(width: 1080, height: 1920, frameRate: 30),
        tracks: [
            TemplateTrack(name: "Video", type: .video),
            TemplateTrack(name: "Audio", type: .audio),
            TemplateTrack(name: "Captions", type: .text),
        ]
    )

    public static let podcast = ProjectTemplate(
        name: "Podcast",
        description: "Audio-focused with video option",
        settings: ProjectSettings(width: 1920, height: 1080, frameRate: 30),
        tracks: [
            TemplateTrack(name: "Camera", type: .video),
            TemplateTrack(name: "Host Audio", type: .audio),
            TemplateTrack(name: "Guest Audio", type: .audio),
            TemplateTrack(name: "Music", type: .audio),
        ]
    )

    public static let documentary = ProjectTemplate(
        name: "Documentary",
        description: "Multi-track with narration and B-roll",
        settings: ProjectSettings(width: 3840, height: 2160, frameRate: 24),
        tracks: [
            TemplateTrack(name: "Interview", type: .video),
            TemplateTrack(name: "B-Roll", type: .video),
            TemplateTrack(name: "Graphics", type: .video),
            TemplateTrack(name: "Dialogue", type: .audio),
            TemplateTrack(name: "Narration", type: .audio),
            TemplateTrack(name: "Music", type: .audio),
            TemplateTrack(name: "SFX", type: .audio),
        ]
    )

    public static let cinematic = ProjectTemplate(
        name: "Cinematic",
        description: "4K 24fps with full production tracks",
        settings: ProjectSettings(width: 3840, height: 2160, frameRate: 24),
        tracks: [
            TemplateTrack(name: "A Camera", type: .video),
            TemplateTrack(name: "B Camera", type: .video),
            TemplateTrack(name: "VFX", type: .effect),
            TemplateTrack(name: "Dialogue", type: .audio),
            TemplateTrack(name: "Foley", type: .audio),
            TemplateTrack(name: "Score", type: .audio),
            TemplateTrack(name: "Subtitles", type: .text),
        ]
    )

    public static let allTemplates: [ProjectTemplate] = [
        youtubeVideo, youtubeShort, podcast, documentary, cinematic
    ]
}
