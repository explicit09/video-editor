import Testing
import Foundation
import AVFoundation
import CoreGraphics
@testable import EditorCore

@Suite("Shot Boundary Detector Tests")
struct ShotBoundaryDetectorTests {

    @Test("No boundaries detected in static single-color content")
    func testDetectsNoBoundariesInStaticContent() async throws {
        let url = try await TestVideoGenerator.generate(
            segments: [(.red, 2.0)],
            size: CGSize(width: 64, height: 64),
            fps: 30
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let detector = ShotBoundaryDetector()
        let boundaries = try await detector.detect(url: url, threshold: 0.3, sampleInterval: 0.5)

        #expect(boundaries.isEmpty, "Static single-color video should have no shot boundaries")
    }

    @Test("Detects one boundary when color changes from red to blue")
    func testDetectsBoundaryOnColorChange() async throws {
        let url = try await TestVideoGenerator.generate(
            segments: [(.red, 2.0), (.blue, 2.0)],
            size: CGSize(width: 64, height: 64),
            fps: 30
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let detector = ShotBoundaryDetector()
        let boundaries = try await detector.detect(url: url, threshold: 0.3, sampleInterval: 0.5)

        #expect(boundaries.count == 1, "Two-color video should have exactly one shot boundary, got \(boundaries.count)")
        if let boundary = boundaries.first {
            // The boundary should be near the 2-second mark (within 1 second tolerance)
            #expect(boundary > 1.0 && boundary < 3.0, "Boundary at \(boundary) should be near the 2-second transition")
        }
    }

    @Test("Detects two boundaries in three-color video")
    func testDetectsMultipleBoundaries() async throws {
        let url = try await TestVideoGenerator.generate(
            segments: [(.red, 2.0), (.green, 2.0), (.blue, 2.0)],
            size: CGSize(width: 64, height: 64),
            fps: 30
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let detector = ShotBoundaryDetector()
        let boundaries = try await detector.detect(url: url, threshold: 0.3, sampleInterval: 0.5)

        #expect(boundaries.count == 2, "Three-color video should have exactly two shot boundaries, got \(boundaries.count)")
        if boundaries.count >= 2 {
            #expect(boundaries[0] > 1.0 && boundaries[0] < 3.0, "First boundary at \(boundaries[0]) should be near 2s")
            #expect(boundaries[1] > 3.0 && boundaries[1] < 5.0, "Second boundary at \(boundaries[1]) should be near 4s")
        }
    }
}

// MARK: - TestVideoGenerator

enum TestVideoGenerator {
    /// Generates a video file with solid color segments.
    /// - Parameters:
    ///   - segments: Array of (color, duration) pairs
    ///   - size: Video frame size in pixels
    ///   - fps: Frames per second
    /// - Returns: URL to a temporary .mov file
    static func generate(
        segments: [(CGColor, TimeInterval)],
        size: CGSize,
        fps: Int32
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-video-\(UUID().uuidString).mov")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let adaptorAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: adaptorAttributes
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let timescale: CMTimeScale = 600
        var currentFrame: Int64 = 0

        for (color, duration) in segments {
            let frameCount = Int64(duration * Double(fps))
            let pixelBuffer = try makePixelBuffer(color: color, size: size)

            for _ in 0..<frameCount {
                while !input.isReadyForMoreMediaData {
                    await Task.yield()
                }
                let pts = CMTime(value: currentFrame * Int64(timescale) / Int64(fps), timescale: timescale)
                adaptor.append(pixelBuffer, withPresentationTime: pts)
                currentFrame += 1
            }
        }

        input.markAsFinished()
        await writer.finishWriting()

        if writer.status != .completed {
            throw VideoGeneratorError.writeFailed(writer.error?.localizedDescription ?? "unknown")
        }

        return url
    }

    private static func makePixelBuffer(color: CGColor, size: CGSize) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw VideoGeneratorError.bufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )

        ctx?.setFillColor(color)
        ctx?.fill(CGRect(origin: .zero, size: size))

        return buffer
    }
}

enum VideoGeneratorError: Error {
    case writeFailed(String)
    case bufferCreationFailed
}

// MARK: - CGColor convenience

private extension CGColor {
    static var red: CGColor { CGColor(red: 1, green: 0, blue: 0, alpha: 1) }
    static var green: CGColor { CGColor(red: 0, green: 1, blue: 0, alpha: 1) }
    static var blue: CGColor { CGColor(red: 0, green: 0, blue: 1, alpha: 1) }
}
