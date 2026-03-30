import Foundation

/// Maps speaker diarization IDs to face track indices.
/// Simple heuristic: at the first moment each speaker talks,
/// the face closest to that speaker's expected position is assigned.
///
/// For a two-person podcast: Speaker 0 = left face (index 0),
/// Speaker 1 = right face (index 1). This is determined once and fixed.
public struct SpeakerFaceMapper: Sendable {

    public init() {}

    /// Map speaker IDs to face indices.
    /// - Parameters:
    ///   - speakerSegments: Diarization segments with speaker IDs and time ranges
    ///   - faceTracks: Detected face tracks from MultiFaceTracker
    /// - Returns: Dictionary mapping speaker ID → face track index
    public func map(
        speakerSegments: [SpeakerSegment],
        faceTracks: [FaceTrack]
    ) -> [Int: Int] {
        guard !faceTracks.isEmpty, !speakerSegments.isEmpty else { return [:] }

        // For two faces: left = index 0, right = index 1
        // Speaker who talks first while on the left = Speaker for face 0
        // This works because podcast hosts don't switch seats

        let faceCount = faceTracks.count
        var mapping: [Int: Int] = [:]

        // Get unique speaker IDs in order of first appearance
        var seenSpeakers: [Int] = []
        for seg in speakerSegments {
            let speakerID = speakerIDFromString(seg.speakerID)
            if !seenSpeakers.contains(speakerID) {
                seenSpeakers.append(speakerID)
            }
            if seenSpeakers.count >= faceCount { break }
        }

        // Simple assignment: first speaker seen → face 0 (leftmost), second → face 1, etc.
        // This works because in most podcast recordings, the hosts are introduced left-to-right.
        for (i, speakerID) in seenSpeakers.prefix(faceCount).enumerated() {
            mapping[speakerID] = i
        }

        return mapping
    }

    /// Extract numeric speaker ID from diarization string (e.g., "Speaker 0" → 0).
    private func speakerIDFromString(_ str: String) -> Int {
        let digits = str.filter(\.isNumber)
        return Int(digits) ?? 0
    }
}
