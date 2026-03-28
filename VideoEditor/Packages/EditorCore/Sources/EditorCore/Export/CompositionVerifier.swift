import Foundation
import AVFoundation
import CoreImage

/// Verifies that a composition produces the expected output.
/// Exports short segments and checks video/audio content.
public struct CompositionVerifier: Sendable {

    public struct VerificationResult: Sendable {
        public let timeRange: String
        public let hasVideo: Bool
        public let hasAudio: Bool
        public let videoFrameValid: Bool
        public let audioLevel: Float  // RMS level, 0 = silent
        public let exportedDuration: Double
        public let issues: [String]

        public var passed: Bool { issues.isEmpty }
    }

    public init() {}

    /// Verify a composition at a specific time range.
    /// Exports a short segment and checks the output.
    public func verify(
        composition: AVMutableComposition,
        audioMix: AVAudioMix?,
        videoComposition: AVVideoComposition?,
        timeRange: CMTimeRange,
        outputURL: URL
    ) async -> VerificationResult {
        var issues: [String] = []

        // Clean up any existing file
        try? FileManager.default.removeItem(at: outputURL)

        // Export the segment
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
            return VerificationResult(timeRange: timeRangeStr(timeRange), hasVideo: false, hasAudio: false, videoFrameValid: false, audioLevel: 0, exportedDuration: 0, issues: ["Failed to create export session"])
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.timeRange = timeRange
        if let audioMix { session.audioMix = audioMix }
        if let videoComposition { session.videoComposition = videoComposition }

        await session.export()

        guard session.status == .completed else {
            let error = session.error?.localizedDescription ?? "unknown"
            return VerificationResult(timeRange: timeRangeStr(timeRange), hasVideo: false, hasAudio: false, videoFrameValid: false, audioLevel: 0, exportedDuration: 0, issues: ["Export failed: \(error)"])
        }

        // Verify the exported file
        let exportedAsset = AVURLAsset(url: outputURL)

        // Check duration
        let exportedDuration: Double
        if let dur = try? await exportedAsset.load(.duration).seconds {
            exportedDuration = dur
        } else {
            exportedDuration = 0
            issues.append("Cannot read exported duration")
        }

        let expectedDuration = timeRange.duration.seconds
        if abs(exportedDuration - expectedDuration) > 0.5 {
            issues.append("Duration mismatch: expected \(String(format: "%.1f", expectedDuration))s, got \(String(format: "%.1f", exportedDuration))s")
        }

        // Check video track exists
        let hasVideo: Bool
        if let videoTracks = try? await exportedAsset.loadTracks(withMediaType: .video) {
            hasVideo = !videoTracks.isEmpty
            if videoTracks.isEmpty { issues.append("No video track in export") }
        } else {
            hasVideo = false
            issues.append("Cannot load video tracks")
        }

        // Check audio track exists and has content
        let hasAudio: Bool
        var audioLevel: Float = 0
        if let audioTracks = try? await exportedAsset.loadTracks(withMediaType: .audio) {
            hasAudio = !audioTracks.isEmpty
            if audioTracks.isEmpty {
                issues.append("No audio track in export")
            } else {
                // Measure audio level
                audioLevel = await measureAudioLevel(url: outputURL)
                if audioLevel < 0.001 {
                    issues.append("Audio is silent (level: \(audioLevel))")
                }
            }
        } else {
            hasAudio = false
            issues.append("Cannot load audio tracks")
        }

        // Check video frame is not black
        let videoFrameValid: Bool
        if hasVideo {
            videoFrameValid = await checkVideoFrame(url: outputURL, at: 0.5)
            if !videoFrameValid {
                issues.append("Video frame appears to be black/empty")
            }
        } else {
            videoFrameValid = false
        }

        // Clean up
        try? FileManager.default.removeItem(at: outputURL)

        return VerificationResult(
            timeRange: timeRangeStr(timeRange),
            hasVideo: hasVideo,
            hasAudio: hasAudio,
            videoFrameValid: videoFrameValid,
            audioLevel: audioLevel,
            exportedDuration: exportedDuration,
            issues: issues
        )
    }

    /// Measure RMS audio level of a file.
    private func measureAudioLevel(url: URL) async -> Float {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return 0 }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return 0 }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { return 0 }

        var totalSquared: Double = 0
        var totalSamples: Int = 0

        while let buffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let numSamples = length / 2
            var data = [Int16](repeating: 0, count: numSamples)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)

            for sample in data {
                let f = Double(abs(Int32(sample))) / Double(Int16.max)
                totalSquared += f * f
            }
            totalSamples += numSamples
        }

        guard totalSamples > 0 else { return 0 }
        return Float(sqrt(totalSquared / Double(totalSamples)))
    }

    /// Check if a video frame at the given time is not black.
    private func checkVideoFrame(url: URL, at time: Double) async -> Bool {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil) else {
            return false
        }

        // Check if the frame has meaningful content (not all black)
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else { return false }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let totalPixels = cgImage.width * cgImage.height
        var brightPixels = 0
        let sampleStep = max(totalPixels / 1000, 1) // Sample ~1000 pixels

        for i in stride(from: 0, to: totalPixels * bytesPerPixel, by: sampleStep * bytesPerPixel) {
            let r = Int(ptr[i])
            let g = Int(ptr[i + 1])
            let b = Int(ptr[i + 2])
            if r + g + b > 30 { // Not black
                brightPixels += 1
            }
        }

        // If more than 10% of sampled pixels are non-black, frame is valid
        return brightPixels > 100
    }

    private func timeRangeStr(_ range: CMTimeRange) -> String {
        "\(String(format: "%.1f", range.start.seconds))s-\(String(format: "%.1f", range.end.seconds))s"
    }
}
