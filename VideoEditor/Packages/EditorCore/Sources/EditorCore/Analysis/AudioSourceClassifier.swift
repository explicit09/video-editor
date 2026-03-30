import Foundation
import AVFoundation
import Accelerate

/// Classifies audio segments as live speech, playback, background noise, or silence.
///
/// Uses a combination of time-domain and frequency-domain features:
/// - **Spectral centroid**: Live speech has lower centroid than compressed playback
/// - **Spectral flatness**: Noise is flat (≈1.0), speech has peaks (≈0.1-0.4)
/// - **Zero-crossing rate**: Speech < noise (voiced sounds cross less)
/// - **Crest factor**: Peak/RMS — speech has higher transients than steady playback
/// - **Energy variance**: Live speech is dynamic; playback is more consistent
/// - **RMS level**: Relative volume helps distinguish direct mic vs speaker playback
public struct AudioSourceClassifier: Sendable {

    public init() {}

    // MARK: - Public API

    /// Classify audio into segments with source labels.
    /// Analyzes in windows (default 2 seconds) and returns per-window classification.
    public func classify(
        url: URL,
        windowDuration: TimeInterval = 2.0,
        sampleRate: Double = 16000
    ) async throws -> [ClassifiedSegment] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        let reader = try AVAssetReader(asset: asset)
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
        guard reader.startReading() else {
            throw ClassifierError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }

        let samplesPerWindow = Int(windowDuration * sampleRate)
        var windowBuffer: [Float] = []
        windowBuffer.reserveCapacity(samplesPerWindow)
        var sampleIndex = 0
        var segments: [ClassifiedSegment] = []

        while let buffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let numSamples = length / 2
            var int16Data = [Int16](repeating: 0, count: numSamples)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &int16Data)

            for sample in int16Data {
                windowBuffer.append(Float(sample) / Float(Int16.max))

                if windowBuffer.count >= samplesPerWindow {
                    let time = Double(sampleIndex) / sampleRate
                    let features = extractFeatures(from: windowBuffer, sampleRate: Float(sampleRate))
                    let classification = classifyWindow(features: features)

                    segments.append(ClassifiedSegment(
                        time: time,
                        duration: windowDuration,
                        source: classification,
                        features: features
                    ))

                    sampleIndex += windowBuffer.count
                    windowBuffer.removeAll(keepingCapacity: true)
                }
            }
        }

        // Flush remaining
        if windowBuffer.count > Int(sampleRate * 0.5) {
            let time = Double(sampleIndex) / sampleRate
            let features = extractFeatures(from: windowBuffer, sampleRate: Float(sampleRate))
            let classification = classifyWindow(features: features)
            segments.append(ClassifiedSegment(
                time: time,
                duration: Double(windowBuffer.count) / sampleRate,
                source: classification,
                features: features
            ))
        }

        // Smooth: single-window outliers get overridden by neighbors
        return smooth(segments)
    }

    /// Classify a specific time range.
    public func classifyRange(
        url: URL,
        start: TimeInterval,
        end: TimeInterval
    ) async throws -> [ClassifiedSegment] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }

        let sampleRate: Double = 16000
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
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
        guard reader.startReading() else { return [] }

        let windowDuration: TimeInterval = 2.0
        let samplesPerWindow = Int(windowDuration * sampleRate)
        var windowBuffer: [Float] = []
        var sampleIndex = 0
        var segments: [ClassifiedSegment] = []

        while let buffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let numSamples = length / 2
            var int16Data = [Int16](repeating: 0, count: numSamples)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &int16Data)

            for sample in int16Data {
                windowBuffer.append(Float(sample) / Float(Int16.max))
                if windowBuffer.count >= samplesPerWindow {
                    let time = start + Double(sampleIndex) / sampleRate
                    let features = extractFeatures(from: windowBuffer, sampleRate: Float(sampleRate))
                    let classification = classifyWindow(features: features)
                    segments.append(ClassifiedSegment(
                        time: time, duration: windowDuration,
                        source: classification, features: features
                    ))
                    sampleIndex += windowBuffer.count
                    windowBuffer.removeAll(keepingCapacity: true)
                }
            }
        }

        return smooth(segments)
    }
}

// MARK: - Models

public enum AudioSource: String, Codable, Sendable {
    case liveSpeech     // Direct mic input — natural dynamics, room acoustics
    case playback       // Audio from speakers — compressed, consistent level, different spectral profile
    case background     // Ambient noise — high spectral flatness, no speech patterns
    case silence        // Below noise floor
}

public struct ClassifiedSegment: Codable, Sendable {
    public let time: TimeInterval
    public let duration: TimeInterval
    public let source: AudioSource
    public let features: AudioFeatures

    public var end: TimeInterval { time + duration }
}

public struct AudioFeatures: Codable, Sendable {
    public let rms: Float                // RMS energy (0-1)
    public let dbFS: Float               // Decibels full scale
    public let spectralCentroid: Float   // Weighted average frequency (Hz)
    public let spectralFlatness: Float   // Geometric/arithmetic mean of spectrum (0=tonal, 1=noise)
    public let zeroCrossingRate: Float   // Zero crossings per sample (0-1)
    public let crestFactor: Float        // Peak/RMS ratio — transient content
    public let energyVariance: Float     // How much energy varies within window
    public let dynamicRange: Float       // Max dB - Min dB within sub-windows
}

public enum ClassifierError: Error, LocalizedError {
    case readerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .readerFailed(let msg): "Audio reader failed: \(msg)"
        }
    }
}

// MARK: - Feature Extraction

extension AudioSourceClassifier {

    /// Extract all audio features from a sample window.
    func extractFeatures(from samples: [Float], sampleRate: Float) -> AudioFeatures {
        let count = samples.count
        guard count > 0 else {
            return AudioFeatures(rms: 0, dbFS: -100, spectralCentroid: 0,
                                 spectralFlatness: 0, zeroCrossingRate: 0,
                                 crestFactor: 1, energyVariance: 0, dynamicRange: 0)
        }

        // RMS
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
        let dbFS = rms > 0 ? 20 * log10(rms) : -100

        // Peak
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))

        // Crest factor
        let crestFactor = rms > 0 ? peak / rms : 1.0

        // Zero-crossing rate
        let zcr = computeZeroCrossingRate(samples)

        // Energy variance (compute RMS in sub-windows, measure variance)
        let energyVariance = computeEnergyVariance(samples, sampleRate: sampleRate)

        // Dynamic range
        let dynamicRange = computeDynamicRange(samples, sampleRate: sampleRate)

        // Spectral features via FFT
        let (centroid, flatness) = computeSpectralFeatures(samples, sampleRate: sampleRate)

        return AudioFeatures(
            rms: rms,
            dbFS: dbFS,
            spectralCentroid: centroid,
            spectralFlatness: flatness,
            zeroCrossingRate: zcr,
            crestFactor: crestFactor,
            energyVariance: energyVariance,
            dynamicRange: dynamicRange
        )
    }

    /// Zero-crossing rate: fraction of adjacent samples that cross zero.
    private func computeZeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i - 1] > 0 && samples[i] < 0) ||
               (samples[i - 1] < 0 && samples[i] > 0) {
                crossings += 1
            }
        }
        return Float(crossings) / Float(samples.count - 1)
    }

    /// Energy variance: RMS of 50ms sub-windows, then variance of those values.
    private func computeEnergyVariance(_ samples: [Float], sampleRate: Float) -> Float {
        let subWindowSize = Int(0.05 * sampleRate) // 50ms
        guard samples.count >= subWindowSize else { return 0 }

        var subRMS: [Float] = []
        var i = 0
        while i + subWindowSize <= samples.count {
            var rms: Float = 0
            samples.withUnsafeBufferPointer { buf in
                vDSP_rmsqv(buf.baseAddress! + i, 1, &rms, vDSP_Length(subWindowSize))
            }
            subRMS.append(rms)
            i += subWindowSize
        }

        guard subRMS.count > 1 else { return 0 }

        var mean: Float = 0
        vDSP_meanv(subRMS, 1, &mean, vDSP_Length(subRMS.count))

        var variance: Float = 0
        for val in subRMS {
            variance += (val - mean) * (val - mean)
        }
        return variance / Float(subRMS.count)
    }

    /// Dynamic range: difference between loudest and quietest 50ms sub-windows in dB.
    private func computeDynamicRange(_ samples: [Float], sampleRate: Float) -> Float {
        let subWindowSize = Int(0.05 * sampleRate)
        guard samples.count >= subWindowSize else { return 0 }

        var maxRMS: Float = 0
        var minRMS: Float = Float.greatestFiniteMagnitude
        var i = 0
        while i + subWindowSize <= samples.count {
            var rms: Float = 0
            samples.withUnsafeBufferPointer { buf in
                vDSP_rmsqv(buf.baseAddress! + i, 1, &rms, vDSP_Length(subWindowSize))
            }
            if rms > maxRMS { maxRMS = rms }
            if rms < minRMS && rms > 0.0001 { minRMS = rms }
            i += subWindowSize
        }

        guard maxRMS > 0, minRMS < Float.greatestFiniteMagnitude else { return 0 }
        let maxDB = 20 * log10(maxRMS)
        let minDB = 20 * log10(minRMS)
        return maxDB - minDB
    }

    /// Compute spectral centroid and spectral flatness using vDSP FFT.
    private func computeSpectralFeatures(_ samples: [Float], sampleRate: Float) -> (centroid: Float, flatness: Float) {
        // Use a power-of-2 FFT size
        let fftSize = 1024
        guard samples.count >= fftSize else { return (0, 0) }

        // Take a chunk from the middle of the window for stability
        let startIdx = (samples.count - fftSize) / 2
        var realPart = Array(samples[startIdx..<(startIdx + fftSize)])

        // Apply Hann window to reduce spectral leakage
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(realPart, 1, window, 1, &realPart, 1, vDSP_Length(fftSize))

        // Setup FFT
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return (0, 0)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Pack into split complex
        let halfN = fftSize / 2
        var imagPart = [Float](repeating: 0, count: halfN)
        var realOut = [Float](repeating: 0, count: halfN)

        // Convert to split complex format
        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )
                // Convert interleaved to split complex
                realOut.withUnsafeMutableBufferPointer { _ in
                    // Pack real data into split complex format
                    let input = realBuf.baseAddress!
                    vDSP_ctoz(UnsafePointer<DSPComplex>(OpaquePointer(input)), 2, &splitComplex, 1, vDSP_Length(halfN))
                }

                // Forward FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Compute magnitude spectrum
                var magnitudes = [Float](repeating: 0, count: halfN)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))

                // Scale
                var scale = Float(1.0 / Float(fftSize))
                vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfN))

                // Compute spectral centroid: sum(f_i * mag_i) / sum(mag_i)
                let freqResolution = sampleRate / Float(fftSize)
                var weightedSum: Float = 0
                var magSum: Float = 0
                for i in 1..<halfN { // skip DC
                    let freq = Float(i) * freqResolution
                    weightedSum += freq * magnitudes[i]
                    magSum += magnitudes[i]
                }
                let centroid = magSum > 0 ? weightedSum / magSum : 0

                // Compute spectral flatness: geometric_mean / arithmetic_mean
                // Use log domain: exp(mean(log(x))) / mean(x)
                var logSum: Float = 0
                var arithmeticSum: Float = 0
                var validBins = 0
                for i in 1..<halfN {
                    if magnitudes[i] > 1e-10 {
                        logSum += log(magnitudes[i])
                        arithmeticSum += magnitudes[i]
                        validBins += 1
                    }
                }

                let flatness: Float
                if validBins > 0 && arithmeticSum > 0 {
                    let geometricMean = exp(logSum / Float(validBins))
                    let arithmeticMean = arithmeticSum / Float(validBins)
                    flatness = min(geometricMean / arithmeticMean, 1.0)
                } else {
                    flatness = 0
                }

                realOut[0] = centroid
                realOut[1] = flatness
            }
        }

        return (realOut[0], realOut[1])
    }
}

// MARK: - Classification Logic

extension AudioSourceClassifier {

    /// Classify a single window based on its features.
    func classifyWindow(features: AudioFeatures) -> AudioSource {
        // Rule 1: Silence — below noise floor
        if features.dbFS < -50 || features.rms < 0.003 {
            return .silence
        }

        // Rule 2: Background noise — high spectral flatness, low energy, high ZCR
        if features.spectralFlatness > 0.6 && features.rms < 0.02 && features.zeroCrossingRate > 0.15 {
            return .background
        }

        // Rule 3: Playback detection
        // Playback audio characteristics:
        // - Lower dynamic range (compressed)
        // - More consistent energy (low variance)
        // - Lower crest factor (compression reduces transients)
        // - Audible but quieter than direct mic
        // - Often lower spectral centroid (muffled through speakers)
        //
        // Multiple detection paths — playback can manifest differently:

        // Path A: Classic playback — steady, compressed, moderate volume
        let classicPlayback =
            features.dynamicRange < 12.0 &&
            features.energyVariance < 0.0005 &&
            features.crestFactor < 5.0 &&
            features.rms > 0.005 &&
            features.rms < 0.03

        // Path B: Quiet playback — very consistent low energy, not silence
        // This catches TV/laptop audio picked up by room mic
        let quietPlayback =
            features.rms > 0.003 &&
            features.rms < 0.015 &&
            features.energyVariance < 0.0001 &&
            features.zeroCrossingRate > 0.05 &&
            features.dynamicRange < 6.0

        // Path C: Spectral signature — playback has different spectral shape
        // Compressed audio through speakers has higher spectral flatness than live voice
        // but lower than pure noise
        let spectralPlayback =
            features.spectralFlatness > 0.3 &&
            features.spectralFlatness < 0.6 &&
            features.energyVariance < 0.0003 &&
            features.rms > 0.003 &&
            features.rms < 0.025

        if classicPlayback || quietPlayback || spectralPlayback {
            return .playback
        }

        // Rule 4: Live speech — everything else with speech-like characteristics
        // Natural speech has:
        // - Higher dynamic range (natural pauses, emphasis)
        // - Higher energy variance
        // - Moderate ZCR (voiced sounds)
        // - Higher crest factor (plosives, transients)
        if features.rms > 0.005 {
            return .liveSpeech
        }

        return .background
    }

    /// Smooth classifications: a single-window outlier gets overridden by neighbors.
    /// e.g., [liveSpeech, playback, liveSpeech] → [liveSpeech, liveSpeech, liveSpeech]
    func smooth(_ segments: [ClassifiedSegment]) -> [ClassifiedSegment] {
        guard segments.count >= 3 else { return segments }

        var smoothed = segments
        for i in 1..<(segments.count - 1) {
            let prev = segments[i - 1].source
            let curr = segments[i].source
            let next = segments[i + 1].source

            // If this window disagrees with both neighbors, adopt neighbor classification
            if curr != prev && curr != next && prev == next {
                smoothed[i] = ClassifiedSegment(
                    time: segments[i].time,
                    duration: segments[i].duration,
                    source: prev,
                    features: segments[i].features
                )
            }
        }

        return smoothed
    }
}

// MARK: - Summary

extension AudioSourceClassifier {

    /// Summarize classification results into contiguous runs.
    public static func summarize(_ segments: [ClassifiedSegment]) -> [SourceRun] {
        guard !segments.isEmpty else { return [] }

        var runs: [SourceRun] = []
        var currentSource = segments[0].source
        var runStart = segments[0].time

        for i in 1..<segments.count {
            if segments[i].source != currentSource {
                runs.append(SourceRun(
                    source: currentSource,
                    start: runStart,
                    end: segments[i].time
                ))
                currentSource = segments[i].source
                runStart = segments[i].time
            }
        }

        // Close final run
        if let last = segments.last {
            runs.append(SourceRun(
                source: currentSource,
                start: runStart,
                end: last.time + last.duration
            ))
        }

        return runs
    }
}

public struct SourceRun: Codable, Sendable {
    public let source: AudioSource
    public let start: TimeInterval
    public let end: TimeInterval
    public var duration: TimeInterval { end - start }
}
