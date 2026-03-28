import Foundation
import AVFoundation

/// Generates volume ramp parameters for audio ducking.
/// Lowers music track volume when speech is detected on the dialogue track.
public struct AudioDucker: Sendable {

    public struct DuckRegion: Sendable {
        public let startTime: TimeInterval
        public let endTime: TimeInterval

        public init(startTime: TimeInterval, endTime: TimeInterval) {
            self.startTime = startTime
            self.endTime = endTime
        }
    }

    /// Target volume for ducked regions (0.0 = silent, 1.0 = full)
    public let duckLevel: Float
    /// Fade-in/out duration for smooth transitions
    public let fadeDuration: TimeInterval

    public init(duckLevel: Float = 0.2, fadeDuration: TimeInterval = 0.3) {
        self.duckLevel = duckLevel
        self.fadeDuration = fadeDuration
    }

    /// Create duck regions from transcript word timestamps.
    /// Groups nearby words into continuous speech regions.
    public func regionsFromTranscript(_ words: [TranscriptWord], gapThreshold: TimeInterval = 0.5) -> [DuckRegion] {
        guard !words.isEmpty else { return [] }

        var regions: [DuckRegion] = []
        var regionStart = words[0].start
        var regionEnd = words[0].end

        for word in words.dropFirst() {
            if word.start - regionEnd > gapThreshold {
                // Gap detected — close current region
                regions.append(DuckRegion(startTime: regionStart, endTime: regionEnd))
                regionStart = word.start
            }
            regionEnd = word.end
        }

        // Close last region
        regions.append(DuckRegion(startTime: regionStart, endTime: regionEnd))
        return regions
    }

    /// Apply ducking volume ramps to an AVMutableAudioMixInputParameters.
    /// Call this for the music track's audio mix parameters.
    public func applyDucking(
        to params: AVMutableAudioMixInputParameters,
        regions: [DuckRegion],
        baseVolume: Float = 1.0
    ) {
        // Start at full volume
        params.setVolume(baseVolume, at: .zero)

        for region in regions {
            let fadeInStart = CMTime(seconds: max(0, region.startTime - fadeDuration), preferredTimescale: 600)
            let duckStart = CMTime(seconds: region.startTime, preferredTimescale: 600)
            let duckEnd = CMTime(seconds: region.endTime, preferredTimescale: 600)
            let fadeOutEnd = CMTime(seconds: region.endTime + fadeDuration, preferredTimescale: 600)

            // Ramp down to duck level
            params.setVolumeRamp(fromStartVolume: baseVolume, toEndVolume: duckLevel,
                                timeRange: CMTimeRange(start: fadeInStart, end: duckStart))

            // Stay ducked
            params.setVolume(duckLevel, at: duckStart)

            // Ramp back up
            params.setVolumeRamp(fromStartVolume: duckLevel, toEndVolume: baseVolume,
                                timeRange: CMTimeRange(start: duckEnd, end: fadeOutEnd))
        }
    }
}
