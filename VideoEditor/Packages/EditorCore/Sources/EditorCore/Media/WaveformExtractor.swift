import Foundation
import AVFoundation

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

        // Load audio track
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        // Get duration to calculate samples per bucket
        let duration: Double
        if let d = try? await asset.load(.duration).seconds, d > 0 {
            duration = d
        } else {
            return nil
        }

        // Configure reader for raw PCM
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

        // Process in streaming fashion — don't load all samples into memory.
        // Get actual sample rate from the audio track format
        let sampleRate: Double
        if let formatDesc = try? await audioTrack.load(.formatDescriptions).first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
            sampleRate = asbd.pointee.mSampleRate
        } else {
            sampleRate = 48000 // Safe fallback for video production
        }

        var peaks = [Float](repeating: 0, count: sampleCount)
        let bucketDuration = duration / Double(sampleCount)
        var currentSampleIndex: Int64 = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            let numSamples = length / MemoryLayout<Int16>.size

            // Read samples
            var data = [Int16](repeating: 0, count: numSamples)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)

            for sample in data {
                let timeInSeconds = Double(currentSampleIndex) / sampleRate
                let bucketIndex = min(Int(timeInSeconds / bucketDuration), sampleCount - 1)

                // Use Int32 to avoid overflow on Int16.min (-32768)
                let amplitude = Float(abs(Int32(sample))) / Float(Int16.max)
                if amplitude > peaks[bucketIndex] {
                    peaks[bucketIndex] = amplitude
                }

                currentSampleIndex += 1
            }
        }

        // Check if we got any data
        let maxPeak = peaks.max() ?? 0
        guard maxPeak > 0 else { return nil }

        return peaks
    }
}
