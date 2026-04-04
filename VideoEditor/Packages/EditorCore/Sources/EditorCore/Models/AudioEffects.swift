import Foundation

/// Audio effect models for EQ, compression, and reverb.
/// These define the parameters; rendering uses AVAudioEngine in a future phase.

// MARK: - Equalizer

public struct EqualizerSettings: Codable, Sendable {
    public var bands: [EQBand]

    public struct EQBand: Codable, Sendable {
        public var frequency: Double  // Hz
        public var gain: Double       // dB (-12 to +12)
        public var bandwidth: Double  // octaves (0.1 to 4.0)

        public init(frequency: Double, gain: Double = 0, bandwidth: Double = 1.0) {
            self.frequency = frequency
            self.gain = gain
            self.bandwidth = bandwidth
        }
    }

    /// Standard 10-band EQ preset frequencies
    public static let tenBand = EqualizerSettings(bands: [
        EQBand(frequency: 31),
        EQBand(frequency: 62),
        EQBand(frequency: 125),
        EQBand(frequency: 250),
        EQBand(frequency: 500),
        EQBand(frequency: 1000),
        EQBand(frequency: 2000),
        EQBand(frequency: 4000),
        EQBand(frequency: 8000),
        EQBand(frequency: 16000),
    ])

    /// Voice clarity preset — boost presence, cut mud
    public static let voiceClarity = EqualizerSettings(bands: [
        EQBand(frequency: 80, gain: -6), // Cut low rumble
        EQBand(frequency: 250, gain: -3), // Reduce mud
        EQBand(frequency: 500, gain: 0),
        EQBand(frequency: 1000, gain: 2),
        EQBand(frequency: 2000, gain: 3), // Presence
        EQBand(frequency: 4000, gain: 4), // Clarity
        EQBand(frequency: 8000, gain: 2), // Air
        EQBand(frequency: 16000, gain: 0),
    ])

    public init(bands: [EQBand]) {
        self.bands = bands
    }
}

// MARK: - Compressor

public struct CompressorSettings: Codable, Sendable {
    public var threshold: Double    // dB (e.g., -20)
    public var ratio: Double        // e.g., 4:1 = 4.0
    public var attack: Double       // seconds
    public var release: Double      // seconds
    public var makeupGain: Double   // dB

    /// Voice compression preset
    public static let voice = CompressorSettings(
        threshold: -20, ratio: 4, attack: 0.01, release: 0.1, makeupGain: 6
    )

    /// Gentle music compression
    public static let music = CompressorSettings(
        threshold: -15, ratio: 2, attack: 0.03, release: 0.3, makeupGain: 3
    )

    /// Heavy limiting for loudness
    public static let limiter = CompressorSettings(
        threshold: -6, ratio: 20, attack: 0.001, release: 0.05, makeupGain: 6
    )

    public init(threshold: Double = -20, ratio: Double = 4, attack: Double = 0.01, release: Double = 0.1, makeupGain: Double = 6) {
        self.threshold = threshold
        self.ratio = ratio
        self.attack = attack
        self.release = release
        self.makeupGain = makeupGain
    }
}

// MARK: - Audio Effect Chain

public struct AudioEffectChain: Codable, Sendable {
    public var eq: EqualizerSettings?
    public var compressor: CompressorSettings?
    public var noiseGateThreshold: Double? // dB
    public var deEsserFrequency: Double?   // Hz
    public var reverbMix: Double?          // 0-1

    public init(
        eq: EqualizerSettings? = nil,
        compressor: CompressorSettings? = nil,
        noiseGateThreshold: Double? = nil,
        deEsserFrequency: Double? = nil,
        reverbMix: Double? = nil
    ) {
        self.eq = eq
        self.compressor = compressor
        self.noiseGateThreshold = noiseGateThreshold
        self.deEsserFrequency = deEsserFrequency
        self.reverbMix = reverbMix
    }

    /// Podcast voice preset
    public static let podcastVoice = AudioEffectChain(
        eq: .voiceClarity,
        compressor: .voice,
        noiseGateThreshold: -40,
        deEsserFrequency: 6000
    )
}
