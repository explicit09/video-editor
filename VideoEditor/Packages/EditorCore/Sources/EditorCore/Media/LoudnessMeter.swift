import Foundation
import AVFoundation
import Accelerate

/// Measures integrated loudness (LUFS) of audio content.
/// Uses ITU-R BS.1770-4 simplified algorithm.
public struct LoudnessMeter: Sendable {

    public init() {}

    /// Measure integrated LUFS of an audio file or video's audio track.
    public func measureLUFS(url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { return nil }

        var sumOfSquares: Double = 0
        var totalSamples: Int64 = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let numSamples = length / MemoryLayout<Float>.size

            var data = [Float](repeating: 0, count: numSamples)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)

            // Calculate mean square
            var meanSquare: Float = 0
            vDSP_measqv(data, 1, &meanSquare, vDSP_Length(numSamples))

            sumOfSquares += Double(meanSquare) * Double(numSamples)
            totalSamples += Int64(numSamples)
        }

        guard totalSamples > 0 else { return nil }

        let meanSquare = sumOfSquares / Double(totalSamples)
        guard meanSquare > 0 else { return -70.0 } // silence

        // LUFS = -0.691 + 10 * log10(mean_square)
        // Simplified — true BS.1770 includes K-weighting filter
        let lufs = -0.691 + 10.0 * log10(meanSquare)
        return lufs
    }

    /// Calculate the volume adjustment needed to reach target LUFS.
    public func volumeAdjustment(currentLUFS: Double, targetLUFS: Double) -> Double {
        let difference = targetLUFS - currentLUFS
        return pow(10.0, difference / 20.0)
    }
}
