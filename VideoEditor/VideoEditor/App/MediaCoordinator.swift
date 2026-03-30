import Foundation
import CoreGraphics
import AVFoundation
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
    private(set) var waveformStates: [UUID: WaveformLoadState] = [:]
    private var pendingTranscriptionProvider: (any TranscriptionProvider)?
    @ObservationIgnored private var waveformTasks: Set<UUID> = []
    @ObservationIgnored private var analysisTasks: [UUID: Task<Void, Never>] = [:]

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

        // Background: proxy generation + local analysis (cancellable)
        analysisTasks[importedAsset.id]?.cancel() // Cancel any existing analysis for this asset
        analysisTasks[importedAsset.id] = Task { [weak self] in
            guard let self else { return }

            // Generate proxy first (analysis uses proxy for speed)
            if importedAsset.type == .video {
                guard !Task.isCancelled else { return }
                if let proxyURL = await proxyService.generateProxy(for: importedAsset) {
                    await mediaManager.setProxyURL(proxyURL, for: importedAsset.id)
                }
            }

            guard !Task.isCancelled else { return }

            // Run local analysis (silence, faces, scenes, OCR) — free, automatic
            let latestAsset = await mediaManager.asset(id: importedAsset.id) ?? importedAsset
            await analysisPipeline.analyze(
                asset: latestAsset,
                mediaManager: mediaManager,
                bundleURL: bundleURL,
                progress: { stage, _ in }
            )

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.analysisTasks.removeValue(forKey: importedAsset.id)
                Task { [weak self] in
                    await self?.refreshAssets()
                    self?.onAnalysisComplete?()
                    self?.onAssetsChanged?()
                }
            }
        }

        assets = await mediaManager.allAssets()
        await reconcileWaveformStates()
        onAssetsChanged?()
        return asset
    }

    func refreshAssets() async {
        assets = await mediaManager.allAssets()
        await reconcileWaveformStates()
        onAssetsChanged?()
    }

    func thumbnail(for assetID: UUID) async -> CGImage? {
        await mediaManager.thumbnail(for: assetID)
    }

    func refreshWaveformState(for assetID: UUID) async {
        guard let asset = await mediaManager.asset(id: assetID) else {
            waveformStates.removeValue(forKey: assetID)
            return
        }
        await updateWaveformState(for: asset)
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
        await ensureTranscriptionConfigured()

        for id in assetIDs {
            guard let asset = await mediaManager.asset(id: id) else { continue }
            _ = try? await transcriptionService.transcribe(
                asset: asset,
                mediaManager: mediaManager,
                bundleURL: bundleURL
            )
        }

        await refreshAssets()
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

    private func reconcileWaveformStates() async {
        let validAssetIDs = Set(assets.map(\.id))
        waveformStates = waveformStates.filter { validAssetIDs.contains($0.key) }

        for asset in assets {
            await updateWaveformState(for: asset)
        }
    }

    private func updateWaveformState(for asset: MediaAsset) async {
        guard asset.type != .image else {
            waveformStates.removeValue(forKey: asset.id)
            return
        }

        if let profile = asset.analysis?.loudnessProfile, !profile.isEmpty {
            waveformStates[asset.id] = .ready(profile)
            waveformTasks.remove(asset.id)
            return
        }

        let hasAudioTrack = await assetHasAudioTrack(asset)
        waveformStates[asset.id] = WaveformLoadStateResolver.resolve(
            for: asset,
            hasAudioTrack: hasAudioTrack,
            extractionInFlight: waveformTasks.contains(asset.id)
        )

        guard hasAudioTrack, !waveformTasks.contains(asset.id) else { return }

        waveformTasks.insert(asset.id)
        waveformStates[asset.id] = .loading

        Task {
            let waveformExtractor = WaveformExtractor()
            let profile = await waveformExtractor.extract(from: asset.sourceURL)

            await MainActor.run {
                self.waveformTasks.remove(asset.id)

                if let profile, !profile.isEmpty {
                    Task {
                        await self.mediaManager.updateAsset(id: asset.id) { asset in
                            var analysis = asset.analysis ?? MediaAnalysis()
                            analysis.loudnessProfile = profile
                            asset.analysis = analysis
                        }
                        await self.refreshAssets()
                        self.onAnalysisComplete?()
                    }
                } else {
                    self.waveformStates[asset.id] = .failed
                    self.onAssetsChanged?()
                }
            }
        }
    }

    private func assetHasAudioTrack(_ asset: MediaAsset) async -> Bool {
        switch asset.type {
        case .audio:
            return true
        case .image:
            return false
        case .video:
            let avAsset = AVURLAsset(url: asset.sourceURL)
            guard let tracks = try? await avAsset.loadTracks(withMediaType: .audio) else { return false }
            return !tracks.isEmpty
        }
    }
}
