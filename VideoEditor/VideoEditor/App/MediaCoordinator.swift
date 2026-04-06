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
    private(set) var bundleURL: URL

    private(set) var assets: [MediaAsset] = []
    private(set) var waveformStates: [UUID: WaveformLoadState] = [:]
    private var pendingTranscriptionProvider: (any TranscriptionProvider)?
    private var pendingLocalTranscriptionProvider: (any TranscriptionProvider)?
    @ObservationIgnored private var waveformTasks: [UUID: Task<Void, Never>] = [:]
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

    func importMedia(from url: URL, mediaDir: URL?) async throws -> MediaAsset {
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
        reconcileWaveformStates()
        onAssetsChanged?()
        return asset
    }

    func refreshAssets() async {
        assets = await mediaManager.allAssets()
        reconcileWaveformStates()
        onAssetsChanged?()
    }

    func regenerateMissingThumbnails() async {
        await mediaManager.regenerateMissingThumbnails()
    }

    /// Update the bundle URL for project switching without recreating the coordinator.
    func updateBundleURL(_ newURL: URL) {
        stopBackgroundWork()
        bundleURL = newURL
    }

    func stopBackgroundWork() {
        analysisTasks.values.forEach { $0.cancel() }
        analysisTasks.removeAll()

        waveformTasks.values.forEach { $0.cancel() }
        waveformTasks.removeAll()

        memoryMonitor.stopMonitoring()
        Task {
            await proxyService.cancelAll()
        }
    }

    func thumbnail(for assetID: UUID) async -> CGImage? {
        await mediaManager.thumbnail(for: assetID)
    }

    func refreshWaveformState(for assetID: UUID) async {
        guard let asset = await mediaManager.asset(id: assetID) else {
            waveformStates.removeValue(forKey: assetID)
            waveformTasks.removeValue(forKey: assetID)?.cancel()
            return
        }
        scheduleWaveformRefresh(for: asset)
    }

    // MARK: - Transcription

    /// Set cloud provider synchronously — configures the actor on first use.
    func setTranscriptionProvider(_ provider: any TranscriptionProvider) {
        pendingTranscriptionProvider = provider
    }

    /// Set local (WhisperKit) provider synchronously — configures the actor on first use.
    func setLocalTranscriptionProvider(_ provider: any TranscriptionProvider) {
        pendingLocalTranscriptionProvider = provider
    }

    /// Ensure transcription service is configured before use.
    func ensureTranscriptionConfigured() async {
        if let provider = pendingTranscriptionProvider {
            await transcriptionService.configure(provider: provider)
            pendingTranscriptionProvider = nil
        }
        if let localProvider = pendingLocalTranscriptionProvider {
            await transcriptionService.configureLocal(provider: localProvider)
            pendingLocalTranscriptionProvider = nil
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

    private func reconcileWaveformStates() {
        let validAssetIDs = Set(assets.map(\.id))
        waveformStates = waveformStates.filter { validAssetIDs.contains($0.key) }
        for assetID in waveformTasks.keys where !validAssetIDs.contains(assetID) {
            waveformTasks.removeValue(forKey: assetID)?.cancel()
        }

        for asset in assets {
            scheduleWaveformRefresh(for: asset)
        }
    }

    private func scheduleWaveformRefresh(for asset: MediaAsset) {
        let extractionInFlight = waveformTasks[asset.id] != nil
        let decision = WaveformRefreshPlanner.makeDecision(
            for: asset,
            extractionInFlight: extractionInFlight
        )

        waveformStates[asset.id] = decision.state

        guard decision.needsExtraction, !extractionInFlight else { return }

        let task = Task {
            let waveformExtractor = WaveformExtractor()
            let profile = await waveformExtractor.extract(from: asset.sourceURL)
            guard !Task.isCancelled else { return }

            if let profile, !profile.isEmpty {
                await self.mediaManager.updateAsset(id: asset.id) { asset in
                    var analysis = asset.analysis ?? MediaAnalysis()
                    analysis.loudnessProfile = profile
                    asset.analysis = analysis
                }
            }

            let updatedAsset = await self.mediaManager.asset(id: asset.id)

            await MainActor.run {
                self.waveformTasks.removeValue(forKey: asset.id)

                if let updatedAsset {
                    if let index = self.assets.firstIndex(where: { $0.id == asset.id }) {
                        self.assets[index] = updatedAsset
                    }

                    if profile != nil {
                        let resolved = WaveformRefreshPlanner.makeDecision(
                            for: updatedAsset,
                            extractionInFlight: false
                        )
                        self.waveformStates[asset.id] = resolved.state
                        self.onAnalysisComplete?()
                        self.onAssetsChanged?()
                    } else {
                        self.waveformStates[asset.id] = .failed
                        self.onAssetsChanged?()
                    }
                } else {
                    self.waveformStates[asset.id] = .failed
                    self.onAssetsChanged?()
                }
            }
        }

        waveformTasks[asset.id] = task
    }

    deinit {
        MainActor.assumeIsolated {
            stopBackgroundWork()
        }
    }
}
