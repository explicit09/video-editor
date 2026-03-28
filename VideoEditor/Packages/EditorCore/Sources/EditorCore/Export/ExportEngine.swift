import Foundation
import AVFoundation

/// Exports timeline to video file using AVAssetExportSession.
/// Phase 1 uses high-level export. Phase 2 will add AVAssetReader/Writer for frame-level control.
@MainActor @Observable
public final class ExportEngine {
    public enum State: Equatable {
        case idle
        case exporting(progress: Float)
        case completed(URL)
        case failed(String)
    }

    public private(set) var state: State = .idle
    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?

    public init() {}

    /// Export the timeline to a file at the given URL.
    public func export(
        timeline: Timeline,
        assets: [MediaAsset],
        to outputURL: URL,
        preset: String = AVAssetExportPresetHighestQuality,
        fileType: AVFileType = .mp4
    ) async {
        state = .exporting(progress: 0)

        // Build composition (same logic as playback)
        let comp = AVMutableComposition()
        var maxDuration: CMTime = .zero

        for track in timeline.tracks {
            for clip in track.clips {
                guard let mediaAsset = assets.first(where: { $0.id == clip.assetID }) else { continue }
                let avAsset = AVURLAsset(url: mediaAsset.sourceURL)

                let insertTime = CMTime(seconds: clip.timelineRange.start, preferredTimescale: 600)
                let sourceStart = CMTime(seconds: clip.sourceRange.start, preferredTimescale: 600)
                let sourceDuration = CMTime(seconds: clip.sourceRange.duration, preferredTimescale: 600)
                let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)

                if track.type != .audio {
                    if let sourceTrack = try? await avAsset.loadTracks(withMediaType: .video).first,
                       let compTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        try? compTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)
                    }
                }

                if let sourceTrack = try? await avAsset.loadTracks(withMediaType: .audio).first,
                   let compTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try? compTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)
                }

                let clipEnd = CMTimeAdd(insertTime, sourceDuration)
                if CMTimeCompare(clipEnd, maxDuration) > 0 {
                    maxDuration = clipEnd
                }
            }
        }

        guard let session = AVAssetExportSession(asset: comp, presetName: preset) else {
            state = .failed("Could not create export session")
            return
        }

        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        session.outputURL = outputURL
        session.outputFileType = fileType
        session.timeRange = CMTimeRange(start: .zero, duration: maxDuration)

        self.exportSession = session

        // Poll progress
        startProgressPolling(session: session)

        await session.export()

        stopProgressPolling()

        switch session.status {
        case .completed:
            state = .completed(outputURL)
        case .failed:
            state = .failed(session.error?.localizedDescription ?? "Export failed")
        case .cancelled:
            state = .failed("Export cancelled")
        default:
            state = .failed("Unexpected export status")
        }
    }

    public func reset() {
        state = .idle
    }

    public func cancel() {
        // Clean up partial output file
        if let outputURL = exportSession?.outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        exportSession?.cancelExport()
        stopProgressPolling()
        state = .idle
    }

    // MARK: - Progress polling

    private func startProgressPolling(session: AVAssetExportSession) {
        let pollSession = session
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            let progress = pollSession.progress
            Task { @MainActor in
                self?.state = .exporting(progress: progress)
            }
        }
    }

    private func stopProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}
