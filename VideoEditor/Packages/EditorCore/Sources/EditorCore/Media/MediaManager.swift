import Foundation
import AVFoundation

/// Owns media asset registry. Single writer for the asset library.
public actor MediaManager {
    public private(set) var assets: [MediaAsset] = []
    private let importer = MediaImporter()
    private var thumbnailCache: [UUID: CGImage] = [:]
    private var thumbnailAccessOrder: [UUID] = []
    private let maxThumbnails = 100

    public init(assets: [MediaAsset] = []) {
        self.assets = assets
    }

    // MARK: - Import

    /// Import a file, copy to bundle, extract metadata, generate thumbnail.
    public func importFile(from sourceURL: URL, bundleMediaDir: URL?) async throws -> MediaAsset {
        var asset = try await importer.importFile(from: sourceURL)

        // Copy to project bundle if a bundle dir is provided
        if let mediaDir = bundleMediaDir {
            let bundleURL = try importer.copyToBundle(
                sourceURL: sourceURL,
                bundleMediaDir: mediaDir,
                assetID: asset.id
            )
            asset = MediaAsset(
                id: asset.id,
                name: asset.name,
                sourceURL: bundleURL,
                type: asset.type,
                duration: asset.duration,
                width: asset.width,
                height: asset.height,
                codec: asset.codec,
                fileSize: asset.fileSize,
                importedAt: asset.importedAt
            )
        }

        // Generate thumbnail
        if asset.type == .video || asset.type == .image {
            if let thumb = try? await importer.generateThumbnail(for: asset.sourceURL) {
                storeThumbnail(thumb, for: asset.id)
            }
        }

        assets.append(asset)
        return asset
    }

    // MARK: - CRUD

    public func add(_ asset: MediaAsset) {
        assets.append(asset)
    }

    public func remove(id: UUID) {
        assets.removeAll { $0.id == id }
        thumbnailCache.removeValue(forKey: id)
    }

    public func asset(id: UUID) -> MediaAsset? {
        assets.first { $0.id == id }
    }

    public func updateAsset(id: UUID, _ transform: @Sendable (inout MediaAsset) -> Void) {
        guard let index = assets.firstIndex(where: { $0.id == id }) else { return }
        transform(&assets[index])
    }

    public func setProxyURL(_ proxyURL: URL, for assetID: UUID) {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
        assets[index].proxyURL = proxyURL
    }

    public func allAssets() -> [MediaAsset] {
        assets
    }

    // MARK: - Thumbnails

    public func thumbnail(for assetID: UUID) -> CGImage? {
        // Move to front of access order (LRU)
        if let idx = thumbnailAccessOrder.firstIndex(of: assetID) {
            thumbnailAccessOrder.remove(at: idx)
            thumbnailAccessOrder.append(assetID)
        }
        return thumbnailCache[assetID]
    }

    private let maxThumbnailBytes: Int = 50 * 1024 * 1024 // 50MB max

    private func storeThumbnail(_ image: CGImage, for id: UUID) {
        thumbnailCache[id] = image
        thumbnailAccessOrder.append(id)

        // Evict oldest if over count or size limit
        while thumbnailCache.count > maxThumbnails || estimatedThumbnailBytes() > maxThumbnailBytes,
              let oldest = thumbnailAccessOrder.first {
            thumbnailAccessOrder.removeFirst()
            thumbnailCache.removeValue(forKey: oldest)
        }
    }

    private func estimatedThumbnailBytes() -> Int {
        thumbnailCache.values.reduce(0) { $0 + $1.width * $1.height * 4 }
    }
}
