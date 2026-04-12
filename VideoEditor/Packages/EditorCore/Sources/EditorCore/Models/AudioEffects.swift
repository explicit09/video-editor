import Foundation

/// Audio effect models for EQ, compression, and dynamic processing.
/// These define the parameters; rendering uses AVAudioEngine / AVAudioProcessingTap.

// MARK: - Legacy EQ / Compressor settings (used by VoiceCleanup, AudioEffectTap DSP)

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

// MARK: - AudioEffectChain

/// Full professional audio processing pipeline:
/// Gate → Compressor → De-Esser → EQ → Limiter, plus optional LUFS normalization.
public struct AudioEffectChain: Codable, Sendable, Equatable {
    public var gate: GateConfig?
    public var compressor: CompressorConfig?
    public var deEsser: DeEsserConfig?
    public var eq: EQConfig?
    public var limiter: LimiterConfig?
    /// Target LUFS for normalization, e.g. -16.0
    public var normalizeLUFS: Double?

    public init(
        gate: GateConfig? = nil,
        compressor: CompressorConfig? = nil,
        deEsser: DeEsserConfig? = nil,
        eq: EQConfig? = nil,
        limiter: LimiterConfig? = nil,
        normalizeLUFS: Double? = nil
    ) {
        self.gate = gate
        self.compressor = compressor
        self.deEsser = deEsser
        self.eq = eq
        self.limiter = limiter
        self.normalizeLUFS = normalizeLUFS
    }

    /// Podcast voice preset — gate, compression, de-essing, -16 LUFS
    public static let podcastVoice = AudioEffectChain(
        gate: GateConfig(thresholdDB: -40),
        compressor: CompressorConfig(ratio: 4.0, thresholdDB: -20),
        deEsser: DeEsserConfig(centerFreqHz: 6000),
        normalizeLUFS: -16.0
    )
}

// MARK: - GateConfig

public struct GateConfig: Codable, Sendable, Equatable {
    public var thresholdDB: Double
    public var attackMS: Double
    public var releaseMS: Double

    public init(
        thresholdDB: Double = -40,
        attackMS: Double = 0.5,
        releaseMS: Double = 50
    ) {
        self.thresholdDB = thresholdDB
        self.attackMS = attackMS
        self.releaseMS = releaseMS
    }
}

// MARK: - CompressorConfig

public struct CompressorConfig: Codable, Sendable, Equatable {
    public var ratio: Double
    public var attackMS: Double
    public var releaseMS: Double
    public var thresholdDB: Double
    public var makeupGainDB: Double

    public init(
        ratio: Double = 4.0,
        attackMS: Double = 5,
        releaseMS: Double = 30,
        thresholdDB: Double = -20,
        makeupGainDB: Double = 3
    ) {
        self.ratio = ratio
        self.attackMS = attackMS
        self.releaseMS = releaseMS
        self.thresholdDB = thresholdDB
        self.makeupGainDB = makeupGainDB
    }
}

// MARK: - DeEsserConfig

public struct DeEsserConfig: Codable, Sendable, Equatable {
    public var centerFreqHz: Double
    public var reductionDB: Double

    public init(
        centerFreqHz: Double = 5500,
        reductionDB: Double = -3
    ) {
        self.centerFreqHz = centerFreqHz
        self.reductionDB = reductionDB
    }
}

// MARK: - EQConfig

public struct EQConfig: Codable, Sendable, Equatable {
    public var bands: [EQBand]

    public init(bands: [EQBand] = []) {
        self.bands = bands
    }
}

// MARK: - EQBand

public struct EQBand: Codable, Sendable, Equatable {
    public var freqHz: Double
    public var gainDB: Double
    public var q: Double
    public var filterType: EQFilterType

    public init(
        freqHz: Double,
        gainDB: Double = 0,
        q: Double = 1.0,
        filterType: EQFilterType = .peak
    ) {
        self.freqHz = freqHz
        self.gainDB = gainDB
        self.q = q
        self.filterType = filterType
    }
}

// MARK: - EQFilterType

public enum EQFilterType: String, Codable, Sendable, Equatable {
    case highPass
    case lowPass
    case peak
    case lowShelf
    case highShelf
}

// MARK: - LimiterConfig

public struct LimiterConfig: Codable, Sendable, Equatable {
    public var thresholdDB: Double
    public var attackMS: Double
    public var releaseMS: Double

    public init(
        thresholdDB: Double = -6,
        attackMS: Double = 1,
        releaseMS: Double = 75
    ) {
        self.thresholdDB = thresholdDB
        self.attackMS = attackMS
        self.releaseMS = releaseMS
    }
}
