import Foundation
import CoreGraphics
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Describes video frames using Apple's on-device VLM.
/// Requires macOS 26+ and Apple Silicon. Falls back to empty descriptions on unsupported systems.
public struct SceneDescriber: Sendable {

    public init() {}

    /// Check if on-device VLM is available on this system.
    public var isAvailable: Bool {
        // FoundationModels VLM requires macOS 26+ with the finalized API.
        // Returns false on current SDK until the API is stable.
        return false
    }

    /// Describe a single video frame using the on-device VLM.
    /// - Parameters:
    ///   - image: CGImage to describe
    ///   - context: Optional context hint (e.g., "This is from a podcast recording")
    /// - Returns: Natural language description, or empty string if VLM unavailable.
    public func describe(image: CGImage, context: String? = nil) async -> String {
        // Returns empty string on current SDK; will delegate to VLM when macOS 26 API is finalized.
        return ""
    }

    /// Describe multiple frames in batch, with progress reporting.
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
}
