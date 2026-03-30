import Foundation

/// Decides which short-form layout to use at each point in the video
/// based on speaker diarization data.
///
/// Rules:
/// - Monologue (one speaker for 8+ seconds): Fill on that speaker
/// - Dialogue (multiple speaker changes): Split
/// - Hysteresis: don't switch layout for segments < 3 seconds
public struct LayoutDecider: Sendable {

    public init() {}

    /// Generate layout segments from speaker diarization data.
    public func decide(
        speakerSegments: [SpeakerSegment],
        speakerToFace: [Int: Int],
        minMonologueDuration: TimeInterval = 8.0,
        minLayoutDuration: TimeInterval = 3.0
    ) -> [LayoutSegment] {
        guard !speakerSegments.isEmpty else {
            return [LayoutSegment(startTime: 0, layout: .split)]
        }

        var rawSegments: [LayoutSegment] = []

        // Analyze speaker activity in sliding windows
        var i = 0
        while i < speakerSegments.count {
            let seg = speakerSegments[i]
            let speakerID = speakerIDFromString(seg.speakerID)
            let faceIdx = speakerToFace[speakerID] ?? 0

            // Check if this is a monologue (same speaker for extended time)
            var monologueEnd = seg.range.end
            var j = i + 1
            while j < speakerSegments.count {
                let nextSeg = speakerSegments[j]
                let nextSpeakerID = speakerIDFromString(nextSeg.speakerID)
                if nextSpeakerID == speakerID && nextSeg.range.start - monologueEnd < 2.0 {
                    // Same speaker continues (with up to 2s gap)
                    monologueEnd = nextSeg.range.end
                    j += 1
                } else {
                    break
                }
            }

            let duration = monologueEnd - seg.range.start

            if duration >= minMonologueDuration {
                // Monologue — Fill on this speaker
                rawSegments.append(LayoutSegment(
                    startTime: seg.range.start,
                    layout: .fill(activeSpeaker: faceIdx)
                ))
                i = j
            } else {
                // Short segment — Split (dialogue)
                rawSegments.append(LayoutSegment(
                    startTime: seg.range.start,
                    layout: .split
                ))
                i += 1
            }
        }

        // Apply hysteresis: merge segments shorter than minLayoutDuration
        return applyHysteresis(rawSegments, minDuration: minLayoutDuration)
    }

    // MARK: - Private

    private func applyHysteresis(_ segments: [LayoutSegment], minDuration: TimeInterval) -> [LayoutSegment] {
        guard segments.count > 1 else { return segments }

        var result: [LayoutSegment] = [segments[0]]

        for i in 1..<segments.count {
            let current = segments[i]
            let previous = result[result.count - 1]
            let duration = current.startTime - previous.startTime

            if duration < minDuration {
                // Too short — keep previous layout (skip this switch)
                continue
            }

            result.append(current)
        }

        return result
    }

    private func speakerIDFromString(_ str: String) -> Int {
        let digits = str.filter(\.isNumber)
        return Int(digits) ?? 0
    }
}
