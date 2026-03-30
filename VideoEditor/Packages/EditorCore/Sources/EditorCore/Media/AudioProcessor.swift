import Foundation
import AVFoundation
import Accelerate

/// Offline audio processing: noise reduction, voice isolation hints.
/// Processes audio files and produces cleaned output files.
public struct AudioProcessor: Sendable {

    public init() {}

    /// Apply noise gate to an audio file.
    /// Reduces audio below the threshold to silence.
    /// - Parameters:
    ///   - sourceURL: Input audio/video file
    ///   - outputURL: Where to write the cleaned audio
    ///   - thresholdDB: Noise floor in dB (default -40dB)
    ///   - attackTime: Attack time in seconds (default 0.01)
    ///   - releaseTime: Release time in seconds (default 0.1)
    public func applyNoiseGate(
        sourceURL: URL,
        outputURL: URL,
        thresholdDB: Float = -40,
        attackTime: Float = 0.01,
        releaseTime: Float = 0.1
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioProcessingError.noAudioTrack
        }

        // Read settings
        let readSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else {
            throw AudioProcessingError.readerFailed
        }
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readSettings)
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)

        // Write settings
        let writeSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
        ]

        guard let writer = try? AVAssetWriter(url: outputURL, fileType: .m4a) else {
            throw AudioProcessingError.writerFailed
        }
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writeSettings)
        writer.add(writerInput)

        guard reader.startReading(), writer.startWriting() else {
            throw AudioProcessingError.processingFailed("Failed to start reading/writing")
        }
        defer { reader.cancelReading() }
        writer.startSession(atSourceTime: .zero)

        // Process
        let threshold = pow(10.0, thresholdDB / 20.0) // Convert dB to linear

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.process")) {
                while writerInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            continuation.resume()
                        }
                        return
                    }

                    // Apply noise gate to the sample buffer
                    if let processedBuffer = self.noiseGate(sampleBuffer: sampleBuffer, threshold: threshold) {
                        writerInput.append(processedBuffer)
                    }
                }
            }
        }
    }

    /// Apply noise gate to a single sample buffer.
    private func noiseGate(sampleBuffer: CMSampleBuffer, threshold: Float) -> CMSampleBuffer? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }

        let length = CMBlockBufferGetDataLength(blockBuffer)
        let numSamples = length / MemoryLayout<Float>.size

        var data = [Float](repeating: 0, count: numSamples)
        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)

        // Apply noise gate: if RMS of a small window is below threshold, zero out
        let windowSize = 256
        for windowStart in stride(from: 0, to: numSamples, by: windowSize) {
            let windowEnd = min(windowStart + windowSize, numSamples)
            let windowCount = windowEnd - windowStart

            var rms: Float = 0
            vDSP_rmsqv(Array(data[windowStart..<windowEnd]), 1, &rms, vDSP_Length(windowCount))

            if rms < threshold {
                // Below threshold — fade to silence
                for i in windowStart..<windowEnd {
                    data[i] *= 0.01 // Attenuate by -40dB rather than hard zero
                }
            }
        }

        // Create new sample buffer with processed data
        let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)
        let timing = UnsafeMutablePointer<CMSampleTimingInfo>.allocate(capacity: 1)
        var timingInfo = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)
        timing.pointee = timingInfo

        var newBlockBuffer: CMBlockBuffer?
        let dataSize = data.count * MemoryLayout<Float>.size
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &newBlockBuffer
        )

        guard let newBlock = newBlockBuffer else { return nil }
        data.withUnsafeBufferPointer { bufferPtr in
            CMBlockBufferReplaceDataBytes(
                with: bufferPtr.baseAddress!,
                blockBuffer: newBlock,
                offsetIntoDestination: 0,
                dataLength: dataSize
            )
        }

        var newSampleBuffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: newBlock,
            formatDescription: formatDesc!,
            sampleCount: CMItemCount(numSamples),
            presentationTimeStamp: timingInfo.presentationTimeStamp,
            packetDescriptions: nil,
            sampleBufferOut: &newSampleBuffer
        )

        timing.deallocate()
        return newSampleBuffer
    }
}

public enum AudioProcessingError: Error, LocalizedError {
    case noAudioTrack
    case readerFailed
    case writerFailed
    case processingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack: "No audio track found"
        case .readerFailed: "Failed to create audio reader"
        case .writerFailed: "Failed to create audio writer"
        case .processingFailed(let msg): "Audio processing failed: \(msg)"
        }
    }
}
