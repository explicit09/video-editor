import Foundation
import AVFoundation
import CoreImage

/// Builds AVComposition + AVVideoComposition + AVAudioMix from Timeline.
/// Shared between PlaybackEngine (proxy URLs) and ExportEngine (source URLs).
///
/// Architecture:
/// - Each video clip gets its own AVMutableCompositionTrack (required because
///   insertTimeRange shifts existing content, making shared tracks unreliable)
/// - An AVVideoComposition with per-clip instructions tells AVFoundation which
///   composition track to render at each point in time
/// - Audio is extracted from ALL tracks (video assets have audio too), with
///   linked A/V pairs handled to prevent double-audio
public struct CompositionBuilder {

    public enum MediaURLMode {
        case preview  // use proxyURL if available
        case export   // always use sourceURL
    }

    public struct Result {
        public let composition: AVMutableComposition
        public let audioMix: AVAudioMix?
        public let videoComposition: AVVideoComposition?
        public let duration: TimeInterval
    }

    public init() {}

    // MARK: - Internal tracking

    /// Records a video clip's composition track + effective time range for building instructions.
    private struct VideoClipEntry {
        let compositionTrack: AVMutableCompositionTrack
        let effectiveTimeRange: CMTimeRange  // After speed adjustment
        let clip: Clip
        let track: Track
    }

    // MARK: - Build

    public func build(
        from timeline: Timeline,
        assets: [MediaAsset],
        urlMode: MediaURLMode = .preview
    ) async -> Result {
        let comp = AVMutableComposition()
        var maxDuration: CMTime = .zero
        var audioParams: [AVMutableAudioMixInputParameters] = []
        var videoEntries: [VideoClipEntry] = []
        var renderSize: CGSize = .zero  // Will be set from first source track

        let anySoloed = timeline.tracks.contains { $0.isSoloed }

        // Collect all linkGroupIDs that have a clip on an audio track.
        // These video clips should NOT extract their own audio (the audio track handles it).
        let audioTrackLinkGroups: Set<UUID> = Set(
            timeline.tracks
                .filter { $0.type == .audio }
                .flatMap(\.clips)
                .compactMap(\.linkGroupID)
        )

        // Process all tracks
        // Reuse composition audio tracks to avoid silent-padding issues.
        // Key: timeline track ID → shared composition audio track.
        // Video tracks' extracted audio shares with their paired audio track.
        var audioTrackCompTracks: [UUID: AVMutableCompositionTrack] = [:]

        // Map video track IDs to their paired audio track IDs for audio routing
        let videoToAudioTrackID: [UUID: UUID] = {
            var map: [UUID: UUID] = [:]
            let videoTracks = timeline.tracks.filter { $0.type != .audio }
            let audioTracks = timeline.tracks.filter { $0.type == .audio }
            for vTrack in videoTracks {
                // Find paired audio track: audio track with clips sharing linkGroupIDs
                let vLinkGroups = Set(vTrack.clips.compactMap(\.linkGroupID))
                if let aTrack = audioTracks.first(where: { track in
                    track.clips.contains { clip in clip.linkGroupID != nil && vLinkGroups.contains(clip.linkGroupID!) }
                }) {
                    map[vTrack.id] = aTrack.id
                }
            }
            return map
        }()

        for track in timeline.tracks {
            guard !track.isMuted else { continue }
            if anySoloed && !track.isSoloed { continue }

            for clip in track.clips {
                guard let mediaAsset = assets.first(where: { $0.id == clip.assetID }) else { continue }

                let mediaURL: URL
                switch urlMode {
                case .preview: mediaURL = mediaAsset.proxyURL ?? mediaAsset.sourceURL
                case .export: mediaURL = mediaAsset.sourceURL
                }
                let avAsset = AVURLAsset(url: mediaURL)

                let ts: CMTimeScale = 600
                let insertTime = CMTime(seconds: clip.timelineRange.start, preferredTimescale: ts)
                let sourceStart = CMTime(seconds: clip.sourceRange.start, preferredTimescale: ts)
                let sourceDuration = CMTime(seconds: max(clip.sourceRange.duration, 0), preferredTimescale: ts)
                let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)

                // Calculate speed-adjusted duration
                let effectiveDuration: CMTime
                if clip.speed != 1.0 {
                    effectiveDuration = CMTime(seconds: sourceDuration.seconds / clip.speed, preferredTimescale: ts)
                } else {
                    effectiveDuration = sourceDuration
                }

                // === VIDEO ===
                if track.type != .audio {
                    if let sourceTrack = try? await avAsset.loadTracks(withMediaType: .video).first,
                       let compTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {

                        try? compTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)

                        // Apply speed
                        if clip.speed != 1.0 {
                            let insertedRange = CMTimeRange(start: insertTime, duration: sourceDuration)
                            compTrack.scaleTimeRange(insertedRange, toDuration: effectiveDuration)
                        }

                        // Set render size from first source track (not a default)
                        if let size = try? await sourceTrack.load(.naturalSize), size.width > 0 {
                            if renderSize == .zero {
                                renderSize = size
                            } else if size.width > renderSize.width {
                                renderSize = size
                            }
                        }

                        // Record for video composition instructions
                        videoEntries.append(VideoClipEntry(
                            compositionTrack: compTrack,
                            effectiveTimeRange: CMTimeRange(start: insertTime, duration: effectiveDuration),
                            clip: clip,
                            track: track
                        ))
                    }

                    // Extract audio from video-type tracks IF no linked audio track handles it
                    let hasLinkedAudio = clip.linkGroupID != nil && audioTrackLinkGroups.contains(clip.linkGroupID!)

                    if !hasLinkedAudio {
                        if let audioSourceTrack = try? await avAsset.loadTracks(withMediaType: .audio).first {
                            // Route to paired audio track's composition track, or create a shared one
                            let routeKey = videoToAudioTrackID[track.id] ?? track.id
                            let audioCompTrack: AVMutableCompositionTrack
                            if let existing = audioTrackCompTracks[routeKey] {
                                audioCompTrack = existing
                            } else if let newTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                                audioTrackCompTracks[routeKey] = newTrack
                                audioCompTrack = newTrack
                            } else {
                                continue
                            }

                            try? audioCompTrack.insertTimeRange(sourceRange, of: audioSourceTrack, at: insertTime)

                            if clip.speed != 1.0 {
                                let insertedRange = CMTimeRange(start: insertTime, duration: sourceDuration)
                                audioCompTrack.scaleTimeRange(insertedRange, toDuration: effectiveDuration)
                            }

                            let effectiveVolume = Float(clip.volume * track.volume)
                            if effectiveVolume != 1.0 {
                                let params = AVMutableAudioMixInputParameters(track: audioCompTrack)
                                params.setVolume(effectiveVolume, at: .zero)
                                audioParams.append(params)
                            }
                        }
                    }
                }

                // === AUDIO ===
                if track.type == .audio {
                    if let sourceTrack = try? await avAsset.loadTracks(withMediaType: .audio).first {
                        // Reuse one composition track per timeline audio track
                        let compTrack: AVMutableCompositionTrack
                        if let existing = audioTrackCompTracks[track.id] {
                            compTrack = existing
                        } else if let newTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                            audioTrackCompTracks[track.id] = newTrack
                            compTrack = newTrack
                        } else {
                            continue
                        }

                        try? compTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)

                        if clip.speed != 1.0 {
                            let insertedRange = CMTimeRange(start: insertTime, duration: sourceDuration)
                            compTrack.scaleTimeRange(insertedRange, toDuration: effectiveDuration)
                        }

                        let effectiveVolume = Float(clip.volume * track.volume)
                        if effectiveVolume != 1.0 {
                            let params = AVMutableAudioMixInputParameters(track: compTrack)
                            params.setVolume(effectiveVolume, at: .zero)
                            audioParams.append(params)
                        }
                    }
                }

                // Update max duration (speed-adjusted)
                let clipEnd = CMTimeAdd(insertTime, effectiveDuration)
                if CMTimeCompare(clipEnd, maxDuration) > 0 {
                    maxDuration = clipEnd
                }
            }
        }

        // === BUILD AUDIO MIX ===
        var audioMix: AVAudioMix?
        if !audioParams.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioParams
            audioMix = mix
        }

        // === BUILD VIDEO COMPOSITION ===
        // ALWAYS create when there are video clips. Without this, only the first
        // composition video track renders — all others are invisible.
        //
        // CRITICAL RULES (AVFoundation requirements):
        // 1. Instructions must cover 0 to composition.duration with NO gaps
        // 2. No overlapping instruction timeRanges
        // 3. layerInstruction trackIDs must exist in composition
        // 4. Use composition.duration (not manually tracked maxDuration) as the authority
        var videoComposition: AVVideoComposition?
        if !videoEntries.isEmpty {
            // Use composition.duration as the authoritative total duration.
            // After insertTimeRange + scaleTimeRange, comp.duration reflects reality.
            let totalDuration = comp.duration

            let sorted = videoEntries.sorted {
                CMTimeCompare($0.effectiveTimeRange.start, $1.effectiveTimeRange.start) < 0
            }

            // Determine if any clip needs the custom compositor
            let needsCustomCompositor = sorted.contains { entry in
                !entry.clip.effects.isEmpty ||
                entry.clip.transform != .identity ||
                !entry.clip.cropRect.isFullFrame ||
                entry.clip.blendMode != .normal ||
                entry.clip.transitionIn.type != .none ||
                entry.clip.opacity * entry.track.opacity < 1.0
            }

            var instructions: [any AVVideoCompositionInstructionProtocol] = []
            var cursor: CMTime = .zero
            var previousEntry: VideoClipEntry? = nil

            for entry in sorted {
                let entryStart = entry.effectiveTimeRange.start
                let entryEnd = entry.effectiveTimeRange.end

                // Clamp to avoid going past totalDuration
                let clampedEnd = CMTimeMinimum(entryEnd, totalDuration)

                // Check for transition on this clip
                let hasTransition = entry.clip.transitionIn.type != .none && previousEntry != nil
                let transitionDuration = hasTransition
                    ? CMTime(seconds: min(entry.clip.transitionIn.duration, 1.0), preferredTimescale: 600)
                    : .zero

                // Gap before this clip → black frame (only if no transition fills it)
                if CMTimeCompare(cursor, entryStart) < 0 && !hasTransition {
                    if needsCustomCompositor {
                        let gap = EffectInstruction(
                            timeRange: CMTimeRange(start: cursor, end: entryStart),
                            sourceTrackID: kCMPersistentTrackID_Invalid,
                            effects: []
                        )
                        instructions.append(gap)
                    } else {
                        let gapInstruction = AVMutableVideoCompositionInstruction()
                        gapInstruction.timeRange = CMTimeRange(start: cursor, end: entryStart)
                        gapInstruction.layerInstructions = []
                        gapInstruction.backgroundColor = CGColor(gray: 0, alpha: 1)
                        instructions.append(gapInstruction)
                    }
                }

                // Skip if entry start is past totalDuration
                guard CMTimeCompare(entryStart, totalDuration) < 0 else { break }

                // Insert TransitionInstruction if this clip has a transition and there's a previous clip
                if hasTransition, let prevEntry = previousEntry {
                    let transStart = entryStart
                    let transEnd = CMTimeAdd(entryStart, transitionDuration)

                    // Shorten the previous clip's instruction to end where transition starts
                    // (already handled by cursor — previous instruction ended at entryStart)

                    // Create transition instruction
                    let transType: TransitionType = entry.clip.transitionIn.type
                    let transInstruction = TransitionInstruction(
                        timeRange: CMTimeRange(start: transStart, end: transEnd),
                        fromTrackID: prevEntry.compositionTrack.trackID,
                        toTrackID: entry.compositionTrack.trackID,
                        transitionType: transType
                    )
                    instructions.append(transInstruction)

                    // Main clip instruction starts after the transition
                    let mainStart = transEnd
                    if CMTimeCompare(mainStart, clampedEnd) < 0 {
                        let effectiveOpacity = Float(entry.clip.opacity * entry.track.opacity)
                        let instruction = EffectInstruction(
                            timeRange: CMTimeRange(start: mainStart, end: clampedEnd),
                            sourceTrackID: entry.compositionTrack.trackID,
                            effects: entry.clip.effects,
                            opacity: effectiveOpacity,
                            transform: entry.clip.transform,
                            cropRect: entry.clip.cropRect,
                            blendMode: entry.clip.blendMode
                        )
                        instructions.append(instruction)
                    }
                } else if needsCustomCompositor {
                    // Use EffectInstruction — carries effects, transform, opacity to EffectCompositor
                    let effectiveOpacity = Float(entry.clip.opacity * entry.track.opacity)
                    let instruction = EffectInstruction(
                        timeRange: CMTimeRange(start: entryStart, end: clampedEnd),
                        sourceTrackID: entry.compositionTrack.trackID,
                        effects: entry.clip.effects,
                        opacity: effectiveOpacity,
                        transform: entry.clip.transform,
                        cropRect: entry.clip.cropRect,
                        blendMode: entry.clip.blendMode
                    )
                    instructions.append(instruction)
                } else {
                    // Standard instruction — no effects, fastest path
                    let instruction = AVMutableVideoCompositionInstruction()
                    instruction.timeRange = CMTimeRange(start: entryStart, end: clampedEnd)
                    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: entry.compositionTrack)
                    instruction.layerInstructions = [layerInstruction]
                    instructions.append(instruction)
                }

                previousEntry = entry
                cursor = clampedEnd
            }

            // Trailing gap to fill remainder of composition
            if CMTimeCompare(cursor, totalDuration) < 0 {
                if needsCustomCompositor {
                    let trail = EffectInstruction(
                        timeRange: CMTimeRange(start: cursor, end: totalDuration),
                        sourceTrackID: kCMPersistentTrackID_Invalid,
                        effects: []
                    )
                    instructions.append(trail)
                } else {
                    let trailInstruction = AVMutableVideoCompositionInstruction()
                    trailInstruction.timeRange = CMTimeRange(start: cursor, end: totalDuration)
                    trailInstruction.layerInstructions = []
                    trailInstruction.backgroundColor = CGColor(gray: 0, alpha: 1)
                    instructions.append(trailInstruction)
                }
            }

            // Debug: validate instructions
            var prevEnd: CMTime = .zero
            for (i, instr) in instructions.enumerated() {
                let instrRange = instr.timeRange
                if CMTimeCompare(instrRange.start, prevEnd) != 0 {
                    print("[CompositionBuilder] WARNING: gap/overlap at instruction \(i): prev end=\(prevEnd.seconds)s, this start=\(instrRange.start.seconds)s")
                }
                prevEnd = instrRange.end
                print("[CompositionBuilder] Instruction \(i): \(String(format: "%.1f", instrRange.start.seconds))s-\(String(format: "%.1f", instrRange.end.seconds))s")
            }
            if CMTimeCompare(prevEnd, totalDuration) != 0 {
                print("[CompositionBuilder] WARNING: instructions end at \(prevEnd.seconds)s but composition is \(totalDuration.seconds)s")
            }

            let vidComp = AVMutableVideoComposition()
            vidComp.instructions = instructions
            vidComp.frameDuration = CMTime(value: 1, timescale: 30)
            vidComp.renderSize = renderSize == .zero ? CGSize(width: 1920, height: 1080) : renderSize
            if needsCustomCompositor {
                vidComp.customVideoCompositorClass = EffectCompositor.self
            }
            videoComposition = vidComp
        }

        return Result(
            composition: comp,
            audioMix: audioMix,
            videoComposition: videoComposition,
            duration: comp.duration.seconds  // Use composition's authoritative duration
        )
    }
}
