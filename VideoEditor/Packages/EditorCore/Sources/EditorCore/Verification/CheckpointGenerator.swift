import Foundation

/// A point in the export to verify against the expected source content.
public struct VerificationCheckpoint: Sendable {
    public enum CheckType: Sendable {
        case content      // Verify audio/video matches expected source
        case silence      // Verify gap is silent
        case effectApplied // Verify effect changed the content
    }

    public let exportTime: TimeInterval
    public let checkType: CheckType
    public let clipID: UUID?
    public let assetID: UUID?
    public let expectedSourceTime: TimeInterval?
    public let speed: Double
    public let effects: [EffectInstance]
    public let label: String

    public init(
        exportTime: TimeInterval,
        checkType: CheckType,
        clipID: UUID? = nil,
        assetID: UUID? = nil,
        expectedSourceTime: TimeInterval? = nil,
        speed: Double = 1.0,
        effects: [EffectInstance] = [],
        label: String = ""
    ) {
        self.exportTime = exportTime
        self.checkType = checkType
        self.clipID = clipID
        self.assetID = assetID
        self.expectedSourceTime = expectedSourceTime
        self.speed = speed
        self.effects = effects
        self.label = label
    }
}

/// Generates verification checkpoints from a Timeline.
/// Pure logic — no I/O, no media access.
public struct CheckpointGenerator: Sendable {

    /// Margin from clip boundaries to avoid transition artifacts.
    private let boundaryMargin: TimeInterval = 0.2

    public init() {}

    /// Generate checkpoints for all clips and gaps in the timeline.
    public func generate(from timeline: Timeline) -> [VerificationCheckpoint] {
        var checkpoints: [VerificationCheckpoint] = []

        // Collect all clips with their track context, sorted by timeline start
        var allClipEntries: [(clip: Clip, track: Track)] = []
        for track in timeline.tracks where !track.isMuted {
            for clip in track.clips {
                allClipEntries.append((clip, track))
            }
        }
        allClipEntries.sort { $0.clip.timelineRange.start < $1.clip.timelineRange.start }

        // Generate content checkpoints per clip
        for entry in allClipEntries {
            let clip = entry.clip
            let duration = clip.timelineRange.duration
            guard duration > 0.1 else { continue }

            let margin = min(boundaryMargin, duration * 0.2)

            // Near start
            let startTime = clip.timelineRange.start + margin
            checkpoints.append(contentCheckpoint(clip: clip, at: startTime, label: "\(clip.metadata.label ?? "Clip") start"))

            // Midpoint
            let midTime = (clip.timelineRange.start + clip.timelineRange.end) / 2
            checkpoints.append(contentCheckpoint(clip: clip, at: midTime, label: "\(clip.metadata.label ?? "Clip") mid"))

            // Near end
            let endTime = clip.timelineRange.end - margin
            if endTime > startTime + 0.1 {
                checkpoints.append(contentCheckpoint(clip: clip, at: endTime, label: "\(clip.metadata.label ?? "Clip") end"))
            }

            // Extra checkpoints for speed-changed clips (errors compound over time)
            if clip.speed != 1.0 && duration > 2.0 {
                let q1 = clip.timelineRange.start + duration * 0.25
                let q3 = clip.timelineRange.start + duration * 0.75
                checkpoints.append(contentCheckpoint(clip: clip, at: q1, label: "\(clip.metadata.label ?? "Clip") q1"))
                checkpoints.append(contentCheckpoint(clip: clip, at: q3, label: "\(clip.metadata.label ?? "Clip") q3"))
            }
        }

        // Generate gap/silence checkpoints
        let gaps = findGaps(in: allClipEntries.map(\.clip), duration: timeline.duration)
        for gap in gaps where gap.duration > 0.1 {
            let midGap = (gap.start + gap.end) / 2
            checkpoints.append(VerificationCheckpoint(
                exportTime: midGap,
                checkType: .silence,
                label: "Gap \(String(format: "%.1f", gap.start))s-\(String(format: "%.1f", gap.end))s"
            ))
        }

        return checkpoints.sorted { $0.exportTime < $1.exportTime }
    }

    // MARK: - Private

    private func contentCheckpoint(clip: Clip, at exportTime: TimeInterval, label: String) -> VerificationCheckpoint {
        let offsetInClip = exportTime - clip.timelineRange.start
        let expectedSourceTime = clip.sourceRange.start + offsetInClip * clip.speed

        return VerificationCheckpoint(
            exportTime: exportTime,
            checkType: clip.effects.isEmpty ? .content : .effectApplied,
            clipID: clip.id,
            assetID: clip.assetID,
            expectedSourceTime: expectedSourceTime,
            speed: clip.speed,
            effects: clip.effects,
            label: label
        )
    }

    private func findGaps(in clips: [Clip], duration: TimeInterval) -> [TimeRange] {
        guard !clips.isEmpty else {
            return duration > 0 ? [TimeRange(start: 0, end: duration)] : []
        }

        let sorted = clips.sorted { $0.timelineRange.start < $1.timelineRange.start }
        var gaps: [TimeRange] = []
        var cursor: TimeInterval = 0

        for clip in sorted {
            if clip.timelineRange.start > cursor + 0.05 {
                gaps.append(TimeRange(start: cursor, end: clip.timelineRange.start))
            }
            cursor = max(cursor, clip.timelineRange.end)
        }

        if cursor < duration - 0.05 {
            gaps.append(TimeRange(start: cursor, end: duration))
        }

        return gaps
    }
}
