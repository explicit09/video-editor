import Foundation
import AVFoundation
import Accelerate

/// Compares audio segments using normalized cross-correlation.
/// Score > 0.85 = same content, < 0.5 = different content.
public struct AudioCrossCorrelator: Sendable {

    /// Duration of each comparison window in seconds.
    private let windowDuration: TimeInterval = 0.8

    /// Sample rate for comparison (downsampled for speed).
    private let sampleRate: Int = 16000

    public init() {}

    /// Compare audio from a composition at `exportTime` against source audio at `sourceTime`.
    /// Returns normalized cross-correlation score (0.0 to 1.0).
    public func compare(
        compositionAudio composition: AVMutableComposition,
        at exportTime: TimeInterval,
        sourceURL: URL,
        at sourceTime: TimeInterval
    ) async -> Float {
        let exportSamples = await extractPCM(from: composition, at: exportTime)
        let sourceSamples = await extractPCM(fromURL: sourceURL, at: sourceTime)

        guard !exportSamples.isEmpty, !sourceSamples.isEmpty else { return 0 }

        return normalizedCrossCorrelation(exportSamples, sourceSamples)
    }

    /// Measure RMS audio level at a specific time in a composition.
    public func measureRMS(
        in composition: AVMutableComposition,
        at time: TimeInterval,
        duration: TimeInterval = 0.5
    ) async -> Float {
        let samples = await extractPCM(from: composition, at: time, duration: duration)
        guard !samples.isEmpty else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    // MARK: - PCM Extraction

    private func extractPCM(
        from asset: AVAsset,
        at time: TimeInterval,
        duration: TimeInterval? = nil
    ) async -> [Float] {
        let dur = duration ?? windowDuration
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return [] }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return [] }
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: max(time, 0), preferredTimescale: 600),
            duration: CMTime(seconds: dur, preferredTimescale: 600)
        )

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { return [] }

        var floatSamples: [Float] = []
        let maxSamples = Int(dur * Double(sampleRate))

        while let buffer = output.copyNextSampleBuffer(), floatSamples.count < maxSamples {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let numSamples = length / 2
            var int16Data = [Int16](repeating: 0, count: numSamples)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &int16Data)

            // Convert Int16 to Float normalized [-1, 1]
            let remaining = maxSamples - floatSamples.count
            let toConvert = min(numSamples, remaining)
            var floatChunk = [Float](repeating: 0, count: toConvert)
            var scale = Float(Int16.max)
            vDSP_vflt16(int16Data, 1, &floatChunk, 1, vDSP_Length(toConvert))
            vDSP_vsdiv(floatChunk, 1, &scale, &floatChunk, 1, vDSP_Length(toConvert))
            floatSamples.append(contentsOf: floatChunk)
        }

        return floatSamples
    }

    private func extractPCM(fromURL url: URL, at time: TimeInterval, duration: TimeInterval? = nil) async -> [Float] {
        await extractPCM(from: AVURLAsset(url: url), at: time, duration: duration)
    }

    // MARK: - Normalized Cross-Correlation

    /// Compute NCC between two signals. Returns 0.0-1.0.
    private func normalizedCrossCorrelation(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 100 else { return 0 }

        // Truncate to same length
        let sigA = Array(a.prefix(n))
        let sigB = Array(b.prefix(n))

        // Compute means
        var meanA: Float = 0, meanB: Float = 0
        vDSP_meanv(sigA, 1, &meanA, vDSP_Length(n))
        vDSP_meanv(sigB, 1, &meanB, vDSP_Length(n))

        // Subtract means
        var centeredA = [Float](repeating: 0, count: n)
        var centeredB = [Float](repeating: 0, count: n)
        var negMeanA = -meanA, negMeanB = -meanB
        vDSP_vsadd(sigA, 1, &negMeanA, &centeredA, 1, vDSP_Length(n))
        vDSP_vsadd(sigB, 1, &negMeanB, &centeredB, 1, vDSP_Length(n))

        // Dot product (numerator)
        var dotProduct: Float = 0
        vDSP_dotpr(centeredA, 1, centeredB, 1, &dotProduct, vDSP_Length(n))

        // Norms (denominator)
        var normA: Float = 0, normB: Float = 0
        vDSP_svesq(centeredA, 1, &normA, vDSP_Length(n))
        vDSP_svesq(centeredB, 1, &normB, vDSP_Length(n))

        let denominator = sqrt(normA * normB)
        guard denominator > 1e-10 else { return 0 }

        return max(0, dotProduct / denominator)
    }
}
