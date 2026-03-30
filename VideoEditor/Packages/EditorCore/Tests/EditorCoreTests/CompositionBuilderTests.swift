import Testing
import Foundation
import AVFoundation
@testable import EditorCore

// MARK: - Synthetic Test Media Generator

/// Generates small audio+video fixtures for composition testing.
/// Video: solid color frames via AVAssetWriter (64x64, 2fps).
/// Audio: sine wave via raw WAV construction (44.1kHz mono).
struct TestMediaGenerator {
    enum VideoPattern {
        case solidColor
        case checkerboard(blockSize: Int)
    }

    let tempDir: URL

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("composition-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Generate a video+audio file with a known color and tone.
    /// Returns (url, duration) where duration is in seconds.
    func makeVideoWithAudio(
        name: String = "test",
        duration: Double = 2.0,
        color: (r: UInt8, g: UInt8, b: UInt8) = (255, 0, 0),  // red
        toneFrequency: Double = 440.0,
        pattern: VideoPattern = .solidColor,
        width: Int = 64,
        height: Int = 64,
        fps: Int = 2
    ) async throws -> URL {
        let videoURL = tempDir.appendingPathComponent("\(name)-video.mov")
        let audioURL = try makeAudioFile(name: "\(name)-audio", duration: duration, frequency: toneFrequency)
        try await writeVideoFile(
            to: videoURL,
            duration: duration,
            color: color,
            pattern: pattern,
            width: width,
            height: height,
            fps: fps
        )

        // Combine video + audio into a single file
        let combinedURL = tempDir.appendingPathComponent("\(name).mov")
        try await combineVideoAudio(videoURL: videoURL, audioURL: audioURL, outputURL: combinedURL)
        return combinedURL
    }

    /// Generate an audio-only WAV file with a sine wave.
    func makeAudioFile(
        name: String = "audio",
        duration: Double = 2.0,
        frequency: Double = 440.0,
        sampleRate: Int = 44_100,
        amplitude: Double = 0.7
    ) throws -> URL {
        let frameCount = Int(Double(sampleRate) * duration)
        var pcm = Data(capacity: frameCount * MemoryLayout<Int16>.size)

        for i in 0..<frameCount {
            let phase = 2 * Double.pi * frequency * Double(i) / Double(sampleRate)
            let sample = Int16((sin(phase) * amplitude) * Double(Int16.max))
            var le = sample.littleEndian
            pcm.append(Data(bytes: &le, count: MemoryLayout<Int16>.size))
        }

        let wav = buildWAV(pcm: pcm, sampleRate: sampleRate, channels: 1, bitsPerSample: 16)
        let url = tempDir.appendingPathComponent("\(name).wav")
        try wav.write(to: url)
        return url
    }

    // MARK: - Private helpers

    private func writeVideoFile(
        to url: URL,
        duration: Double,
        color: (r: UInt8, g: UInt8, b: UInt8),
        pattern: VideoPattern,
        width: Int,
        height: Int,
        fps: Int
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(duration * Double(fps))
        let pixelBuffer = try createPixelBuffer(width: width, height: height, color: color, pattern: pattern)

        for frame in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
            adaptor.append(pixelBuffer, withPresentationTime: time)
        }

        input.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw TestMediaError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    private func createPixelBuffer(
        width: Int,
        height: Int,
        color: (r: UInt8, g: UInt8, b: UInt8),
        pattern: VideoPattern
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, nil, &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw TestMediaError.pixelBufferFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let baseAddress = CVPixelBufferGetBaseAddress(buffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let pixelColor: (r: UInt8, g: UInt8, b: UInt8)
                switch pattern {
                case .solidColor:
                    pixelColor = color
                case .checkerboard(let blockSize):
                    let safeBlockSize = max(blockSize, 1)
                    let usePrimary = ((x / safeBlockSize) + (y / safeBlockSize)) % 2 == 0
                    pixelColor = usePrimary ? color : (0, 0, 0)
                }
                let offset = y * bytesPerRow + x * 4
                ptr[offset + 0] = pixelColor.b  // B
                ptr[offset + 1] = pixelColor.g  // G
                ptr[offset + 2] = pixelColor.r  // R
                ptr[offset + 3] = 255      // A
            }
        }
        return buffer
    }

    private func combineVideoAudio(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        let comp = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        if let vTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
           let compVTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: 1) {
            let duration = try await videoAsset.load(.duration)
            try compVTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: vTrack, at: .zero)
        }
        if let aTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let compATrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: 2) {
            let duration = try await audioAsset.load(.duration)
            try compATrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: aTrack, at: .zero)
        }

        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else {
            throw TestMediaError.exportFailed("Cannot create export session")
        }
        session.outputURL = outputURL
        session.outputFileType = .mov
        await session.export()
        guard session.status == .completed else {
            throw TestMediaError.exportFailed(session.error?.localizedDescription ?? "unknown")
        }
    }

    private func buildWAV(pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + pcm.count).le)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).le)
        data.append(UInt16(1).le)
        data.append(UInt16(channels).le)
        data.append(UInt32(sampleRate).le)
        data.append(UInt32(byteRate).le)
        data.append(UInt16(blockAlign).le)
        data.append(UInt16(bitsPerSample).le)
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(pcm.count).le)
        data.append(pcm)
        return data
    }
}

private extension FixedWidthInteger {
    var le: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}

enum TestMediaError: Error {
    case writerFailed(String)
    case pixelBufferFailed
    case exportFailed(String)
    case verificationFailed(String)
}

// MARK: - Helper: build a Timeline + assets for testing

private func makeTestTimeline(
    videoAssetURL: URL,
    audioAssetURL: URL? = nil,
    assetDuration: Double,
    clips: [(start: Double, duration: Double, sourceStart: Double, speed: Double, linkGroupID: UUID?)] = [],
    audioClips: [(start: Double, duration: Double, sourceStart: Double, speed: Double, linkGroupID: UUID?)] = [],
    trackVolume: Double = 1.0,
    trackMuted: Bool = false
) -> (Timeline, [MediaAsset]) {
    let assetID = UUID()
    let asset = MediaAsset(
        id: assetID, name: "test-video",
        sourceURL: videoAssetURL, type: .video,
        duration: assetDuration, width: 64, height: 64
    )

    var assets: [MediaAsset] = [asset]

    let videoClips = clips.map { c in
        Clip(
            assetID: assetID,
            timelineRange: TimeRange(start: c.start, duration: c.duration),
            sourceRange: TimeRange(start: c.sourceStart, duration: c.duration * c.speed),
            speed: c.speed,
            linkGroupID: c.linkGroupID
        )
    }
    let videoTrack = Track(name: "Video", type: .video, clips: videoClips, isMuted: trackMuted, volume: trackVolume)

    var tracks = [videoTrack]

    if !audioClips.isEmpty {
        let audioAssetID: UUID
        if let audioURL = audioAssetURL {
            let aAsset = MediaAsset(id: UUID(), name: "test-audio", sourceURL: audioURL, type: .audio, duration: assetDuration)
            assets.append(aAsset)
            audioAssetID = aAsset.id
        } else {
            audioAssetID = assetID  // Use video asset (has embedded audio)
        }

        let aClips = audioClips.map { c in
            Clip(
                assetID: audioAssetID,
                timelineRange: TimeRange(start: c.start, duration: c.duration),
                sourceRange: TimeRange(start: c.sourceStart, duration: c.duration * c.speed),
                speed: c.speed,
                linkGroupID: c.linkGroupID
            )
        }
        let audioTrack = Track(name: "Audio", type: .audio, clips: aClips, volume: trackVolume)
        tracks.append(audioTrack)
    }

    return (Timeline(tracks: tracks), assets)
}

// MARK: - Layer A: Structural Composition Tests (no export)

@Suite("Composition Builder — Structural Tests")
struct CompositionStructuralTests {

    let media = TestMediaGenerator()

    // MARK: - Single clip

    @Test("Single video clip produces correct track structure")
    func singleClipStructure() async throws {
        let url = try await media.makeVideoWithAudio(name: "single", duration: 2.0)
        defer { media.cleanup() }

        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [(start: 0, duration: 2, sourceStart: 0, speed: 1.0, linkGroupID: nil)]
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)
        let comp = result.composition

        // Should have 1 video track + 1 audio track (extracted from video)
        let videoTracks = comp.tracks(withMediaType: .video)
        let audioTracks = comp.tracks(withMediaType: .audio)
        #expect(videoTracks.count == 1, "Expected 1 video track, got \(videoTracks.count)")
        #expect(audioTracks.count == 1, "Expected 1 audio track (extracted), got \(audioTracks.count)")

        // Duration should match
        #expect(abs(comp.duration.seconds - 2.0) < 0.1, "Duration should be ~2.0s, got \(comp.duration.seconds)")

        // Video track segment should reference the source file
        let vSegments = videoTracks[0].segments ?? []
        #expect(vSegments.count == 1, "Expected 1 video segment")
        if let seg = vSegments.first {
            #expect(!seg.isEmpty, "Segment should not be empty")
            #expect(seg.sourceURL == url, "Segment should reference test file")
            #expect(abs(seg.timeMapping.target.start.seconds) < 0.01, "Should start at 0")
        }
    }

    // MARK: - Split clip (two clips from same source, adjacent)

    @Test("Clips on same timeline track share one composition video track")
    func splitClipStructure() async throws {
        let url = try await media.makeVideoWithAudio(name: "split", duration: 2.0)
        defer { media.cleanup() }

        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [
                (start: 0, duration: 1, sourceStart: 0, speed: 1.0, linkGroupID: nil),
                (start: 1, duration: 1, sourceStart: 1, speed: 1.0, linkGroupID: nil),
            ]
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)
        let comp = result.composition

        // Non-overlapping clips on the same timeline track share 1 composition video track
        let videoTracks = comp.tracks(withMediaType: .video)
        #expect(videoTracks.count == 1, "Clips on same track should share 1 video comp track, got \(videoTracks.count)")

        // Composition covers 0-2s
        #expect(abs(comp.duration.seconds - 2.0) < 0.1)

        // Audio: should be 1 shared track
        let audioTracks = comp.tracks(withMediaType: .audio)
        #expect(audioTracks.count == 1, "Unlinked clips should share 1 audio track, got \(audioTracks.count)")
    }

    // MARK: - Linked A/V: video clip with linked audio does not extract double audio

    @Test("Linked video+audio clips produce exactly 1 audio composition track")
    func linkedAVNoDoubleAudio() async throws {
        let url = try await media.makeVideoWithAudio(name: "linked", duration: 2.0)
        defer { media.cleanup() }

        let linkID = UUID()
        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [(start: 0, duration: 2, sourceStart: 0, speed: 1.0, linkGroupID: linkID)],
            audioClips: [(start: 0, duration: 2, sourceStart: 0, speed: 1.0, linkGroupID: linkID)]
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)
        let comp = result.composition

        let audioTracks = comp.tracks(withMediaType: .audio)
        #expect(audioTracks.count == 1, "Linked A/V should produce exactly 1 audio track, got \(audioTracks.count)")
    }

    // MARK: - Linked A/V split: both halves on shared audio track

    @Test("Split linked clips share audio tracks (no silence gaps)")
    func splitLinkedSharedAudio() async throws {
        let url = try await media.makeVideoWithAudio(name: "splitlinked", duration: 2.0)
        defer { media.cleanup() }

        let link1 = UUID(), link2 = UUID()
        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [
                (start: 0, duration: 1, sourceStart: 0, speed: 1.0, linkGroupID: link1),
                (start: 1, duration: 1, sourceStart: 1, speed: 1.0, linkGroupID: link2),
            ],
            audioClips: [
                (start: 0, duration: 1, sourceStart: 0, speed: 1.0, linkGroupID: link1),
                (start: 1, duration: 1, sourceStart: 1, speed: 1.0, linkGroupID: link2),
            ]
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)
        let comp = result.composition

        let audioTracks = comp.tracks(withMediaType: .audio)
        #expect(audioTracks.count == 1, "Split linked clips should share 1 audio track, got \(audioTracks.count)")

        // The single audio track covers the full 0-2s range (AVFoundation may merge adjacent segments)
        let segments = (audioTracks[0].segments ?? []).filter { !$0.isEmpty }
        #expect(segments.count >= 1, "Should have at least 1 non-empty audio segment, got \(segments.count)")
        // Verify total coverage: segments should span 0 to ~2s
        let totalCoverage = segments.reduce(0.0) { $0 + $1.timeMapping.target.duration.seconds }
        #expect(abs(totalCoverage - 2.0) < 0.1, "Audio segments should cover ~2s, got \(totalCoverage)")
    }

    // MARK: - Muted track produces no composition tracks

    @Test("Muted track is excluded from composition")
    func mutedTrackExcluded() async throws {
        let url = try await media.makeVideoWithAudio(name: "muted", duration: 2.0)
        defer { media.cleanup() }

        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [(start: 0, duration: 2, sourceStart: 0, speed: 1.0, linkGroupID: nil)],
            trackMuted: true
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)

        #expect(result.composition.tracks.isEmpty, "Muted track should produce no composition tracks")
        #expect(result.duration == 0, "Muted-only timeline should have 0 duration")
    }

    // MARK: - Speed change: segment target duration reflects speed

    @Test("Speed 2x halves the composition duration")
    func speedChangeSegmentDuration() async throws {
        let url = try await media.makeVideoWithAudio(name: "speed", duration: 2.0)
        defer { media.cleanup() }

        // Source duration is 2s. At 2x speed, timeline duration = 2/2 = 1s.
        // sourceRange duration = timeline duration * speed = 1 * 2 = 2s (the full source)
        let assetID = UUID()
        let asset = MediaAsset(id: assetID, name: "test", sourceURL: url, type: .video, duration: 2.0, width: 64, height: 64)
        let clip = Clip(
            assetID: assetID,
            timelineRange: TimeRange(start: 0, duration: 1.0),  // 1s on timeline
            sourceRange: TimeRange(start: 0, duration: 2.0),     // 2s of source
            speed: 2.0
        )
        let timeline = Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])

        let result = await CompositionBuilder().build(from: timeline, assets: [asset])

        #expect(abs(result.duration - 1.0) < 0.2, "2s source at 2x should be ~1s, got \(result.duration)")
    }

    // MARK: - Video composition instruction coverage

    @Test("Video composition instructions cover full duration with no gaps")
    func instructionCoverage() async throws {
        let url = try await media.makeVideoWithAudio(name: "coverage", duration: 2.0)
        defer { media.cleanup() }

        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [
                (start: 0, duration: 1, sourceStart: 0, speed: 1.0, linkGroupID: nil),
                (start: 1, duration: 1, sourceStart: 1, speed: 1.0, linkGroupID: nil),
            ]
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)
        let vidComp = result.videoComposition

        #expect(vidComp != nil, "Should have video composition")

        guard let instructions = vidComp?.instructions as? [AVMutableVideoCompositionInstruction] else {
            Issue.record("Instructions should be AVMutableVideoCompositionInstruction")
            return
        }

        // Verify no gaps: each instruction starts where the previous ended
        var cursor: CMTime = .zero
        for (i, instr) in instructions.enumerated() {
            let start = instr.timeRange.start
            let end = instr.timeRange.end
            #expect(
                abs(start.seconds - cursor.seconds) < 0.01,
                "Instruction \(i) starts at \(start.seconds)s but cursor is at \(cursor.seconds)s — GAP"
            )
            #expect(CMTimeCompare(end, start) > 0, "Instruction \(i) has zero or negative duration")
            cursor = end
        }

        // Should cover up to composition duration
        let compDuration = result.composition.duration
        #expect(
            abs(cursor.seconds - compDuration.seconds) < 0.01,
            "Instructions end at \(cursor.seconds)s but composition is \(compDuration.seconds)s"
        )
    }

    // MARK: - Empty timeline

    @Test("Empty timeline produces zero-duration result")
    func emptyTimeline() async {
        let timeline = Timeline(tracks: [])
        let result = await CompositionBuilder().build(from: timeline, assets: [])

        #expect(result.composition.tracks.isEmpty)
        #expect(result.duration == 0)
        #expect(result.videoComposition == nil)
        #expect(result.audioMix == nil)
    }

    // MARK: - Volume creates audio mix

    @Test("Non-default volume creates audio mix parameters")
    func volumeCreatesAudioMix() async throws {
        let url = try await media.makeVideoWithAudio(name: "volume", duration: 2.0)
        defer { media.cleanup() }

        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [(start: 0, duration: 2, sourceStart: 0, speed: 1.0, linkGroupID: nil)],
            trackVolume: 0.5
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)

        #expect(result.audioMix != nil, "Track volume 0.5 should create an audio mix")
        let params = (result.audioMix as? AVMutableAudioMix)?.inputParameters ?? []
        #expect(!params.isEmpty, "Audio mix should have input parameters")
    }
}

// MARK: - Layer B: Export Round-Trip Tests

@Suite("Composition Builder — Export Round-Trip Tests")
struct CompositionExportTests {

    let media = TestMediaGenerator()

    // MARK: - Single clip export

    @Test("Single clip exports with correct duration and tracks", .timeLimit(.minutes(1)))
    func singleClipExport() async throws {
        let url = try await media.makeVideoWithAudio(name: "exp-single", duration: 2.0)
        defer { media.cleanup() }

        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [(start: 0, duration: 2, sourceStart: 0, speed: 1.0, linkGroupID: nil)]
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)
        let exportURL = media.tempDir.appendingPathComponent("export-single.mp4")

        try await exportComposition(result, to: exportURL)

        // Verify exported file
        let exported = AVURLAsset(url: exportURL)
        let duration = try await exported.load(.duration).seconds
        let videoTracks = try await exported.loadTracks(withMediaType: .video)
        let audioTracks = try await exported.loadTracks(withMediaType: .audio)

        #expect(abs(duration - 2.0) < 0.5, "Exported duration should be ~2s, got \(duration)")
        #expect(!videoTracks.isEmpty, "Export should have video")
        #expect(!audioTracks.isEmpty, "Export should have audio")
    }

    // MARK: - Split clip export: audio at both halves

    @Test("Split clip has audio in both halves", .timeLimit(.minutes(1)))
    func splitClipAudioBothHalves() async throws {
        let url = try await media.makeVideoWithAudio(name: "exp-split", duration: 2.0, toneFrequency: 880.0)
        defer { media.cleanup() }

        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [
                (start: 0, duration: 1, sourceStart: 0, speed: 1.0, linkGroupID: nil),
                (start: 1, duration: 1, sourceStart: 1, speed: 1.0, linkGroupID: nil),
            ]
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)
        let exportURL = media.tempDir.appendingPathComponent("export-split.mp4")
        try await exportComposition(result, to: exportURL)

        // Check audio in first half (0-1s)
        let level1 = await measureAudioRMS(url: exportURL, from: 0, duration: 0.8)
        #expect(level1 > 0.01, "First half audio RMS should be >0.01, got \(level1)")

        // Check audio in second half (1-2s)
        let level2 = await measureAudioRMS(url: exportURL, from: 1.1, duration: 0.8)
        #expect(level2 > 0.01, "Second half audio RMS should be >0.01, got \(level2)")
    }

    // MARK: - Linked split: audio in both halves

    @Test("Linked split clip has audio in both halves", .timeLimit(.minutes(1)))
    func linkedSplitAudioBothHalves() async throws {
        let url = try await media.makeVideoWithAudio(name: "exp-linkedsplit", duration: 2.0, toneFrequency: 660.0)
        defer { media.cleanup() }

        let link1 = UUID(), link2 = UUID()
        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [
                (start: 0, duration: 1, sourceStart: 0, speed: 1.0, linkGroupID: link1),
                (start: 1, duration: 1, sourceStart: 1, speed: 1.0, linkGroupID: link2),
            ],
            audioClips: [
                (start: 0, duration: 1, sourceStart: 0, speed: 1.0, linkGroupID: link1),
                (start: 1, duration: 1, sourceStart: 1, speed: 1.0, linkGroupID: link2),
            ]
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)
        let exportURL = media.tempDir.appendingPathComponent("export-linkedsplit.mp4")
        try await exportComposition(result, to: exportURL)

        let level1 = await measureAudioRMS(url: exportURL, from: 0, duration: 0.8)
        let level2 = await measureAudioRMS(url: exportURL, from: 1.1, duration: 0.8)

        #expect(level1 > 0.01, "Linked split first half audio RMS should be >0.01, got \(level1)")
        #expect(level2 > 0.01, "Linked split second half audio RMS should be >0.01, got \(level2)")
    }

    // MARK: - Speed change: exported duration matches

    @Test("2x speed clip exports at half duration", .timeLimit(.minutes(1)))
    func speedExportDuration() async throws {
        let url = try await media.makeVideoWithAudio(name: "exp-speed", duration: 2.0)
        defer { media.cleanup() }

        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [(start: 0, duration: 2, sourceStart: 0, speed: 2.0, linkGroupID: nil)]
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)
        let exportURL = media.tempDir.appendingPathComponent("export-speed.mp4")
        try await exportComposition(result, to: exportURL)

        let exported = AVURLAsset(url: exportURL)
        let duration = try await exported.load(.duration).seconds

        #expect(abs(duration - 1.0) < 0.5, "2x speed of 2s should export ~1s, got \(duration)")
    }

    // MARK: - Video frame is not black

    @Test("Exported video frame has expected color (not black)", .timeLimit(.minutes(1)))
    func exportedFrameNotBlack() async throws {
        let url = try await media.makeVideoWithAudio(name: "exp-color", duration: 2.0, color: (255, 0, 0))
        defer { media.cleanup() }

        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [(start: 0, duration: 2, sourceStart: 0, speed: 1.0, linkGroupID: nil)]
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)
        let exportURL = media.tempDir.appendingPathComponent("export-color.mp4")
        try await exportComposition(result, to: exportURL)

        let isValid = await checkFrameNotBlack(url: exportURL, at: 0.5)
        #expect(isValid, "Exported frame at 0.5s should not be black")
    }

    // MARK: - Mixed: unlinked hook + linked main (the real-world scenario)

    @Test("Unlinked hook + linked main content has audio everywhere", .timeLimit(.minutes(2)))
    func hookPlusLinkedMainAudio() async throws {
        let url = try await media.makeVideoWithAudio(name: "exp-hook", duration: 4.0, toneFrequency: 550.0)
        defer { media.cleanup() }

        // Hook: unlinked video clip at 0-1s (extracts own audio)
        // Main: linked V+A at 1-4s
        let linkID = UUID()
        let assetID = UUID()
        let asset = MediaAsset(id: assetID, name: "test", sourceURL: url, type: .video, duration: 4.0, width: 64, height: 64)

        let timeline = Timeline(tracks: [
            Track(name: "Video", type: .video, clips: [
                Clip(assetID: assetID, timelineRange: TimeRange(start: 0, duration: 1),
                     sourceRange: TimeRange(start: 0, duration: 1)),  // unlinked hook
                Clip(assetID: assetID, timelineRange: TimeRange(start: 1, duration: 3),
                     sourceRange: TimeRange(start: 1, duration: 3), linkGroupID: linkID),
            ]),
            Track(name: "Audio", type: .audio, clips: [
                Clip(assetID: assetID, timelineRange: TimeRange(start: 1, duration: 3),
                     sourceRange: TimeRange(start: 1, duration: 3), linkGroupID: linkID),
            ]),
        ])

        let result = await CompositionBuilder().build(from: timeline, assets: [asset])

        // Structural: should have 1 audio track (shared)
        let audioTracks = result.composition.tracks(withMediaType: .audio)
        #expect(audioTracks.count == 1, "Hook + linked should share 1 audio track, got \(audioTracks.count)")

        // Export and verify audio at all positions
        let exportURL = media.tempDir.appendingPathComponent("export-hook.mp4")
        try await exportComposition(result, to: exportURL)

        let level_hook = await measureAudioRMS(url: exportURL, from: 0, duration: 0.8)
        let level_main_start = await measureAudioRMS(url: exportURL, from: 1.2, duration: 0.8)
        let level_main_mid = await measureAudioRMS(url: exportURL, from: 2.5, duration: 0.8)

        #expect(level_hook > 0.01, "Hook audio should be present, RMS=\(level_hook)")
        #expect(level_main_start > 0.01, "Main start audio should be present, RMS=\(level_main_start)")
        #expect(level_main_mid > 0.01, "Main mid audio should be present, RMS=\(level_main_mid)")
    }

    // MARK: - Effect rendering through composition pipeline

    @Test("Clip with blur effect exports a blurred frame (not raw source)", .timeLimit(.minutes(2)))
    func effectActuallyRendersInExport() async throws {
        let url = try await media.makeVideoWithAudio(
            name: "exp-effect",
            duration: 2.0,
            color: (255, 255, 255),
            pattern: .checkerboard(blockSize: 4)
        )
        defer { media.cleanup() }

        // Create a clip WITH a blur effect
        let assetID = UUID()
        let asset = MediaAsset(id: assetID, name: "test", sourceURL: url, type: .video, duration: 2.0, width: 64, height: 64)
        let clip = Clip(
            assetID: assetID,
            timelineRange: TimeRange(start: 0, duration: 2),
            sourceRange: TimeRange(start: 0, duration: 2),
            effects: [EffectInstance(type: "blur", parameters: ["radius": 20])]
        )
        let timeline = Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])

        let result = await CompositionBuilder().build(from: timeline, assets: [asset])

        // The video composition MUST use the custom compositor when effects are present
        #expect(result.videoComposition != nil, "Should have video composition")

        // Check that customVideoCompositorClass is set
        guard let vidComp = result.videoComposition as? AVMutableVideoComposition else {
            throw TestMediaError.verificationFailed("Expected AVMutableVideoComposition when effects are present")
        }
        #expect(vidComp.customVideoCompositorClass != nil,
                "Effects present but customVideoCompositorClass not set — effects won't render!")
        #expect(vidComp.customVideoCompositorClass == EffectCompositor.self,
                "customVideoCompositorClass should be EffectCompositor")

        // Check instructions are EffectInstruction (not AVMutableVideoCompositionInstruction)
        let hasEffectInstructions = vidComp.instructions.contains { $0 is EffectInstruction }
        #expect(hasEffectInstructions, "Instructions should be EffectInstruction when effects are applied")

        // Export and verify the frame is actually different from the source
        let exportURL = media.tempDir.appendingPathComponent("export-effect.mp4")
        try await exportComposition(result, to: exportURL)

        // Verify the export completed (custom compositor didn't crash)
        let exportAsset = AVURLAsset(url: exportURL)
        let exportDuration = try await exportAsset.load(.duration).seconds
        #expect(abs(exportDuration - 2.0) < 0.5, "Export with effects should complete: got \(exportDuration)s")

        let sourceFrame = try extractFrame(url: url, at: 0.5)
        let exportFrame = try extractFrame(url: exportURL, at: 0.5)
        let checker = EffectPropertyChecker()
        let sourceProps = checker.measureProperties(sourceFrame)
        let exportProps = checker.measureProperties(exportFrame)
        let sharpnessRatio = exportProps.laplacianVariance / max(sourceProps.laplacianVariance, 0.001)

        #expect(sourceProps.laplacianVariance > 0.1,
                "Checkerboard source should contain measurable detail before blur validation")
        #expect(sharpnessRatio < 0.9,
                "Blurred export should reduce sharpness versus source, got ratio=\(sharpnessRatio)")
    }

    @Test("Clip with brightness effect exports a brighter frame", .timeLimit(.minutes(2)))
    func brightnessEffectRendersInExport() async throws {
        let url = try await media.makeVideoWithAudio(name: "exp-bright", duration: 2.0, color: (100, 50, 50))
        defer { media.cleanup() }

        let assetID = UUID()
        let asset = MediaAsset(id: assetID, name: "test", sourceURL: url, type: .video, duration: 2.0, width: 64, height: 64)
        let clip = Clip(
            assetID: assetID,
            timelineRange: TimeRange(start: 0, duration: 2),
            sourceRange: TimeRange(start: 0, duration: 2),
            effects: [EffectInstance(type: "colorCorrection", parameters: ["brightness": 0.5, "contrast": 1.0, "saturation": 1.0])]
        )
        let timeline = Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])

        let result = await CompositionBuilder().build(from: timeline, assets: [asset])

        // Verify compositor is wired
        guard let vidComp = result.videoComposition as? AVMutableVideoComposition else {
            throw TestMediaError.verificationFailed("Expected AVMutableVideoComposition for brightness effect export")
        }
        #expect(vidComp.customVideoCompositorClass == EffectCompositor.self,
                "Brightness effect present but EffectCompositor not wired")

        let exportURL = media.tempDir.appendingPathComponent("export-bright.mp4")
        try await exportComposition(result, to: exportURL)

        let exportFrame = try extractFrame(url: exportURL, at: 0.5)
        let sourceFrame = try extractFrame(url: url, at: 0.5)
        let checker = EffectPropertyChecker()
        let exportProps = checker.measureProperties(exportFrame)
        let sourceProps = checker.measureProperties(sourceFrame)

        #expect(exportProps.meanLuminance > sourceProps.meanLuminance + 5,
                "Brightness +0.5 should increase luminance: export=\(exportProps.meanLuminance), source=\(sourceProps.meanLuminance) — effect may not be rendering!")
    }

    @Test("Clip without effects does NOT use custom compositor (fast path)", .timeLimit(.minutes(1)))
    func noEffectsUsesFastPath() async throws {
        let url = try await media.makeVideoWithAudio(name: "exp-noeffect", duration: 2.0)
        defer { media.cleanup() }

        let (timeline, assets) = makeTestTimeline(
            videoAssetURL: url, assetDuration: 2.0,
            clips: [(start: 0, duration: 2, sourceStart: 0, speed: 1.0, linkGroupID: nil)]
        )

        let result = await CompositionBuilder().build(from: timeline, assets: assets)

        if let vidComp = result.videoComposition as? AVMutableVideoComposition {
            #expect(vidComp.customVideoCompositorClass == nil,
                    "No effects — should use fast path without custom compositor")
        }
    }

    @Test("Crop rect enables custom compositor and is carried into instructions", .timeLimit(.minutes(1)))
    func cropRectUsesCustomCompositor() async throws {
        let url = try await media.makeVideoWithAudio(name: "exp-crop", duration: 2.0)
        defer { media.cleanup() }

        let assetID = UUID()
        let asset = MediaAsset(id: assetID, name: "crop", sourceURL: url, type: .video, duration: 2.0, width: 64, height: 64)
        let clip = Clip(
            assetID: assetID,
            timelineRange: TimeRange(start: 0, duration: 2),
            sourceRange: TimeRange(start: 0, duration: 2),
            cropRect: CropRect(x: 0.35, y: 0, width: 0.65, height: 1)
        )
        let timeline = Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])

        let result = await CompositionBuilder().build(from: timeline, assets: [asset])

        guard let vidComp = result.videoComposition as? AVMutableVideoComposition else {
            Issue.record("Crop should produce a video composition")
            return
        }

        #expect(vidComp.customVideoCompositorClass == EffectCompositor.self)

        let cropInstructions = vidComp.instructions.compactMap { $0 as? EffectInstruction }
        #expect(!cropInstructions.isEmpty)
        #expect(cropInstructions.first?.cropRect == clip.cropRect)
    }

    // MARK: - Helpers

    private func exportComposition(_ result: CompositionBuilder.Result, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        guard let session = AVAssetExportSession(asset: result.composition, presetName: AVAssetExportPreset640x480) else {
            throw TestMediaError.exportFailed("Cannot create session")
        }
        session.outputURL = url
        session.outputFileType = .mp4
        if let mix = result.audioMix { session.audioMix = mix }
        if let vidComp = result.videoComposition { session.videoComposition = vidComp }
        await session.export()
        guard session.status == .completed else {
            throw TestMediaError.exportFailed(session.error?.localizedDescription ?? "status: \(session.status.rawValue)")
        }
    }

    private func measureAudioRMS(url: URL, from startTime: Double, duration: Double) async -> Float {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return 0 }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return 0 }
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 44100),
            duration: CMTime(seconds: duration, preferredTimescale: 44100)
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { return 0 }

        var totalSquared: Double = 0
        var totalSamples: Int = 0

        while let buffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let numSamples = length / 2
            var data = [Int16](repeating: 0, count: numSamples)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &data)
            for sample in data {
                let f = Double(abs(Int32(sample))) / Double(Int16.max)
                totalSquared += f * f
            }
            totalSamples += numSamples
        }

        guard totalSamples > 0 else { return 0 }
        return Float(sqrt(totalSquared / Double(totalSamples)))
    }

    private func extractFrame(url: URL, at time: Double) throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        return try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
    }

    private func checkFrameNotBlack(url: URL, at time: Double) async -> Bool {
        guard let cgImage = try? extractFrame(url: url, at: time) else {
            return false
        }
        guard let data = cgImage.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return false }
        let bpp = cgImage.bitsPerPixel / 8
        let total = cgImage.width * cgImage.height
        var bright = 0
        let step = max(total / 200, 1)
        for i in stride(from: 0, to: total * bpp, by: step * bpp) {
            if Int(ptr[i]) + Int(ptr[i + 1]) + Int(ptr[i + 2]) > 30 { bright += 1 }
        }
        return bright > 20
    }
}
