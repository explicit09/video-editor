import Foundation
import CoreGraphics
import EditorCore
import AIServices

/// Orchestrates media import, proxy generation, and cache management.
/// Extracted from AppState to keep it focused on editor state + commands.
@MainActor @Observable
final class MediaCoordinator {
    let mediaManager: MediaManager
    let proxyService: ProxyService
    let transcriptionService: TranscriptionService
    let analysisPipeline: LocalAnalysisPipeline
    let thumbnailCache: DiskCache
    let renderCache: DiskCache
    let memoryMonitor: MemoryPressureMonitor
    let bundleURL: URL

    private(set) var assets: [MediaAsset] = []
    private var pendingTranscriptionProvider: (any TranscriptionProvider)?

    /// Called when background analysis/proxy completes. AppState uses this to rebuild composition.
    var onAnalysisComplete: (() -> Void)?
    /// Called when assets change (import, proxy, analysis). AppState uses this to trigger save.
    var onAssetsChanged: (() -> Void)?

    init(bundleURL: URL) {
        self.bundleURL = bundleURL
        self.mediaManager = MediaManager()
        self.proxyService = ProxyService(proxiesDir: bundleURL.appendingPathComponent("proxies"))
        self.transcriptionService = TranscriptionService()
        self.analysisPipeline = LocalAnalysisPipeline()
        self.thumbnailCache = DiskCache(
            directory: bundleURL.appendingPathComponent("cache/thumbnails"),
            policy: .thumbnails
        )
        self.renderCache = DiskCache(
            directory: bundleURL.appendingPathComponent("cache/render"),
            policy: .renderCache
        )
        self.memoryMonitor = MemoryPressureMonitor()

        startMemoryMonitoring()
    }

    // MARK: - Import

    func importMedia(from url: URL, mediaDir: URL) async throws -> MediaAsset {
        var asset = try await mediaManager.importFile(from: url, bundleMediaDir: mediaDir)

        let importedAsset = asset

        // Background: proxy generation + local analysis
        Task {
            // Generate proxy first (analysis uses proxy for speed)
            if importedAsset.type == .video {
                if let proxyURL = await proxyService.generateProxy(for: importedAsset) {
                    await mediaManager.setProxyURL(proxyURL, for: importedAsset.id)
                }
            }

            // Run local analysis (silence, faces, scenes, OCR) — free, automatic
            let latestAsset = await mediaManager.asset(id: importedAsset.id) ?? importedAsset
            await analysisPipeline.analyze(
                asset: latestAsset,
                mediaManager: mediaManager,
                bundleURL: bundleURL,
                progress: { stage, _ in
                    // Could update UI progress here in the future
                }
            )

            await MainActor.run {
                Task {
                    self.assets = await self.mediaManager.allAssets()
                    self.onAnalysisComplete?()
                    self.onAssetsChanged?()
                }
            }
        }

        assets = await mediaManager.allAssets()
        onAssetsChanged?()
        return asset
    }

    func refreshAssets() async {
        assets = await mediaManager.allAssets()
    }

    func thumbnail(for assetID: UUID) async -> CGImage? {
        await mediaManager.thumbnail(for: assetID)
    }

    // MARK: - Transcription

    /// Set provider synchronously — configures the actor on first use.
    func setTranscriptionProvider(_ provider: any TranscriptionProvider) {
        pendingTranscriptionProvider = provider
    }

    /// Ensure transcription service is configured before use.
    func ensureTranscriptionConfigured() async {
        if let provider = pendingTranscriptionProvider {
            await transcriptionService.configure(provider: provider)
            pendingTranscriptionProvider = nil
        }
    }

    func configureTranscription(provider: any TranscriptionProvider) async {
        await transcriptionService.configure(provider: provider)
    }

    /// Transcribe specific assets (only if not already transcribed).
    func transcribeAssets(_ assetIDs: [UUID]) async {
        for id in assetIDs {
            guard let asset = await mediaManager.asset(id: id) else { continue }
            _ = try? await transcriptionService.transcribe(
                asset: asset,
                mediaManager: mediaManager,
                bundleURL: bundleURL
            )
        }
        assets = await mediaManager.allAssets()
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
