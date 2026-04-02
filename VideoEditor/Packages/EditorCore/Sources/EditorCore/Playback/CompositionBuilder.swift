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
    static let minimumRenderableClipDuration: TimeInterval = 0.02

    public enum MediaURLMode {
        case preview  // use proxyURL if available
        case export   // always use sourceURL
    }

    public struct Result {
        public let composition: AVMutableComposition
        public let audioMix: AVAudioMix?
        public let videoComposition: AVVideoComposition?
        public let duration: TimeInterval

        /// Quick sanity check — false means the composition is likely broken.
        public var isValid: Bool {
            let trackCount = composition.tracks.count
            let hasVideoTracks = !composition.tracks(withMediaType: .video).isEmpty
            return trackCount > 0
                && duration > 0
                && (!hasVideoTracks || videoComposition != nil)
        }
    }

    public init() {}

    static func resolvedMediaURL(
        for asset: MediaAsset,
        mode: MediaURLMode,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        switch mode {
        case .preview:
            if let proxyURL = asset.proxyURL, fileExists(proxyURL.path) {
                return proxyURL
            }
            return asset.sourceURL
        case .export:
            return asset.sourceURL
        }
    }

    static func resolvedAudioURL(
        for asset: MediaAsset,
        mode: MediaURLMode
    ) -> URL {
        switch mode {
        case .preview:
            // Keep preview audio on the source file. Proxy audio encodes can
            // drift at hard cut boundaries, which shows up after silence removal.
            return asset.sourceURL
        case .export:
            return asset.sourceURL
        }
    }

    static func shouldBuildClip(_ clip: Clip) -> Bool {
        clip.timelineRange.duration >= minimumRenderableClipDuration
        && clip.sourceRange.duration >= minimumRenderableClipDuration
    }

    static func captionWords(for clip: Clip, asset: MediaAsset) -> [TranscriptWord] {
        let sourceWords = asset.analysis?.transcript ?? clip.metadata.transcriptSegment?.words ?? []
        guard !sourceWords.isEmpty else { return [] }

        let sourceStart = clip.sourceRange.start
        let sourceEnd = clip.sourceRange.end
        let timelineStart = clip.timelineRange.start
        let speed = max(clip.speed, 0.1)

        return sourceWords.compactMap { word in
            let clampedStart = max(word.start, sourceStart)
            let clampedEnd = min(word.end, sourceEnd)
            guard clampedEnd > clampedStart else { return nil }

            let exportStart = timelineStart + ((clampedStart - sourceStart) / speed)
            let exportEnd = timelineStart + ((clampedEnd - sourceStart) / speed)
            guard exportEnd > exportStart else { return nil }

            return TranscriptWord(
                word: word.word,
                lemma: word.lemma,
                start: exportStart,
                end: exportEnd,
                confidence: word.confidence
            )
        }
    }

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
        urlMode: MediaURLMode = .preview,
        broadcastOverlay: BroadcastOverlayConfig? = nil,
        shortFormConfig: ShortFormConfig? = nil,
        captionStyle: CaptionStyler.CaptionStyle = .standard
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

            let clips = track.clips.sorted {
                if $0.timelineRange.start != $1.timelineRange.start {
                    return $0.timelineRange.start < $1.timelineRange.start
                }
                return $0.timelineRange.end < $1.timelineRange.end
            }

            for clip in clips where Self.shouldBuildClip(clip) {
                guard let mediaAsset = assets.first(where: { $0.id == clip.assetID }) else { continue }

                let mediaURL = Self.resolvedMediaURL(for: mediaAsset, mode: urlMode)
                let audioURL = Self.resolvedAudioURL(for: mediaAsset, mode: urlMode)
                let avAsset = AVURLAsset(url: mediaURL)
                let audioAsset = AVURLAsset(url: audioURL)

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
                        if let audioSourceTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first {
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
                    if let sourceTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first {
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
            let captionWordsByClipID: [UUID: [TranscriptWord]] = Dictionary(
                uniqueKeysWithValues: sorted.map { entry in
                    let asset = assets.first(where: { $0.id == entry.clip.assetID })
                    let captionWords = asset.map { Self.captionWords(for: entry.clip, asset: $0) } ?? []
                    return (entry.clip.id, captionWords)
                }
            )
            let hasCaptionWords = captionWordsByClipID.values.contains { !$0.isEmpty }

            // Determine if any clip needs the custom compositor
            print("[CompositionBuilder] shortFormConfig: \(shortFormConfig?.isEnabled ?? false) faceTracks: \(shortFormConfig?.faceTracks.count ?? 0), broadcastOverlay: \(broadcastOverlay?.isEnabled ?? false), needsCustom will be: \(broadcastOverlay?.isEnabled == true || shortFormConfig?.isEnabled == true)")
            let needsCustomCompositor = broadcastOverlay?.isEnabled == true || shortFormConfig?.isEnabled == true || sorted.contains { entry in
                !entry.clip.effects.isEmpty ||
                entry.clip.transform != .identity ||
                !entry.clip.cropRect.isFullFrame ||
                entry.clip.blendMode != .normal ||
                entry.clip.transitionIn.type != .none ||
                entry.clip.opacity * entry.track.opacity < 1.0
            } || hasCaptionWords

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
                            effects: [],
                            broadcastOverlay: broadcastOverlay,
                            shortFormConfig: shortFormConfig,
                            captionStyle: captionStyle
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
                            blendMode: entry.clip.blendMode,
                            broadcastOverlay: broadcastOverlay,
                            shortFormConfig: shortFormConfig,
                            captionStyle: captionStyle,
                            captionWords: captionWordsByClipID[entry.clip.id] ?? []
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
                        blendMode: entry.clip.blendMode,
                        broadcastOverlay: broadcastOverlay,
                        shortFormConfig: shortFormConfig,
                        captionStyle: captionStyle,
                        captionWords: captionWordsByClipID[entry.clip.id] ?? []
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
                        effects: [],
                        broadcastOverlay: broadcastOverlay,
                        shortFormConfig: shortFormConfig
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
            // Use short-form output size if active, otherwise source size
            if let sfConfig = shortFormConfig, sfConfig.isEnabled {
                vidComp.renderSize = sfConfig.outputAspect.size
            } else {
                vidComp.renderSize = renderSize == .zero ? CGSize(width: 1920, height: 1080) : renderSize
            }
            if needsCustomCompositor {
                vidComp.customVideoCompositorClass = EffectCompositor.self
            }
            videoComposition = vidComp
        }

        let result = Result(
            composition: comp,
            audioMix: audioMix,
            videoComposition: videoComposition,
            duration: comp.duration.seconds  // Use composition's authoritative duration
        )

        // Diagnostic validation — log warnings but never block
        if comp.tracks.isEmpty {
            print("[CompositionBuilder] WARNING: composition has 0 tracks")
        }
        if result.duration <= 0 {
            print("[CompositionBuilder] WARNING: composition duration is \(result.duration)s")
        }
        if !comp.tracks(withMediaType: .video).isEmpty && videoComposition == nil {
            print("[CompositionBuilder] WARNING: video tracks present but videoComposition is nil")
        }

        return result
    }

}
