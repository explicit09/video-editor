import Foundation
import CoreGraphics

// MARK: - Short-Form Configuration

/// Configuration for recomposing video into vertical short-form layouts.
/// Attached to EffectInstruction, read by the compositor per-frame.
public struct ShortFormConfig: Codable, Sendable {
    public var isEnabled: Bool
    public var outputAspect: OutputAspect
    public var faceTracks: [FaceTrack]
    public var speakerToFace: [Int: Int]     // Speaker diarization ID → face track index
    public var layoutSegments: [LayoutSegment]
    public var sourceTimeOffset: TimeInterval  // Added to timeline time to get source time for face lookups
    public var captionWords: [TranscriptWord] // Words for karaoke captions (source-time-relative)
    public var dividerWidth: CGFloat         // Pixels between stacked speakers (at 1080 reference)
    public var captionRegionHeight: CGFloat  // Bottom caption area height (at 1920 reference)

    public init(
        isEnabled: Bool = false,
        outputAspect: OutputAspect = .vertical9x16,
        faceTracks: [FaceTrack] = [],
        speakerToFace: [Int: Int] = [:],
        layoutSegments: [LayoutSegment] = [],
        sourceTimeOffset: TimeInterval = 0,
        captionWords: [TranscriptWord] = [],
        dividerWidth: CGFloat = 4,
        captionRegionHeight: CGFloat = 200
    ) {
        self.isEnabled = isEnabled
        self.outputAspect = outputAspect
        self.faceTracks = faceTracks
        self.speakerToFace = speakerToFace
        self.layoutSegments = layoutSegments
        self.sourceTimeOffset = sourceTimeOffset
        self.captionWords = captionWords
        self.dividerWidth = dividerWidth
        self.captionRegionHeight = captionRegionHeight
    }

    public static let empty = ShortFormConfig()

    /// Get the active layout at a given time.
    public func layoutAt(time: TimeInterval) -> ShortFormLayout {
        // Find the last segment that started before this time
        for segment in layoutSegments.reversed() {
            if segment.startTime <= time {
                return segment.layout
            }
        }
        return .split // Default to split for two-person content
    }

    /// Get interpolated face center for a face track at a given time.
    public func faceCenterAt(faceIndex: Int, time: TimeInterval) -> CGPoint? {
        guard faceIndex < faceTracks.count else { return nil }
        return faceTracks[faceIndex].interpolatedCenter(at: time)
    }
}

// MARK: - Output Aspect

public enum OutputAspect: String, Codable, Sendable {
    case vertical9x16   // 1080x1920 — TikTok, Shorts, Reels
    case square1x1      // 1080x1080 — Instagram feed, X
    case portrait4x5    // 1080x1350 — Instagram feed

    public var size: CGSize {
        switch self {
        case .vertical9x16: CGSize(width: 1080, height: 1920)
        case .square1x1: CGSize(width: 1080, height: 1080)
        case .portrait4x5: CGSize(width: 1080, height: 1350)
        }
    }

    public var aspectRatio: CGFloat {
        size.width / size.height
    }
}

// MARK: - Layout

public enum ShortFormLayout: Codable, Sendable, Equatable {
    case split                          // Two speakers stacked 50/50
    case fill(activeSpeaker: Int)       // Single speaker fills frame
    case sidebar(activeSpeaker: Int)    // Active speaker 2/3, other 1/3
}

public struct LayoutSegment: Codable, Sendable, Equatable {
    public var startTime: TimeInterval
    public var layout: ShortFormLayout

    public init(startTime: TimeInterval, layout: ShortFormLayout) {
        self.startTime = startTime
        self.layout = layout
    }
}

// MARK: - Face Track

/// Pre-computed face positions over time for one person.
public struct FaceTrack: Codable, Sendable, Equatable {
    public var samples: [FaceSample]

    public init(samples: [FaceSample] = []) {
        self.samples = samples
    }

    /// Interpolate face center at a given time (smooth between samples).
    public func interpolatedCenter(at time: TimeInterval) -> CGPoint? {
        guard !samples.isEmpty else { return nil }

        // Before first sample
        if time <= samples[0].time { return samples[0].center }

        // After last sample
        if time >= samples[samples.count - 1].time {
            return samples[samples.count - 1].center
        }

        // Find bracketing samples and interpolate
        for i in 0..<(samples.count - 1) {
            let a = samples[i]
            let b = samples[i + 1]
            if time >= a.time && time < b.time {
                let t = CGFloat((time - a.time) / (b.time - a.time))
                return CGPoint(
                    x: a.center.x + (b.center.x - a.center.x) * t,
                    y: a.center.y + (b.center.y - a.center.y) * t
                )
            }
        }

        return samples.last?.center
    }
}

public struct FaceSample: Codable, Sendable, Equatable {
    public var time: TimeInterval
    public var center: CGPoint      // Normalized 0-1 within source frame
    public var size: CGFloat        // Normalized face width relative to source

    public init(time: TimeInterval, center: CGPoint, size: CGFloat) {
        self.time = time
        self.center = center
        self.size = size
    }
}

// CGPoint is Codable in CoreGraphics on macOS 14+
