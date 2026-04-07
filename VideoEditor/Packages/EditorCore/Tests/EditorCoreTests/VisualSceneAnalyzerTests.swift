import XCTest
@testable import EditorCore
import AVFoundation
import CoreGraphics

final class VisualSceneAnalyzerTests: XCTestCase {

    func testProducesSceneSegmentsFromVideo() async throws {
        // Create a 6-second video with 3 distinct color scenes (red, green, blue) - 2s each
        let url = try await TestVideoGenerator.createTestVideo(
            frames: 180,
            colors: [CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                     CGColor(red: 0, green: 1, blue: 0, alpha: 1),
                     CGColor(red: 0, green: 0, blue: 1, alpha: 1)],
            fps: 30
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let analyzer = VisualSceneAnalyzer()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_scenes_\(UUID().uuidString)")

        let scenes = try await analyzer.analyze(url: url, thumbnailCacheDir: cacheDir) { _ in }

        // Should have 3 scenes (one per color block)
        XCTAssertEqual(scenes.count, 3)
        // Scenes should start near 0
        XCTAssertEqual(scenes.first?.range.start ?? 99, 0.0, accuracy: 0.5)
        // Each scene should have positive duration
        for scene in scenes {
            XCTAssertTrue(scene.range.duration > 0)
        }
        // Thumbnails should be saved
        for scene in scenes {
            if let path = scene.thumbnailPath {
                XCTAssertTrue(FileManager.default.fileExists(atPath: path))
            }
        }

        try? FileManager.default.removeItem(at: cacheDir)
    }

    func testSingleSceneVideoProducesOneSegment() async throws {
        let url = try await TestVideoGenerator.createTestVideo(
            frames: 60,
            colors: [CGColor(red: 1, green: 0, blue: 0, alpha: 1)],
            fps: 30
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let analyzer = VisualSceneAnalyzer()
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_scenes_\(UUID().uuidString)")

        let scenes = try await analyzer.analyze(url: url, thumbnailCacheDir: cacheDir) { _ in }

        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].range.start, 0.0, accuracy: 0.1)

        try? FileManager.default.removeItem(at: cacheDir)
    }
}

// MARK: - TestVideoGenerator (XCTest-compatible)

extension TestVideoGenerator {
    /// Creates a test video from a flat array of frames distributed evenly across colors.
    /// - Parameters:
    ///   - frames: Total number of frames
    ///   - colors: Colors to cycle through, each gets an equal share of frames
    ///   - fps: Frames per second
    /// - Returns: URL to a temporary .mov file
    static func createTestVideo(
        frames: Int,
        colors: [CGColor],
        fps: Int32
    ) async throws -> URL {
        guard !colors.isEmpty else {
            throw VideoGeneratorError.bufferCreationFailed
        }
        let framesPerColor = frames / colors.count
        let size = CGSize(width: 64, height: 64)
        let segments: [(CGColor, TimeInterval)] = colors.map { color in
            (color, TimeInterval(framesPerColor) / TimeInterval(fps))
        }
        return try await TestVideoGenerator.generate(
            segments: segments,
            size: size,
            fps: fps
        )
    }
}
