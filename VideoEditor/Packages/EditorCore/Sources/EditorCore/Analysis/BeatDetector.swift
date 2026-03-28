import Foundation
import AVFoundation
import Accelerate

/// Detects beats and tempo (BPM) from audio for cut-to-beat editing.
/// Uses onset detection via spectral flux analysis.
public struct BeatDetector: Sendable {

    public struct BeatAnalysis: Sendable {
        /// Estimated tempo in beats per minute
        public let bpm: Double
        /// Beat timestamps in seconds
        public let beats: [TimeInterval]
        /// Strong beat timestamps (downbeats / bar starts)
        public let strongBeats: [TimeInterval]
    }

    public init() {}

    /// Analyze audio and detect beats.
    public func analyze(url: URL) async -> BeatAnalysis? {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { return nil }

        // Read all samples
        var allSamples: [Float] = []
        let sampleRate: Double = 44100

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let numSamples = length / MemoryLayout<Int16>.size
            var data = [Int16](repeating: 0, count: numSamples)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)

            // Convert to float and take absolute value for envelope
            let floats = data.map { Float(abs(Int32($0))) / Float(Int16.max) }
            allSamples.append(contentsOf: floats)
        }

        guard allSamples.count > Int(sampleRate) else { return nil }

        // Compute onset detection function using energy in windows
        let windowSize = Int(sampleRate * 0.02) // 20ms windows
        let hopSize = windowSize / 2
        var onsets: [Float] = []
        var previousEnergy: Float = 0

        for start in stride(from: 0, to: allSamples.count - windowSize, by: hopSize) {
            let window = Array(allSamples[start..<(start + windowSize)])
            var energy: Float = 0
            vDSP_measqv(window, 1, &energy, vDSP_Length(windowSize))

            // Onset = positive energy increase
            let onset = max(energy - previousEnergy, 0)
            onsets.append(onset)
            previousEnergy = energy
        }

        // Find peaks in onset function (beats)
        let beats = findPeaks(onsets, hopSize: hopSize, sampleRate: sampleRate)

        // Estimate BPM from inter-beat intervals
        let bpm = estimateBPM(beats)

        // Identify strong beats (every 4th beat approximately)
        let strongBeats = identifyStrongBeats(beats, bpm: bpm)

        return BeatAnalysis(bpm: bpm, beats: beats, strongBeats: strongBeats)
    }

    /// Find peaks in the onset detection function.
    private func findPeaks(_ onsets: [Float], hopSize: Int, sampleRate: Double) -> [TimeInterval] {
        guard onsets.count > 2 else { return [] }

        // Adaptive threshold: median * 1.5
        let sorted = onsets.sorted()
        let median = sorted[sorted.count / 2]
        let threshold = median * 2.0

        var peaks: [TimeInterval] = []
        let minPeakDistance = 8 // Minimum ~160ms between beats at 44.1kHz

        for i in 1..<(onsets.count - 1) {
            if onsets[i] > threshold &&
               onsets[i] > onsets[i - 1] &&
               onsets[i] >= onsets[i + 1] {
                let time = Double(i * hopSize) / sampleRate
                if peaks.isEmpty || (time - peaks.last!) > Double(minPeakDistance * hopSize) / sampleRate {
                    peaks.append(time)
                }
            }
        }

        return peaks
    }

    /// Estimate BPM from beat timestamps using inter-beat intervals.
    private func estimateBPM(_ beats: [TimeInterval]) -> Double {
        guard beats.count >= 3 else { return 120 } // default

        var intervals: [Double] = []
        for i in 1..<beats.count {
            intervals.append(beats[i] - beats[i - 1])
        }

        // Use median interval for robustness
        let sorted = intervals.sorted()
        let medianInterval = sorted[sorted.count / 2]

        guard medianInterval > 0 else { return 120 }
        let bpm = 60.0 / medianInterval

        // Clamp to reasonable range
        if bpm < 60 { return bpm * 2 }
        if bpm > 200 { return bpm / 2 }
        return bpm
    }

    /// Identify strong beats (downbeats) — approximately every 4 beats.
    private func identifyStrongBeats(_ beats: [TimeInterval], bpm: Double) -> [TimeInterval] {
        guard !beats.isEmpty else { return [] }

        let beatInterval = 60.0 / bpm
        let barLength = beatInterval * 4 // 4/4 time

        var strongBeats: [TimeInterval] = [beats[0]]
        var lastStrong = beats[0]

        for beat in beats.dropFirst() {
            if beat - lastStrong >= barLength * 0.9 { // Within 10% of a full bar
                strongBeats.append(beat)
                lastStrong = beat
            }
        }

        return strongBeats
    }

    /// Suggest cut points that align with beats.
    /// Returns the nearest beat time for each requested cut point.
    public func snapToBeats(_ times: [TimeInterval], beats: [TimeInterval]) -> [TimeInterval] {
        times.map { time in
            beats.min(by: { abs($0 - time) < abs($1 - time) }) ?? time
        }
    }
}
