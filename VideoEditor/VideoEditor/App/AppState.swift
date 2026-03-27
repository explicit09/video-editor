import SwiftUI
import EditorCore
import Combine

@Observable
@MainActor
final class AppState {
    let context: EditingContext
    let commandHistory: CommandHistory
    let intentResolver: IntentResolver
    let timelineViewState: TimelineViewState
    let playbackEngine: PlaybackEngine
    let exportEngine: ExportEngine

    // Reactive access — SwiftUI reads these directly
    var timeline: Timeline { context.timelineState.timeline }
    private(set) var assets: [MediaAsset] = []

    /// Project bundle directory for storing media, proxies, cache.
    private(set) var projectBundleURL: URL
    private var playbackSyncTimer: Timer?

    init() {
        // Create a default project bundle in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleURL = appSupport.appendingPathComponent("VideoEditor/DefaultProject.veditor")
        try? FileManager.default.createDirectory(at: bundleURL.appendingPathComponent("media"), withIntermediateDirectories: true)

        self.projectBundleURL = bundleURL
        self.context = EditingContext()
        self.commandHistory = CommandHistory()
        self.intentResolver = IntentResolver()
        self.timelineViewState = TimelineViewState()
        self.playbackEngine = PlaybackEngine()
        self.exportEngine = ExportEngine()

        startPlayheadSync()
    }

    // MARK: - The ONLY write path for editing actions

    func perform(_ intent: EditorIntent) throws {
        var command = try intentResolver.resolve(intent)
        try commandHistory.execute(&command, context: context)
        rebuildComposition()
    }

    func undo() throws {
        try commandHistory.undo(context: context)
        rebuildComposition()
    }

    func redo() throws {
        try commandHistory.redo(context: context)
        rebuildComposition()
    }

    // MARK: - Media import

    func importMedia(from url: URL) async throws -> MediaAsset {
        let mediaDir = projectBundleURL.appendingPathComponent("media")
        let asset = try await context.media.importFile(from: url, bundleMediaDir: mediaDir)
        assets = await context.media.allAssets()
        return asset
    }

    func refreshAssets() async {
        assets = await context.media.allAssets()
    }

    // MARK: - Playback

    /// Rebuild the AVComposition from current timeline + assets.
    /// Called after every timeline mutation.
    func rebuildComposition() {
        let allAssets = assets
        playbackEngine.buildComposition(from: timeline, assets: allAssets)
    }

    /// Sync playhead position between PlaybackEngine and TimelineViewState.
    private func startPlayheadSync() {
        // Timer fires 30x/sec to sync playhead during playback
        playbackSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.playbackEngine.isPlaying {
                    self.timelineViewState.playheadPosition = self.playbackEngine.currentTime
                    self.timelineViewState.isPlaying = true
                } else {
                    self.timelineViewState.isPlaying = false
                }
            }
        }
    }

    /// Seek playback when user drags the playhead.
    func seekFromPlayhead() {
        playbackEngine.seek(to: timelineViewState.playheadPosition)
    }
}
