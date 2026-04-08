import Testing
import Foundation
@testable import EditorCore

@Suite("Audio Effect Command Tests")
struct AudioEffectCommandTests {

    // MARK: - Helpers

    @MainActor
    private func makeContext(clip: Clip) -> EditingContext {
        EditingContext(
            timelineState: TimelineState(
                timeline: Timeline(tracks: [Track(name: "A", type: .audio, clips: [clip])])
            )
        )
    }

    // MARK: - ApplyGateCommand

    @MainActor
    @Test("ApplyGate sets gate config and undo removes chain when it was nil")
    func applyGate() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5))
        let ctx = makeContext(clip: clip)

        var cmd = ApplyGateCommand(clipID: clip.id, config: GateConfig(thresholdDB: -35, attackMS: 1.0, releaseMS: 40))
        try cmd.execute(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.gate?.thresholdDB == -35)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.gate?.attackMS == 1.0)

        try cmd.undo(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects == nil)
    }

    @MainActor
    @Test("ApplyGate undo restores previous gate when chain existed")
    func applyGateUndoRestoresPrevious() throws {
        let existingChain = AudioEffectChain(gate: GateConfig(thresholdDB: -50))
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), audioEffects: existingChain)
        let ctx = makeContext(clip: clip)

        var cmd = ApplyGateCommand(clipID: clip.id, config: GateConfig(thresholdDB: -35))
        try cmd.execute(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.gate?.thresholdDB == -35)

        try cmd.undo(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.gate?.thresholdDB == -50)
    }

    // MARK: - ApplyCompressorCommand

    @MainActor
    @Test("ApplyCompressor sets compressor config and undo removes chain when it was nil")
    func applyCompressor() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5))
        let ctx = makeContext(clip: clip)

        let config = CompressorConfig(ratio: 6.0, attackMS: 10, releaseMS: 100, thresholdDB: -18, makeupGainDB: 4)
        var cmd = ApplyCompressorCommand(clipID: clip.id, config: config)
        try cmd.execute(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.compressor?.ratio == 6.0)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.compressor?.thresholdDB == -18)

        try cmd.undo(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects == nil)
    }

    @MainActor
    @Test("ApplyCompressor undo restores previous compressor when chain existed")
    func applyCompressorUndoRestoresPrevious() throws {
        let existingChain = AudioEffectChain(compressor: CompressorConfig(ratio: 4.0))
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), audioEffects: existingChain)
        let ctx = makeContext(clip: clip)

        var cmd = ApplyCompressorCommand(clipID: clip.id, config: CompressorConfig(ratio: 8.0))
        try cmd.execute(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.compressor?.ratio == 8.0)

        try cmd.undo(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.compressor?.ratio == 4.0)
    }

    // MARK: - ApplyDeEsserCommand

    @MainActor
    @Test("ApplyDeEsser sets de-esser config and undo removes chain when it was nil")
    func applyDeEsser() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5))
        let ctx = makeContext(clip: clip)

        let config = DeEsserConfig(centerFreqHz: 7000, reductionDB: -5)
        var cmd = ApplyDeEsserCommand(clipID: clip.id, config: config)
        try cmd.execute(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.deEsser?.centerFreqHz == 7000)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.deEsser?.reductionDB == -5)

        try cmd.undo(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects == nil)
    }

    @MainActor
    @Test("ApplyDeEsser undo restores previous de-esser when chain existed")
    func applyDeEsserUndoRestoresPrevious() throws {
        let existingChain = AudioEffectChain(deEsser: DeEsserConfig(centerFreqHz: 5500))
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), audioEffects: existingChain)
        let ctx = makeContext(clip: clip)

        var cmd = ApplyDeEsserCommand(clipID: clip.id, config: DeEsserConfig(centerFreqHz: 7000))
        try cmd.execute(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.deEsser?.centerFreqHz == 7000)

        try cmd.undo(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.deEsser?.centerFreqHz == 5500)
    }

    // MARK: - ApplyEQCommand

    @MainActor
    @Test("ApplyEQ sets EQ config and undo removes chain when it was nil")
    func applyEQ() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5))
        let ctx = makeContext(clip: clip)

        let config = EQConfig(bands: [EQBand(freqHz: 1000, gainDB: 3, q: 1.0, filterType: .peak)])
        var cmd = ApplyEQCommand(clipID: clip.id, config: config)
        try cmd.execute(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.eq?.bands.count == 1)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.eq?.bands[0].freqHz == 1000)

        try cmd.undo(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects == nil)
    }

    @MainActor
    @Test("ApplyEQ undo restores previous EQ when chain existed")
    func applyEQUndoRestoresPrevious() throws {
        let existingEQ = EQConfig(bands: [EQBand(freqHz: 500, gainDB: -2)])
        let existingChain = AudioEffectChain(eq: existingEQ)
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), audioEffects: existingChain)
        let ctx = makeContext(clip: clip)

        let newEQ = EQConfig(bands: [EQBand(freqHz: 2000, gainDB: 4)])
        var cmd = ApplyEQCommand(clipID: clip.id, config: newEQ)
        try cmd.execute(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.eq?.bands[0].freqHz == 2000)

        try cmd.undo(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.eq?.bands[0].freqHz == 500)
    }

    // MARK: - ApplyLimiterCommand

    @MainActor
    @Test("ApplyLimiter sets limiter config and undo removes chain when it was nil")
    func applyLimiter() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5))
        let ctx = makeContext(clip: clip)

        let config = LimiterConfig(thresholdDB: -3, attackMS: 0.5, releaseMS: 50)
        var cmd = ApplyLimiterCommand(clipID: clip.id, config: config)
        try cmd.execute(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.limiter?.thresholdDB == -3)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.limiter?.attackMS == 0.5)

        try cmd.undo(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects == nil)
    }

    @MainActor
    @Test("ApplyLimiter undo restores previous limiter when chain existed")
    func applyLimiterUndoRestoresPrevious() throws {
        let existingChain = AudioEffectChain(limiter: LimiterConfig(thresholdDB: -6))
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), audioEffects: existingChain)
        let ctx = makeContext(clip: clip)

        var cmd = ApplyLimiterCommand(clipID: clip.id, config: LimiterConfig(thresholdDB: -2))
        try cmd.execute(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.limiter?.thresholdDB == -2)

        try cmd.undo(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.limiter?.thresholdDB == -6)
    }

    // MARK: - NormalizeLUFSCommand

    @MainActor
    @Test("NormalizeLUFS sets target LUFS and undo removes chain when it was nil")
    func normalizeLUFS() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5))
        let ctx = makeContext(clip: clip)

        var cmd = NormalizeLUFSCommand(clipID: clip.id, targetLUFS: -16.0)
        try cmd.execute(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.normalizeLUFS == -16.0)

        try cmd.undo(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects == nil)
    }

    @MainActor
    @Test("NormalizeLUFS undo restores previous LUFS when chain existed")
    func normalizeLUFSUndoRestoresPrevious() throws {
        let existingChain = AudioEffectChain(normalizeLUFS: -14.0)
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), audioEffects: existingChain)
        let ctx = makeContext(clip: clip)

        var cmd = NormalizeLUFSCommand(clipID: clip.id, targetLUFS: -23.0)
        try cmd.execute(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.normalizeLUFS == -23.0)

        try cmd.undo(context: ctx)
        #expect(ctx.timelineState.timeline.tracks[0].clips[0].audioEffects?.normalizeLUFS == -14.0)
    }

    // MARK: - IntentResolver Integration

    @MainActor
    @Test("IntentResolver resolves all audio effect intents")
    func intentResolverAudioEffects() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5))
        let resolver = IntentResolver()

        let gateCmd = try resolver.resolve(.applyGate(clipID: clip.id, config: GateConfig()))
        #expect(gateCmd.name == "Apply Gate")

        let compressorCmd = try resolver.resolve(.applyCompressor(clipID: clip.id, config: CompressorConfig()))
        #expect(compressorCmd.name == "Apply Compressor")

        let deEsserCmd = try resolver.resolve(.applyDeEsser(clipID: clip.id, config: DeEsserConfig()))
        #expect(deEsserCmd.name == "Apply De-Esser")

        let eqCmd = try resolver.resolve(.applyEQ(clipID: clip.id, config: EQConfig()))
        #expect(eqCmd.name == "Apply EQ")

        let limiterCmd = try resolver.resolve(.applyLimiter(clipID: clip.id, config: LimiterConfig()))
        #expect(limiterCmd.name == "Apply Limiter")

        let lufsCmd = try resolver.resolve(.normalizeLUFS(clipID: clip.id, targetLUFS: -16.0))
        #expect(lufsCmd.name == "Normalize Audio to LUFS")
    }
}
