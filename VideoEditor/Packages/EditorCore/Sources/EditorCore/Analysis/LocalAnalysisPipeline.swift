import Foundation

/// Runs all local (free) analysis tasks on an asset.
/// Called automatically on import. Runs on proxy media when available.
public actor LocalAnalysisPipeline {
    private let silenceDetector = SilenceDetector()
    private let visualAnalyzer = VisualAnalyzer()
    private let sceneAnalyzer = VisualSceneAnalyzer()
    private var inProgress: Set<UUID> = []
    private var paused = false

    public init() {}

    /// Run all local analysis on an asset. Uses proxy URL if available.
    public func analyze(
        asset: MediaAsset,
        mediaManager: MediaManager,
        bundleURL: URL,
        progress: @escaping @Sendable (String, Double) -> Void
    ) async {
        guard !inProgress.contains(asset.id), !paused else { return }
        inProgress.insert(asset.id)
        defer { inProgress.remove(asset.id) }

        let mediaURL = asset.proxyURL ?? asset.sourceURL

        // 1. Silence detection
        progress("Detecting silence...", 0.05)
        let silenceRanges = (try? await silenceDetector.detect(url: mediaURL)) ?? []

        await mediaManager.updateAsset(id: asset.id) { asset in
            var analysis = asset.analysis ?? MediaAnalysis()
            analysis.silenceRanges = silenceRanges.map { TimeRange(start: $0.start, end: $0.end) }
            asset.analysis = analysis
        }
        progress("Silence detected", 0.2)

        // 2. Visual analysis (faces, scenes, OCR) — only for video
        if asset.type == .video {
            progress("Analyzing video frames...", 0.25)
            let visualResult = try? await visualAnalyzer.analyze(url: mediaURL, sampleInterval: 2.0)

            if let visual = visualResult {
                await mediaManager.updateAsset(id: asset.id) { asset in
                    var analysis = asset.analysis ?? MediaAnalysis()
                    // Store shot boundaries from shot type transitions
                    analysis.shotBoundaries = visual.shotTypes.map(\.start)
                    asset.analysis = analysis
                }

                // Persist visual analysis to project bundle
                persistVisualAnalysis(visual, assetID: asset.id, bundleURL: bundleURL)
            }
            progress("Visual analysis complete", 0.5)
        }

        // 3. Scene-level visual understanding (VLM descriptions) — only for video
        if asset.type == .video {
            progress("Analyzing scenes...", 0.6)
            let sceneCacheDir = bundleURL
                .appendingPathComponent("analysis/visual_scenes")
                .appendingPathComponent(asset.id.uuidString)

            let scenes = try? await sceneAnalyzer.analyze(
                url: mediaURL,
                thumbnailCacheDir: sceneCacheDir
            ) { p in
                progress("Analyzing scenes...", 0.6 + 0.3 * p)
            }

            if let scenes = scenes, !scenes.isEmpty {
                await mediaManager.updateAsset(id: asset.id) { asset in
                    var analysis = asset.analysis ?? MediaAnalysis()
                    analysis.sceneDescriptions = scenes
                    asset.analysis = analysis
                }
            }
            progress("Scene analysis complete", 0.95)
        }

        progress("Analysis complete", 1.0)
    }

    /// Pause all analysis (memory pressure response).
    public func pause() { paused = true }

    /// Resume analysis.
    public func resume() { paused = false }

    /// Check if analysis is running for an asset.
    public func isAnalyzing(assetID: UUID) -> Bool {
        inProgress.contains(assetID)
    }

    // MARK: - Persistence

    private func persistVisualAnalysis(_ result: VisualAnalysisResult, assetID: UUID, bundleURL: URL) {
        let dir = bundleURL.appendingPathComponent("analysis/segments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(assetID.uuidString).json")
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: url)
        }
    }

    /// Load persisted visual analysis.
    public func loadVisualAnalysis(for assetID: UUID, bundleURL: URL) -> VisualAnalysisResult? {
        let path = bundleURL.appendingPathComponent("analysis/segments/\(assetID.uuidString).json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(VisualAnalysisResult.self, from: data)
    }
}
