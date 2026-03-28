import Foundation
import AVFoundation
import Accelerate

/// Extracts a downsampled waveform (amplitude envelope) from an audio or video file.
/// The result is an array of normalized peak amplitudes (0.0–1.0), suitable for rendering.
public struct WaveformExtractor: Sendable {

    public init() {}

    /// Extract waveform data from a media file.
    /// - Parameters:
    ///   - url: Source media file (video or audio)
    ///   - sampleCount: Number of amplitude values to return (default 200)
    /// - Returns: Array of normalized peak amplitudes, or nil if no audio track
    public func extract(from url: URL, sampleCount: Int = 200) async -> [Float]? {
        let asset = AVURLAsset(url: url)

        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        // Configure reader for raw PCM samples
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else { return nil }

        // Read all samples into a buffer
        var allSamples: [Int16] = []
        allSamples.reserveCapacity(44100 * 60) // Pre-allocate for ~1 minute

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            let sampleCount = length / MemoryLayout<Int16>.size

            var data = [Int16](repeating: 0, count: sampleCount)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)

            allSamples.append(contentsOf: data)
        }

        guard !allSamples.isEmpty else { return nil }

        // Downsample to target count by taking peak amplitude of each chunk
        return downsample(allSamples, to: sampleCount)
    }

    /// Downsample raw Int16 samples to N peak amplitude values (0.0–1.0).
    private func downsample(_ samples: [Int16], to targetCount: Int) -> [Float] {
        let chunkSize = max(1, samples.count / targetCount)
        var result = [Float](repeating: 0, count: targetCount)

        for i in 0..<targetCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, samples.count)
            guard start < end else { continue }

            // Find peak absolute value in this chunk
            var peak: Int16 = 0
            for j in start..<end {
                let abs = samples[j] < 0 ? -samples[j] : samples[j]
                if abs > peak { peak = abs }
            }

            result[i] = Float(peak) / Float(Int16.max)
        }

        return result
    }
}
