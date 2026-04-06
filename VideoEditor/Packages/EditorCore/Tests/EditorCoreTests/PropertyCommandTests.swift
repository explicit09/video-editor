import Testing
import Foundation
@testable import EditorCore

@Suite("Property Command Tests")
struct PropertyCommandTests {

    @MainActor
    @Test("SetClipVolume changes volume and undo restores")
    func setClipVolume() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), volume: 1.0)
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "A", type: .audio, clips: [clip])])))

        var cmd = SetClipVolumeCommand(clipID: clip.id, volume: 0.5)
        try cmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].volume == 0.5)

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].volume == 1.0)
    }

    @MainActor
    @Test("SetClipOpacity clamps and undo restores")
    func setClipOpacity() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5))
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])))

        var cmd = SetClipOpacityCommand(clipID: clip.id, opacity: 1.5)
        try cmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].opacity == 1.0) // clamped

        var cmd2 = SetClipOpacityCommand(clipID: clip.id, opacity: 0.3)
        try cmd2.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].opacity == 0.3)

        try cmd2.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].opacity == 1.0, "Undo should restore clamped value")
    }

    @MainActor
    @Test("MuteTrack toggles and undo restores")
    func muteTrack() throws {
        let track = Track(name: "V1", type: .video)
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [track])))

        var cmd = MuteTrackCommand(trackID: track.id, muted: true)
        try cmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].isMuted == true)

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].isMuted == false)
    }

    @MainActor
    @Test("SetClipTransform via intent updates the clip and undo restores")
    func setClipTransformViaIntent() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5))
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])))
        let resolver = IntentResolver()
        let transform = Transform2D(positionX: 120, positionY: -40, scaleX: 1.25, scaleY: 0.8, rotation: 15)

        var cmd = try resolver.resolve(.setClipTransform(clipID: clip.id, transform: transform))
        try cmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].transform == transform)

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].transform == .identity)
    }

    @MainActor
    @Test("SetTrackVolume via intent clamps negatives and undo restores")
    func setTrackVolumeViaIntent() throws {
        let track = Track(name: "A1", type: .audio, volume: 1.0)
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [track])))

        var cmd = try IntentResolver().resolve(.setTrackVolume(trackID: track.id, volume: -2))
        try cmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].volume == 0)

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].volume == 1.0)
    }

    @MainActor
    @Test("SetClipSpeed via intent updates timeline duration and undo restores")
    func setClipSpeedViaIntent() throws {
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 10),
            sourceRange: TimeRange(start: 0, end: 10),
            speed: 1.0
        )
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])))

        var cmd = try IntentResolver().resolve(.setClipSpeed(clipID: clip.id, speed: 2.0))
        try cmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].speed == 2.0)
        #expect(context.timelineState.timeline.tracks[0].clips[0].timelineRange == TimeRange(start: 0, end: 5))

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].speed == 1.0)
        #expect(context.timelineState.timeline.tracks[0].clips[0].timelineRange == TimeRange(start: 0, end: 10))
    }

    @MainActor
    @Test("SetClipEffect replaces matching types and remove effect undo restores")
    func setAndRemoveClipEffect() throws {
        let originalEffect = EffectInstance(type: "blur", parameters: ["radius": 4])
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5),
            effects: [originalEffect]
        )
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])))
        let replacement = EffectInstance(type: "blur", parameters: ["radius": 20])
        let resolver = IntentResolver()

        var setCmd = try resolver.resolve(.setClipEffect(clipID: clip.id, effect: replacement))
        try setCmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects.count == 1)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects[0].id == replacement.id)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects[0].parameters["radius"] == 20)

        var removeCmd = try resolver.resolve(.removeClipEffect(clipID: clip.id, effectID: replacement.id))
        try removeCmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects.isEmpty)

        try removeCmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects.count == 1)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects[0].id == replacement.id)

        try setCmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects.count == 1)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects[0].id == originalEffect.id)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects[0].parameters["radius"] == 4)
    }

    @MainActor
    @Test("ReplacePrimaryClipEffect swaps the full tool-managed stack and undo restores")
    func replacePrimaryClipEffect() throws {
        let originalEffects = [
            EffectInstance(type: "blur", parameters: ["radius": 4]),
            EffectInstance(type: "sharpen", parameters: ["sharpness": 0.5]),
        ]
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5),
            effects: originalEffects
        )
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])))
        let replacement = EffectInstance.videoDenoise(level: 0.45)

        var cmd = try IntentResolver().resolve(.replacePrimaryClipEffect(clipID: clip.id, effect: replacement))
        try cmd.execute(context: context)

        #expect(context.timelineState.timeline.tracks[0].clips[0].effects.count == 1)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects[0].type == EffectInstance.typeVideoDenoise)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects[0].parameters["level"] == 0.45)

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects.count == 2)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects[0].type == EffectInstance.typeBlur)
        #expect(context.timelineState.timeline.tracks[0].clips[0].effects[1].type == EffectInstance.typeSharpen)
    }

    @MainActor
    @Test("Transition, blend mode, and linking commands round-trip through undo")
    func transitionBlendAndLinkRoundTrip() throws {
        let clipA = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 4), sourceRange: TimeRange(start: 0, end: 4))
        let clipB = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 4), sourceRange: TimeRange(start: 0, end: 4))
        let context = EditingContext(
            timelineState: TimelineState(
                timeline: Timeline(tracks: [
                    Track(name: "V1", type: .video, clips: [clipA]),
                    Track(name: "A1", type: .audio, clips: [clipB]),
                ])
            )
        )
        let resolver = IntentResolver()
        let transition = ClipTransition(type: .crossDissolve, duration: 0.75)
        let linkGroupID = UUID()

        var transitionCmd = try resolver.resolve(.setClipTransition(clipID: clipA.id, transition: transition))
        try transitionCmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].transitionIn == transition)

        var blendCmd = try resolver.resolve(.setClipBlendMode(clipID: clipA.id, blendMode: .multiply))
        try blendCmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].blendMode == .multiply)

        var linkCmd = try resolver.resolve(.linkClips(clipIDs: [clipA.id, clipB.id], linkGroupID: linkGroupID))
        try linkCmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].linkGroupID == linkGroupID)
        #expect(context.timelineState.timeline.tracks[1].clips[0].linkGroupID == linkGroupID)

        try linkCmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].linkGroupID == nil)
        #expect(context.timelineState.timeline.tracks[1].clips[0].linkGroupID == nil)

        try blendCmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].blendMode == .normal)

        try transitionCmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].transitionIn == .none)
    }

    @MainActor
    @Test("DuplicateClip creates copy at end of original")
    func duplicateClip() throws {
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5),
            cropRect: CropRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
            metadata: ClipMetadata(label: "Original"),
            linkGroupID: UUID(),
            blendMode: .screen
        )
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])))

        var cmd = DuplicateClipCommand(clipID: clip.id)
        try cmd.execute(context: context)

        let clips = context.timelineState.timeline.tracks[0].clips
        #expect(clips.count == 2)
        #expect(clips[1].timelineRange.start == 5) // starts at end of original
        #expect(clips[1].metadata.label == "Original (copy)")
        #expect(clips[1].assetID == clip.assetID)
        #expect(clips[1].cropRect == clip.cropRect)
        #expect(clips[1].linkGroupID == clip.linkGroupID)
        #expect(clips[1].blendMode == clip.blendMode)

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips.count == 1)
    }

    @MainActor
    @Test("SetClipCrop clamps and undo restores")
    func setClipCrop() throws {
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5),
            cropRect: .fullFrame
        )
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])))

        var cmd = SetClipCropCommand(
            clipID: clip.id,
            cropRect: CropRect(x: -0.2, y: 0.1, width: 1.4, height: 1.2)
        )
        try cmd.execute(context: context)

        let applied = context.timelineState.timeline.tracks[0].clips[0].cropRect
        #expect(applied == CropRect(x: 0, y: 0.1, width: 1, height: 0.9))

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].cropRect == .fullFrame)
    }

    @MainActor
    @Test("SetClipOverlayPresentation updates the clip presentation")
    func setClipOverlayPresentation() throws {
        let clip = Clip(assetID: UUID(), timelineRange: .init(start: 0, duration: 5), sourceRange: .init(start: 0, duration: 5))
        let track = Track(name: "Video 1", type: .video, clips: [clip])
        let context = EditingContext(timelineState: .init(timeline: .init(tracks: [track])))
        let resolver = IntentResolver()

        let presentation = OverlayPresentation(
            mode: .pip,
            border: .init(isVisible: true, width: 6, colorHex: "#FFFFFF"),
            shadow: .medium,
            cornerRadius: 18,
            maskShape: .roundedRect,
            entranceAnimation: .scaleIn,
            exitAnimation: .fadeOut
        )

        var command = try resolver.resolve(.setClipOverlayPresentation(clipID: clip.id, presentation: presentation))
        try command.execute(context: context)

        #expect(context.timelineState.timeline.tracks[0].clips[0].overlayPresentation == presentation)
    }

    @MainActor
    @Test("ApplyClipPiPPreset updates transform and presentation")
    func applyClipPiPPreset() throws {
        let clip = Clip(assetID: UUID(), timelineRange: .init(start: 0, duration: 5), sourceRange: .init(start: 0, duration: 5))
        let track = Track(name: "Video 2", type: .video, clips: [clip])
        let context = EditingContext(timelineState: .init(timeline: .init(tracks: [track])))
        let resolver = IntentResolver()

        var command = try resolver.resolve(.applyClipPiPPreset(clipID: clip.id, preset: .bottomRight))
        try command.execute(context: context)

        let updated = context.timelineState.timeline.tracks[0].clips[0]
        #expect(updated.overlayPresentation.mode == .pip)
        #expect(updated.transform.scaleX < 1.0)
        #expect(updated.transform.positionX > 0)
        #expect(updated.transform.positionY < 0)
    }

    @MainActor
    @Test("RenameClip changes label and undo restores")
    func renameClip() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), metadata: ClipMetadata(label: "Before"))
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])))

        var cmd = RenameClipCommand(clipID: clip.id, label: "After")
        try cmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].metadata.label == "After")

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].metadata.label == "Before")
    }

}
