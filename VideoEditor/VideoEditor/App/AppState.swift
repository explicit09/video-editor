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
    let proxyService: ProxyService
    let memoryMonitor: MemoryPressureMonitor
    let thumbnailCache: DiskCache
    let renderCache: DiskCache

    // Reactive access — SwiftUI reads these directly
    var timeline: Timeline { context.timelineState.timeline }
    private(set) var assets: [MediaAsset] = []
    private(set) var proxyProgress: [UUID: Float] = [:]

    /// Project bundle directory for storing media, proxies, cache.
    private(set) var projectBundleURL: URL
    private var playbackSyncTimer: Timer?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleURL = appSupport.appendingPathComponent("VideoEditor/DefaultProject.veditor")
        for subdir in ["media", "proxies", "cache/thumbnails", "cache/waveforms", "cache/render", "analysis"] {
            try? FileManager.default.createDirectory(
                at: bundleURL.appendingPathComponent(subdir),
                withIntermediateDirectories: true
            )
        }

        self.projectBundleURL = bundleURL
        self.context = EditingContext()
        self.commandHistory = CommandHistory()
        self.intentResolver = IntentResolver()
        self.timelineViewState = TimelineViewState()
        self.playbackEngine = PlaybackEngine()
        self.exportEngine = ExportEngine()
        self.proxyService = ProxyService(proxiesDir: bundleURL.appendingPathComponent("proxies"))
        self.memoryMonitor = MemoryPressureMonitor()
        self.thumbnailCache = DiskCache(
            directory: bundleURL.appendingPathComponent("cache/thumbnails"),
            policy: .thumbnails
        )
        self.renderCache = DiskCache(
            directory: bundleURL.appendingPathComponent("cache/render"),
            policy: .renderCache
        )

        // Open SQLite action log
        let dbPath = bundleURL.appendingPathComponent("metadata.sqlite").path
        Task { try? await context.actionLog.open(at: dbPath) }

        startPlayheadSync()
        startMemoryMonitoring()
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

    // MARK: - Media import + proxy generation

    func importMedia(from url: URL) async throws -> MediaAsset {
        let mediaDir = projectBundleURL.appendingPathComponent("media")
        var asset = try await context.media.importFile(from: url, bundleMediaDir: mediaDir)

        // Kick off proxy generation in background
        if asset.type == .video {
            let assetID = asset.id
            Task {
                if let proxyURL = await proxyService.generateProxy(for: asset) {
                    // Update asset with proxy URL
                    await context.media.setProxyURL(proxyURL, for: assetID)
                    assets = await context.media.allAssets()
                }
                proxyProgress.removeValue(forKey: assetID)
            }
        }

        assets = await context.media.allAssets()
        return asset
    }

    func refreshAssets() async {
        assets = await context.media.allAssets()
    }

    // MARK: - Playback

    func rebuildComposition() {
        playbackEngine.buildComposition(from: timeline, assets: assets)
    }

    private func startPlayheadSync() {
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

    func seekFromPlayhead() {
        playbackEngine.seek(to: timelineViewState.playheadPosition)
    }

    // MARK: - Memory pressure

    private func startMemoryMonitoring() {
        let thumbCache = thumbnailCache
        let rendCache = renderCache
        let proxySvc = proxyService

        memoryMonitor.startMonitoring { level in
            Task {
                await DegradationResponse.respond(
                    level: level,
                    thumbnailCache: thumbCache,
                    renderCache: rendCache,
                    proxyService: proxySvc
                )
            }
        }
    }
}
