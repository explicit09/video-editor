import Foundation
import AVFoundation
import Vision

/// Runs Apple Vision framework analysis on video frames.
/// Face detection, scene classification, OCR — all local, zero cost.
public struct VisualAnalyzer: Sendable {

    public init() {}

    /// Analyze a video by sampling frames at the given interval.
    /// - Parameters:
    ///   - url: Video file URL (use proxy for speed)
    ///   - sampleInterval: Seconds between sampled frames (default 1.0)
    public func analyze(
        url: URL,
        sampleInterval: TimeInterval = 1.0
    ) async throws -> VisualAnalysisResult {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360) // Analyze at low res for speed

        var faceAppearances: [FaceAppearance] = []
        var sceneLabels: [SceneLabel] = []
        var detectedTexts: [DetectedText] = []

        var time: TimeInterval = 0
        while time < duration {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            guard let cgImage = try? await generator.image(at: cmTime).image else {
                time += sampleInterval
                continue
            }

            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            // Face detection
            let faceRequest = VNDetectFaceRectanglesRequest()
            try? requestHandler.perform([faceRequest])
            if let results = faceRequest.results, !results.isEmpty {
                for face in results {
                    faceAppearances.append(FaceAppearance(
                        time: time,
                        boundingBox: face.boundingBox,
                        confidence: Double(face.confidence)
                    ))
                }
            }

            // Scene classification
            let classifyRequest = VNClassifyImageRequest()
            try? requestHandler.perform([classifyRequest])
            if let results = classifyRequest.results {
                let topLabels = results
                    .filter { $0.confidence > 0.3 }
                    .prefix(3)
                    .map { SceneLabel(time: time, label: $0.identifier, confidence: Double($0.confidence)) }
                sceneLabels.append(contentsOf: topLabels)
            }

            // OCR text detection
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .fast
            try? requestHandler.perform([textRequest])
            if let results = textRequest.results {
                for observation in results {
                    if let text = observation.topCandidates(1).first?.string, !text.isEmpty {
                        detectedTexts.append(DetectedText(
                            time: time,
                            text: text,
                            confidence: Double(observation.confidence),
                            boundingBox: observation.boundingBox
                        ))
                    }
                }
            }

            time += sampleInterval
        }

        // Cluster faces — group appearances by visual similarity
        let faceClusters = clusterFaces(faceAppearances)

        // Classify shot types from scene labels + face data
        let shotTypes = classifyShotTypes(
            sceneLabels: sceneLabels,
            faceAppearances: faceAppearances,
            duration: duration,
            sampleInterval: sampleInterval
        )

        return VisualAnalysisResult(
            faceClusters: faceClusters,
            sceneLabels: sceneLabels,
            detectedTexts: detectedTexts,
            shotTypes: shotTypes
        )
    }

    // MARK: - Face clustering (simple: by time proximity for now)

    private func clusterFaces(_ appearances: [FaceAppearance]) -> [FaceCluster] {
        // Simple clustering: faces that appear in consecutive frames are the same person
        // A real implementation would use face embeddings for cross-scene matching
        guard !appearances.isEmpty else { return [] }

        var clusters: [FaceCluster] = []
        var currentTimes: [TimeInterval] = [appearances[0].time]

        for i in 1..<appearances.count {
            let gap = appearances[i].time - appearances[i-1].time
            if gap <= 2.0 { // Within 2 seconds = same cluster
                currentTimes.append(appearances[i].time)
            } else {
                clusters.append(FaceCluster(
                    id: "face_\(clusters.count)",
                    appearances: currentTimes
                ))
                currentTimes = [appearances[i].time]
            }
        }
        clusters.append(FaceCluster(id: "face_\(clusters.count)", appearances: currentTimes))

        return clusters
    }

    // MARK: - Shot type classification

    private func classifyShotTypes(
        sceneLabels: [SceneLabel],
        faceAppearances: [FaceAppearance],
        duration: TimeInterval,
        sampleInterval: TimeInterval
    ) -> [ShotTypeSegment] {
        var segments: [ShotTypeSegment] = []
        let faceTimes = Set(faceAppearances.map { Int($0.time) })

        var time: TimeInterval = 0
        var currentType: ShotType?
        var segmentStart: TimeInterval = 0

        while time < duration {
            let hasFace = faceTimes.contains(Int(time))
            let type: ShotType = hasFace ? .talkingHead : .bRoll

            if type != currentType {
                if let prev = currentType {
                    segments.append(ShotTypeSegment(type: prev, start: segmentStart, end: time))
                }
                currentType = type
                segmentStart = time
            }
            time += sampleInterval
        }

        if let last = currentType {
            segments.append(ShotTypeSegment(type: last, start: segmentStart, end: duration))
        }

        return segments
    }
}

// MARK: - Result types

public struct VisualAnalysisResult: Codable, Sendable {
    public let faceClusters: [FaceCluster]
    public let sceneLabels: [SceneLabel]
    public let detectedTexts: [DetectedText]
    public let shotTypes: [ShotTypeSegment]
}

public struct FaceAppearance: Codable, Sendable {
    public let time: TimeInterval
    public let boundingBox: CGRect
    public let confidence: Double
}

public struct FaceCluster: Codable, Sendable {
    public let id: String
    public let appearances: [TimeInterval]
}

public struct SceneLabel: Codable, Sendable {
    public let time: TimeInterval
    public let label: String
    public let confidence: Double
}

public struct DetectedText: Codable, Sendable {
    public let time: TimeInterval
    public let text: String
    public let confidence: Double
    public let boundingBox: CGRect
}

public struct ShotTypeSegment: Codable, Sendable {
    public let type: ShotType
    public let start: TimeInterval
    public let end: TimeInterval
    public var duration: TimeInterval { end - start }
}

public enum ShotType: String, Codable, Sendable {
    case talkingHead = "talking_head"
    case bRoll = "b_roll"
    case titleCard = "title_card"
    case unknown
}
