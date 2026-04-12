import Foundation
import CoreGraphics
import AVFoundation
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Describes video frames by running Apple Vision analysis (faces, scene classification, OCR)
/// and synthesizing the results into natural language using the on-device foundation model.
public struct SceneDescriber: Sendable {

    public init() {}

    /// Check if the on-device language model is available.
    public var isAvailable: Bool {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { return false }
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    /// Describe a single video frame by analyzing it with Vision and synthesizing with the LLM.
    public func describe(image: CGImage, context: String? = nil) async -> String {
        // Step 1: Run Vision analysis on the frame
        let analysis = analyzeFrame(image)

        #if canImport(FoundationModels)
        // Step 2: If LLM available, synthesize natural language from analysis
        guard isAvailable, #available(macOS 26, *) else { return analysis.summary }
        return await synthesizeDescription(analysis: analysis, context: context)
        #else
        return analysis.summary
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func synthesizeDescription(analysis: FrameAnalysis, context: String?) async -> String {
        do {
            let session = LanguageModelSession(instructions:
                "You describe video frames based on analysis data. Write 1 concise sentence."
            )
            var prompt = "Based on this frame analysis, describe what's happening:\n\(analysis.description)"
            if let context = context {
                prompt += "\nContext: \(context)"
            }
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? analysis.summary : text
        } catch {
            return analysis.summary
        }
    }
    #endif

    /// Describe multiple frames in batch with progress reporting.
    public func describeBatch(
        frames: [(time: TimeInterval, image: CGImage)],
        context: String? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> [(time: TimeInterval, description: String)] {
        guard !frames.isEmpty else { return [] }

        var results: [(time: TimeInterval, description: String)] = []

        for (index, frame) in frames.enumerated() {
            let description = await describe(image: frame.image, context: context)
            results.append((time: frame.time, description: description))
            progress(Double(index + 1) / Double(frames.count))
        }

        return results
    }

    // MARK: - Vision Analysis

    private struct FrameAnalysis: Sendable {
        let faceCount: Int
        let sceneLabels: [(String, Float)]
        let detectedText: [String]
        let shotType: String

        var description: String {
            var parts: [String] = []
            parts.append("Shot type: \(shotType)")
            parts.append("Faces detected: \(faceCount)")
            if !sceneLabels.isEmpty {
                let labels = sceneLabels.map { "\($0.0) (\(String(format: "%.1f", $0.1)))" }.joined(separator: ", ")
                parts.append("Scene labels: \(labels)")
            }
            if !detectedText.isEmpty {
                parts.append("Text on screen: \(detectedText.joined(separator: ", "))")
            } else {
                parts.append("Text on screen: none")
            }
            return parts.joined(separator: "\n")
        }

        /// Fallback summary when LLM is unavailable
        var summary: String {
            var s = "\(faceCount) face\(faceCount == 1 ? "" : "s")"
            if !sceneLabels.isEmpty {
                s += ", \(sceneLabels.first!.0)"
            }
            s += " (\(shotType))"
            return s
        }
    }

    private func analyzeFrame(_ image: CGImage) -> FrameAnalysis {
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])

        // Face detection
        var faceCount = 0
        let faceRequest = VNDetectFaceRectanglesRequest()
        try? requestHandler.perform([faceRequest])
        faceCount = faceRequest.results?.count ?? 0

        // Scene classification
        var sceneLabels: [(String, Float)] = []
        let classifyRequest = VNClassifyImageRequest()
        try? requestHandler.perform([classifyRequest])
        if let results = classifyRequest.results {
            sceneLabels = results
                .filter { $0.confidence > 0.3 }
                .prefix(3)
                .map { ($0.identifier, $0.confidence) }
        }

        // OCR
        var detectedText: [String] = []
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        try? requestHandler.perform([textRequest])
        if let results = textRequest.results {
            detectedText = results.compactMap { $0.topCandidates(1).first?.string }
        }

        // Shot type from face presence
        let shotType = faceCount > 0 ? "talking_head" : "b_roll"

        return FrameAnalysis(
            faceCount: faceCount,
            sceneLabels: sceneLabels,
            detectedText: detectedText,
            shotType: shotType
        )
    }
}
