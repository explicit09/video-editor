import Foundation

/// Maps speaker diarization IDs to face track indices.
/// Simple heuristic: at the first moment each speaker talks,
/// the face closest to that speaker's expected position is assigned.
///
/// For a two-person podcast: Speaker 0 = left face (index 0),
/// Speaker 1 = right face (index 1). This is determined once and fixed.
public struct SpeakerFaceMapper: Sendable {

    public init() {}

    /// Map speaker IDs to face indices by first-appearance order.
    /// Face 0 = leftmost in frame, face 1 = rightmost (from MultiFaceTracker).
    /// First speaker seen in diarization → face 0, second → face 1, etc.
    /// Deepgram speaker IDs are arbitrary, so we use appearance order not numeric value.
    public func map(
        speakerSegments: [SpeakerSegment],
        faceTracks: [FaceTrack]
    ) -> [Int: Int] {
        guard !faceTracks.isEmpty, !speakerSegments.isEmpty else { return [:] }

        let faceCount = faceTracks.count
        var mapping: [Int: Int] = [:]
        var nextSlot = 0

        for seg in speakerSegments {
            let id = speakerIDFromString(seg.speakerID)
            if mapping[id] == nil {
                mapping[id] = nextSlot
                nextSlot += 1
                if nextSlot >= faceCount { break }
            }
        }

        return mapping
    }

    /// Extract numeric speaker ID from diarization string (e.g., "Speaker 0" → 0).
    private func speakerIDFromString(_ str: String) -> Int {
        let digits = str.filter(\.isNumber)
        return Int(digits) ?? 0
    }
}
