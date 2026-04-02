import Foundation
import AVFoundation

/// Export presets optimized for specific social media platforms.
public struct PlatformPreset: Sendable {
    public let name: String
    public let platform: Platform
    public let avPreset: String          // AVAssetExportSession preset
    public let fileType: AVFileType
    public let maxDuration: TimeInterval? // Platform's max duration (nil = unlimited)
    public let targetLUFS: Double        // Loudness target

    public enum Platform: String, CaseIterable, Sendable {
        case tiktok = "tiktok"
        case youtubeShorts = "youtube_shorts"
        case youtubeHD = "youtube_hd"
        case youtube4K = "youtube_4k"
        case instagramReels = "instagram_reels"
        case instagramFeed = "instagram_feed"
        case linkedin = "linkedin"
        case twitter = "twitter"
        case pinterest = "pinterest"
        case spotifyPodcast = "spotify_podcast"
        case applePodcast = "apple_podcast"
    }

    public static let all: [PlatformPreset] = [
        // Short-form vertical (9:16)
        PlatformPreset(name: "TikTok", platform: .tiktok,
                       avPreset: AVAssetExportPresetHighestQuality, fileType: .mp4,
                       maxDuration: 600, targetLUFS: -14),
        PlatformPreset(name: "YouTube Shorts", platform: .youtubeShorts,
                       avPreset: AVAssetExportPresetHighestQuality, fileType: .mp4,
                       maxDuration: 180, targetLUFS: -14),
        PlatformPreset(name: "Instagram Reels", platform: .instagramReels,
                       avPreset: AVAssetExportPresetHighestQuality, fileType: .mp4,
                       maxDuration: 900, targetLUFS: -14),
        // Long-form horizontal (16:9)
        PlatformPreset(name: "YouTube HD", platform: .youtubeHD,
                       avPreset: AVAssetExportPreset1920x1080, fileType: .mp4,
                       maxDuration: nil, targetLUFS: -14),
        PlatformPreset(name: "YouTube 4K", platform: .youtube4K,
                       avPreset: AVAssetExportPreset3840x2160, fileType: .mp4,
                       maxDuration: nil, targetLUFS: -14),
        // Feed formats
        PlatformPreset(name: "Instagram Feed", platform: .instagramFeed,
                       avPreset: AVAssetExportPresetHighestQuality, fileType: .mp4,
                       maxDuration: 3600, targetLUFS: -14),
        PlatformPreset(name: "LinkedIn", platform: .linkedin,
                       avPreset: AVAssetExportPreset1920x1080, fileType: .mp4,
                       maxDuration: 900, targetLUFS: -14),
        PlatformPreset(name: "X/Twitter", platform: .twitter,
                       avPreset: AVAssetExportPreset1920x1080, fileType: .mp4,
                       maxDuration: 140, targetLUFS: -14),
        PlatformPreset(name: "Pinterest", platform: .pinterest,
                       avPreset: AVAssetExportPresetHighestQuality, fileType: .mp4,
                       maxDuration: 900, targetLUFS: -14),
        // Podcast
        PlatformPreset(name: "Spotify Podcast", platform: .spotifyPodcast,
                       avPreset: AVAssetExportPreset1920x1080, fileType: .mp4,
                       maxDuration: nil, targetLUFS: -14),
        PlatformPreset(name: "Apple Podcast", platform: .applePodcast,
                       avPreset: AVAssetExportPresetAppleM4A, fileType: .m4a,
                       maxDuration: nil, targetLUFS: -16),
    ]

    public static func preset(for platform: Platform) -> PlatformPreset? {
        all.first { $0.platform == platform }
    }
}
