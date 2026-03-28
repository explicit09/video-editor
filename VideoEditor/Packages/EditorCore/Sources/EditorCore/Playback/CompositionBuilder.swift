import Foundation
import AVFoundation

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

        for track in timeline.tracks {
            guard !track.isMuted else { continue }

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

                // Video track
                if track.type != .audio {
                    if let sourceTrack = try? await avAsset.loadTracks(withMediaType: .video).first,
                       let compTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        try? compTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)
                    }
                }

                // Audio track
                if track.type == .audio {
                    if let sourceTrack = try? await avAsset.loadTracks(withMediaType: .audio).first,
                       let compTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        try? compTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)

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

        return Result(
            composition: comp,
            audioMix: audioMix,
            duration: maxDuration.seconds
        )
    }
}
