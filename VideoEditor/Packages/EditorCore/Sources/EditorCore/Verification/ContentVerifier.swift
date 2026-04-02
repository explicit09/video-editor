import Foundation
import AVFoundation

/// Tier 2 content verification: verifies the RIGHT content plays at the RIGHT time.
/// Reads directly from the AVMutableComposition (no export needed for most checks).
public struct ContentVerifier: Sendable {
    static let silenceThreshold: Float = 0.005

    struct AudioVerificationContext: Sendable {
        let assetType: MediaType
        let trackType: TrackType?
        let activeAudioClipCount: Int

        var shouldCompareSourceAudio: Bool {
            guard assetType != .image else { return false }
            guard activeAudioClipCount <= 1 else { return false }

            switch trackType {
            case .video?, .audio?:
                return true
            default:
                return assetType == .audio
            }
        }
    }

    struct VisualVerificationContext: Sendable {
        let assetType: MediaType
        let trackType: TrackType?
        let clip: Clip?

        var shouldCompareSourceVideo: Bool {
            guard assetType == .video else { return false }
            guard trackType == .video else { return false }
            guard let clip else { return true }
            guard clip.transform == .identity else { return false }
            guard clip.cropRect.isFullFrame else { return false }
            guard clip.opacity >= 0.999 else { return false }
            guard clip.effects.isEmpty else { return false }
            guard clip.blendMode == .normal else { return false }
            guard clip.transitionIn.type == .none else { return false }
            return true
        }
    }

    public enum Mode: Sendable {
        case quick     // ~2s: check 2 points per clip
        case thorough  // ~5-10s: check all clip boundaries + silence scan
    }

    /// Result for a single checkpoint.
    public struct CheckResult: Sendable {
        public let checkpoint: VerificationCheckpoint
        public let audioNCC: Float?       // Normalized cross-correlation (nil if no source to compare)
        public let videoPHashDist: Int?   // Perceptual hash hamming distance (nil if no video)
        public let audioRMS: Float        // Audio level at this point
        public let frameValid: Bool       // Frame is not black
        public let effectChecks: [EffectPropertyChecker.EffectCheckResult]
        public let passed: Bool
        public let detail: String

        public var statusIcon: String { passed ? "PASS" : "FAIL" }
    }

    /// Full verification report.
    public struct Report: Sendable {
        public let checkResults: [CheckResult]
        public let unexpectedSilences: [SilenceMapper.SilenceRegion]
        public let expectedDuration: TimeInterval
        public let actualDuration: TimeInterval
        public let durationMatch: Bool
        public let mode: Mode

        public var passCount: Int { checkResults.filter(\.passed).count }
        public var failCount: Int { checkResults.filter { !$0.passed }.count }
        public var totalChecks: Int { checkResults.count }
        public var allPassed: Bool { failCount == 0 && durationMatch && unexpectedSilences.isEmpty }

        /// Human-readable report string.
        public var summary: String {
            var lines: [String] = []
            lines.append("=== CONTENT VERIFICATION ===")
            lines.append("Mode: \(mode == .quick ? "quick" : "thorough") | Checkpoints: \(totalChecks) | Duration: expected \(fmt(expectedDuration))s, actual \(fmt(actualDuration))s \(durationMatch ? "✓" : "✗")")
            lines.append("")

            for r in checkResults {
                var detail = "[\(r.statusIcon)] \(r.checkpoint.label) @ \(fmt(r.checkpoint.exportTime))s:"
                if let ncc = r.audioNCC { detail += " audio NCC=\(String(format: "%.2f", ncc))" }
                if let dist = r.videoPHashDist { detail += " video pHash=\(dist)" }
                detail += " RMS=\(String(format: "%.4f", r.audioRMS))"
                if !r.detail.isEmpty { detail += " — \(r.detail)" }
                lines.append(detail)
                for ec in r.effectChecks {
                    lines.append("    \(ec.passed ? "✓" : "✗") \(ec.effectType): \(ec.detail)")
                }
            }

            if !unexpectedSilences.isEmpty {
                lines.append("")
                lines.append("Unexpected silence regions:")
                for s in unexpectedSilences {
                    lines.append("  ⚠ \(fmt(s.start))s-\(fmt(s.end))s (\(fmt(s.duration))s)")
                }
            }

            lines.append("")
            lines.append("Result: \(passCount)/\(totalChecks) PASS\(failCount > 0 ? ", \(failCount) FAIL" : "")\(unexpectedSilences.isEmpty ? "" : ", \(unexpectedSilences.count) unexpected silence")")

            return lines.joined(separator: "\n")
        }

        private func fmt(_ v: TimeInterval) -> String { String(format: "%.1f", v) }
    }

    // MARK: - Audio NCC thresholds
    private let nccPassThreshold: Float = 0.7
    private let pHashPassThreshold: Int = 15

    public init() {}

    /// Run verification on a built composition against its source timeline.
    /// Pass videoComposition if available (needed for multi-track frame extraction).
    public func verify(
        composition: AVMutableComposition,
        timeline: Timeline,
        assets: [MediaAsset],
        videoComposition: AVVideoComposition? = nil,
        mode: Mode = .quick
    ) async -> Report {
        let checkpointGen = CheckpointGenerator()
        var allCheckpoints = checkpointGen.generate(from: timeline)

        // In quick mode, reduce to 2 per clip (start + mid only)
        if mode == .quick {
            allCheckpoints = reduceToQuick(allCheckpoints)
        }

        let audioCorrelator = AudioCrossCorrelator()
        let hasher = PerceptualHasher()
        let vidComp = videoComposition
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let clipsByID = Dictionary(uniqueKeysWithValues: timeline.tracks.flatMap { track in
            track.clips.map { ($0.id, $0) }
        })
        let trackTypeByClipID: [UUID: TrackType] = Dictionary(
            uniqueKeysWithValues: timeline.tracks.flatMap { track in
                track.clips.map { ($0.id, track.type) }
            }
        )
        let activeAudioClipCountAtTime: (TimeInterval) -> Int = { exportTime in
            timeline.tracks
                .filter { $0.type == .audio && !$0.isMuted }
                .flatMap(\.clips)
                .filter { clip in
                    exportTime >= clip.timelineRange.start && exportTime < clip.timelineRange.end
                }
                .count
        }

        var results: [CheckResult] = []

        for cp in allCheckpoints {
            switch cp.checkType {
            case .content, .effectApplied:
                let audioContext: AudioVerificationContext? = {
                    guard let assetID = cp.assetID, let asset = assetsByID[assetID] else { return nil }
                    let trackType = cp.clipID.flatMap { trackTypeByClipID[$0] }
                    return AudioVerificationContext(
                        assetType: asset.type,
                        trackType: trackType,
                        activeAudioClipCount: activeAudioClipCountAtTime(cp.exportTime)
                    )
                }()
                let visualContext: VisualVerificationContext? = {
                    guard let assetID = cp.assetID, let asset = assetsByID[assetID] else { return nil }
                    return VisualVerificationContext(
                        assetType: asset.type,
                        trackType: cp.clipID.flatMap { trackTypeByClipID[$0] },
                        clip: cp.clipID.flatMap { clipsByID[$0] }
                    )
                }()
                let result = await verifyContentCheckpoint(
                    cp: cp,
                    composition: composition,
                    videoComposition: vidComp,
                    assetsByID: assetsByID,
                    audioCorrelator: audioCorrelator,
                    hasher: hasher,
                    audioContext: audioContext,
                    visualContext: visualContext
                )
                results.append(result)

            case .silence:
                let rms = await audioCorrelator.measureRMS(in: composition, at: cp.exportTime)
                let isSilent = rms < 0.005
                results.append(CheckResult(
                    checkpoint: cp,
                    audioNCC: nil,
                    videoPHashDist: nil,
                    audioRMS: rms,
                    frameValid: true,
                    effectChecks: [],
                    passed: isSilent,
                    detail: isSilent ? "silent as expected" : "audio present in expected gap"
                ))
            }
        }

        // Silence scan (thorough mode only)
        var unexpectedSilences: [SilenceMapper.SilenceRegion] = []
        if mode == .thorough {
            let mapper = SilenceMapper()
            let allSilences = await mapper.scan(composition: composition, timeline: timeline)
            unexpectedSilences = allSilences.filter { !$0.isExpected }
        }

        let expectedDuration = timeline.duration
        let actualDuration = composition.duration.seconds
        let durationMatch = abs(expectedDuration - actualDuration) < 0.1

        return Report(
            checkResults: results,
            unexpectedSilences: unexpectedSilences,
            expectedDuration: expectedDuration,
            actualDuration: actualDuration,
            durationMatch: durationMatch,
            mode: mode
        )
    }

    // MARK: - Private

    private func verifyContentCheckpoint(
        cp: VerificationCheckpoint,
        composition: AVMutableComposition,
        videoComposition: AVVideoComposition?,
        assetsByID: [UUID: MediaAsset],
        audioCorrelator: AudioCrossCorrelator,
        hasher: PerceptualHasher,
        audioContext: AudioVerificationContext?,
        visualContext: VisualVerificationContext?
    ) async -> CheckResult {
        // Audio check: cross-correlate with source
        var audioNCC: Float? = nil
        var sourceRMS: Float? = nil
        if let assetID = cp.assetID,
           let asset = assetsByID[assetID],
           let sourceTime = cp.expectedSourceTime,
           audioContext?.shouldCompareSourceAudio == true {
            audioNCC = await audioCorrelator.compare(
                compositionAudio: composition,
                at: cp.exportTime,
                sourceURL: asset.sourceURL,
                at: sourceTime
            )
            sourceRMS = await measureSourceRMS(asset: AVURLAsset(url: asset.sourceURL), at: sourceTime)
        }

        // Audio RMS
        let rms = await audioCorrelator.measureRMS(in: composition, at: cp.exportTime)

        // Video check: pHash comparison with source
        var pHashDist: Int? = nil
        var frameValid = true
        var sourceFrameValid: Bool? = nil
        if let assetID = cp.assetID,
           let asset = assetsByID[assetID],
           asset.type == .video {
            frameValid = await hasher.frameIsValid(composition: composition, at: cp.exportTime, videoComposition: videoComposition)
            if let sourceTime = cp.expectedSourceTime {
                sourceFrameValid = await hasher.frameIsValid(sourceURL: asset.sourceURL, at: sourceTime)
            }

            if let sourceTime = cp.expectedSourceTime,
               visualContext?.shouldCompareSourceVideo != false {
                let exportHash = await hasher.hash(composition: composition, at: cp.exportTime, videoComposition: videoComposition)
                let sourceHash = await hasher.hash(sourceURL: asset.sourceURL, at: sourceTime)
                if exportHash != 0 && sourceHash != 0 {
                    pHashDist = hasher.distance(exportHash, sourceHash)
                }
            }
        }

        // Determine pass/fail
        var passed = true
        var detail = ""

        if let ncc = audioNCC {
            if cp.checkType == .effectApplied || cp.speed != 1.0 {
                // Effects or speed changes alter audio — just check it's not silent
                if rms < 0.001 {
                    // Only fail if source also has audio (it might be a genuinely quiet section)
                    if Self.shouldFailSilentComposition(compositionRMS: rms, sourceRMS: sourceRMS) {
                        passed = false
                        detail = "audio silent \(cp.speed != 1.0 ? "at \(String(format: "%.2f", cp.speed))x speed" : "with effect")"
                    }
                }
            } else if Self.shouldFailAudioMismatch(ncc: ncc, sourceRMS: sourceRMS, threshold: nccPassThreshold) {
                passed = false
                detail = "audio content mismatch (NCC=\(String(format: "%.2f", ncc))<\(nccPassThreshold))"
            }
        }

        if rms < 0.001 && cp.checkType != .silence {
            // No audio at all where we expect content
            if let assetID = cp.assetID, let asset = assetsByID[assetID], asset.type == .video {
                // Video asset should have audio (unless source is also silent)
                if Self.shouldFailSilentComposition(compositionRMS: rms, sourceRMS: sourceRMS) {
                    let srcRMS = sourceRMS ?? 0
                    passed = false
                    detail += (detail.isEmpty ? "" : "; ") + "silent but source has audio (srcRMS=\(String(format: "%.4f", srcRMS)))"
                }
            }
        }

        if Self.shouldFailBlackFrame(frameValid: frameValid, sourceFrameValid: sourceFrameValid) {
            passed = false
            detail += (detail.isEmpty ? "" : "; ") + "black frame"
        }

        if let dist = pHashDist, dist > pHashPassThreshold, cp.checkType == .content {
            passed = false
            detail += (detail.isEmpty ? "" : "; ") + "video content mismatch (pHash dist=\(dist)>\(pHashPassThreshold))"
        }

        // Effect verification: check that effects actually changed the frame
        var effectChecks: [EffectPropertyChecker.EffectCheckResult] = []
        if cp.checkType == .effectApplied, !cp.effects.isEmpty,
           let assetID = cp.assetID,
           let asset = assetsByID[assetID],
           asset.type == .video,
           let sourceTime = cp.expectedSourceTime {
            let checker = EffectPropertyChecker()
            if let compFrame = hasher.extractFramePublic(from: composition, at: cp.exportTime, videoComposition: videoComposition),
               let srcFrame = hasher.extractFramePublic(from: AVURLAsset(url: asset.sourceURL), at: sourceTime) {
                effectChecks = checker.check(compositionFrame: compFrame, sourceFrame: srcFrame, effects: cp.effects)
                for ec in effectChecks where !ec.passed {
                    passed = false
                    detail += (detail.isEmpty ? "" : "; ") + "effect \(ec.effectType): \(ec.detail)"
                }
            }
        }

        if detail.isEmpty { detail = "OK" }

        return CheckResult(
            checkpoint: cp,
            audioNCC: audioNCC,
            videoPHashDist: pHashDist,
            audioRMS: rms,
            frameValid: frameValid,
            effectChecks: effectChecks,
            passed: passed,
            detail: detail
        )
    }

    private func measureSourceRMS(asset: AVURLAsset, at time: TimeInterval) async -> Float {
        let correlator = AudioCrossCorrelator()
        // Create a trivial composition from the source to use the correlator's extractPCM
        let comp = AVMutableComposition()
        if let track = try? await asset.loadTracks(withMediaType: .audio).first,
           let compTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let sourceRange = CMTimeRange(
                start: CMTime(seconds: max(time - 1, 0), preferredTimescale: 600),
                duration: CMTime(seconds: 2, preferredTimescale: 600)
            )
            try? compTrack.insertTimeRange(sourceRange, of: track, at: .zero)
            return await correlator.measureRMS(in: comp, at: 0.5)
        }
        return 0
    }

    private func reduceToQuick(_ checkpoints: [VerificationCheckpoint]) -> [VerificationCheckpoint] {
        // Keep first and second checkpoint per clip, plus all silence checks
        var count: [UUID: Int] = [:]
        return checkpoints.filter { cp in
            if cp.checkType == .silence { return true }
            guard let clipID = cp.clipID else { return true }
            let c = count[clipID, default: 0]
            count[clipID] = c + 1
            return c < 2  // Keep first 2 per clip
        }
    }

    static func shouldFailAudioMismatch(ncc: Float, sourceRMS: Float?, threshold: Float) -> Bool {
        guard ncc < threshold else { return false }
        guard let sourceRMS else { return true }
        return sourceRMS > silenceThreshold
    }

    static func shouldFailSilentComposition(compositionRMS: Float, sourceRMS: Float?) -> Bool {
        guard compositionRMS < 0.001 else { return false }
        guard let sourceRMS else { return false }
        return sourceRMS > silenceThreshold
    }

    static func shouldFailBlackFrame(frameValid: Bool, sourceFrameValid: Bool?) -> Bool {
        guard !frameValid else { return false }
        guard let sourceFrameValid else { return true }
        return sourceFrameValid
    }
}
