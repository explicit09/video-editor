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

    // Reactive access
    var timeline: Timeline { context.timelineState.timeline }
    var assets: [MediaAsset] { media.assets }

    /// Project bundle directory.
    let projectBundleURL: URL

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
        self.media = MediaCoordinator(bundleURL: bundleURL)
        self.aiChat = AIChatController()

        // Load API keys from .env file or environment
        let keys = Self.loadEnvKeys()
        if let claudeKey = keys["ANTHROPIC_API_KEY"] {
            aiChat.configure(provider: ClaudeProvider(apiKey: claudeKey))
        }
        if let dgKey = keys["DEEPGRAM_API_KEY"] {
            Task { await media.configureTranscription(provider: DeepgramProvider(apiKey: dgKey)) }
        }

        let dbPath = bundleURL.appendingPathComponent("metadata.sqlite").path
        Task { try? await context.actionLog.open(at: dbPath) }

        startPlayheadSync()
    }

    // MARK: - Intent pipeline (ONLY write path)

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
        let envPaths = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("VideoEditor/.env"),
        ]
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
