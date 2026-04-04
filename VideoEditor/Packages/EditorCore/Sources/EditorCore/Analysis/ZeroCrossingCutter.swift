import Foundation
import AVFoundation

/// Adjusts cut points to the nearest audio zero-crossing to prevent pops/clicks.
/// Searches within a configurable window (default ±10ms) around each target time.
public struct ZeroCrossingCutter: Sendable {

    public init() {}

    /// Find the nearest audio zero-crossing within a window around the target time.
    /// Returns the adjusted cut time, or the original if no audio track exists.
    public func findZeroCrossing(
        url: URL,
        targetTime: TimeInterval,
        windowMs: Double = 10.0
    ) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return targetTime
        }

        let sampleRate: Double = 44100
        let windowSeconds = windowMs / 1000.0
        let readStart = max(targetTime - windowSeconds, 0)
        let readDuration = windowSeconds * 2

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: readStart, preferredTimescale: 44100),
            duration: CMTime(seconds: readDuration, preferredTimescale: 44100)
        )

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { return targetTime }
        defer { reader.cancelReading() }

        // Read all samples in the window
        var samples: [Int16] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let count = length / 2
            var chunk = [Int16](repeating: 0, count: count)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &chunk)
            samples.append(contentsOf: chunk)
        }

        guard samples.count > 1 else { return targetTime }

        // Find the sample index closest to targetTime
        let targetSample = Int((targetTime - readStart) * sampleRate)
        let clampedTarget = min(max(targetSample, 0), samples.count - 1)

        // Search outward from target for a zero-crossing (sign change)
        var bestOffset = 0
        var bestDistance = Int.max

        for offset in 0..<samples.count {
            for dir in [-1, 1] {
                let idx = clampedTarget + (offset * dir)
                guard idx > 0, idx < samples.count else { continue }

                let prev = samples[idx - 1]
                let curr = samples[idx]

                // Zero-crossing: sign change or exact zero
                let isCrossing = curr == 0 ||
                    (prev > 0 && curr < 0) ||
                    (prev < 0 && curr > 0)

                if isCrossing && offset < bestDistance {
                    bestDistance = offset
                    bestOffset = idx - clampedTarget
                }
            }
            if bestDistance <= offset { break } // Can't find closer
        }

        let adjustedTime = readStart + Double(clampedTarget + bestOffset) / sampleRate
        return max(adjustedTime, 0)
    }

    /// Adjust all cut boundaries in a CutPlan to the nearest zero-crossings.
    public func adjustCutPoints(
        _ cutPoints: [TimeInterval],
        url: URL
    ) async -> [TimeInterval] {
        var adjusted: [TimeInterval] = []
        for point in cutPoints {
            let snapped = (try? await findZeroCrossing(url: url, targetTime: point)) ?? point
            adjusted.append(snapped)
        }
        return adjusted
    }
}
