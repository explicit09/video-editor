import Foundation
import AVFoundation
import Accelerate

/// Scans audio for silence regions and compares against expected timeline coverage.
public struct SilenceMapper: Sendable {

    /// A detected silence region in the audio.
    public struct SilenceRegion: Sendable {
        public let start: TimeInterval
        public let end: TimeInterval
        public let isExpected: Bool   // true if no clip covers this region
        public var duration: TimeInterval { end - start }
    }

    /// RMS threshold below which audio is considered silent.
    private let silenceThreshold: Float = 0.002

    /// Window size in seconds for RMS computation.
    private let windowDuration: TimeInterval = 0.1

    /// Minimum silence duration to report (avoids flagging brief pauses).
    private let minSilenceDuration: TimeInterval = 0.3

    public init() {}

    /// Scan audio in a composition and find all silence regions.
    /// Compares against expected coverage from the timeline.
    public func scan(
        composition: AVMutableComposition,
        timeline: Timeline
    ) async -> [SilenceRegion] {
        let rmsProfile = await computeRMSProfile(asset: composition)
        guard !rmsProfile.isEmpty else { return [] }

        // Find raw silence regions from RMS profile
        var rawSilences: [(start: TimeInterval, end: TimeInterval)] = []
        var silenceStart: TimeInterval?

        for (index, rms) in rmsProfile.enumerated() {
            let time = Double(index) * windowDuration
            if rms < silenceThreshold {
                if silenceStart == nil { silenceStart = time }
            } else {
                if let start = silenceStart {
                    let end = time
                    if end - start >= minSilenceDuration {
                        rawSilences.append((start, end))
                    }
                    silenceStart = nil
                }
            }
        }
        // Close trailing silence
        if let start = silenceStart {
            let end = Double(rmsProfile.count) * windowDuration
            if end - start >= minSilenceDuration {
                rawSilences.append((start, end))
            }
        }

        // Build expected audio coverage from timeline
        let audioCoverage = buildAudioCoverage(from: timeline)

        // Classify each silence region as expected or unexpected
        return rawSilences.map { silence in
            let isExpected = !audioCoverage.contains { coverage in
                // Silence overlaps with expected audio coverage
                silence.start < coverage.end && silence.end > coverage.start
            }
            return SilenceRegion(start: silence.start, end: silence.end, isExpected: isExpected)
        }
    }

    /// Quick check: count unexpected silence regions.
    public func unexpectedSilenceCount(
        composition: AVMutableComposition,
        timeline: Timeline
    ) async -> Int {
        let regions = await scan(composition: composition, timeline: timeline)
        return regions.filter { !$0.isExpected }.count
    }

    // MARK: - Private

    /// Compute RMS levels in windows across the full audio.
    private func computeRMSProfile(asset: AVAsset) async -> [Float] {
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

        let samplesPerWindow = Int(windowDuration * 16000)
        var profile: [Float] = []
        var windowBuffer = [Float]()

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
                    profile.append(rms)
                    windowBuffer.removeAll(keepingCapacity: true)
                }
            }
        }

        // Flush remaining
        if windowBuffer.count > 50 {
            var rms: Float = 0
            vDSP_rmsqv(windowBuffer, 1, &rms, vDSP_Length(windowBuffer.count))
            profile.append(rms)
        }

        return profile
    }

    /// Build time ranges where audio should be present (from non-muted tracks with clips).
    private func buildAudioCoverage(from timeline: Timeline) -> [TimeRange] {
        var ranges: [TimeRange] = []
        for track in timeline.tracks where !track.isMuted {
            for clip in track.clips {
                ranges.append(clip.timelineRange)
            }
        }
        // Merge overlapping ranges
        let sorted = ranges.sorted { $0.start < $1.start }
        var merged: [TimeRange] = []
        for range in sorted {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1] = TimeRange(start: last.start, end: max(last.end, range.end))
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
