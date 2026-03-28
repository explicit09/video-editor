import Foundation

/// AI voice cleanup — combines noise reduction, EQ, and compression
/// into a single one-click enhancement pipeline.
/// Equivalent to Descript's "Studio Sound" or Premiere's "Enhance Speech."
public struct VoiceCleanup: Sendable {

    public enum CleanupPreset: String, Sendable, CaseIterable {
        case standard    // General voice cleanup
        case podcast     // Optimized for podcast recording
        case interview   // Optimized for on-location interview
        case presentation // Optimized for webinar/screencast
        case music       // Light cleanup preserving musical content
    }

    public struct CleanupSettings: Sendable {
        public let noiseGateThreshold: Float      // dB
        public let eq: EqualizerSettings
        public let compressor: CompressorSettings
        public let deEsserFrequency: Double?      // Hz, nil = disabled

        public init(noiseGateThreshold: Float, eq: EqualizerSettings, compressor: CompressorSettings, deEsserFrequency: Double?) {
            self.noiseGateThreshold = noiseGateThreshold
            self.eq = eq
            self.compressor = compressor
            self.deEsserFrequency = deEsserFrequency
        }
    }

    /// Get settings for a cleanup preset.
    public static func settings(for preset: CleanupPreset) -> CleanupSettings {
        switch preset {
        case .standard:
            return CleanupSettings(
                noiseGateThreshold: -40,
                eq: .voiceClarity,
                compressor: .voice,
                deEsserFrequency: 6000
            )
        case .podcast:
            return CleanupSettings(
                noiseGateThreshold: -35,
                eq: EqualizerSettings(bands: [
                    .init(frequency: 60, gain: -8),   // Aggressive low cut
                    .init(frequency: 200, gain: -4),   // Reduce proximity
                    .init(frequency: 1000, gain: 1),
                    .init(frequency: 3000, gain: 3),   // Presence boost
                    .init(frequency: 5000, gain: 4),   // Clarity
                    .init(frequency: 10000, gain: 2),  // Air
                ]),
                compressor: CompressorSettings(threshold: -18, ratio: 5, attack: 0.005, release: 0.1, makeupGain: 8),
                deEsserFrequency: 5500
            )
        case .interview:
            return CleanupSettings(
                noiseGateThreshold: -30,  // More aggressive for noisy environments
                eq: EqualizerSettings(bands: [
                    .init(frequency: 100, gain: -6),
                    .init(frequency: 300, gain: -2),
                    .init(frequency: 1500, gain: 2),
                    .init(frequency: 4000, gain: 3),
                ]),
                compressor: CompressorSettings(threshold: -15, ratio: 6, attack: 0.008, release: 0.15, makeupGain: 10),
                deEsserFrequency: 6000
            )
        case .presentation:
            return CleanupSettings(
                noiseGateThreshold: -38,
                eq: EqualizerSettings(bands: [
                    .init(frequency: 80, gain: -5),
                    .init(frequency: 250, gain: -2),
                    .init(frequency: 2000, gain: 2),
                    .init(frequency: 4000, gain: 3),
                    .init(frequency: 8000, gain: 1),
                ]),
                compressor: .voice,
                deEsserFrequency: nil  // Usually not needed for presentations
            )
        case .music:
            return CleanupSettings(
                noiseGateThreshold: -45,  // Very gentle
                eq: .tenBand,  // Flat — preserve original
                compressor: .music,
                deEsserFrequency: nil
            )
        }
    }

    /// Generate a description of what the cleanup will do.
    public static func describe(preset: CleanupPreset) -> String {
        switch preset {
        case .standard: "Removes background noise, enhances voice clarity, compresses dynamics, reduces sibilance"
        case .podcast: "Aggressive noise removal, proximity reduction, strong presence boost, heavy compression for consistent levels"
        case .interview: "Strong noise gate for noisy locations, presence boost, heavy compression, de-essing"
        case .presentation: "Light noise removal, clarity boost, moderate compression"
        case .music: "Very gentle cleanup preserving musical dynamics and frequency balance"
        }
    }
}
