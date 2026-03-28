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
        let builder = CompositionBuilder()
        let result = await builder.build(from: timeline, assets: assets, urlMode: .preview)

        guard !Task.isCancelled else { return }

        self.composition = result.composition
        self.duration = result.duration

        let playerItem = AVPlayerItem(asset: result.composition)
        if let audioMix = result.audioMix {
            playerItem.audioMix = audioMix
        }
        if let videoComp = result.videoComposition {
            playerItem.videoComposition = videoComp
        }
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
