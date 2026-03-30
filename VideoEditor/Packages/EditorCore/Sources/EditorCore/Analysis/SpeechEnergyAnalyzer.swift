import Foundation
import AVFoundation
import Accelerate

/// Analyzes speech energy, pace, and quality over time.
/// Returns per-second metrics for scoring segment engagement.
public struct SpeechEnergyAnalyzer: Sendable {

    /// Per-second energy reading.
    public struct EnergyReading: Sendable {
        public let time: TimeInterval       // Seconds from start
        public let rms: Float               // RMS amplitude (0-1)
        public let dbFS: Float              // Decibels full scale (-inf to 0)
        public let isSpeech: Bool           // Above speech threshold
        public let isSilence: Bool          // Below silence threshold
    }

    /// Summary of a time range's audio characteristics.
    public struct SegmentSummary: Sendable {
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let avgRMS: Float            // Average energy
        public let peakRMS: Float           // Peak energy
        public let speechRatio: Float       // % of time with speech (0-1)
        public let silenceRatio: Float      // % of time silent (0-1)
        public let energyVariance: Float    // How much energy varies (dynamic delivery)
        public let avgDBFS: Float

        public var duration: TimeInterval { endTime - startTime }

        /// Engagement score 0-100 based on audio characteristics alone.
        public var engagementScore: Int {
            var score: Float = 0
            // High speech ratio = someone is talking (good)
            score += speechRatio * 30
            // Higher energy = more engaging delivery
            score += min(avgRMS * 500, 25)  // Cap at 25
            // Energy variance = dynamic delivery (not monotone)
            score += min(energyVariance * 2000, 20)  // Cap at 20
            // Low silence = tight content
            score += (1 - silenceRatio) * 15
            // Peak energy = moments of emphasis
            score += min(peakRMS * 200, 10)  // Cap at 10
            return min(100, Int(score))
        }
    }

    private let speechThresholdDB: Float = -35   // Above this = speech
    private let silenceThresholdDB: Float = -50   // Below this = silence
    private let windowDuration: TimeInterval = 1.0 // 1 second windows

    public init() {}

    /// Analyze audio energy for the full asset. Returns per-second readings.
    public func analyze(url: URL) async -> [EnergyReading] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return [] }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { return [] }
        defer { reader.cancelReading() }

        let sampleRate = 16000
        let samplesPerWindow = Int(windowDuration * Double(sampleRate))
        var readings: [EnergyReading] = []
        var windowBuffer = [Float]()
        var windowIndex = 0

        let speechThresholdLinear = pow(10.0, speechThresholdDB / 20.0)
        let silenceThresholdLinear = pow(10.0, silenceThresholdDB / 20.0)

        while let buffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let numSamples = length / 2
            var int16Data = [Int16](repeating: 0, count: numSamples)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &int16Data)

            for sample in int16Data {
                windowBuffer.append(Float(abs(Int32(sample))) / Float(Int16.max))

                if windowBuffer.count >= samplesPerWindow {
                    var rms: Float = 0
                    vDSP_rmsqv(windowBuffer, 1, &rms, vDSP_Length(windowBuffer.count))
                    let dbFS = rms > 0 ? 20 * log10(rms) : -100
                    let time = Double(windowIndex) * windowDuration

                    readings.append(EnergyReading(
                        time: time,
                        rms: rms,
                        dbFS: dbFS,
                        isSpeech: rms > speechThresholdLinear,
                        isSilence: rms < silenceThresholdLinear
                    ))

                    windowBuffer.removeAll(keepingCapacity: true)
                    windowIndex += 1
                }
            }
        }

        // Flush remaining
        if windowBuffer.count > 100 {
            var rms: Float = 0
            vDSP_rmsqv(windowBuffer, 1, &rms, vDSP_Length(windowBuffer.count))
            let dbFS = rms > 0 ? 20 * log10(rms) : -100
            readings.append(EnergyReading(
                time: Double(windowIndex) * windowDuration,
                rms: rms,
                dbFS: dbFS,
                isSpeech: rms > speechThresholdLinear,
                isSilence: rms < silenceThresholdLinear
            ))
        }

        return readings
    }

    /// Analyze a specific time range and return a summary.
    public func analyzeRange(url: URL, start: TimeInterval, end: TimeInterval) async -> SegmentSummary {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return SegmentSummary(startTime: start, endTime: end, avgRMS: 0, peakRMS: 0, speechRatio: 0, silenceRatio: 1, energyVariance: 0, avgDBFS: -100)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else {
            return SegmentSummary(startTime: start, endTime: end, avgRMS: 0, peakRMS: 0, speechRatio: 0, silenceRatio: 1, energyVariance: 0, avgDBFS: -100)
        }
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else {
            return SegmentSummary(startTime: start, endTime: end, avgRMS: 0, peakRMS: 0, speechRatio: 0, silenceRatio: 1, energyVariance: 0, avgDBFS: -100)
        }
        defer { reader.cancelReading() }

        let sampleRate = 16000
        let samplesPerWindow = Int(windowDuration * Double(sampleRate))
        var windowBuffer = [Float]()
        var windowRMSValues = [Float]()

        let speechThresholdLinear = pow(10.0, speechThresholdDB / 20.0)
        let silenceThresholdLinear = pow(10.0, silenceThresholdDB / 20.0)
        var speechWindows = 0
        var silenceWindows = 0

        while let buffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let numSamples = length / 2
            var int16Data = [Int16](repeating: 0, count: numSamples)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &int16Data)

            for sample in int16Data {
                windowBuffer.append(Float(abs(Int32(sample))) / Float(Int16.max))
                if windowBuffer.count >= samplesPerWindow {
                    var rms: Float = 0
                    vDSP_rmsqv(windowBuffer, 1, &rms, vDSP_Length(windowBuffer.count))
                    windowRMSValues.append(rms)
                    if rms > speechThresholdLinear { speechWindows += 1 }
                    if rms < silenceThresholdLinear { silenceWindows += 1 }
                    windowBuffer.removeAll(keepingCapacity: true)
                }
            }
        }

        guard !windowRMSValues.isEmpty else {
            return SegmentSummary(startTime: start, endTime: end, avgRMS: 0, peakRMS: 0, speechRatio: 0, silenceRatio: 1, energyVariance: 0, avgDBFS: -100)
        }

        let n = vDSP_Length(windowRMSValues.count)
        var avg: Float = 0
        vDSP_meanv(windowRMSValues, 1, &avg, n)
        let peak = windowRMSValues.max() ?? 0

        // Variance
        var meanSq: Float = 0
        var sq = [Float](repeating: 0, count: windowRMSValues.count)
        vDSP_vsq(windowRMSValues, 1, &sq, 1, n)
        vDSP_meanv(sq, 1, &meanSq, n)
        let variance = max(meanSq - avg * avg, 0)

        let total = Float(windowRMSValues.count)
        let avgDB = avg > 0 ? 20 * log10(avg) : -100

        return SegmentSummary(
            startTime: start,
            endTime: end,
            avgRMS: avg,
            peakRMS: peak,
            speechRatio: Float(speechWindows) / total,
            silenceRatio: Float(silenceWindows) / total,
            energyVariance: variance,
            avgDBFS: avgDB
        )
    }

    /// Score multiple segments and rank them by audio engagement.
    public func rankSegments(url: URL, segments: [(start: TimeInterval, end: TimeInterval)]) async -> [(start: TimeInterval, end: TimeInterval, summary: SegmentSummary)] {
        var results: [(start: TimeInterval, end: TimeInterval, summary: SegmentSummary)] = []
        for seg in segments {
            let summary = await analyzeRange(url: url, start: seg.start, end: seg.end)
            results.append((seg.start, seg.end, summary))
        }
        return results.sorted { $0.summary.engagementScore > $1.summary.engagementScore }
    }
}
