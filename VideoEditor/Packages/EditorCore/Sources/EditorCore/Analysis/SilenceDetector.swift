import Foundation
import AVFoundation

/// Detects silent segments in audio by analyzing amplitude.
/// Runs locally, zero cost, fast.
public struct SilenceDetector: Sendable {

    public init() {}

    /// Analyze audio and return silence ranges.
    /// - Parameters:
    ///   - url: Audio or video file URL
    ///   - thresholdDB: Silence threshold in decibels (default -40 dB)
    ///   - minDuration: Minimum silence duration in seconds to report (default 0.5s)
    ///   - sampleWindow: Analysis window size in seconds (default 0.05s)
    public func detect(
        url: URL,
        thresholdDB: Float = -40,
        minDuration: TimeInterval = 0.5,
        sampleWindow: TimeInterval = 0.05
    ) async throws -> [SilenceRange] {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)

        guard reader.startReading() else {
            throw SilenceDetectorError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        defer { reader.cancelReading() }

        // Convert threshold from dB to linear amplitude
        let thresholdLinear = pow(10.0, thresholdDB / 20.0)
        let thresholdInt16 = Int16(thresholdLinear * Float(Int16.max))

        let sampleRate: Double = 16000
        let samplesPerWindow = Int(sampleWindow * sampleRate)

        var silenceRanges: [SilenceRange] = []
        var silenceStart: TimeInterval?
        var sampleIndex: Int = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            guard let data = dataPointer else { continue }

            let sampleCount = length / 2 // 16-bit samples
            let samples = data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { ptr in
                Array(UnsafeBufferPointer(start: ptr, count: sampleCount))
            }

            // Process in windows
            var i = 0
            while i < samples.count {
                let windowEnd = min(i + samplesPerWindow, samples.count)
                let window = samples[i..<windowEnd]

                // Calculate peak amplitude in window
                // Use Int32 to avoid overflow on Int16.min (-32768)
                let peak = window.reduce(Int32(0)) { max(abs(Int32($0)), abs(Int32($1))) }
                let isSilent = peak < Int32(thresholdInt16)

                let windowTime = Double(sampleIndex + i) / sampleRate

                if isSilent {
                    if silenceStart == nil {
                        silenceStart = windowTime
                    }
                } else {
                    if let start = silenceStart {
                        let duration = windowTime - start
                        if duration >= minDuration {
                            silenceRanges.append(SilenceRange(start: start, end: windowTime))
                        }
                        silenceStart = nil
                    }
                }

                i += samplesPerWindow
            }

            sampleIndex += sampleCount
        }

        // Close trailing silence
        if let start = silenceStart {
            let totalDuration = Double(sampleIndex) / sampleRate
            let duration = totalDuration - start
            if duration >= minDuration {
                silenceRanges.append(SilenceRange(start: start, end: totalDuration))
            }
        }

        return silenceRanges
    }
}

// MARK: - SilenceRange

public struct SilenceRange: Codable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval
    public var duration: TimeInterval { end - start }

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }
}

// MARK: - Error

public enum SilenceDetectorError: Error, LocalizedError {
    case readerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .readerFailed(let msg): "Audio reader failed: \(msg)"
        }
    }
}
