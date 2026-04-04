import Foundation
import Vision
import AVFoundation
import CoreImage

/// Tracks objects or faces across video frames using Vision framework.
/// Returns per-frame bounding box positions for attaching graphics or effects.
public struct ObjectTracker: Sendable {

    public struct TrackingResult: Sendable {
        /// Per-frame positions (normalized 0-1 coordinates)
        public let positions: [(time: TimeInterval, rect: CGRect, confidence: Float)]
        /// Whether tracking was lost at any point
        public let trackingLost: Bool
    }

    public init() {}

    /// Track a rectangular region across frames.
    /// - Parameters:
    ///   - url: Video file URL
    ///   - initialRect: Starting bounding box (normalized coordinates)
    ///   - startTime: When tracking begins
    ///   - duration: How long to track
    public func track(
        url: URL,
        initialRect: CGRect,
        startTime: TimeInterval = 0,
        duration: TimeInterval? = nil
    ) async -> TrackingResult? {
        let asset = AVURLAsset(url: url)
        guard let videoDuration = try? await asset.load(.duration).seconds else { return nil }

        let trackDuration = duration ?? (videoDuration - startTime)
        let endTime = startTime + trackDuration

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        var positions: [(time: TimeInterval, rect: CGRect, confidence: Float)] = []
        var trackingLost = false
        let sampleInterval: TimeInterval = 1.0 / 15.0 // 15fps tracking

        // Initialize tracking request
        let observation = VNDetectedObjectObservation(boundingBox: initialRect)

        var currentObservation: VNDetectedObjectObservation = observation
        var time = startTime

        while time < endTime {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
                time += sampleInterval
                continue
            }

            let trackRequest = VNTrackObjectRequest(detectedObjectObservation: currentObservation)
            trackRequest.trackingLevel = .fast

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([trackRequest])

            if let result = trackRequest.results?.first as? VNDetectedObjectObservation {
                let rect = result.boundingBox
                let confidence = result.confidence

                positions.append((time: time, rect: rect, confidence: confidence))

                if confidence < 0.3 {
                    trackingLost = true
                }

                currentObservation = result
            } else {
                trackingLost = true
                // Use last known position
                if let lastPos = positions.last {
                    positions.append((time: time, rect: lastPos.rect, confidence: 0))
                }
            }

            time += sampleInterval
        }

        return TrackingResult(positions: positions, trackingLost: trackingLost)
    }

    /// Track the largest face across frames.
    public func trackFace(url: URL, startTime: TimeInterval = 0, duration: TimeInterval? = nil) async -> TrackingResult? {
        let asset = AVURLAsset(url: url)
        let cmTime = CMTime(seconds: startTime, preferredTimescale: 600)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        guard let firstFrame = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
            return nil
        }

        // Detect initial face
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: firstFrame, options: [:])
        try? handler.perform([faceRequest])

        guard let face = faceRequest.results?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) else {
            return nil
        }

        // Track from detected face position
        return await track(url: url, initialRect: face.boundingBox, startTime: startTime, duration: duration)
    }
}
