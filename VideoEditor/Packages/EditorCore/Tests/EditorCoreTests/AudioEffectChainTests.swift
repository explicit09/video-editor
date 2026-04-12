import Foundation
import Testing
@testable import EditorCore

@Suite("AudioEffectChain")
struct AudioEffectChainTests {

    // MARK: - Default chain

    @Test("Default chain has all nil fields")
    func defaultChainIsEmpty() {
        let chain = AudioEffectChain()
        #expect(chain.gate == nil)
        #expect(chain.compressor == nil)
        #expect(chain.deEsser == nil)
        #expect(chain.eq == nil)
        #expect(chain.limiter == nil)
        #expect(chain.normalizeLUFS == nil)
    }

    // MARK: - Individual configs with defaults

    @Test("GateConfig default values")
    func gateConfigDefaults() {
        let gate = GateConfig()
        #expect(gate.thresholdDB == -40)
        #expect(gate.attackMS == 0.5)
        #expect(gate.releaseMS == 50)
    }

    @Test("CompressorConfig default values")
    func compressorConfigDefaults() {
        let comp = CompressorConfig()
        #expect(comp.ratio == 4.0)
        #expect(comp.attackMS == 5)
        #expect(comp.releaseMS == 30)
        #expect(comp.thresholdDB == -20)
        #expect(comp.makeupGainDB == 3)
    }

    @Test("DeEsserConfig default values")
    func deEsserConfigDefaults() {
        let de = DeEsserConfig()
        #expect(de.centerFreqHz == 5500)
        #expect(de.reductionDB == -3)
    }

    @Test("EQConfig default has empty bands")
    func eqConfigDefaults() {
        let eq = EQConfig()
        #expect(eq.bands.isEmpty)
    }

    @Test("EQBand default values")
    func eqBandDefaults() {
        let band = EQBand(freqHz: 1000)
        #expect(band.freqHz == 1000)
        #expect(band.gainDB == 0)
        #expect(band.q == 1.0)
        #expect(band.filterType == .peak)
    }

    @Test("LimiterConfig default values")
    func limiterConfigDefaults() {
        let lim = LimiterConfig()
        #expect(lim.thresholdDB == -6)
        #expect(lim.attackMS == 1)
        #expect(lim.releaseMS == 75)
    }

    // MARK: - Chain with individual configs

    @Test("Chain with gate only")
    func chainWithGate() {
        let gate = GateConfig(thresholdDB: -50, attackMS: 1.0, releaseMS: 100)
        let chain = AudioEffectChain(gate: gate)
        #expect(chain.gate == gate)
        #expect(chain.compressor == nil)
        #expect(chain.deEsser == nil)
        #expect(chain.eq == nil)
        #expect(chain.limiter == nil)
    }

    @Test("Chain with compressor only")
    func chainWithCompressor() {
        let comp = CompressorConfig(ratio: 6.0, attackMS: 10, releaseMS: 60, thresholdDB: -18, makeupGainDB: 5)
        let chain = AudioEffectChain(compressor: comp)
        #expect(chain.compressor == comp)
        #expect(chain.gate == nil)
    }

    @Test("Chain with LUFS normalization")
    func chainWithLUFS() {
        let chain = AudioEffectChain(normalizeLUFS: -16.0)
        #expect(chain.normalizeLUFS == -16.0)
    }

    @Test("Chain with EQ bands")
    func chainWithEQ() {
        let bands = [
            EQBand(freqHz: 80, gainDB: -3, q: 0.7, filterType: .highPass),
            EQBand(freqHz: 8000, gainDB: 2, q: 1.5, filterType: .highShelf)
        ]
        let eq = EQConfig(bands: bands)
        let chain = AudioEffectChain(eq: eq)
        #expect(chain.eq?.bands.count == 2)
        #expect(chain.eq?.bands[0].filterType == .highPass)
        #expect(chain.eq?.bands[1].filterType == .highShelf)
    }

    // MARK: - Full processing stack

    @Test("Full processing stack")
    func fullProcessingStack() {
        let gate = GateConfig(thresholdDB: -45)
        let compressor = CompressorConfig(ratio: 3.0, thresholdDB: -22)
        let deEsser = DeEsserConfig(centerFreqHz: 6000, reductionDB: -4)
        let eq = EQConfig(bands: [EQBand(freqHz: 200, gainDB: -2)])
        let limiter = LimiterConfig(thresholdDB: -3)

        let chain = AudioEffectChain(
            gate: gate,
            compressor: compressor,
            deEsser: deEsser,
            eq: eq,
            limiter: limiter,
            normalizeLUFS: -14.0
        )

        #expect(chain.gate != nil)
        #expect(chain.compressor != nil)
        #expect(chain.deEsser != nil)
        #expect(chain.eq != nil)
        #expect(chain.limiter != nil)
        #expect(chain.normalizeLUFS == -14.0)
        #expect(chain.gate?.thresholdDB == -45)
        #expect(chain.compressor?.ratio == 3.0)
        #expect(chain.deEsser?.centerFreqHz == 6000)
        #expect(chain.limiter?.thresholdDB == -3)
    }

    // MARK: - Codable round-trip

    @Test("AudioEffectChain codable round-trip (empty)")
    func codableRoundTripEmpty() throws {
        let chain = AudioEffectChain()
        let data = try JSONEncoder().encode(chain)
        let decoded = try JSONDecoder().decode(AudioEffectChain.self, from: data)
        #expect(decoded == chain)
    }

    @Test("AudioEffectChain codable round-trip (full stack)")
    func codableRoundTripFull() throws {
        let chain = AudioEffectChain(
            gate: GateConfig(thresholdDB: -38, attackMS: 0.3, releaseMS: 60),
            compressor: CompressorConfig(ratio: 5.0, attackMS: 8, releaseMS: 40, thresholdDB: -24, makeupGainDB: 4),
            deEsser: DeEsserConfig(centerFreqHz: 5800, reductionDB: -5),
            eq: EQConfig(bands: [
                EQBand(freqHz: 100, gainDB: -6, q: 0.9, filterType: .lowShelf),
                EQBand(freqHz: 3000, gainDB: 1.5, q: 2.0, filterType: .peak)
            ]),
            limiter: LimiterConfig(thresholdDB: -2, attackMS: 0.5, releaseMS: 50),
            normalizeLUFS: -16.0
        )
        let data = try JSONEncoder().encode(chain)
        let decoded = try JSONDecoder().decode(AudioEffectChain.self, from: data)
        #expect(decoded == chain)
        #expect(decoded.eq?.bands.count == 2)
        #expect(decoded.normalizeLUFS == -16.0)
    }

    @Test("EQFilterType codable round-trip")
    func eqFilterTypeCodable() throws {
        let allTypes: [EQFilterType] = [.highPass, .lowPass, .peak, .lowShelf, .highShelf]
        for filterType in allTypes {
            let data = try JSONEncoder().encode(filterType)
            let decoded = try JSONDecoder().decode(EQFilterType.self, from: data)
            #expect(decoded == filterType)
        }
    }

    // MARK: - Clip integration

    @Test("Clip audioEffects defaults to nil")
    func clipAudioEffectsDefaultsNil() {
        let clip = Clip(
            assetID: .init(),
            timelineRange: TimeRange(start: 0, end: 10),
            sourceRange: TimeRange(start: 0, end: 10)
        )
        #expect(clip.audioEffects == nil)
    }

    @Test("Clip can hold an AudioEffectChain")
    func clipWithAudioEffects() {
        let chain = AudioEffectChain(normalizeLUFS: -16.0)
        var clip = Clip(
            assetID: .init(),
            timelineRange: TimeRange(start: 0, end: 10),
            sourceRange: TimeRange(start: 0, end: 10)
        )
        clip.audioEffects = chain
        #expect(clip.audioEffects?.normalizeLUFS == -16.0)
    }
}
