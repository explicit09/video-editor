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
    let thumbnailCache: DiskCache
    let renderCache: DiskCache
    let memoryMonitor: MemoryPressureMonitor
    let bundleURL: URL

    private(set) var assets: [MediaAsset] = []

    init(bundleURL: URL) {
        self.bundleURL = bundleURL
        self.mediaManager = MediaManager()
        self.proxyService = ProxyService(proxiesDir: bundleURL.appendingPathComponent("proxies"))
        self.transcriptionService = TranscriptionService()
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

        // Background proxy generation for video
        if asset.type == .video {
            let assetID = asset.id
            Task {
                if let proxyURL = await proxyService.generateProxy(for: asset) {
                    await mediaManager.setProxyURL(proxyURL, for: assetID)
                    assets = await mediaManager.allAssets()
                }
            }
        }

        assets = await mediaManager.allAssets()
        return asset
    }

    func refreshAssets() async {
        assets = await mediaManager.allAssets()
    }

    func thumbnail(for assetID: UUID) async -> CGImage? {
        await mediaManager.thumbnail(for: assetID)
    }

    // MARK: - Transcription

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
