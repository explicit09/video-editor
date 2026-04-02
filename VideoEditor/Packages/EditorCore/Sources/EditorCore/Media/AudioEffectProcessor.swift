import Foundation
import AVFoundation
import Accelerate

/// Processes audio through an effect chain (EQ, compression, noise gate, de-esser).
/// Uses AVAssetReader/Writer for offline processing — not real-time.
public struct AudioEffectProcessor: Sendable {

    public init() {}

    /// Process audio from a source URL through an effect chain, writing to output URL.
    public func process(
        inputURL: URL,
        outputURL: URL,
        effectChain: AudioEffectChain,
        sampleRate: Double = 44100
    ) async throws {
        let asset = AVURLAsset(url: inputURL)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioEffectError.noAudioTrack
        }

        try? FileManager.default.removeItem(at: outputURL)

        let reader = try AVAssetReader(asset: asset)
        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        writer.add(writerInput)

        guard reader.startReading() else {
            throw AudioEffectError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        defer { reader.cancelReading() }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Build EQ biquad coefficients
        var eqFilters: [BiquadFilter] = []
        if let eq = effectChain.eq {
            for band in eq.bands where band.gain != 0 {
                let biquad = BiquadFilter.peakingEQ(
                    frequency: band.frequency,
                    gain: band.gain,
                    bandwidth: band.bandwidth,
                    sampleRate: sampleRate
                )
                eqFilters.append(biquad)
            }
        }

        // Compressor state
        var compEnvelope: Float = 0
        let compSettings = effectChain.compressor

        // Noise gate threshold
        let noiseGateThresholdLinear: Float? = effectChain.noiseGateThreshold.map { Float(pow(10.0, $0 / 20.0)) }

        // De-esser state
        var deEsserFilter: BiquadFilter? = nil
        var deEsserEnvelope: Float = 0
        if let freq = effectChain.deEsserFrequency, freq > 0 {
            deEsserFilter = BiquadFilter.bandpass(frequency: freq, q: 2.0, sampleRate: sampleRate)
        }

        // Process buffers
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let sampleCount = length / MemoryLayout<Float>.size
            var samples = [Float](repeating: 0, count: sampleCount)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &samples)

            // Apply noise gate
            if let threshold = noiseGateThresholdLinear {
                applyNoiseGate(&samples, threshold: threshold)
            }

            // Apply EQ (cascade of biquad filters)
            for i in 0..<eqFilters.count {
                eqFilters[i].process(&samples)
            }

            // Apply compression
            if let comp = compSettings {
                applyCompression(&samples, settings: comp, envelope: &compEnvelope, sampleRate: Float(sampleRate))
            }

            // Apply de-esser (after EQ and compression)
            if deEsserFilter != nil {
                applyDeEsser(&samples, sidechainFilter: &deEsserFilter!, envelope: &deEsserEnvelope, sampleRate: Float(sampleRate))
            }

            // Write processed samples
            let processedData = samples.withUnsafeBufferPointer { Data(buffer: $0) }
            if let newBuffer = createSampleBuffer(from: processedData, sampleCount: sampleCount, sampleRate: sampleRate) {
                while !writerInput.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(10))
                }
                writerInput.append(newBuffer)
            }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw AudioEffectError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    // MARK: - Noise Gate

    private func applyNoiseGate(_ samples: inout [Float], threshold: Float) {
        for i in 0..<samples.count {
            if abs(samples[i]) < threshold {
                samples[i] = 0
            }
        }
    }

    // MARK: - Compression

    private func applyCompression(_ samples: inout [Float], settings: CompressorSettings, envelope: inout Float, sampleRate: Float) {
        let thresholdLinear = Float(pow(10.0, settings.threshold / 20.0))
        let ratio = Float(settings.ratio)
        let attackCoeff = exp(-1.0 / (Float(settings.attack) * sampleRate))
        let releaseCoeff = exp(-1.0 / (Float(settings.release) * sampleRate))
        let makeupGainLinear = Float(pow(10.0, settings.makeupGain / 20.0))

        for i in 0..<samples.count {
            let inputLevel = abs(samples[i])

            // Envelope follower
            if inputLevel > envelope {
                envelope = attackCoeff * envelope + (1 - attackCoeff) * inputLevel
            } else {
                envelope = releaseCoeff * envelope + (1 - releaseCoeff) * inputLevel
            }

            // Gain computation
            var gain: Float = 1.0
            if envelope > thresholdLinear {
                let dbOver = 20 * log10(envelope / thresholdLinear)
                let dbReduction = dbOver * (1 - 1 / ratio)
                gain = pow(10.0, -dbReduction / 20.0)
            }

            samples[i] = samples[i] * gain * makeupGainLinear
            // Soft clip to prevent overflow
            samples[i] = max(-1.0, min(1.0, samples[i]))
        }
    }

    // MARK: - De-Esser

    /// Frequency-targeted compressor using sidechain bandpass filtering.
    /// When energy in the sibilance band exceeds the threshold, the main signal is attenuated.
    private func applyDeEsser(
        _ samples: inout [Float],
        sidechainFilter: inout BiquadFilter,
        envelope: inout Float,
        sampleRate: Float
    ) {
        let threshold: Float = 0.15        // Sibilance detection threshold (linear)
        let ratio: Float = 6.0             // Heavy ratio for sibilance reduction
        let attackCoeff = exp(-1.0 / (0.001 * sampleRate))   // 1ms attack — fast to catch transients
        let releaseCoeff = exp(-1.0 / (0.02 * sampleRate))   // 20ms release

        // Run sidechain filter on a copy to detect sibilance energy
        var sidechain = samples
        sidechainFilter.process(&sidechain)

        for i in 0..<samples.count {
            let sidechainLevel = abs(sidechain[i])

            // Envelope follower on sidechain signal
            if sidechainLevel > envelope {
                envelope = attackCoeff * envelope + (1 - attackCoeff) * sidechainLevel
            } else {
                envelope = releaseCoeff * envelope + (1 - releaseCoeff) * sidechainLevel
            }

            // Attenuate main signal when sidechain exceeds threshold
            if envelope > threshold {
                let dbOver = 20 * log10(envelope / threshold)
                let dbReduction = dbOver * (1 - 1 / ratio)
                let gain = pow(10.0, -dbReduction / 20.0)
                samples[i] *= gain
            }
        }
    }

    // MARK: - Biquad EQ Filter

    struct BiquadFilter {
        var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

        /// Peaking EQ biquad coefficients (Audio EQ Cookbook by Robert Bristow-Johnson)
        static func peakingEQ(frequency: Double, gain: Double, bandwidth: Double, sampleRate: Double) -> BiquadFilter {
            let A = Float(pow(10.0, gain / 40.0))
            let w0 = Float(2.0 * Double.pi * frequency / sampleRate)
            let alpha = sin(w0) * Float(sinh(log(2.0) / 2.0 * bandwidth * Double(w0) / Double(sin(w0))))

            let b0 = 1 + alpha * A
            let b1 = -2 * cos(w0)
            let b2 = 1 - alpha * A
            let a0 = 1 + alpha / A
            let a1 = -2 * cos(w0)
            let a2 = 1 - alpha / A

            return BiquadFilter(
                b0: b0 / a0, b1: b1 / a0, b2: b2 / a0,
                a1: a1 / a0, a2: a2 / a0
            )
        }

        /// Bandpass biquad coefficients (Audio EQ Cookbook by Robert Bristow-Johnson)
        static func bandpass(frequency: Double, q: Double, sampleRate: Double) -> BiquadFilter {
            let w0 = Float(2.0 * Double.pi * frequency / sampleRate)
            let alpha = sin(w0) / Float(2.0 * q)

            let b0 = alpha
            let b1: Float = 0
            let b2 = -alpha
            let a0 = 1 + alpha
            let a1 = -2 * cos(w0)
            let a2 = 1 - alpha

            return BiquadFilter(
                b0: b0 / a0, b1: b1 / a0, b2: b2 / a0,
                a1: a1 / a0, a2: a2 / a0
            )
        }

        mutating func process(_ samples: inout [Float]) {
            for i in 0..<samples.count {
                let x0 = samples[i]
                let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = x0
                y2 = y1; y1 = y0
                samples[i] = y0
            }
        }
    }

    // MARK: - Sample Buffer Creation

    private func createSampleBuffer(from data: Data, sampleCount: Int, sampleRate: Double) -> CMSampleBuffer? {
        var blockBuffer: CMBlockBuffer?
        let dataLength = data.count

        data.withUnsafeBytes { rawPtr in
            guard let baseAddress = rawPtr.baseAddress else { return }
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: dataLength,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: dataLength,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
            if let block = blockBuffer {
                CMBlockBufferReplaceDataBytes(
                    with: baseAddress,
                    blockBuffer: block,
                    offsetIntoDestination: 0,
                    dataLength: dataLength
                )
            }
        }

        guard let block = blockBuffer else { return nil }

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard let fmt = formatDescription else { return nil }

        var sampleBuffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: fmt,
            sampleCount: sampleCount,
            presentationTimeStamp: .zero,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }
}

public enum AudioEffectError: Error, LocalizedError {
    case noAudioTrack
    case readerFailed(String)
    case writerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack: "No audio track found"
        case .readerFailed(let msg): "Audio reader failed: \(msg)"
        case .writerFailed(let msg): "Audio writer failed: \(msg)"
        }
    }
}
