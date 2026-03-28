import Foundation
import AVFoundation

/// Builds AVComposition from Timeline and drives playback.
@MainActor @Observable
public final class PlaybackEngine {
    public private(set) var player: AVPlayer
    public private(set) var isPlaying = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0

    private var composition: AVMutableComposition?
    private var timeObserver: Any?
    private var buildTask: Task<Void, Never>?

    public init() {
        self.player = AVPlayer()
        setupTimeObserver()
    }

    deinit {
        MainActor.assumeIsolated {
            if let timeObserver {
                player.removeTimeObserver(timeObserver)
            }
        }
    }

    // MARK: - Build composition from timeline

    public func buildComposition(from timeline: Timeline, assets: [MediaAsset]) {
        // Cancel any in-flight build to prevent race conditions
        buildTask?.cancel()
        buildTask = Task { await buildCompositionAsync(from: timeline, assets: assets) }
    }

    private func buildCompositionAsync(from timeline: Timeline, assets: [MediaAsset]) async {
        let comp = AVMutableComposition()
        var maxDuration: CMTime = .zero

        for track in timeline.tracks {
            for clip in track.clips {
                guard let mediaAsset = assets.first(where: { $0.id == clip.assetID }) else { continue }
                let mediaURL = mediaAsset.proxyURL ?? mediaAsset.sourceURL
                let avAsset = AVURLAsset(url: mediaURL)

                let insertTime = CMTime(seconds: clip.timelineRange.start, preferredTimescale: 600)
                let sourceStart = CMTime(seconds: clip.sourceRange.start, preferredTimescale: 600)
                let sourceDuration = CMTime(seconds: clip.sourceRange.duration, preferredTimescale: 600)
                let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)

                // Insert video only for visual tracks.
                if track.type != .audio, !track.isMuted {
                    if let sourceTrack = try? await avAsset.loadTracks(withMediaType: .video).first,
                       let compTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        try? compTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)
                    }
                }

                // Audio is authored explicitly on audio tracks.
                if track.type == .audio, !track.isMuted,
                   let sourceTrack = try? await avAsset.loadTracks(withMediaType: .audio).first,
                   let compTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try? compTrack.insertTimeRange(sourceRange, of: sourceTrack, at: insertTime)
                }

                let clipEnd = CMTimeAdd(insertTime, sourceDuration)
                if CMTimeCompare(clipEnd, maxDuration) > 0 {
                    maxDuration = clipEnd
                }
            }
        }

        // Don't apply if this task was cancelled (a newer build superseded us)
        guard !Task.isCancelled else { return }

        self.composition = comp
        self.duration = maxDuration.seconds

        let playerItem = AVPlayerItem(asset: comp)
        player.replaceCurrentItem(with: playerItem)
    }

    // MARK: - Transport controls

    public func play() {
        guard player.currentItem != nil else { return }
        player.play()
        isPlaying = true
    }

    public func pause() {
        player.pause()
        isPlaying = false
    }

    public func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    public func seek(to time: TimeInterval) {
        let clampedTime = max(0, time)
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clampedTime
    }

    // MARK: - Time observer

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.currentTime = time.seconds
            }
        }
    }
}
