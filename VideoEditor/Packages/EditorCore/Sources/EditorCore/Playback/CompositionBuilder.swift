import Foundation
import AVFoundation
import CoreImage

/// Builds AVComposition + AVAudioMix from Timeline.
/// Shared between PlaybackEngine (proxy URLs) and ExportEngine (source URLs).
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

    /// Build composition from timeline.
    public func build(
        from timeline: Timeline,
        assets: [MediaAsset],
        urlMode: MediaURLMode = .preview
    ) async -> Result {
        let comp = AVMutableComposition()
        var maxDuration: CMTime = .zero
        var audioParams: [AVMutableAudioMixInputParameters] = []
        var videoInstructions: [AVMutableVideoCompositionLayerInstruction] = []
        var effectInstructions: [EffectInstruction] = []
        var hasOpacityChanges = false
        var hasEffects = false
        var renderSize: CGSize = CGSize(width: 1920, height: 1080)

        let anySoloed = timeline.tracks.contains { $0.isSoloed }

        for track in timeline.tracks {
            // Skip muted tracks. If any track is soloed, skip non-soloed tracks.
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

                let insertTime = CMTime(seconds: clip.timelineRange.start, preferredTimescale: 600)
                let sourceStart = CMTime(seconds: clip.sourceRange.start, preferredTimescale: 600)
                let sourceDuration = CMTime(seconds: max(clip.sourceRange.duration, 0), preferredTimescale: 600)
                let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)
                let effectiveSpeed = clip.speed

                // Video track
                if track.type != .audio {
                    if let sourceTrack = try? await avAsset.loadTracks(withMediaType: .video).first,
                       let compTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        try? compTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)

                        // Apply speed change via time scaling
                        if effectiveSpeed != 1.0 {
                            let insertedRange = CMTimeRange(start: insertTime, duration: sourceDuration)
                            let scaledDuration = CMTime(seconds: sourceDuration.seconds / effectiveSpeed, preferredTimescale: 600)
                            compTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                        }

                        // Track natural size for render
                        if let naturalSize = try? await sourceTrack.load(.naturalSize), naturalSize.width > 0 {
                            if naturalSize.width > renderSize.width { renderSize = naturalSize }
                        }

                        // Check if this clip needs effects processing
                        let effectiveOpacity = clip.opacity * track.opacity
                        let activeEffects = clip.effects.filter(\.isEnabled)
                        let needsTransform = clip.transform != .identity
                        let needsEffects = !activeEffects.isEmpty || effectiveOpacity < 1.0 || needsTransform

                        if needsEffects {
                            // Create per-clip effect instruction for custom compositor
                            let clipDuration = effectiveSpeed != 1.0
                                ? CMTime(seconds: sourceDuration.seconds / effectiveSpeed, preferredTimescale: 600)
                                : sourceDuration
                            let effectInstruction = EffectInstruction(
                                timeRange: CMTimeRange(start: insertTime, duration: clipDuration),
                                sourceTrackID: compTrack.trackID,
                                effects: activeEffects,
                                opacity: Float(effectiveOpacity),
                                transform: clip.transform
                            )
                            effectInstructions.append(effectInstruction)
                            hasEffects = true
                        } else if effectiveOpacity < 1.0 {
                            // Fallback: simple opacity via layer instruction
                            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
                            layerInstruction.setOpacity(Float(effectiveOpacity), at: insertTime)
                            videoInstructions.append(layerInstruction)
                            hasOpacityChanges = true
                        }
                    }
                }

                // Audio track
                if track.type == .audio {
                    if let sourceTrack = try? await avAsset.loadTracks(withMediaType: .audio).first,
                       let compTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        try? compTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)

                        if effectiveSpeed != 1.0 {
                            let insertedRange = CMTimeRange(start: insertTime, duration: sourceDuration)
                            let scaledDuration = CMTime(seconds: sourceDuration.seconds / effectiveSpeed, preferredTimescale: 600)
                            compTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                        }

                        // Apply volume: clip.volume * track.volume
                        let effectiveVolume = Float(clip.volume * track.volume)
                        if effectiveVolume != 1.0 {
                            let params = AVMutableAudioMixInputParameters(track: compTrack)
                            params.setVolume(effectiveVolume, at: .zero)
                            audioParams.append(params)
                        }
                    }
                }

                let clipEnd = CMTimeAdd(insertTime, sourceDuration)
                if CMTimeCompare(clipEnd, maxDuration) > 0 {
                    maxDuration = clipEnd
                }
            }
        }

        // Build audio mix if any volume adjustments
        var audioMix: AVAudioMix?
        if !audioParams.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioParams
            audioMix = mix
        }

        // Build video composition
        var videoComposition: AVVideoComposition?
        if hasEffects, !effectInstructions.isEmpty {
            // Use custom compositor for effects (CIFilter pipeline)
            let vidComp = AVMutableVideoComposition()
            vidComp.customVideoCompositorClass = EffectCompositor.self
            vidComp.instructions = effectInstructions
            vidComp.frameDuration = CMTime(value: 1, timescale: 30)
            vidComp.renderSize = renderSize
            videoComposition = vidComp
        } else if hasOpacityChanges, !videoInstructions.isEmpty {
            // Simple opacity-only path (no custom compositor needed)
            let mainInstruction = AVMutableVideoCompositionInstruction()
            mainInstruction.timeRange = CMTimeRange(start: .zero, duration: maxDuration)
            mainInstruction.layerInstructions = videoInstructions

            let vidComp = AVMutableVideoComposition()
            vidComp.instructions = [mainInstruction]
            vidComp.frameDuration = CMTime(value: 1, timescale: 30)
            vidComp.renderSize = renderSize
            videoComposition = vidComp
        }

        return Result(
            composition: comp,
            audioMix: audioMix,
            videoComposition: videoComposition,
            duration: maxDuration.seconds
        )
    }
}
