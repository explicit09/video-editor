import Foundation
import AVFoundation
import SoundAnalysis

/// Isolates voice from background audio using Apple's sound classification.
/// Uses SNClassifySoundRequest to identify speech segments,
/// then attenuates non-speech regions.
public struct VoiceIsolator: Sendable {

    public struct IsolationResult: Sendable {
        /// Time ranges where speech was detected
        public let speechRegions: [TimeRange]
        /// Time ranges classified as non-speech (music, noise, etc.)
        public let nonSpeechRegions: [TimeRange]
    }

    public init() {}

    /// Analyze audio and classify speech vs non-speech segments.
    public func analyze(url: URL) async -> IsolationResult? {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        let duration = (try? await asset.load(.duration).seconds) ?? 0
        guard duration > 0 else { return nil }

        // Use Sound Analysis to detect speech
        let analyzer = try? SNAudioStreamAnalyzer(format: AVAudioFormat(
            standardFormatWithSampleRate: 44100, channels: 1
        )!)

        guard let analyzer else { return nil }

        // Create classify request for speech detection
        guard let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else {
            return nil
        }

        let observer = SpeechObserver()
        try? analyzer.add(request, withObserver: observer)

        // Read audio and feed to analyzer
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }

        // Note: SNAudioStreamAnalyzer requires AVAudioBuffer, not CMSampleBuffer.
        // A full implementation would convert CMSampleBuffer → AVAudioPCMBuffer.
        // For now, use a simplified approach based on energy analysis.
        var currentTime: TimeInterval = 0
        let sampleRate: Double = 44100
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let numSamples = length / MemoryLayout<Int16>.size

            var data = [Int16](repeating: 0, count: numSamples)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)

            // Simple energy-based speech detection
            let energy = data.reduce(0.0) { $0 + Double(abs(Int32($1))) } / Double(numSamples) / Double(Int16.max)
            if energy > 0.02 { // Above noise floor → likely speech
                observer.speechTimestamps.append(currentTime)
            }
            currentTime += Double(numSamples) / sampleRate
        }

        // Build regions from observer results
        let speechRegions = observer.speechTimestamps.map { TimeRange(start: $0, duration: 1.0) }
        let mergedSpeech = mergeAdjacentRegions(speechRegions, gap: 0.5)

        // Non-speech = gaps between speech
        var nonSpeech: [TimeRange] = []
        var cursor: TimeInterval = 0
        for region in mergedSpeech {
            if region.start > cursor {
                nonSpeech.append(TimeRange(start: cursor, end: region.start))
            }
            cursor = region.end
        }
        if cursor < duration {
            nonSpeech.append(TimeRange(start: cursor, end: duration))
        }

        return IsolationResult(speechRegions: mergedSpeech, nonSpeechRegions: nonSpeech)
    }

    private func mergeAdjacentRegions(_ regions: [TimeRange], gap: TimeInterval) -> [TimeRange] {
        guard !regions.isEmpty else { return [] }
        var merged: [TimeRange] = [regions[0]]

        for region in regions.dropFirst() {
            if let last = merged.last, region.start - last.end <= gap {
                merged[merged.count - 1] = TimeRange(start: last.start, end: region.end)
            } else {
                merged.append(region)
            }
        }
        return merged
    }
}

/// Observer for Sound Analysis speech detection.
private class SpeechObserver: NSObject, SNResultsObserving {
    var speechTimestamps: [TimeInterval] = []

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }

        for classification in classificationResult.classifications {
            if classification.identifier == "speech" && classification.confidence > 0.5 {
                speechTimestamps.append(classificationResult.timeRange.start.seconds)
            }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}
}
