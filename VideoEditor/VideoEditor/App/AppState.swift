import SwiftUI
import EditorCore
import AIServices

@Observable
@MainActor
final class AppState {
    let context: EditingContext
    let commandHistory: CommandHistory
    let intentResolver: IntentResolver
    let timelineViewState: TimelineViewState
    let playbackEngine: PlaybackEngine
    let exportEngine: ExportEngine
    let media: MediaCoordinator
    let aiChat: AIChatController
    let projectStore: ProjectStore

    // Reactive access
    var timeline: Timeline { context.timelineState.timeline }
    var assets: [MediaAsset] { media.assets }

    /// Project bundle directory.
    let projectBundleURL: URL

    private var playbackSyncTimer: Timer?
    private var saveDebounceTask: Task<Void, Never>?

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
        self.projectStore = ProjectStore()
        self.context = EditingContext()
        self.commandHistory = CommandHistory()
        self.intentResolver = IntentResolver()
        self.timelineViewState = TimelineViewState()
        self.playbackEngine = PlaybackEngine()
        self.exportEngine = ExportEngine()
        self.media = MediaCoordinator(bundleURL: bundleURL)
        self.aiChat = AIChatController()

        // Load API keys from .env file or environment
        let keys = Self.loadEnvKeys()
        if let claudeKey = keys["ANTHROPIC_API_KEY"] {
            aiChat.configure(provider: ClaudeProvider(apiKey: claudeKey))
        }
        if let dgKey = keys["DEEPGRAM_API_KEY"] {
            media.setTranscriptionProvider(DeepgramProvider(apiKey: dgKey))
        }

        // Rebuild composition when proxy/analysis completes in background
        media.onAnalysisComplete = { [weak self] in
            self?.rebuildComposition()
        }
        // Save when assets change (import, proxy, analysis, transcription)
        media.onAssetsChanged = { [weak self] in
            self?.scheduleSave()
        }

        // Load existing project if timeline.json exists
        loadProject()

        let dbPath = bundleURL.appendingPathComponent("metadata.sqlite").path
        Task { try? await context.actionLog.open(at: dbPath) }

        startPlayheadSync()
    }

    // MARK: - Intent pipeline (ONLY write path)

    func perform(_ intent: EditorIntent, source: ActionSource = .user) throws {
        var command = try intentResolver.resolve(intent)
        try commandHistory.execute(&command, context: context, source: source)
        rebuildComposition()
        scheduleSave()
    }

    func undo() throws {
        try commandHistory.undo(context: context)
        rebuildComposition()
        scheduleSave()
    }

    func redo() throws {
        try commandHistory.redo(context: context)
        rebuildComposition()
        scheduleSave()
    }

    // MARK: - Project persistence

    /// Save project after a short debounce (avoids saving on every keystroke/drag).
    private func scheduleSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            // Save timeline
            try? await projectStore.save(to: projectBundleURL, timeline: timeline)
            // Save asset registry
            let allAssets = await media.mediaManager.allAssets()
            let assetsURL = projectBundleURL.appendingPathComponent("assets.json")
            if let data = try? JSONEncoder().encode(allAssets) {
                try? data.write(to: assetsURL)
            }
        }
    }

    /// Load project from bundle on launch.
    private func loadProject() {
        let timelinePath = projectBundleURL.appendingPathComponent("timeline.json")
        guard FileManager.default.fileExists(atPath: timelinePath.path) else { return }

        Task {
            // Load timeline
            if let loadedTimeline = try? await projectStore.load(from: projectBundleURL) {
                context.timelineState.timeline = loadedTimeline
            }

            // Load assets and merge persisted transcripts
            let assetsURL = projectBundleURL.appendingPathComponent("assets.json")
            if let data = try? Data(contentsOf: assetsURL),
               let loadedAssets = try? JSONDecoder().decode([MediaAsset].self, from: data) {
                for var asset in loadedAssets {
                    // Restore transcript from disk if not in assets.json
                    if asset.analysis?.transcript == nil || asset.analysis!.transcript!.isEmpty {
                        if let diskResult = await media.transcriptionService.loadTranscript(
                            for: asset.id, bundleURL: projectBundleURL, sourceURL: asset.sourceURL
                        ) {
                            var analysis = asset.analysis ?? MediaAnalysis()
                            analysis.transcript = diskResult.words
                            analysis.speakerSegments = diskResult.speakers
                            asset.analysis = analysis
                        }
                    }
                    await media.mediaManager.add(asset)
                }
                await media.refreshAssets()
            }

            rebuildComposition()
        }
    }

    // MARK: - Media import

    func importMedia(from url: URL) async throws -> MediaAsset {
        let mediaDir = projectBundleURL.appendingPathComponent("media")
        return try await media.importMedia(from: url, mediaDir: mediaDir)
    }

    // MARK: - Playback

    func rebuildComposition() {
        playbackEngine.buildComposition(from: timeline, assets: assets)
    }

    func seekFromPlayhead() {
        playbackEngine.seek(to: timelineViewState.playheadPosition)
    }

    // MARK: - API key loading

    /// Load all KEY=VALUE pairs from .env files and environment.
    private static func loadEnvKeys() -> [String: String] {
        var keys: [String: String] = [:]

        // Load from .env files
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let envPaths = [
            appSupport?.appendingPathComponent("VideoEditor/.env"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("VideoEditor/.env"),
        ].compactMap { $0 }
        for envPath in envPaths {
            if let contents = try? String(contentsOf: envPath, encoding: .utf8) {
                for line in contents.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                    if let eqIndex = trimmed.firstIndex(of: "=") {
                        let key = String(trimmed[trimmed.startIndex..<eqIndex])
                        let value = String(trimmed[trimmed.index(after: eqIndex)...])
                        if !value.isEmpty { keys[key] = value }
                    }
                }
            }
        }

        // Environment variables override .env file
        for key in ["ANTHROPIC_API_KEY", "DEEPGRAM_API_KEY"] {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                keys[key] = value
            }
        }

        return keys
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
}
