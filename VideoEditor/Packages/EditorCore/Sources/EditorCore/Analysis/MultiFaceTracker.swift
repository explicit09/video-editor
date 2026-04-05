import Foundation
import AVFoundation
import Vision

/// Tracks ALL faces in a video over time, returning per-face position samples.
/// Used for short-form content: detect two podcast hosts, track each independently.
///
/// Faces are sorted left-to-right by X position and assigned stable indices
/// (face 0 = leftmost, face 1 = next, etc.)
public struct MultiFaceTracker: Sendable {

    public init() {}

    /// Track all faces in the video, returning one FaceTrack per detected face.
    /// Samples every `sampleInterval` seconds.
    public func track(
        url: URL,
        sampleInterval: TimeInterval = 0.5,
        expectedFaces: Int = 2,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil
    ) async throws -> [FaceTrack] {
        let asset = AVURLAsset(url: url)
        let assetDuration = try await asset.load(.duration).seconds
        guard let _ = try await asset.loadTracks(withMediaType: .video).first else {
            throw MultiFaceTrackerError.noVideoTrack
        }

        let rangeStart = startTime ?? 0
        let rangeEnd = endTime ?? assetDuration

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 960, height: 540)

        var frameDetections: [(time: TimeInterval, faces: [DetectedFace])] = []

        var time: TimeInterval = rangeStart
        while time < rangeEnd {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
                time += sampleInterval
                continue
            }

            let faces = detectAllFaces(in: cgImage)
            if !faces.isEmpty {
                frameDetections.append((time: time, faces: faces))
            }

            time += sampleInterval
        }

        guard !frameDetections.isEmpty else {
            return []
        }

        // Determine face count from the mode (most common count across frames)
        let faceCount = determineFaceCount(from: frameDetections, expected: expectedFaces)

        // Build face tracks by assigning faces to stable slots (left-to-right)
        return buildTracks(from: frameDetections, faceCount: faceCount)
    }

    /// Track faces in a specific time range only (for clip extraction).
    public func trackRange(
        url: URL,
        start: TimeInterval,
        end: TimeInterval,
        sampleInterval: TimeInterval = 0.5,
        expectedFaces: Int = 2
    ) async throws -> [FaceTrack] {
        let asset = AVURLAsset(url: url)
        guard let _ = try await asset.loadTracks(withMediaType: .video).first else {
            throw MultiFaceTrackerError.noVideoTrack
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 960, height: 540)

        var frameDetections: [(time: TimeInterval, faces: [DetectedFace])] = []

        var time = start
        while time < end {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
                time += sampleInterval
                continue
            }

            let faces = detectAllFaces(in: cgImage)
            if !faces.isEmpty {
                frameDetections.append((time: time, faces: faces))
            }

            time += sampleInterval
        }

        guard !frameDetections.isEmpty else { return [] }
        let faceCount = determineFaceCount(from: frameDetections, expected: expectedFaces)
        return buildTracks(from: frameDetections, faceCount: faceCount)
    }
}

// MARK: - Face Detection

private struct DetectedFace {
    let center: CGPoint    // Normalized 0-1, Vision coordinates (bottom-left origin)
    let size: CGFloat      // Normalized width of bounding box
}

extension MultiFaceTracker {

    /// Detect all faces in an image, sorted left-to-right by X position.
    private func detectAllFaces(in image: CGImage) -> [DetectedFace] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        guard let _ = try? handler.perform([request]),
              let results = request.results, !results.isEmpty else {
            return []
        }

        return results
            .map { face in
                DetectedFace(
                    center: CGPoint(
                        x: face.boundingBox.midX,
                        y: 1.0 - face.boundingBox.midY // Convert to top-left origin
                    ),
                    size: face.boundingBox.width
                )
            }
            .sorted { $0.center.x < $1.center.x } // Left to right
    }
}

// MARK: - Track Building

extension MultiFaceTracker {

    /// Determine how many faces to track based on detection frequency.
    private func determineFaceCount(
        from detections: [(time: TimeInterval, faces: [DetectedFace])],
        expected: Int
    ) -> Int {
        // Count how many frames have each face count
        var countFreq: [Int: Int] = [:]
        for d in detections {
            countFreq[d.faces.count, default: 0] += 1
        }

        // If the expected count appears in >30% of frames, use it
        let totalFrames = detections.count
        if let expectedFreq = countFreq[expected], Double(expectedFreq) / Double(totalFrames) > 0.3 {
            return expected
        }

        // Otherwise use the most common count
        return countFreq.max(by: { $0.value < $1.value })?.key ?? expected
    }

    /// Build FaceTrack arrays from raw detections.
    /// Assigns faces to slots by X position (leftmost = index 0).
    private func buildTracks(
        from detections: [(time: TimeInterval, faces: [DetectedFace])],
        faceCount: Int
    ) -> [FaceTrack] {
        guard faceCount > 0 else { return [] }

        var tracks = (0..<faceCount).map { _ in FaceTrack() }

        // Previous positions for smoothing
        var prevCenters: [CGPoint?] = Array(repeating: nil, count: faceCount)

        for detection in detections {
            let faces = detection.faces

            if faces.count == faceCount {
                // Exact match — assign left-to-right
                for (i, face) in faces.enumerated() {
                    let smoothed = smooth(current: face.center, previous: prevCenters[i])
                    tracks[i].samples.append(FaceSample(
                        time: detection.time,
                        center: smoothed,
                        size: face.size
                    ))
                    prevCenters[i] = smoothed
                }
            } else if faces.count > faceCount {
                // More faces than expected — pick the largest N, sorted left-to-right
                let largest = faces
                    .sorted { $0.size > $1.size }
                    .prefix(faceCount)
                    .sorted { $0.center.x < $1.center.x }

                for (i, face) in largest.enumerated() {
                    let smoothed = smooth(current: face.center, previous: prevCenters[i])
                    tracks[i].samples.append(FaceSample(
                        time: detection.time,
                        center: smoothed,
                        size: face.size
                    ))
                    prevCenters[i] = smoothed
                }
            } else {
                // Fewer faces than expected — assign to nearest unclaimed slot
                var claimed: Set<Int> = []
                for face in faces {
                    let bestSlot = nearestSlot(for: face.center, prevCenters: prevCenters, faceCount: faceCount, excluding: claimed)
                    claimed.insert(bestSlot)
                    let smoothed = smooth(current: face.center, previous: prevCenters[bestSlot])
                    tracks[bestSlot].samples.append(FaceSample(
                        time: detection.time,
                        center: smoothed,
                        size: face.size
                    ))
                    prevCenters[bestSlot] = smoothed
                }
            }
        }

        return tracks
    }

    /// Smooth face position: 60% previous + 40% current (same as AutoReframer).
    private func smooth(current: CGPoint, previous: CGPoint?) -> CGPoint {
        guard let prev = previous else { return current }
        return CGPoint(
            x: prev.x * 0.6 + current.x * 0.4,
            y: prev.y * 0.6 + current.y * 0.4
        )
    }

    /// Find the nearest existing slot for a detected face based on X distance.
    private func nearestSlot(for center: CGPoint, prevCenters: [CGPoint?], faceCount: Int, excluding claimed: Set<Int> = []) -> Int {
        var bestSlot = 0
        var bestDist = CGFloat.greatestFiniteMagnitude

        for i in 0..<faceCount where !claimed.contains(i) {
            let slotX = prevCenters[i]?.x ?? (CGFloat(i) + 0.5) / CGFloat(faceCount)
            let dist = abs(center.x - slotX)
            if dist < bestDist {
                bestDist = dist
                bestSlot = i
            }
        }

        return bestSlot
    }
}

// MARK: - Error

public enum MultiFaceTrackerError: Error, LocalizedError {
    case noVideoTrack

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack: "No video track found"
        }
    }
}
